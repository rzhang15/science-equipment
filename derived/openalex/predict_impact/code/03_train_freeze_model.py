"""
03_train_freeze_model.py

Train, cross-validate, and freeze LightGBM models that predict paper impact
from paper + PI ex-ante features.

Targets
-------
cite_pct       continuous, in [0,1]  -> LightGBM regressor
y_topdecile    binary                -> LightGBM classifier
y_top15        binary                -> LightGBM classifier

OLS / logit benchmarks were dropped from the CV loop: we've established the
LGB models beat them and the diagnostic value is now near zero. If you need
them back for a specific check, run them ad hoc.

Validation
----------
5-fold GroupKFold keyed on athr_id. For each fold, metrics:
- continuous: R^2, Spearman rho
- binary:     ROC-AUC, Brier, calibration slope (1.0 if calibrated)

Group CV is the honest evaluation: it prevents leakage from PI track-record
features that would otherwise sneak across train/test when the same author
appears in both. Standard-KFold was previously included as a sanity check
(standard should beat group by a few points); we've established that pattern
holds and dropped it to halve CV time.

Within each fold we hold out a random 10% of the training rows for LightGBM
early stopping; the outer va slice is used only for scoring.

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
from sklearn.metrics import brier_score_loss, r2_score, roc_auc_score
from sklearn.model_selection import GroupKFold, train_test_split

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
    # papers -> nulls, which LightGBM handles natively. log_min_mesh_year_freq
    # was dropped: monotone transform of min_mesh_year_freq, 0 gain in trees.
    "n_mesh_terms",
    "mean_mesh_year_freq",
    "min_mesh_year_freq",
    "mean_mesh_alltime_freq",
]
PI_FEATS = [
    # Leave-one-paper-out versions from 02c. For training rows (year < 2014)
    # the row's own cite_pct / y_top15 has been removed from the PI aggregate
    # to prevent target leakage. For scoring rows (year >= 2014) these equal
    # the full pre-2014 aggregate exactly.
    "mean_cite_pct_pre_loo",
    "total_pubs_pre_loo",
    "top15_count_pre_loo",
    "pubs_per_yr_pre_loo",
    "min_year",
    "pi_cluster",
    "r1_share_pre",
    "n_coauthors_pre",
    "pi_modal_cluster_pre2013",
    "which_athr",
    # is_r1_modal dropped: mathematical function of r1_share_pre, 0 gain.
]
# Author topic-mix embedding: TruncatedSVD of the tfidf_universe matrix from
# foia_similarity_wts (see 02e). Continuous dense vector -- captures within-
# cluster nuance that pi_cluster (k=30 categorical) misses. Missing for non-
# US or scrubbed authors; LightGBM routes as null.
PI_SVD_FEATS = [f"pi_svd_{i+1}" for i in range(20)]
FEATURE_COLS = PAPER_FEATS + PI_FEATS + PI_SVD_FEATS
CATEGORICAL = [
    "paper_modal_cluster",
    "pi_cluster",
    "pi_modal_cluster_pre2013",
    "which_athr",
    "has_r1_author",
    "topic_distance_from_PI_core",
]
# The raw pre-features (mean_cite_pct_pre, total_pubs_pre, top15_count_pre,
# pubs_per_yr_pre) are also treated as leakage guards -- if a bare (non-loo)
# version sneaks back into FEATURE_COLS the assert below will catch it.
LEAKAGE = {
    "cite_pct", "y_topdecile", "y_top15", "avg_cite_yr", "jrnl",
    "mean_cite_pct_pre", "total_pubs_pre", "top15_count_pre",
    "pubs_per_yr_pre",
}

LGB_PARAMS = dict(
    n_estimators=500,
    learning_rate=0.05,
    num_leaves=63,
    min_data_in_leaf=200,
    random_state=SEED,
    verbose=-1,
    n_jobs=-1,
)
EARLY_STOPPING_ROUNDS = 30
INNER_VAL_FRAC = 0.1  # slice of the train fold used for LGB early stopping


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


def run_cv_lgb(make_estimator, X, y, groups, cv, target_name, model_name,
               predict_fn, score_fn, rows, best_iters):
    """5-fold GroupKFold with LightGBM early stopping on a 10% inner val slice.

    best_iters is a list this function appends the fold's best_iteration_ to.
    The refit at the end uses the median of these to size n_estimators.
    """
    for fold, (tr, va) in enumerate(cv.split(X, y, groups=groups)):
        inner_tr, inner_va = train_test_split(
            tr, test_size=INNER_VAL_FRAC, random_state=SEED + fold
        )
        est = make_estimator()
        est.fit(
            X.iloc[inner_tr], y[inner_tr],
            eval_set=[(X.iloc[inner_va], y[inner_va])],
            categorical_feature=CATEGORICAL,
            callbacks=[lgb.early_stopping(EARLY_STOPPING_ROUNDS, verbose=False)],
        )
        best_iters.append(int(est.best_iteration_ or LGB_PARAMS["n_estimators"]))
        preds = predict_fn(est, X.iloc[va])
        for metric, val in score_fn(y[va], preds).items():
            rows.append(
                dict(
                    model=model_name,
                    target=target_name,
                    cv_type="group",
                    fold=fold,
                    metric=metric,
                    value=val,
                )
            )
        print(
            f"      {model_name:24s}  fold {fold}  best_iter={est.best_iteration_}",
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

    y_reg = df["cite_pct"].to_numpy()
    y_top10 = df["y_topdecile"].to_numpy().astype(int)
    y_top15 = df["y_top15"].to_numpy().astype(int)
    groups = df["athr_id"].to_numpy()

    cv = GroupKFold(n_splits=5)
    rows = []
    best_iters_by_stem = {"lgbm_reg": [], "lgbm_clf_topdecile": [], "lgbm_clf_top15": []}

    print("CV: LightGBM regressor on cite_pct", flush=True)
    run_cv_lgb(
        lambda: lgb.LGBMRegressor(**LGB_PARAMS),
        X, y_reg, groups, cv,
        "cite_pct", "lgbm_reg", predict_reg, score_continuous, rows,
        best_iters_by_stem["lgbm_reg"],
    )

    print("CV: LightGBM classifier on y_topdecile", flush=True)
    run_cv_lgb(
        lambda: lgb.LGBMClassifier(**LGB_PARAMS),
        X, y_top10, groups, cv,
        "y_topdecile", "lgbm_clf_topdecile", predict_proba, score_binary, rows,
        best_iters_by_stem["lgbm_clf_topdecile"],
    )

    print("CV: LightGBM classifier on y_top15", flush=True)
    run_cv_lgb(
        lambda: lgb.LGBMClassifier(**LGB_PARAMS),
        X, y_top15, groups, cv,
        "y_top15", "lgbm_clf_top15", predict_proba, score_binary, rows,
        best_iters_by_stem["lgbm_clf_top15"],
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
        # Size the refit's boosting rounds to the median best_iteration_ from
        # CV. Refit is on ALL pre-2014 rows (no held-out), so we can't rely on
        # early stopping here; the median from the folds is a defensible cap.
        best_iters = best_iters_by_stem[stem]
        n_est_refit = int(np.median(best_iters)) if best_iters else LGB_PARAMS["n_estimators"]
        print(
            f"  refitting {stem} with n_estimators={n_est_refit} "
            f"(fold best_iters={best_iters})",
            flush=True,
        )
        params = {**LGB_PARAMS, "n_estimators": n_est_refit}
        est = Cls(**params)
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
        pi_svd_gain = imp.loc[imp.feature.isin(PI_SVD_FEATS), "gain"].sum()
        denom = paper_gain + pi_gain + pi_svd_gain or 1.0
        share_paper = 100 * paper_gain / denom
        share_pi = 100 * pi_gain / denom
        share_pi_svd = 100 * pi_svd_gain / denom
        gain_rows.append(
            dict(
                model=stem,
                paper_gain_share=share_paper,
                pi_gain_share=share_pi,
                pi_svd_gain_share=share_pi_svd,
            )
        )
        print(
            f"  {stem}: paper = {share_paper:.1f}%  "
            f"PI (classic) = {share_pi:.1f}%  "
            f"PI (SVD topic) = {share_pi_svd:.1f}%",
            flush=True,
        )

    pd.DataFrame(gain_rows).to_csv(
        os.path.join(DIAG_DIR, "gain_share_paper_vs_pi.csv"), index=False
    )

    print(f"done in {time.time() - t0:.1f}s", flush=True)


if __name__ == "__main__":
    main()
