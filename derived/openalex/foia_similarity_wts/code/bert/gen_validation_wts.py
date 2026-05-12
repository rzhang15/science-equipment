"""
Build top-K cosine-similarity validation weights from dense BERT embeddings.

Mirrors gen_validation_wts.py but reads dense `.npy` embeddings instead of
sparse TF-IDF matrices. Output is a sparse FOIA x FOIA weight matrix that
loov.py can consume unchanged.
"""
import argparse
import os
import numpy as np
import pandas as pd
import scipy.sparse


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="allenai-specter",
                        help="Model tag matching 1_vectorize_bert.py output filenames.")
    parser.add_argument("--k", type=int, default=50,
                        help="Top-K neighbors to keep (must be >= max K used in loov sweep).")
    parser.add_argument("--tag-suffix", default="",
                        help="Appended to model tag so variants don't clobber each other.")
    args = parser.parse_args()

    tag = args.model.replace("/", "_") + args.tag_suffix
    foia_emb_path = f"../../output/bert_foia_{tag}.npy"
    foia_ids_path = f"../../output/bert_foia_ids_{tag}.csv"
    output_path = f"../../output/validation_weights_bert_{tag}_k{args.k}.npz"

    print(f"Loading {foia_emb_path}")
    E = np.load(foia_emb_path)  # shape (n_foia, dim)
    df_ids = pd.read_csv(foia_ids_path)
    print(f"Embeddings: {E.shape}")

    # cosine similarity (embeddings already L2-normalized in 1_vectorize_bert.py)
    sim = E @ E.T  # (n_foia, n_foia)

    # top-K filter per row (preserve self for now; loov.py zeros it out)
    print(f"Filtering to top {args.k} per row...")
    n = sim.shape[0]
    if args.k < n:
        for r in range(n):
            row = sim[r, :]
            cutoff = np.partition(row, -args.k)[-args.k]
            row[row < cutoff] = 0
            sim[r, :] = row

    # row-normalize
    row_sums = sim.sum(axis=1, keepdims=True)
    row_sums[row_sums == 0] = 1.0
    W = sim / row_sums
    W_sparse = scipy.sparse.csr_matrix(W)

    print(f"Saving {output_path}")
    scipy.sparse.save_npz(output_path, W_sparse)

    # also write a foia_ids_ordered-style file so loov.py can find the same id order
    aligned_ids = f"../../output/foia_ids_ordered_bert_{tag}.csv"
    df_ids.to_csv(aligned_ids, index=False)
    print(f"Saved {aligned_ids}")


if __name__ == "__main__":
    main()
