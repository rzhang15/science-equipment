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
../temp/pi_svd_features.parquet             (from step 02e; optional)
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
             mean_mesh_alltime_freq
PI-level:    mean_cite_pct_pre, mean_cite_pct_pre_loo,
             total_pubs_pre, total_pubs_pre_loo,
             top15_count_pre, top15_count_pre_loo,
             min_year, pubs_per_yr_pre, pubs_per_yr_pre_loo,
             pi_cluster, r1_share_pre, n_coauthors_pre,
             pi_modal_cluster_pre2013,
             pi_svd_1 ... pi_svd_20  (from 02e; author topic-mix embedding)
paper x PI:  topic_distance_from_PI_core

Notes
-----
- pi_modal_cluster_pre2013 is built here (not in 02b) because it needs
  paper_modal_cluster from step 02.
- We do NOT filter null cite_pct here -- scoring (step 04) needs every row.
  Training (step 03) drops rows whose label is null.
- The four *_loo variants are the leave-one-paper-out versions used for
  training (year < 2014). Without them the row's own cite_pct / y_top15 is
  baked into the "PI mean" feature: for authors with few pre-2014 papers this
  is near-perfect target leakage, which is why mean_cite_pct_pre carried 94%
  of the LGBM gain in the previous iteration. For scoring rows (year >= 2014)
  the row is not in the pre-2014 pool, so the LOO adjustment is identity and
  we just copy the full-pool value. Step 03 uses the *_loo columns; step 04
  (scoring) uses them too because for post-2014 rows they equal the full mean.
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
PI_SVD_FEATS = "../temp/pi_svd_features.parquet"
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
    if os.path.exists(PI_SVD_FEATS):
        pi_svd = pl.read_parquet(PI_SVD_FEATS)
        print(f"   PI SVD features loaded: {pi_svd.height:,} authors, "
              f"{len(pi_svd.columns) - 1} dims", flush=True)
    else:
        print("   PI SVD features not found -- proceeding without them", flush=True)
        pi_svd = None

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
    if pi_svd is not None:
        # Cast athr_id to the same dtype in case parquet trip changed it.
        pi_svd = pi_svd.with_columns(pl.col("athr_id").cast(df["athr_id"].dtype))
        df = df.join(pi_svd, on="athr_id", how="left")
        svd_cols = [c for c in pi_svd.columns if c.startswith("pi_svd_")]
        matched = df.filter(pl.col(svd_cols[0]).is_not_null()).height
        print(
            f"   PI SVD merged onto {matched:,} / {df.height:,} rows "
            f"({100 * matched / df.height:.1f}%)",
            flush=True,
        )

    print("computing topic_distance_from_PI_core", flush=True)
    df = df.with_columns(
        topic_distance_from_PI_core=(
            pl.col("paper_modal_cluster") != pl.col("pi_modal_cluster_pre2013")
        ).cast(pl.Int8)
    )

    print("building leave-one-paper-out PI features for pre-2014 rows", flush=True)
    # For pre-2014 rows, the row's own cite_pct / y_top15 is baked into the PI
    # aggregate; we subtract it to get the LOO version. For post-2014 rows the
    # aggregate does not contain the row, so LOO == full-pool value.
    is_pre = pl.col("year") < 2014
    y_top15_row = pl.col("y_top15").cast(pl.Int64).fill_null(0)

    # mean_cite_pct_pre_loo: (sum - row's cite_pct) / (n_nonnull - 1)
    # nulls-only handling: row with null cite_pct is not in the sum/count, so
    # LOO reduces to the full mean.
    sum_pre = pl.col("sum_cite_pct_pre")
    n_pre = pl.col("n_nonnull_cite_pct_pre")
    denom_loo = pl.when(pl.col("cite_pct").is_not_null())
    denom = pl.when(is_pre).then(
        denom_loo.then(n_pre - 1).otherwise(n_pre)
    ).otherwise(n_pre)
    numer = pl.when(is_pre).then(
        denom_loo.then(sum_pre - pl.col("cite_pct")).otherwise(sum_pre)
    ).otherwise(sum_pre)
    mean_loo = pl.when(denom > 0).then(numer / denom).otherwise(None)

    total_pubs_loo = pl.when(is_pre).then(
        (pl.col("total_pubs_pre") - 1).clip(lower_bound=0)
    ).otherwise(pl.col("total_pubs_pre"))
    top15_loo = pl.when(is_pre).then(
        pl.col("top15_count_pre") - y_top15_row
    ).otherwise(pl.col("top15_count_pre"))

    yrs_active = pl.max_horizontal(
        (2013 - pl.col("min_year") + 1).cast(pl.Float64),
        pl.lit(1.0),
    )
    df = df.with_columns(
        mean_cite_pct_pre_loo=mean_loo,
        total_pubs_pre_loo=total_pubs_loo,
        top15_count_pre_loo=top15_loo,
    ).with_columns(
        pubs_per_yr_pre_loo=pl.col("total_pubs_pre_loo") / yrs_active
    )

    # Sanity: for pre-2014 rows the LOO mean should differ from the raw mean;
    # for post-2014 rows it should equal it exactly.
    pre_diff = df.filter(is_pre & pl.col("cite_pct").is_not_null()).select(
        (pl.col("mean_cite_pct_pre_loo") - pl.col("mean_cite_pct_pre"))
        .abs().mean().alias("mean_abs_shift")
    )
    post_diff = df.filter(~is_pre).select(
        (pl.col("mean_cite_pct_pre_loo") - pl.col("mean_cite_pct_pre"))
        .abs().max().alias("max_abs_shift_post")
    )
    print(f"   pre-2014 mean|LOO - full| = {pre_diff.item():.5f}", flush=True)
    print(f"   post-2014 max|LOO - full| = {post_diff.item()}", flush=True)

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
