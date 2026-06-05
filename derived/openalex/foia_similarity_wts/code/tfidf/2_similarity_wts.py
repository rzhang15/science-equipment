import argparse
import os
import numpy as np
import pandas as pd
import scipy.sparse
from joblib import Parallel, delayed

# --- CONFIGURATION ---
OUT_DIR = "../../output"


def _paths(tag: str) -> dict:
    if tag and not tag.startswith("_"):
        tag = "_" + tag
    return {
        "universe_matrix": f"{OUT_DIR}/tfidf_universe{tag}.npz",
        "foia_matrix":     f"{OUT_DIR}/tfidf_foia{tag}.npz",
        "universe_ids":    f"{OUT_DIR}/universe_ids{tag}.parquet",
        "out_weights":     f"{OUT_DIR}/weight_matrix{tag}.npz",
        "out_diag":        f"{OUT_DIR}/match_diagnostics{tag}.parquet",
    }

# Each universe author gets weight on its top-K most-similar FOIA PIs. The weights
# are then L1-normalized and used to impute spending shares: assumption is that
# topical similarity ⇒ similar product-spending mix.
#
# Tuning rationale for the 200K→200 matching problem:
#   - K=5: averages over a handful of nearest PIs to smooth idiosyncratic noise
#     in any one PI's spending, but small enough that distant PIs do not dilute.
#   - SIMILARITY_FLOOR=0.05: cosine < 0.05 means almost no shared discriminative
#     vocab — those "matches" are noise; refuse to use them as weight.
#   - SHARPEN_POWER>1 raises similarities to a power before normalization, so the
#     #1 match dominates more than #5. Set to 1.0 to disable.
#   - UNMATCHED_MAX_SIM_THRESHOLD: authors whose best FOIA match is below this
#     are flagged unmatched (zero weights). Downstream imputation should drop or
#     handle these separately rather than receive a spurious imputation.
BATCH_SIZE = 25_000
# Defaults below are overridable via CLI. Recipe presets:
#   variance-preserving (nearest neighbor): --k 1
#   sharp soft-NN:                          --k 3  --sharpen 5
#   current default:                        --k 5  --sharpen 2
#   confidence-scaled (with step 3):        --no-l1-normalize  (then step 3
#                                                               scales by row-sum)
K_NEIGHBORS = 5
SIMILARITY_FLOOR = 0.05
SHARPEN_POWER = 2.0
UNMATCHED_MAX_SIM_THRESHOLD = 0.05
L1_NORMALIZE = True

N_JOBS = int(os.environ.get("SLURM_CPUS_PER_TASK", os.cpu_count() or 1))


def process_batch(start, end, X_univ, X_foia_T_dense, k, n_pis):
    """Compute similarities for rows [start, end), extract top-K, build weight triplets."""
    batch = X_univ[start:end]
    # Sparse @ dense returns dense — uses GEMM, much faster than sparse @ sparse.
    batch_sim = batch.dot(X_foia_T_dense)
    b = batch_sim.shape[0]

    # Per-row top-K via argpartition (unsorted within top-K, fine since we re-normalize).
    if k < n_pis:
        topk_idx = np.argpartition(-batch_sim, k - 1, axis=1)[:, :k]
    else:
        topk_idx = np.tile(np.arange(n_pis), (b, 1))
    rows_local = np.repeat(np.arange(b), k)
    topk_vals = batch_sim[rows_local, topk_idx.ravel()].reshape(b, k).astype(np.float32)

    # Pre-modification diagnostics.
    max_sim_b = batch_sim.max(axis=1).astype(np.float32)
    mean_topk_b = topk_vals.mean(axis=1)
    n_above_floor_b = (batch_sim >= SIMILARITY_FLOOR).sum(axis=1).astype(np.int32)

    # Apply floor.
    topk_vals[topk_vals < SIMILARITY_FLOOR] = 0.0

    # Sharpen so the closest PI dominates the weight.
    if SHARPEN_POWER != 1.0:
        topk_vals = np.power(topk_vals, SHARPEN_POWER, dtype=np.float32)

    # Unmatched rows: zero out all weights.
    row_unmatched = max_sim_b < UNMATCHED_MAX_SIM_THRESHOLD
    topk_vals[row_unmatched, :] = 0.0

    if L1_NORMALIZE:
        # Weighted-average form: row sums to 1, imputed exposure is a weighted
        # avg of FOIA exposures. Compresses variance (Jensen-like shrinkage).
        row_sums = topk_vals.sum(axis=1, keepdims=True)
        row_sums[row_sums == 0] = 1.0
        topk_weights = topk_vals / row_sums
    else:
        # Raw-sharpened-similarity form: rows do NOT sum to 1. Low-confidence
        # universe authors get small weights (and thus small imputed values).
        # Preserves more cross-PI variance at the cost of the "weighted-avg"
        # interpretation. Use with --scale-by-confidence semantics in step 3.
        topk_weights = topk_vals

    # Flatten non-zero triplets (with global row offset).
    nz_mask = (topk_weights > 0).ravel()
    flat_rows = (rows_local + start)[nz_mask]
    flat_cols = topk_idx.ravel()[nz_mask]
    flat_vals = topk_weights.ravel()[nz_mask]

    return {
        'start': start, 'end': end,
        'rows': flat_rows.astype(np.int64),
        'cols': flat_cols.astype(np.int32),
        'vals': flat_vals.astype(np.float32),
        'max_sim': max_sim_b,
        'mean_topk_sim': mean_topk_b,
        'n_above_floor': n_above_floor_b,
        'unmatched': row_unmatched,
    }


