"""
Impute exposure using within-cluster weight matrices.

Applies W @ E where W is the within-cluster weight matrix from
2_similarity_wts_within_cluster.py. Each universe author's imputed exposure
comes from a weighted average of FOIAs in their assigned cluster only.

Usage:
  python 3_impute_exposure_within_cluster.py --tag restricted

Output:
  output/final_imputed_exposure_within_cluster_{tag}.csv
  output/final_imputed_shift_share_within_cluster_{tag}.csv
"""
import argparse
import os
import numpy as np
import pandas as pd
import scipy.sparse

OUT_DIR = "../../output"
USER_EXPOSURE_FILE = "../../external/exposure_wts/athr_exposure.dta"

IMPUTE_VARS = ["exposure", "mkt_spend_shr", "hc_spend_shr"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="restricted",
                    help="Tag matching prior clustering (default 'restricted').")
    ap.add_argument("--min-max-sim", type=float, default=0.0,
                    help="Drop universe authors with max_sim below this. "
                         "Default 0.0 = keep all.")
    args = ap.parse_args()

    tag = args.tag
    if tag and not tag.startswith("_"):
        tag = "_" + tag

    weights_file = f"{OUT_DIR}/weight_matrix_within_cluster{tag}.npz"
    universe_ids_file = f"{OUT_DIR}/universe_ids{tag}.parquet"
    foia_ids_file = f"{OUT_DIR}/foia_ids_ordered{tag}.csv"
    diag_file = f"{OUT_DIR}/match_diagnostics_within_cluster{tag}.parquet"

    out_suffix = ""
    if args.min_max_sim > 0:
        out_suffix += f"_ms{int(round(args.min_max_sim * 100)):03d}"
    output_file = f"{OUT_DIR}/final_imputed_exposure_within_cluster{tag}{out_suffix}.csv"

    # Check inputs
    for p in (weights_file, universe_ids_file, foia_ids_file, USER_EXPOSURE_FILE):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")

    print(f"Loading Pre-Computed Weights (within-cluster, tag={args.tag!r})...")
    W = scipy.sparse.load_npz(weights_file)
    print(f"  W shape: {W.shape}  nnz: {W.nnz:,}")

    print("Loading IDs...")
    df_univ_ids = pd.read_parquet(universe_ids_file)
    df_foia_ids = pd.read_csv(foia_ids_file)

    print("Aligning Exposure Data...")
    df_values = pd.read_stata(USER_EXPOSURE_FILE)
    df_aligned = pd.merge(df_foia_ids, df_values, on='athr_id', how='left')

    missing = [v for v in IMPUTE_VARS if v not in df_aligned.columns]
    if missing:
        raise SystemExit(f"IMPUTE_VARS missing from {USER_EXPOSURE_FILE}: {missing}")

    print(f"Imputing {IMPUTE_VARS} via W.dot()...")
    for var in IMPUTE_VARS:
        E = df_aligned[var].fillna(0).to_numpy()
        imputed = W.dot(E)
        df_univ_ids[var] = imputed
        nz = (imputed != 0).sum()
        print(f"  {var}: mean={imputed.mean():.5f}  sd={imputed.std():.5f}  "
              f"nonzero={nz:,}/{len(imputed):,}")

    if args.min_max_sim > 0:
        if not os.path.exists(diag_file):
            raise SystemExit(f"--min-max-sim needs {diag_file}; run 2_similarity_wts_within_cluster.py first.")
        diag = pd.read_parquet(diag_file)[["athr_id", "max_sim_to_cluster"]]
        n_before = len(df_univ_ids)
        df_univ_ids = df_univ_ids.merge(diag, on="athr_id", how="left")
        n_no_sim = df_univ_ids["max_sim_to_cluster"].isna().sum()
        keep_mask = df_univ_ids["max_sim_to_cluster"] >= args.min_max_sim
        df_univ_ids = df_univ_ids.loc[keep_mask].drop(columns=["max_sim_to_cluster"])
        print(f"\nmax_sim filter (>= {args.min_max_sim}):")
        print(f"  authors dropped: {n_before - len(df_univ_ids):,} of {n_before:,} "
              f"({100*(n_before-len(df_univ_ids))/n_before:.2f}%)")
        print(f"  authors kept:    {len(df_univ_ids):,}")

    df_univ_ids.to_csv(output_file, index=False)
    print(f"Done! Saved to {output_file}")


if __name__ == "__main__":
    main()
