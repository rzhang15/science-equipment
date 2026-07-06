"""
04_score_papers.py

Score every 2010-2019 paper-author row where the focal author is in the
analysis sample (athr_id present in athr_panel_full_year_last_all_jrnls.dta).

Applies the three frozen LightGBM models from step 03 and assigns within-
(field, year) tiers from the predicted score:
    pred_tier             from pred_cite_pct
    pred_tier_topdecile   from pred_p_topdecile
    pred_tier_top15       from pred_p_top15

Tier definition: high = rank >= 0.75, low = rank <= 0.25, mid otherwise.

Inputs
------
../temp/all_features.parquet                              (step 02c)
../external/samp/athr_panel_full_year_last_all_jrnls.dta  (analysis-sample PIs)
../output/models/lgbm_reg.pkl
../output/models/lgbm_clf_topdecile.pkl
../output/models/lgbm_clf_top15.pkl

Output
------
../output/scoring/scored_papers_2010_2019.parquet
"""

import os
import pickle
import sys
import time

import pandas as pd
import polars as pl

try:
    import pyreadstat
except ImportError:
    sys.exit("ERROR: pyreadstat not installed. pip install --user pyreadstat")

SRC = "../temp/all_features.parquet"
PANEL = "../external/samp/athr_panel_full_year_last_all_jrnls.dta"
MODEL_DIR = "../output/models"
DST_DIR = "../output/scoring"
DST = os.path.join(DST_DIR, "scored_papers_2010_2019.parquet")


def to_X_for_scoring(df_pl, bundle):
    """Build the pandas DataFrame the saved model expects.

    Reconstruct pd.Categorical columns with the same category levels seen at
    training so LightGBM uses its stored encoding, not a freshly-discovered
    one. Categories present at scoring but not training fall through as NaN
    (LightGBM routes them as missing).
    """
    cols = bundle["columns"]
    cats = bundle.get("categorical", [])
    cat_levels = bundle.get("cat_levels", {})
    X = df_pl.select(cols).to_pandas()
    for c in cats:
        if c not in X.columns:
            continue
        levels = cat_levels.get(c)
        if levels is None:
            X[c] = X[c].astype("category")
        else:
            X[c] = pd.Categorical(X[c], categories=levels)
    return X


def tier_within(df, score_col, tier_col):
    """High if rank >= 0.75, low if rank <= 0.25, mid otherwise, within
    (field, year). Rows with null score get null tier."""
    rk_col = f"__rk_{tier_col}"
    df = df.with_columns(
        (
            pl.col(score_col).rank("average").over(["field", "year"])
            / pl.col(score_col).count().over(["field", "year"])
        ).alias(rk_col)
    )
    df = df.with_columns(
        pl.when(pl.col(rk_col).is_null())
        .then(None)
        .when(pl.col(rk_col) >= 0.75)
        .then(pl.lit("high"))
        .when(pl.col(rk_col) <= 0.25)
        .then(pl.lit("low"))
        .otherwise(pl.lit("mid"))
        .alias(tier_col)
    )
    return df.drop(rk_col)


def main():
    for path in (SRC, PANEL):
        if not os.path.exists(path):
            sys.exit(f"ERROR: missing input {path}")

    os.makedirs(DST_DIR, exist_ok=True)
    t0 = time.time()

    print(f"reading analysis-sample PIs from {PANEL}", flush=True)
    try:
        panel_df, _ = pyreadstat.read_dta(PANEL, usecols=["athr_id"])
    except TypeError:
        panel_df, _ = pyreadstat.read_dta(PANEL)
        panel_df = panel_df[["athr_id"]]
    sample_pis = set(panel_df["athr_id"].dropna().unique().tolist())
    print(f"   {len(sample_pis):,} distinct analysis-sample PIs", flush=True)

    print(f"reading {SRC}", flush=True)
    df = pl.read_parquet(SRC).filter(
        (pl.col("year") >= 2010) & (pl.col("year") <= 2019)
    )
    print(f"   {df.height:,} rows in 2010-2019", flush=True)

    df = df.filter(pl.col("athr_id").is_in(list(sample_pis)))
    print(f"   {df.height:,} rows after analysis-sample filter", flush=True)

    specs = [
        ("lgbm_reg", "pred_cite_pct", False),
        ("lgbm_clf_topdecile", "pred_p_topdecile", True),
        ("lgbm_clf_top15", "pred_p_top15", True),
    ]
    for stem, pred_col, is_prob in specs:
        path = os.path.join(MODEL_DIR, f"{stem}.pkl")
        if not os.path.exists(path):
            sys.exit(f"ERROR: missing model {path}; run step 03 first")
        with open(path, "rb") as f:
            bundle = pickle.load(f)
        X = to_X_for_scoring(df, bundle)
        est = bundle["estimator"]
        print(f"scoring {stem} -> {pred_col}", flush=True)
        if is_prob:
            preds = est.predict_proba(X)[:, 1]
        else:
            preds = est.predict(X)
        df = df.with_columns(pl.Series(pred_col, preds, dtype=pl.Float64))

    print("computing within-(field, year) tiers", flush=True)
    df = tier_within(df, "pred_cite_pct", "pred_tier")
    df = tier_within(df, "pred_p_topdecile", "pred_tier_topdecile")
    df = tier_within(df, "pred_p_top15", "pred_tier_top15")

    out = df.select(
        [
            "id",
            "athr_id",
            "year",
            "field",
            "jrnl",
            "cite_pct",
            "y_topdecile",
            "y_top15",
            "paper_modal_cluster",
            "pi_modal_cluster_pre2013",
            "team_size",
            "junior_share",
            "pred_cite_pct",
            "pred_p_topdecile",
            "pred_p_top15",
            "pred_tier",
            "pred_tier_topdecile",
            "pred_tier_top15",
        ]
    )

    # Sanity: tier counts within (field, year) should be ~25/50/25.
    tier_counts = (
        out.group_by("pred_tier")
        .len()
        .sort("pred_tier")
    )
    print("pred_tier distribution:", flush=True)
    print(tier_counts, flush=True)

    print(f"writing {DST}", flush=True)
    out.write_parquet(DST, compression="snappy")
    print(f"done in {time.time() - t0:.1f}s", flush=True)


if __name__ == "__main__":
    main()
