"""
02c_assemble_training_table.py

Assemble the full features-and-labels table covering every paper-author row in
the universe. Step 03 (training) and step 04 (scoring) both filter from this.

Inputs
------
../temp/paper_athr_field_year_pct.parquet   (from step 01; labels + field)
../temp/paper_features.parquet              (from step 02)
../temp/pi_features.parquet                 (from step 02b)
../temp/paper_mesh_features.parquet         (from step 02d; optional)
../temp/papers_all.parquet                  (from step 00; for which_athr)

Output
------
../temp/all_features.parquet

Schema
------
keys:        id, athr_id, year
labels:      cite_pct, y_topdecile, y_top15
context:     field, jrnl, avg_cite_yr, which_athr
paper-level: team_size, junior_share, cross_cluster_team,
             paper_modal_cluster, multi_inst, has_r1_author,
             n_mesh_terms, mean_mesh_year_freq, min_mesh_year_freq,
             log_min_mesh_year_freq, mean_mesh_alltime_freq
PI-level:    mean_cite_pct_pre, total_pubs_pre, top15_count_pre,
             min_year, pubs_per_yr_pre, pi_cluster5,
             r1_share_pre, is_r1_modal, n_coauthors_pre,
             pi_modal_cluster_pre2013
paper x PI:  topic_distance_from_PI_core

Notes
-----
- pi_modal_cluster_pre2013 is built here (not in 02b) because it needs
  paper_modal_cluster from step 02.
- We do NOT filter null cite_pct here -- scoring (step 04) needs every row.
  Training (step 03) drops rows whose label is null.
"""

import os
import sys
import time

import polars as pl

PCT = "../temp/paper_athr_field_year_pct.parquet"
PAPER_FEATS = "../temp/paper_features.parquet"
PI_FEATS = "../temp/pi_features.parquet"
PAPERS = "../temp/papers_all.parquet"
MESH_FEATS = "../temp/paper_mesh_features.parquet"
DST = "../temp/all_features.parquet"


def main():
    for path in (PCT, PAPER_FEATS, PI_FEATS, PAPERS):
        if not os.path.exists(path):
            sys.exit(f"ERROR: missing input {path}")

    t0 = time.time()

    print("loading inputs", flush=True)
    pct = pl.read_parquet(PCT)
    paper_feats = pl.read_parquet(PAPER_FEATS)
    pi_feats = pl.read_parquet(PI_FEATS)
    papers = (
        pl.read_parquet(PAPERS, columns=["id", "athr_id", "which_athr"])
        .unique(subset=["id", "athr_id"])
    )
    if os.path.exists(MESH_FEATS):
        mesh_feats = pl.read_parquet(MESH_FEATS)
        print(f"   mesh features loaded: {mesh_feats.height:,} papers", flush=True)
    else:
        print("   mesh features not found -- proceeding without them", flush=True)
        mesh_feats = None

    print("computing pi_modal_cluster_pre2013", flush=True)
    pre = pct.filter(pl.col("year") < 2014).select(["id", "athr_id"])
    pre_with_pmc = pre.join(
        paper_feats.select(["id", "paper_modal_cluster"]), on="id", how="inner"
    )
    pi_modal = pre_with_pmc.group_by("athr_id").agg(
        pi_modal_cluster_pre2013=pl.col("paper_modal_cluster")
        .drop_nulls()
        .mode()
        .first()
    )
    pi_feats = pi_feats.join(pi_modal, on="athr_id", how="left")

    print("joining paper + PI features onto label rows", flush=True)
    df = (
        pct.join(paper_feats, on="id", how="left")
        .join(pi_feats, on="athr_id", how="left")
        .join(papers, on=["id", "athr_id"], how="left")
    )
    if mesh_feats is not None:
        df = df.join(mesh_feats, on="id", how="left")

    print("computing topic_distance_from_PI_core", flush=True)
    df = df.with_columns(
        topic_distance_from_PI_core=(
            pl.col("paper_modal_cluster") != pl.col("pi_modal_cluster_pre2013")
        ).cast(pl.Int8)
    )

    print(f"   total rows: {df.height:,}", flush=True)
    print(
        f"   rows w/ non-null label (cite_pct): "
        f"{df.filter(pl.col('cite_pct').is_not_null()).height:,}",
        flush=True,
    )
    print(
        f"   rows w/ non-null pi feats:        "
        f"{df.filter(pl.col('mean_cite_pct_pre').is_not_null()).height:,}",
        flush=True,
    )

    print(f"writing {DST}", flush=True)
    df.write_parquet(DST, compression="snappy")
    print(f"done in {time.time() - t0:.1f}s", flush=True)


if __name__ == "__main__":
    main()
