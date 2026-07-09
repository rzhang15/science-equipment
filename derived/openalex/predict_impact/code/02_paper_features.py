"""
02_paper_features.py

Builds paper-level ex-ante features (one row per paper id). These vary across
papers but are constant across the author-rows of the same paper; the within-PI
variation they introduce is exactly what Variant A could not deliver.

Inputs
------
../temp/papers_all.parquet                              (from step 00)
../external/clusters/author_static_clusters_30.csv      (athr_id -> cluster_label)
../external/ipeds/ipeds_openalex.csv                    (inst_id -> R1/R2)

Output
------
../temp/paper_features.parquet

Columns
-------
id                      paper id
team_size               distinct athr_id on the paper
junior_share            share of authors with (year - first_pub_year) < 5
cross_cluster_team      distinct cluster_30 values among authors
paper_modal_cluster     modal cluster_30 among authors (first mode on ties)
multi_inst              distinct inst_id among authors
has_r1_author           1 if any author at an R1 institution

Notes
-----
- first_pub_year per author is computed over the FULL panel (no pre-2014
  restriction here -- that restriction goes in step 02c where we assemble the
  training table). The feature itself is ex-ante for the paper because we
  compare paper.year to athr_first_pub_year.
- has_r1_author is paper-level; institution attributed via inst_id on the
  paper-author row, then OR'd across authors.
- Authors not in the cluster file get null field; cross_cluster_team and
  paper_modal_cluster ignore those rows. The k=30 US-specific cluster file
  from us_cluster_fields covers only US-affiliated authors, so non-US
  co-authors on the same paper drop out of these two aggregates.
"""

import os
import sys
import time

import polars as pl

PAPERS = "../temp/papers_all.parquet"
# k=30 US-specific clusters (us_cluster_fields). Non-US authors get null field
# and are excluded from cross_cluster_team / paper_modal_cluster.
CLUSTERS = "../external/clusters/author_static_clusters_30.csv"
IPEDS = "../external/ipeds/ipeds_openalex.csv"
DST = "../temp/paper_features.parquet"

JUNIOR_WINDOW = 5  # years since first publication


def main():
    for path in (PAPERS, CLUSTERS, IPEDS):
        if not os.path.exists(path):
            sys.exit(f"ERROR: missing input {path}")

    t0 = time.time()

    print(f"reading papers {PAPERS}", flush=True)
    papers = pl.read_parquet(
        PAPERS, columns=["id", "athr_id", "year", "inst_id"]
    )
    print(f"   {papers.height:,} paper-author rows", flush=True)

    print(f"reading clusters {CLUSTERS}", flush=True)
    clusters = (
        pl.read_csv(CLUSTERS, schema_overrides={"cluster_label": pl.Int32})
        .rename({"cluster_label": "field"})
        .select(["athr_id", "field"])
        .unique(subset=["athr_id"])
    )

    print(f"reading ipeds {IPEDS}", flush=True)
    ipeds = (
        pl.read_csv(IPEDS, columns=["inst_id", "type"])
        .with_columns(
            r1_flag=(pl.col("type").str.to_lowercase() == "r1").cast(pl.Int8)
        )
        .select(["inst_id", "r1_flag"])
        .unique(subset=["inst_id"])
    )

    print("computing first publication year per author", flush=True)
    athr_first = (
        papers.group_by("athr_id")
        .agg(athr_first_pub_year=pl.col("year").min())
    )

    print("joining cluster + ipeds + first_pub_year onto paper-author rows", flush=True)
    df = (
        papers.join(clusters, on="athr_id", how="left")
        .join(ipeds, on="inst_id", how="left")
        .join(athr_first, on="athr_id", how="left")
        .with_columns(
            is_junior=(
                (pl.col("year") - pl.col("athr_first_pub_year")) < JUNIOR_WINDOW
            ).cast(pl.Int8),
            r1_flag=pl.col("r1_flag").fill_null(0),
        )
    )

    print("collapsing to paper level", flush=True)
    paper_features = df.group_by("id").agg(
        team_size=pl.col("athr_id").n_unique(),
        junior_share=pl.col("is_junior").mean(),
        cross_cluster_team=pl.col("field").drop_nulls().n_unique(),
        paper_modal_cluster=pl.col("field").drop_nulls().mode().first(),
        multi_inst=pl.col("inst_id").drop_nulls().n_unique(),
        has_r1_author=pl.col("r1_flag").max(),
    )

    # Sanity
    print(
        f"   paper rows: {paper_features.height:,}",
        flush=True,
    )
    s = paper_features.select(
        [
            pl.col("team_size").mean().alias("mean_team_size"),
            pl.col("team_size").median().alias("med_team_size"),
            pl.col("team_size").max().alias("max_team_size"),
            pl.col("junior_share").mean().alias("mean_junior_share"),
            pl.col("cross_cluster_team").mean().alias("mean_cross_cluster"),
            pl.col("multi_inst").mean().alias("mean_multi_inst"),
            pl.col("has_r1_author").mean().alias("share_has_r1"),
        ]
    )
    print(s, flush=True)

    print(f"writing {DST}", flush=True)
    paper_features.write_parquet(DST, compression="snappy")
    print(f"done in {time.time() - t0:.1f}s", flush=True)


if __name__ == "__main__":
    main()
