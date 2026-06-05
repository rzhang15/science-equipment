import argparse
import os
import numpy as np
import pandas as pd
import scipy.sparse

OUT_DIR = "../../output"
USER_EXPOSURE_FILE = "../../external/exposure_wts/athr_exposure.dta"

# Per-PI scalar variables to impute onto the universe via W.dot(.). All are
# read from USER_EXPOSURE_FILE keyed on athr_id; missing values are filled
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
    args = ap.parse_args()

    tag = args.tag
    if tag and not tag.startswith("_"):
        tag = "_" + tag

    weights_file      = f"{OUT_DIR}/weight_matrix{tag}.npz"
    universe_ids_file = f"{OUT_DIR}/universe_ids{tag}.parquet"
    foia_ids_file     = f"{OUT_DIR}/foia_ids_ordered{tag}.csv"
    diag_file         = f"{OUT_DIR}/match_diagnostics{tag}.parquet"
    output_file       = f"{OUT_DIR}/final_imputed_exposure{tag}.csv"

    if not os.path.exists(USER_EXPOSURE_FILE):
        raise SystemExit("Please create your exposure CSV first!")
    for p in (weights_file, universe_ids_file, foia_ids_file):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")

    print(f"Loading Pre-Computed Weights (tag={args.tag!r}, rescale={args.rescale})...")
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

    # Pre-compute rescale factor if needed.
    rescale_vec = None
    if args.rescale == "rowsum":
        import numpy as np
        row_sums = np.asarray(W.sum(axis=1)).ravel()
        rescale_vec = np.where(row_sums > 0, 1.0 / row_sums, 0.0)
    elif args.rescale == "confidence":
        if not os.path.exists(diag_file):
            raise SystemExit(f"missing diagnostics file for --rescale confidence: {diag_file}")
        diag = pd.read_parquet(diag_file)
        # Align by athr_id to be safe even if ordering matches.
        diag = diag.set_index("athr_id").loc[df_univ_ids["athr_id"].values]
        rescale_vec = diag["max_sim"].to_numpy()

    print(f"Imputing {IMPUTE_VARS} via W.dot()...")
    for var in IMPUTE_VARS:
        E = df_aligned[var].fillna(0).to_numpy()
        imputed = W.dot(E)
        if rescale_vec is not None:
            imputed = imputed * rescale_vec
        df_univ_ids[var] = imputed
        nz = (imputed != 0).sum()
        print(f"  {var}: mean={imputed.mean():.5f}  sd={imputed.std():.5f}  "
              f"nonzero={nz:,}/{len(imputed):,}")

    df_univ_ids.to_csv(output_file, index=False)
    print(f"Done! Saved to {output_file}")


if __name__ == "__main__":
    main()
