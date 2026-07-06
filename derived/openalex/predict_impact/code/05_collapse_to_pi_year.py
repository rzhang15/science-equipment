"""
05_collapse_to_pi_year.py

Collapse the scored 2010-2019 paper-author rows to (athr_id, year) tier counts.

Predicted tier counts come from step 04. Realized tier comes from cite_pct
(rank within field-year, already in [0,1]). Team-size and junior-share tiers
come from within-(field, year) percentile thresholds.

Input
-----
../output/scoring/scored_papers_2010_2019.parquet   (from step 04)

Outputs
-------
../temp/pi_year_pred_tiers.parquet
../temp/pi_year_pred_tiers.dta                       (consumed by build.do)

Columns at PI-year level
------------------------
athr_id, year
n_scored                 -- rows scored (sanity vs panel's ppr_cnt)
n_pred_high / mid / low                     (from pred_cite_pct tiers)
n_pred_high_topdecile, n_pred_low_topdecile (from pred_p_topdecile tiers)
n_pred_high_top15,    n_pred_low_top15      (from pred_p_top15 tiers)
n_real_high, n_real_low                     (from cite_pct quartiles)
n_large_team, n_small_team                  (within-field-year team_size quartiles)
n_high_junior, n_low_junior                 (within-field-year junior_share quartiles)
"""

import os
import sys
import time

import polars as pl

SRC = "../output/scoring/scored_papers_2010_2019.parquet"
DST_PARQ = "../temp/pi_year_pred_tiers.parquet"
DST_DTA = "../temp/pi_year_pred_tiers.dta"


def tier_within(df, score_col, tier_col):
    rk_col = f"__rk_{tier_col}"
    return (
        df.with_columns(
            (
                pl.col(score_col).rank("average").over(["field", "year"])
                / pl.col(score_col).count().over(["field", "year"])
            ).alias(rk_col)
        )
        .with_columns(
            pl.when(pl.col(rk_col).is_null())
            .then(None)
            .when(pl.col(rk_col) >= 0.75)
            .then(pl.lit("high"))
            .when(pl.col(rk_col) <= 0.25)
            .then(pl.lit("low"))
            .otherwise(pl.lit("mid"))
            .alias(tier_col)
        )
        .drop(rk_col)
    )


def main():
    if not os.path.exists(SRC):
        sys.exit(f"ERROR: missing input {SRC}; run step 04 first")

    t0 = time.time()
    print(f"reading {SRC}", flush=True)
    df = pl.read_parquet(SRC)
    print(f"   {df.height:,} scored rows", flush=True)

    # Realized tier from cite_pct (already a percentile in [0,1]).
    df = df.with_columns(
        real_tier=pl.when(pl.col("cite_pct").is_null())
        .then(None)
        .when(pl.col("cite_pct") >= 0.75)
        .then(pl.lit("high"))
        .when(pl.col("cite_pct") <= 0.25)
        .then(pl.lit("low"))
        .otherwise(pl.lit("mid"))
    )

    # Team-size and junior-share tiers, within (field, year).
    df = tier_within(df, "team_size", "team_tier")
    df = tier_within(df, "junior_share", "junior_tier")

    print("collapsing to (athr_id, year)", flush=True)
    out = df.group_by(["athr_id", "year"]).agg(
        n_scored=pl.len(),
        # pred_cite_pct tiers
        n_pred_high=(pl.col("pred_tier") == "high").sum(),
        n_pred_mid=(pl.col("pred_tier") == "mid").sum(),
        n_pred_low=(pl.col("pred_tier") == "low").sum(),
        # pred_p_topdecile tiers
        n_pred_high_topdecile=(pl.col("pred_tier_topdecile") == "high").sum(),
        n_pred_low_topdecile=(pl.col("pred_tier_topdecile") == "low").sum(),
        # pred_p_top15 tiers
        n_pred_high_top15=(pl.col("pred_tier_top15") == "high").sum(),
        n_pred_low_top15=(pl.col("pred_tier_top15") == "low").sum(),
        # realized tier (from cite_pct)
        n_real_high=(pl.col("real_tier") == "high").sum(),
        n_real_low=(pl.col("real_tier") == "low").sum(),
        # team / junior composition (Phase 3.3)
        n_large_team=(pl.col("team_tier") == "high").sum(),
        n_small_team=(pl.col("team_tier") == "low").sum(),
        n_high_junior=(pl.col("junior_tier") == "high").sum(),
        n_low_junior=(pl.col("junior_tier") == "low").sum(),
    )

    cnt_cols = [c for c in out.columns if c.startswith("n_") or c == "n_scored"]
    out = out.with_columns([pl.col(c).cast(pl.Int32) for c in cnt_cols])

    print(f"   {out.height:,} (athr_id, year) cells", flush=True)

    print(f"writing {DST_PARQ}", flush=True)
    out.write_parquet(DST_PARQ, compression="snappy")

    print(f"writing {DST_DTA}", flush=True)
    # pandas.to_stata is the easiest path; ~200k rows handles fine.
    out.to_pandas().to_stata(DST_DTA, write_index=False, version=118)

    print(f"done in {time.time() - t0:.1f}s", flush=True)


if __name__ == "__main__":
    main()
