"""
06_assemble_self_management_panel.py

Build the Phase 3 self-management variables.

Two outputs feed build.do:

1. pi_year_self_mgmt.dta  --  PI-year main-line / side-line publication counts
   (Phase 3.2). "Main line" = a 2010-2019 paper whose paper_modal_cluster
   equals the PI's pre-2013 modal paper cluster.

2. pi_static_self_mgmt.dta  --  PI-level static splits for Phase 3.1:
   - portfolio_hhi    Herfindahl over paper_modal_cluster across the PI's
                      pre-2014 papers (higher = more focused).
   - lab_size_pre     distinct pre-2014 coauthors (from pi_features.n_coauthors_pre).

(Per-pub grants are already in athr_panel via num_grants -- no new column needed
 for the grants_per_pub split; it can be built in Stata.)

Inputs
------
../output/scoring/scored_papers_2010_2019.parquet
../temp/paper_athr_field_year_pct.parquet
../temp/paper_features.parquet
../temp/pi_features.parquet
"""

import os
import sys
import time

import polars as pl

SCORED = "../output/scoring/scored_papers_2010_2019.parquet"
PCT = "../temp/paper_athr_field_year_pct.parquet"
PAPER_FEATS = "../temp/paper_features.parquet"
PI_FEATS = "../temp/pi_features.parquet"

DST_YR_PARQ = "../temp/pi_year_self_mgmt.parquet"
DST_YR_DTA = "../temp/pi_year_self_mgmt.dta"
DST_STATIC_PARQ = "../temp/pi_static_self_mgmt.parquet"
DST_STATIC_DTA = "../temp/pi_static_self_mgmt.dta"


def main():
    for path in (SCORED, PCT, PAPER_FEATS, PI_FEATS):
        if not os.path.exists(path):
            sys.exit(f"ERROR: missing input {path}; run earlier steps first")

    t0 = time.time()

    # -------- main-line vs side-line by PI-year --------
    print(f"reading {SCORED}", flush=True)
    sc = pl.read_parquet(
        SCORED,
        columns=[
            "athr_id",
            "year",
            "paper_modal_cluster",
            "pi_modal_cluster_pre2013",
        ],
    )
    sc = sc.with_columns(
        is_main_line=pl.when(pl.col("pi_modal_cluster_pre2013").is_null())
        .then(None)
        .when(
            pl.col("paper_modal_cluster") == pl.col("pi_modal_cluster_pre2013")
        )
        .then(1)
        .otherwise(0)
        .cast(pl.Int8)
    )
    yr = sc.group_by(["athr_id", "year"]).agg(
        n_main_line=(pl.col("is_main_line") == 1).sum().cast(pl.Int32),
        n_side_line=(pl.col("is_main_line") == 0).sum().cast(pl.Int32),
    )
    print(f"   {yr.height:,} (athr_id, year) cells", flush=True)
    yr.write_parquet(DST_YR_PARQ, compression="snappy")
    yr.to_pandas().to_stata(DST_YR_DTA, write_index=False, version=118)
    print(f"   wrote {DST_YR_DTA}", flush=True)

    # -------- static portfolio_hhi and lab_size_pre --------
    print("computing portfolio_hhi over pre-2014 papers", flush=True)
    pct = pl.read_parquet(PCT, columns=["id", "athr_id", "year"])
    paper_feats = pl.read_parquet(
        PAPER_FEATS, columns=["id", "paper_modal_cluster"]
    )
    pre = (
        pct.filter(pl.col("year") < 2014)
        .join(paper_feats, on="id", how="inner")
        .filter(pl.col("paper_modal_cluster").is_not_null())
        .unique(subset=["id", "athr_id"])
    )

    pc = pre.group_by(["athr_id", "paper_modal_cluster"]).agg(
        n_pc=pl.len()
    )
    tot = pc.group_by("athr_id").agg(n_tot=pl.col("n_pc").sum())
    pc = pc.join(tot, on="athr_id", how="inner").with_columns(
        share2=(pl.col("n_pc") / pl.col("n_tot")) ** 2
    )
    hhi = pc.group_by("athr_id").agg(
        portfolio_hhi=pl.col("share2").sum().cast(pl.Float64)
    )

    pi_feats = pl.read_parquet(
        PI_FEATS, columns=["athr_id", "n_coauthors_pre"]
    ).rename({"n_coauthors_pre": "lab_size_pre"})

    static = hhi.join(pi_feats, on="athr_id", how="left")
    print(f"   {static.height:,} PIs in static panel", flush=True)
    static.write_parquet(DST_STATIC_PARQ, compression="snappy")
    static.to_pandas().to_stata(DST_STATIC_DTA, write_index=False, version=118)
    print(f"   wrote {DST_STATIC_DTA}", flush=True)

    print(f"done in {time.time() - t0:.1f}s", flush=True)


if __name__ == "__main__":
    main()
