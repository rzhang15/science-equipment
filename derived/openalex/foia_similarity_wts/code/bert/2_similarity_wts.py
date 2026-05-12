"""
GPU cosine similarity: universe BERT embeddings x FOIA BERT embeddings.

Mirrors tfidf/2_similarity_wts.py but operates on dense L2-normalized
embeddings produced by bert/1_vectorize.py --universe. Cosine sim is just a
torch matmul; we batch rows of the universe to bound peak GPU memory, apply
top-K + threshold filters, row-normalize, and stream into a sparse COO matrix
to keep the on-disk artifact small.
"""
import argparse
import time
import numpy as np
import scipy.sparse
import torch


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="allenai-specter",
                        help="Model tag matching 1_vectorize.py output filenames.")
    parser.add_argument("--k", type=int, default=5,
                        help="Top-K neighbors to keep per universe author.")
    parser.add_argument("--threshold", type=float, default=0.0,
                        help="Drop similarities below this cutoff (cosine).")
    parser.add_argument("--batch-size", type=int, default=200_000,
                        help="Rows of universe per GPU matmul batch.")
    args = parser.parse_args()

    tag = args.model.replace("/", "_")
    univ_emb_path = f"../../output/bert_universe_{tag}.npy"
    foia_emb_path = f"../../output/bert_foia_{tag}.npy"
    out_path = f"../../output/bert_weight_matrix_{tag}.npz"

    device = "cuda" if torch.cuda.is_available() else "cpu"
    if device == "cpu":
        print("WARNING: no GPU detected — this will be slow.")
    print(f"Device: {device}")

    # mmap universe so we don't pay 4GB+ host RAM up front
    print(f"Loading {univ_emb_path}")
    X_univ = np.load(univ_emb_path, mmap_mode="r")
    print(f"Loading {foia_emb_path}")
    X_foia = np.load(foia_emb_path)
    n_univ, dim = X_univ.shape
    n_foia = X_foia.shape[0]
    print(f"Universe: {n_univ:,} x {dim}   FOIA: {n_foia} x {dim}")
    assert X_foia.shape[1] == dim, "FOIA and universe embedding dims must match"

    foia_t = torch.from_numpy(X_foia).to(device).half()  # (n_foia, dim) fp16

    row_ind: list[np.ndarray] = []
    col_ind: list[np.ndarray] = []
    data_val: list[np.ndarray] = []

    k = min(args.k, n_foia)
    t0 = time.time()
    for start in range(0, n_univ, args.batch_size):
        end = min(start + args.batch_size, n_univ)
        batch = torch.from_numpy(np.ascontiguousarray(X_univ[start:end])).to(device).half()
        sim = batch @ foia_t.T  # (B, n_foia)
        del batch

        # top-K per row
        topk_vals, topk_idx = torch.topk(sim, k=k, dim=1)  # (B, k)
        if args.threshold > 0:
            topk_vals = torch.where(topk_vals >= args.threshold,
                                    topk_vals, torch.zeros_like(topk_vals))

        # row-normalize so weights sum to 1
        row_sums = topk_vals.sum(dim=1, keepdim=True)
        row_sums = torch.where(row_sums > 0, row_sums, torch.ones_like(row_sums))
        topk_vals = topk_vals / row_sums

        # back to numpy COO triples
        vals = topk_vals.cpu().float().numpy()
        cols = topk_idx.cpu().numpy()
        rows = np.repeat(np.arange(start, end, dtype=np.int64), k).reshape(-1, k)

        keep = vals > 0
        row_ind.append(rows[keep])
        col_ind.append(cols[keep])
        data_val.append(vals[keep])

        elapsed = time.time() - t0
        rate = end / elapsed if elapsed else 0.0
        eta = (n_univ - end) / rate if rate else float("inf")
        print(f"  {end:,}/{n_univ:,}  ({rate:,.0f}/s, ETA {eta/60:.1f}min)", flush=True)

    print("Building sparse matrix...")
    rows_all = np.concatenate(row_ind)
    cols_all = np.concatenate(col_ind)
    vals_all = np.concatenate(data_val).astype(np.float32)
    W = scipy.sparse.coo_matrix(
        (vals_all, (rows_all, cols_all)),
        shape=(n_univ, n_foia),
    ).tocsr()

    print(f"Saving {out_path}  shape={W.shape}  nnz={W.nnz:,}")
    scipy.sparse.save_npz(out_path, W)


if __name__ == "__main__":
    main()
