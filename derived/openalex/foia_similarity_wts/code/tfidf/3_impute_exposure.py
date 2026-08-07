import argparse
import os
import numpy as np
import pandas as pd
import scipy.sparse

OUT_DIR = "../../output"
EXPOSURE_DIR = "../../external/exposure_wts"

# Three FOIA-level exposure files from derived/exposure_msr, differing only in
# the denominator used to build mkt_spend_shr (and therefore exposure):
#   hc         : denominator = high-confidence markets   (keep == 1)
#   all        : denominator = all consumable markets    (no restriction)
#   treated_hc : denominator = treated HC markets        (keep == 1 & treated == 1)
#                -> mkt_spend_shr sums to 1 per FOIA by construction
# Downstream code expects columns literally named `exposure` and
# `mkt_spend_shr`, so we write one output CSV per version rather than
# suffixing columns.
VERSIONS = ["hc", "all", "treated_hc"]

# Per-PI scalar variables to impute onto the universe via W.dot(.). All are
# read from each version's DTA keyed on athr_id; missing values are filled
# with 0 before the matmul. `mkt_spend_shr` is included so downstream DiD
# can control for incomplete-shares (analog of the s_it term in
# expenditure_by_athr).
IMPUTE_VARS = ["exposure", "mkt_spend_shr", "hc_spend_shr"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="",
                    help="Suffix matching the --tag used by 1_vectorize.py and "
                         "2_similarity_wts.py. Empty = baseline artifacts.")
    ap.add_argument("--rescale", choices=["none", "rowsum", "confidence"],
                    default="none",
                    help="Post-hoc rescaling of imputed values. "
                         "'none' (default): imputed = W @ E exactly as before "
                         "(weighted average if W was L1-normalized; "
                         "similarity-scaled sum otherwise). "
                         "'rowsum': divide W @ E by W.row-sum, recovering a "
                         "weighted average from non-L1 weights (use when step 2 "
                         "ran with --no-l1-normalize but you still want averages). "
                         "'confidence': multiply by per-author max-similarity from "
                         "the diagnostics file — preserves cross-PI variance by "
                         "shrinking low-confidence imputations toward zero.")
    ap.add_argument("--cluster-filter", default="",
                    help="Path to author_static_clusters_K.csv from "
                         "openalex/us_cluster_fields. After imputation, drop universe "
                         "authors whose K-cluster contains fewer FOIA PIs than "
                         "--min-foia-per-cluster — those imputations rest on "
                         "out-of-domain TF-IDF vocabulary overlap, not real "
                         "topical similarity. Also drops authors with no cluster "
                         "assignment.")
    ap.add_argument("--min-foia-per-cluster", type=int, default=1,
                    help="Minimum FOIA count required for a cluster to be kept "
                         "under --cluster-filter. Default 1: drops only fully "
                         "empty clusters (backward-compatible). Set 5 to keep "
                         "only 'FOIA-rich' clusters, matching "
                         "cluster_sanity_check.py's tiering (own-cluster W share "
                         "is well above chance there; thin 1-4 FOIA clusters "
                         "have median own-share 0).")
    ap.add_argument("--min-max-sim", type=float, default=0.0,
                    help="Drop universe authors whose max cosine to any FOIA PI is "
                         "below this threshold. Authors below the threshold get "
                         "imputed_exposure=0 by the W @ E identity (no surviving "
                         "neighbors above 2_similarity_wts.py's floor), so they "
                         "are not really being imputed — they're being defaulted to "
                         "zero. The holdout-FOIA stress test shows positive R² "
                         "only above max_sim ~ 0.22; use that (or higher) here "
                         "to keep only authors the imputation actually predicts. "
                         "Default 0.0 = keep all (backward compatible).")
    ap.add_argument("--versions", nargs="+", default=VERSIONS, choices=VERSIONS,
                    help="Which exposure-denominator versions to impute. "
                         "Default: all three (hc, all, treated_hc). Each version "
                         "reads athr_exposure_{version}.dta and writes a separate "
                         "final_imputed_exposure_{version}{tag}{suffix}.csv.")
    args = ap.parse_args()

    tag = args.tag
    if tag and not tag.startswith("_"):
        tag = "_" + tag

    weights_file      = f"{OUT_DIR}/weight_matrix{tag}.npz"
    universe_ids_file = f"{OUT_DIR}/universe_ids{tag}.parquet"
    foia_ids_file     = f"{OUT_DIR}/foia_ids_ordered{tag}.csv"
    diag_file         = f"{OUT_DIR}/match_diagnostics{tag}.parquet"
    out_suffix = ""
    if args.cluster_filter:
        out_suffix += "_cf" if args.min_foia_per_cluster <= 1 else f"_cf{args.min_foia_per_cluster}"
    if args.min_max_sim > 0:
        # Tag with the threshold so different cutoffs coexist as outputs.
        # _ms020 = 0.20, _ms022 = 0.22, etc.
        out_suffix += f"_ms{int(round(args.min_max_sim * 100)):03d}"

    for p in (weights_file, universe_ids_file, foia_ids_file):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")
    for v in args.versions:
        f = f"{EXPOSURE_DIR}/athr_exposure_{v}.dta"
        if not os.path.exists(f):
            raise SystemExit(f"missing exposure file for version {v!r}: {f}")

    print(f"Loading Pre-Computed Weights (tag={args.tag!r}, rescale={args.rescale})...")
    W = scipy.sparse.load_npz(weights_file)
    print(f"  W shape: {W.shape}  nnz: {W.nnz:,}")
    print("Loading IDs...")
    df_univ_ids_base = pd.read_parquet(universe_ids_file)
    df_foia_ids = pd.read_csv(foia_ids_file)

    # Pre-compute rescale factor if needed (identical across versions since W
    # doesn't change).
    rescale_vec = None
    if args.rescale == "rowsum":
        row_sums = np.asarray(W.sum(axis=1)).ravel()
        rescale_vec = np.where(row_sums > 0, 1.0 / row_sums, 0.0)
    elif args.rescale == "confidence":
        if not os.path.exists(diag_file):
            raise SystemExit(f"missing diagnostics file for --rescale confidence: {diag_file}")
        diag = pd.read_parquet(diag_file)
        # Align by athr_id to be safe even if ordering matches.
        diag = diag.set_index("athr_id").loc[df_univ_ids_base["athr_id"].values]
        rescale_vec = diag["max_sim"].to_numpy()

    # Pre-load filter inputs once (shared across versions).
    diag_maxsim = None
    if args.min_max_sim > 0:
        if not os.path.exists(diag_file):
            raise SystemExit(f"--min-max-sim needs {diag_file}; run 2_similarity_wts.py first.")
        diag_maxsim = pd.read_parquet(diag_file)[["athr_id", "max_sim"]]

    cluster_info = None
    if args.cluster_filter:
        cl = pd.read_csv(args.cluster_filter)
        if "cluster_label" not in cl.columns or "athr_id" not in cl.columns:
            raise SystemExit(
                f"--cluster-filter file must have columns [athr_id, cluster_label]: "
                f"got {list(cl.columns)}"
            )
        min_n = args.min_foia_per_cluster
        foia_counts = (
            df_foia_ids.merge(cl, on="athr_id", how="inner")["cluster_label"]
            .value_counts()
        )
        kept_clusters  = set(foia_counts[foia_counts >= min_n].index)
        thin_clusters  = set(foia_counts[foia_counts < min_n].index)
        empty_clusters = set(cl["cluster_label"].unique()) - set(foia_counts.index)
        print(f"\nCluster filter: {args.cluster_filter}  (min-foia-per-cluster={min_n})")
        print(f"  total clusters: {cl['cluster_label'].nunique()}  "
              f"kept (>={min_n} FOIA): {len(kept_clusters)}  "
              f"thin (1-{min_n-1} FOIA): {len(thin_clusters)}  "
              f"empty: {len(empty_clusters)}")
        cluster_info = (cl, kept_clusters, thin_clusters, empty_clusters, min_n)

    for version in args.versions:
        exposure_file = f"{EXPOSURE_DIR}/athr_exposure_{version}.dta"
        output_file   = f"{OUT_DIR}/final_imputed_exposure_{version}{tag}{out_suffix}.csv"
        print(f"\n========== version={version} ==========")
        print(f"Aligning exposure data from {exposure_file}...")
        df_values  = pd.read_stata(exposure_file)
        df_aligned = pd.merge(df_foia_ids, df_values, on="athr_id", how="left")

        missing = [v for v in IMPUTE_VARS if v not in df_aligned.columns]
        if missing:
            raise SystemExit(f"IMPUTE_VARS missing from {exposure_file}: {missing}")

        df_out = df_univ_ids_base.copy()
        print(f"Imputing {IMPUTE_VARS} via W.dot()...")
        for var in IMPUTE_VARS:
            E = df_aligned[var].fillna(0).to_numpy()
            imputed = W.dot(E)
            if rescale_vec is not None:
                imputed = imputed * rescale_vec
            df_out[var] = imputed
            nz = (imputed != 0).sum()
            print(f"  {var}: mean={imputed.mean():.5f}  sd={imputed.std():.5f}  "
                  f"nonzero={nz:,}/{len(imputed):,}")

        if diag_maxsim is not None:
            n_before = len(df_out)
            df_out = df_out.merge(diag_maxsim, on="athr_id", how="left")
            n_no_sim = df_out["max_sim"].isna().sum()
            keep_mask = df_out["max_sim"] >= args.min_max_sim
            df_out = df_out.loc[keep_mask].drop(columns=["max_sim"])
            print(f"max_sim filter (>= {args.min_max_sim}): "
                  f"dropped {n_before - len(df_out):,}/{n_before:,} "
                  f"({100*(n_before-len(df_out))/n_before:.2f}%)  "
                  f"(no max_sim: {n_no_sim:,})")

        if cluster_info is not None:
            cl, kept_clusters, thin_clusters, empty_clusters, min_n = cluster_info
            n_before = len(df_out)
            df_out = df_out.merge(cl, on="athr_id", how="left")
            n_no_cluster = int(df_out["cluster_label"].isna().sum())
            cluster_col = df_out["cluster_label"]
            keep_mask   = cluster_col.notna() & cluster_col.isin(kept_clusters)
            n_in_thin   = int((cluster_col.notna() & cluster_col.isin(thin_clusters)).sum())
            n_in_empty  = int((cluster_col.notna() & cluster_col.isin(empty_clusters)).sum())
            df_out = df_out.loc[keep_mask].drop(columns=["cluster_label"])
            print(f"cluster filter: dropped {n_before - len(df_out):,}/{n_before:,} "
                  f"({100*(n_before-len(df_out))/n_before:.2f}%)  "
                  f"(thin: {n_in_thin:,}, empty: {n_in_empty:,}, "
                  f"no cluster: {n_no_cluster:,})")

        df_out.to_csv(output_file, index=False)
        print(f"Saved {output_file}")

    print("\nDone!")


if __name__ == "__main__":
    main()