def main():
    # Declare globals first — Python requires this before any read of the names
    # in this function scope (including reading them as argparse defaults).
    global K_NEIGHBORS, SHARPEN_POWER, SIMILARITY_FLOOR
    global UNMATCHED_MAX_SIM_THRESHOLD, L1_NORMALIZE

    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="",
                    help="Suffix matching the --tag passed to 1_vectorize.py. "
                         "Empty = baseline artifacts.")
    ap.add_argument("--k", type=int, default=K_NEIGHBORS,
                    help=f"Top-K nearest FOIAs to keep per universe author "
                         f"(default {K_NEIGHBORS}). Use --k 1 for nearest-neighbor "
                         f"(maximum variance preservation).")
    ap.add_argument("--sharpen", type=float, default=SHARPEN_POWER,
                    help=f"Power applied to similarities before weighting "
                         f"(default {SHARPEN_POWER}). Higher = closer to "
                         f"nearest-neighbor without the K=1 discontinuity.")
    ap.add_argument("--floor", type=float, default=SIMILARITY_FLOOR,
                    help=f"Similarities below this are set to zero (default "
                         f"{SIMILARITY_FLOOR}). Higher = drop more low-quality "
                         f"matches, fewer matched authors but higher confidence.")
    ap.add_argument("--unmatched-threshold", type=float,
                    default=UNMATCHED_MAX_SIM_THRESHOLD,
                    help="Authors whose best FOIA sim is below this get zero "
                         "weights entirely (flagged unmatched).")
    ap.add_argument("--no-l1-normalize", action="store_true",
                    help="Skip L1 normalization of top-K weights. Use this with "
                         "step-3's confidence-scaled imputation to preserve "
                         "cross-PI variance.")
    args = ap.parse_args()
    paths = _paths(args.tag)

    # Override module-level constants so process_batch sees the chosen recipe.
    K_NEIGHBORS = args.k
    SHARPEN_POWER = args.sharpen
    SIMILARITY_FLOOR = args.floor
    UNMATCHED_MAX_SIM_THRESHOLD = args.unmatched_threshold
    L1_NORMALIZE = not args.no_l1_normalize
    print(f"Recipe: K={K_NEIGHBORS}  sharpen={SHARPEN_POWER}  floor={SIMILARITY_FLOOR}  "
          f"unmatched<{UNMATCHED_MAX_SIM_THRESHOLD}  L1_normalize={L1_NORMALIZE}")

    print(f"Using N_JOBS={N_JOBS} threads  tag={args.tag!r}")
    print("Loading TF-IDF Matrices...")
    X_univ = scipy.sparse.load_npz(paths["universe_matrix"]).tocsr().astype(np.float32)
    X_foia = scipy.sparse.load_npz(paths["foia_matrix"]).tocsr().astype(np.float32)

    # Densify the (n_pis × V) FOIA transpose once. Tiny: 200 × ~few-K features.
    X_foia_T_dense = X_foia.T.toarray().astype(np.float32)

    n_users = X_univ.shape[0]
    n_pis = X_foia.shape[0]
    k = min(K_NEIGHBORS, n_pis)

    print(f"Universe Authors: {n_users:,}")
    print(f"FOIA PIs (Targets): {n_pis}")
    print(f"X_foia dense size: {X_foia_T_dense.nbytes / 1e6:.1f} MB")
    print(f"Computing top-{k} weights in parallel (batch={BATCH_SIZE:,})...")

    batches = [(i, min(i + BATCH_SIZE, n_users)) for i in range(0, n_users, BATCH_SIZE)]
    # Threading backend: scipy sparse @ dense and numpy ops release the GIL, so
    # threads scale well — and we avoid pickling huge sparse slices to subprocesses.
    results = Parallel(n_jobs=N_JOBS, backend="threading", verbose=5)(
        delayed(process_batch)(s, e, X_univ, X_foia_T_dense, k, n_pis) for s, e in batches
    )

    print("Merging results...")
    all_rows = np.concatenate([r['rows'] for r in results])
    all_cols = np.concatenate([r['cols'] for r in results])
    all_vals = np.concatenate([r['vals'] for r in results])

    max_sim = np.empty(n_users, dtype=np.float32)
    mean_topk_sim = np.empty(n_users, dtype=np.float32)
    n_above_floor = np.empty(n_users, dtype=np.int32)
    unmatched = np.empty(n_users, dtype=bool)
    for r in results:
        s, e = r['start'], r['end']
        max_sim[s:e] = r['max_sim']
        mean_topk_sim[s:e] = r['mean_topk_sim']
        n_above_floor[s:e] = r['n_above_floor']
        unmatched[s:e] = r['unmatched']

    W = scipy.sparse.coo_matrix(
        (all_vals, (all_rows, all_cols)), shape=(n_users, n_pis)
    ).tocsr()

    print(f"Total non-zero weights: {W.nnz:,}")
    print(f"Unmatched authors (max sim < {UNMATCHED_MAX_SIM_THRESHOLD}): "
          f"{unmatched.sum():,} ({100*unmatched.mean():.2f}%)")
    print(f"Mean max-similarity:   {max_sim.mean():.4f}")
    print(f"Median max-similarity: {np.median(max_sim):.4f}")

    print(f"Saving weight matrix -> {paths['out_weights']}")
    scipy.sparse.save_npz(paths["out_weights"], W)

    print("Saving per-author match diagnostics...")
    universe_ids = pd.read_parquet(paths["universe_ids"])
    pd.DataFrame({
        'athr_id': universe_ids['athr_id'].values,
        'max_sim': max_sim,
        'mean_topk_sim': mean_topk_sim,
        'n_foia_above_floor': n_above_floor,
        'unmatched': unmatched,
    }).to_parquet(paths["out_diag"], index=False)

    print("Done. Weights precomputed.")


if __name__ == "__main__":
    main()
