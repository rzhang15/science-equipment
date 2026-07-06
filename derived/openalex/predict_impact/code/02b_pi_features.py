"""
02b_pi_features.py

Builds PI-level (athr_id-level) ex-ante features from pre-2014 history. These
are the "track record" features that the original Variant A used in isolation;
in the revised plan they sit alongside paper-level features (step 02) so the
model can read paper-level signals over and above PI averages.

Inputs
------
../temp/paper_athr_field_year_pct.parquet   (from step 01)
../temp/papers_all.parquet                  (from step 00; for inst_id history)
../external/clusters/author_static_clusters_5.csv

Output
------
../temp/pi_features.parquet

Columns (one row per athr_id with >= 1 pre-2014 publication)
------------------------------------------------------------
athr_id
mean_cite_pct_pre       mean(cite_pct) over the PI's pre-2014 paper-author rows
total_pubs_pre          n distinct (id, athr_id) pre-2014
top15_count_pre         n pre-2014 paper-author rows with y_top15 == 1
min_year                min(year) over the full panel (PI age)
pubs_per_yr_pre         total_pubs_pre / (2013 - min_year + 1)
pi_cluster5             k=5 author cluster
r1_share_pre            share of pre-2014 paper-author rows at an R1 institution
is_r1_modal             1 if r1_share_pre >= 0.5
n_coauthors_pre         distinct coauthors observed on pre-2014 papers, capped
                        at team-size 50 to bound the self-join

The PI's modal pre-2013 cluster (used to define topic_distance_from_PI_core in
step 02c) is computed there, not here, since it needs the paper_modal_cluster
from step 02.
"""

import os
import sys
import time

import polars as pl

PCT = "../temp/paper_athr_field_year_pct.parquet"
PAPERS = "../temp/papers_all.parquet"
CLUSTERS = "../external/clusters/author_static_clusters_5.csv"
IPEDS = "../external/ipeds/ipeds_openalex.csv"
DST = "../temp/pi_features.parquet"

TEAM_CAP_FOR_COAUTH = 50  # drop consortium papers from the self-join


def main():
    for path in (PCT, PAPERS, CLUSTERS, IPEDS):
        if not os.path.exists(path):
            sys.exit(f"ERROR: missing input {path}")

    t0 = time.time()

    print(f"reading {PCT}", flush=True)
    pct = pl.read_parquet(
        PCT, columns=["id", "athr_id", "year", "cite_pct", "y_top15"]
    )

    # min_year is over the full panel (defines PI age, not restricted to pre-2014)
    print("computing min_year (full panel)", flush=True)
    min_year = pct.group_by("athr_id").agg(min_year=pl.col("year").min())

    pre = pct.filter(pl.col("year") < 2014)

    print("computing self-track-record features (pre-2014)", flush=True)
    self_feats = pre.group_by("athr_id").agg(
        mean_cite_pct_pre=pl.col("cite_pct").mean(),
        total_pubs_pre=pl.col("id").n_unique(),
        top15_count_pre=pl.col("y_top15").sum(),
    )

    pi = self_feats.join(min_year, on="athr_id", how="left").with_columns(
        pubs_per_yr_pre=pl.col("total_pubs_pre")
        / pl.max_horizontal(
            (2013 - pl.col("min_year") + 1).cast(pl.Float64),
            pl.lit(1.0),
        )
    )

    print(f"reading clusters {CLUSTERS}", flush=True)
    clusters = (
        pl.read_csv(CLUSTERS, schema_overrides={"cluster_label": pl.Int32})
        .rename({"cluster_label": "pi_cluster5"})
        .select(["athr_id", "pi_cluster5"])
        .unique(subset=["athr_id"])
    )
    pi = pi.join(clusters, on="athr_id", how="left")

    print("computing r1_share_pre from pre-2014 paper-author rows", flush=True)
    papers = pl.read_parquet(PAPERS, columns=["athr_id", "year", "inst_id"])
    papers_pre = papers.filter(pl.col("year") < 2014)

    ipeds = (
        pl.read_csv(IPEDS, columns=["inst_id", "type"])
        .with_columns(
            r1_flag=(pl.col("type").str.to_lowercase() == "r1").cast(pl.Int8)
        )
        .select(["inst_id", "r1_flag"])
        .unique(subset=["inst_id"])
    )
    papers_pre = papers_pre.join(ipeds, on="inst_id", how="left").with_columns(
        r1_flag=pl.col("r1_flag").fill_null(0)
    )
    r1 = papers_pre.group_by("athr_id").agg(
        r1_share_pre=pl.col("r1_flag").mean()
    ).with_columns(
        is_r1_modal=(pl.col("r1_share_pre") >= 0.5).cast(pl.Int8)
    )
    pi = pi.join(r1, on="athr_id", how="left")

    print(
        f"computing n_coauthors_pre via self-join "
        f"(team_size cap = {TEAM_CAP_FOR_COAUTH})",
        flush=True,
    )
    # de-duplicate (id, athr_id) within pre-2014
    ap = pre.select(["id", "athr_id"]).unique()
    team_sizes = ap.group_by("id").agg(team_size=pl.col("athr_id").n_unique())
    small_papers = team_sizes.filter(
        pl.col("team_size") <= TEAM_CAP_FOR_COAUTH
    ).select("id")
    ap_small = ap.join(small_papers, on="id", how="inner")

    ego = ap_small.rename({"athr_id": "ego"})
    alter = ap_small.rename({"athr_id": "alter"})
    pairs = ego.join(alter, on="id", how="inner").filter(
        pl.col("ego") != pl.col("alter")
    )
    n_coauth = (
        pairs.group_by("ego")
        .agg(n_coauthors_pre=pl.col("alter").n_unique())
        .rename({"ego": "athr_id"})
    )
    pi = pi.join(n_coauth, on="athr_id", how="left").with_columns(
        n_coauthors_pre=pl.col("n_coauthors_pre").fill_null(0)
    )

    print(
        f"   PI rows: {pi.height:,}",
        flush=True,
    )
    summary = pi.select(
        [
            pl.col("mean_cite_pct_pre").mean().alias("mean_meancitepct"),
            pl.col("total_pubs_pre").mean().alias("mean_totalpubs"),
            pl.col("top15_count_pre").mean().alias("mean_top15ct"),
            pl.col("pubs_per_yr_pre").mean().alias("mean_pubsperyr"),
            pl.col("r1_share_pre").mean().alias("mean_r1share"),
            pl.col("n_coauthors_pre").mean().alias("mean_ncoauth"),
        ]
    )
    print(summary, flush=True)

    print(f"writing {DST}", flush=True)
    pi.write_parquet(DST, compression="snappy")
    print(f"done in {time.time() - t0:.1f}s", flush=True)


if __name__ == "__main__":
    main()
