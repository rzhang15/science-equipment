"""
Impute exposure for every universe author via BERT similarity weights.

Mirror of tfidf/3_impute_exposure.py: loads the sparse weight matrix produced
by 2_similarity_wts.py, aligns the FOIA exposure vector to the column order
that 1_vectorize.py wrote, and saves (universe_athr_id, exposure).
"""
import argparse
import os
import numpy as np
import pandas as pd
import polars as pl
import scipy.sparse


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="allenai-specter",
                        help="Model tag matching 1_vectorize.py output filenames.")
    args = parser.parse_args()

    tag = args.model.replace("/", "_")
    weights_file = f"../../output/bert_weight_matrix_{tag}.npz"
    univ_ids_file = f"../../output/bert_universe_ids_{tag}.parquet"
    foia_ids_file = f"../../output/bert_foia_ids_{tag}.csv"
    exposure_file = "../../external/exposure_wts/athr_exposure.dta"
    out_file = f"../../output/final_imputed_exposure_bert_{tag}.csv"

    if not os.path.exists(exposure_file):
        raise SystemExit(f"Missing exposure file: {exposure_file}")

    print(f"Loading weights {weights_file}")
    W = scipy.sparse.load_npz(weights_file)

    print("Loading IDs")
    df_univ = pl.read_parquet(univ_ids_file).to_pandas()
    df_foia = pd.read_csv(foia_ids_file)
    print(f"Universe: {len(df_univ):,}   FOIA: {len(df_foia)}   W: {W.shape}")
    assert W.shape == (len(df_univ), len(df_foia)), \
        "weight matrix shape doesn't match id files"

    print("Aligning exposure to FOIA column order")
    df_exp = pd.read_stata(exposure_file)
    df_aligned = pd.merge(df_foia, df_exp, on="athr_id", how="left")
    df_aligned["exposure"] = df_aligned["exposure"].fillna(0)
    E = df_aligned["exposure"].values

    print("Imputing...")
    imputed = W.dot(E)
    df_univ["exposure"] = imputed
    df_univ.to_csv(out_file, index=False)

    print(f"Saved {out_file}")
    print(f"mean={np.mean(imputed):.5f}  median={np.median(imputed):.5f}  "
          f"nonzero={np.mean(imputed > 0):.3f}")


if __name__ == "__main__":
    main()
