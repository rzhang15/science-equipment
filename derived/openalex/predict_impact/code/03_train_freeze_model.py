"""
03_train_freeze_model.py

Train, cross-validate, and freeze LightGBM models that predict paper impact
from paper + PI ex-ante features.

Targets
-------
cite_pct       continuous, in [0,1]  -> LightGBM regressor + OLS benchmark
y_topdecile    binary                -> LightGBM classifier + logit
y_top15        binary                -> LightGBM classifier + logit

Validation
----------
5-fold standard KFold (shuffle, random_state=8975) AND 5-fold GroupKFold
keyed on athr_id. For each fold, metrics:
- continuous: R^2, Spearman rho
- binary:     ROC-AUC, Brier, calibration slope (1.0 if calibrated)

Standard CV should beat group CV by a few points because PI track-record
features leak across train/test when an author appears in both. If standard
< group, something is wrong (target leakage).

Freeze
------
After CV, refit each LightGBM on ALL pre-2014 rows and pickle to
../output/models/. Feature importances written to ../output/diagnostics/.
Paper-feature vs PI-feature gain share is the key sanity number.

Inputs
------
../temp/all_features.parquet    (from step 02c)

Outputs
-------
../output/models/lgbm_reg.pkl
../output/models/lgbm_clf_topdecile.pkl
../output/models/lgbm_clf_top15.pkl
../output/diagnostics/cv_metrics.csv
../output/diagnostics/cv_summary.csv
../output/diagnostics/feature_imp_<stem>.csv
"""

import os
import pickle
import sys
import time

import numpy as np
import pandas as pd
import polars as pl
from scipy.stats import spearmanr
from sklearn.linear_model import LinearRegression, LogisticRegression
from sklearn.metrics import brier_score_loss, r2_score, roc_auc_score
from sklearn.model_selection import GroupKFold, KFold

try:
    import lightgbm as lgb
except ImportError:
    sys.exit("ERROR: lightgbm not installed. pip install --user lightgbm")

SRC = "../temp/all_features.parquet"
MODEL_DIR = "../output/models"
DIAG_DIR = "../output/diagnostics"
SEED = 8975

PAPER_FEATS = [
    "team_size",
    "junior_share",
    "cross_cluster_team",
    "paper_modal_cluster",
    "multi_inst",
    "has_r1_author",
    "topic_distance_from_PI_core",
    # MeSH-based topic-rarity signals (from step 02d). Missing on non-mesh
    # papers -> nulls, which LightGBM handles natively.
    "n_mesh_terms",
    "mean_mesh_year_freq",
    "min_mesh_year_freq",
    "log_min_mesh_year_freq",
    "mean_mesh_alltime_freq",
]
PI_FEATS = [
    "mean_cite_pct_pre",
    "total_pubs_pre",
    "top15_count_pre",
    "pubs_per_yr_pre",
    "min_year",
    "pi_cluster5",
    "r1_share_pre",
    "is_r1_modal",
    "n_coauthors_pre",
    "pi_modal_cluster_pre2013",
    "which_athr",
]
FEATURE_COLS = PAPER_FEATS + PI_FEATS
CATEGORICAL = [
    "paper_modal_cluster",
    "pi_cluster5",
    "pi_modal_cluster_pre2013",
    "which_athr",
    "has_r1_author",
    "is_r1_modal",
    "topic_distance_from_PI_core",
]
LEAKAGE = {"cite_pct", "y_topdecile", "y_top15", "avg_cite_yr", "jrnl"}

LGB_PARAMS = dict(
    n_estimators=500,
    learning_rate=0.05,
    num_leaves=63,
    min_data_in_leaf=200,
    random_state=SEED,
    verbose=-1,
    n_jobs=-1,
)


def assert_no_leakage():
    bad = set(FEATURE_COLS) & LEAKAGE
    if bad:
        sys.exit(f"ERROR: feature columns leak target: {bad}")


def to_X(df_pl):
    X = df_pl.select(FEATURE_COLS).to_pandas()
    for c in CATEGORICAL:
        if c in X.columns:
            X[c] = X[c].astype("category")
    return X


def to_X_linear(X):
    """Convert categoricals to integer codes and median-impute for linear models."""
    Xl = X.copy()
    for c in CATEGORICAL:
        if c in Xl.columns:
            Xl[c] = pd.factorize(Xl[c].astype(str), sort=False)[0].astype(float)
    Xl = Xl.apply(pd.to_numeric, errors="coerce")
    medians = Xl.median(numeric_only=True)
    Xl = Xl.fillna(medians).fillna(0.0)
    return Xl


def calibration_slope(y, p):
    p = np.asarray(p, dtype=float)
    y = np.asarray(y, dtype=float)
    p_m = p.mean()
    var = ((p - p_m) ** 2).sum()
    return float("nan") if var == 0 else float(((p - p_m) * (y - y.mean())).sum() / var)


def score_continuous(y, pred):
    rho, _ = spearmanr(y, pred)
    return dict(r2=float(r2_score(y, pred)), spearman=float(rho))


def score_binary(y, p):
    return dict(
        auc=float(roc_auc_score(y, p)),
        brier=float(brier_score_loss(y, p)),
        cal_slope=calibration_slope(y, p),
    )


def run_cv(make_estimator, X, y, groups, cv_objs, target_name, model_name,
           predict_fn, score_fn, rows):
    for cv_type, cv in cv_objs.items():
        for fold, (tr, va) in enumerate(cv.split(X, y, groups=groups)):
            est = make_estimator()
            est.fit(X.iloc[tr], y[tr])
            preds = predict_fn(est, X.iloc[va])
            for metric, val in score_fn(y[va], preds).items():
                rows.append(
                    dict(
                        model=model_name,
                        target=target_name,
                        cv_type=cv_type,
                        fold=fold,
                        metric=metric,
                        value=val,
                    )
                )
            print(
                f"      {model_name:24s}  {cv_type:8s}  fold {fold}  done",
                flush=True,
            )


