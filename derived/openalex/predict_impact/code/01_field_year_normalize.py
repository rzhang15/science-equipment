"""
01_field_year_normalize.py

For every (paper, athr_id) row, compute the citation percentile within the
(author's cluster_30 field, publication year) bucket and the two binary impact
targets.

Inputs
------
../temp/papers_all.parquet                              (from step 00)
../external/clusters/author_static_clusters_30.csv      (athr_id -> cluster_label)

Output
------
../temp/paper_athr_field_year_pct.parquet

Columns
-------
id, athr_id, year, field, jrnl, avg_cite_yr,
cite_pct        rank(avg_cite_yr) / N within (field, year)
y_topdecile     cite_pct >= 0.9
y_top15         jrnl in TOP_JRNLS

Notes
-----
- field is attached at the author-row level: every (paper, athr_id) row inherits
  the author's k=30 cluster. Same convention the PI-year panel uses via affl_wt.
- Authors not in the cluster file are dropped (they'd be unrankable without a
  field). Reports the drop rate.
- avg_cite_yr is null for rows where years_since_pub is 0 in clean_ls_samp; we
  leave their cite_pct / y_topdecile as null and exclude them from training in
  step 03.
- TOP_JRNLS mirrors derived/openalex/make_jrnl_cuts/code/build.do line 16
  (the list is "top 15" but contains 19 journals; keep them all to match).
"""

import os
import sys
import time

import polars as pl

PAPERS = "../temp/papers_all.parquet"
# k=30 US-specific clusters (us_cluster_fields). Non-US authors have no cluster
# label here and get dropped from the field-year normalization.
CLUSTERS = "../external/clusters/author_static_clusters_30.csv"
DST = "../temp/paper_athr_field_year_pct.parquet"

# Mirror make_jrnl_cuts/code/build.do line 16.
TOP_JRNLS = [
    "Science", "Nature", "Cell", "Neuron", "Nature Genetics",
    "Nature Medicine", "Nature Biotechnology", "Nature Neuroscience",
    "Nature Cell Biology", "Nature Chemical Biology",
    "Cell stem cell", "PLoS ONE", "Journal of Biological Chemistry",
    "Oncogene", "The FASEB Journal",
    "BMJ", "JAMA", "New England Journal of Medicine", "The Lancet",
]


def main():
    for path in (PAPERS, CLUSTERS):
        if not os.path.exists(path):
            sys.exit(f"ERROR: missing input {path}")

    t0 = time.time()

    print(f"reading clusters {CLUSTERS}", flush=True)
    clusters = (
        pl.read_csv(CLUSTERS, schema_overrides={"cluster_label": pl.Int32})
        .rename({"cluster_label": "field"})
        .select(["athr_id", "field"])
        .unique(subset=["athr_id"])
    )
    print(f"   {clusters.height:,} authors", flush=True)

    print(f"reading papers {PAPERS}", flush=True)
    papers = pl.read_parquet(
        PAPERS,
        columns=["id", "athr_id", "year", "jrnl", "avg_cite_yr"],
    )
    n0 = papers.height
    print(f"   {n0:,} paper-author rows", flush=True)

    # inner join drops rows without a cluster; report
    papers = papers.join(clusters, on="athr_id", how="inner")
    print(
        f"   after cluster join: {papers.height:,} rows "
        f"(dropped {n0 - papers.height:,} = {100 * (1 - papers.height / n0):.1f}%)",
        flush=True,
    )

    # Per (field, year): rank(avg_cite_yr) / N. Nulls in avg_cite_yr -> null cite_pct.
    print("computing field-year citation percentile", flush=True)
    papers = papers.with_columns(
        n_in_bucket=pl.col("avg_cite_yr").count().over(["field", "year"]),
        rank_in_bucket=pl.col("avg_cite_yr").rank("average").over(["field", "year"]),
    ).with_columns(
        cite_pct=pl.when(pl.col("n_in_bucket") > 0)
        .then(pl.col("rank_in_bucket") / pl.col("n_in_bucket"))
        .otherwise(None),
    )

    print("building binary targets", flush=True)
    papers = papers.with_columns(
        y_topdecile=(pl.col("cite_pct") >= 0.9).cast(pl.Int8),
        y_top15=pl.col("jrnl").is_in(TOP_JRNLS).cast(pl.Int8),
    )

    out = papers.select(
        [
            "id",
            "athr_id",
            "year",
            "field",
            "jrnl",
            "avg_cite_yr",
            "cite_pct",
            "y_topdecile",
            "y_top15",
        ]
    )

    # Sanity reports
    n_null = out.filter(pl.col("cite_pct").is_null()).height
    n_top15 = out.filter(pl.col("y_top15") == 1).height
    n_top10 = out.filter(pl.col("y_topdecile") == 1).height
    print(
        f"   cite_pct null rows: {n_null:,} ({100 * n_null / out.height:.2f}%)",
        flush=True,
    )
    print(
        f"   y_top15  positive rate: {100 * n_top15 / out.height:.3f}%",
        flush=True,
    )
    print(
        f"   y_topdecile positive rate: {100 * n_top10 / out.height:.3f}% "
        f"(expected ~10%)",
        flush=True,
    )

    print(f"writing {DST}", flush=True)
    out.write_parquet(DST, compression="snappy")
    print(f"done in {time.time() - t0:.1f}s", flush=True)


if __name__ == "__main__":
    main()