def predict_reg(est, X):
    return est.predict(X)


def predict_proba(est, X):
    return est.predict_proba(X)[:, 1]


def main():
    assert_no_leakage()
    os.makedirs(MODEL_DIR, exist_ok=True)
    os.makedirs(DIAG_DIR, exist_ok=True)

    t0 = time.time()
    print(f"reading {SRC}", flush=True)
    df = pl.read_parquet(SRC).filter(
        (pl.col("year") < 2014) & pl.col("cite_pct").is_not_null()
    )
    print(f"   training rows: {df.height:,}", flush=True)

    X = to_X(df)
    X_lin = to_X_linear(X)

    y_reg = df["cite_pct"].to_numpy()
    y_top10 = df["y_topdecile"].to_numpy().astype(int)
    y_top15 = df["y_top15"].to_numpy().astype(int)
    groups = df["athr_id"].to_numpy()

    cv_objs = {
        "standard": KFold(n_splits=5, shuffle=True, random_state=SEED),
        "group": GroupKFold(n_splits=5),
    }
    rows = []

    print("CV: LightGBM regressor on cite_pct", flush=True)
    run_cv(
        lambda: lgb.LGBMRegressor(**LGB_PARAMS),
        X, y_reg, groups, cv_objs,
        "cite_pct", "lgbm_reg", predict_reg, score_continuous, rows,
    )

    print("CV: OLS benchmark on cite_pct", flush=True)
    run_cv(
        lambda: LinearRegression(),
        X_lin, y_reg, groups, cv_objs,
        "cite_pct", "ols", predict_reg, score_continuous, rows,
    )

    for target_name, y_bin in [("y_topdecile", y_top10), ("y_top15", y_top15)]:
        print(f"CV: LightGBM classifier on {target_name}", flush=True)
        run_cv(
            lambda: lgb.LGBMClassifier(**LGB_PARAMS),
            X, y_bin, groups, cv_objs,
            target_name, f"lgbm_clf_{target_name}",
            predict_proba, score_binary, rows,
        )
        print(f"CV: Logit benchmark on {target_name}", flush=True)
        run_cv(
            lambda: LogisticRegression(max_iter=500, solver="lbfgs"),
            X_lin, y_bin, groups, cv_objs,
            target_name, f"logit_{target_name}",
            predict_proba, score_binary, rows,
        )

    cv_df = pd.DataFrame(rows)
    cv_df.to_csv(os.path.join(DIAG_DIR, "cv_metrics.csv"), index=False)
    summary = (
        cv_df.groupby(["model", "target", "cv_type", "metric"])["value"]
        .agg(["mean", "std"])
        .reset_index()
    )
    summary.to_csv(os.path.join(DIAG_DIR, "cv_summary.csv"), index=False)
    print("CV summary (mean ± std across folds):", flush=True)
    print(summary.to_string(index=False), flush=True)

    print("freezing final models on all pre-2014 data", flush=True)
    # Persist categorical levels so step 04 can rebuild pd.Categorical columns
    # with the same encoding LightGBM saw at training.
    cat_levels = {
        c: X[c].cat.categories.tolist() for c in CATEGORICAL if c in X.columns
    }

    freeze_specs = [
        ("cite_pct", y_reg, "lgbm_reg", lgb.LGBMRegressor),
        ("y_topdecile", y_top10, "lgbm_clf_topdecile", lgb.LGBMClassifier),
        ("y_top15", y_top15, "lgbm_clf_top15", lgb.LGBMClassifier),
    ]
    gain_rows = []
    for target_name, y, stem, Cls in freeze_specs:
        est = Cls(**LGB_PARAMS)
        est.fit(X, y, categorical_feature=CATEGORICAL)
        with open(os.path.join(MODEL_DIR, f"{stem}.pkl"), "wb") as f:
            pickle.dump(
                dict(
                    estimator=est,
                    columns=FEATURE_COLS,
                    categorical=CATEGORICAL,
                    cat_levels=cat_levels,
                ),
                f,
            )

        imp = pd.DataFrame(
            dict(
                feature=est.booster_.feature_name(),
                gain=est.booster_.feature_importance(importance_type="gain"),
            )
        )
        total = imp["gain"].sum() or 1.0
        imp["gain_pct"] = 100 * imp["gain"] / total
        imp = imp.sort_values("gain", ascending=False)
        imp.to_csv(
            os.path.join(DIAG_DIR, f"feature_imp_{stem}.csv"), index=False
        )

        paper_gain = imp.loc[imp.feature.isin(PAPER_FEATS), "gain"].sum()
        pi_gain = imp.loc[imp.feature.isin(PI_FEATS), "gain"].sum()
        denom = paper_gain + pi_gain or 1.0
        share_paper = 100 * paper_gain / denom
        share_pi = 100 * pi_gain / denom
        gain_rows.append(
            dict(model=stem, paper_gain_share=share_paper, pi_gain_share=share_pi)
        )
        print(
            f"  {stem}: paper-feature gain share = {share_paper:.1f}%  "
            f"PI = {share_pi:.1f}%",
            flush=True,
        )

    pd.DataFrame(gain_rows).to_csv(
        os.path.join(DIAG_DIR, "gain_share_paper_vs_pi.csv"), index=False
    )

    print(f"done in {time.time() - t0:.1f}s", flush=True)


if __name__ == "__main__":
    main()
