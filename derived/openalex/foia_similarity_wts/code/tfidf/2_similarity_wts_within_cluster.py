"""
Build per-cluster weight matrices for within-cluster imputation.

For each universe author assigned to a cluster, compute top-K weights using only
FOIAs in that cluster. This improves imputation signal by matching within
topically-similar neighborhoods.

Usage:
  python 2_similarity_wts_within_cluster.py --tag restricted --n-clusters 15 --k 5

Output:
  output/weight_matrix_within_cluster_{tag}.npz     (sparse, shape n_universe × n_foia)
  output/match_diagnostics_within_cluster_{tag}.parquet

Same format as 2_similarity_wts.py output, but W has block-diagonal structure:
each row uses only FOIAs in that author's assigned cluster.
"""
import argparse
import os
import numpy as np
import pandas as pd
import scipy.sparse
import scipy.spatial

OUT_DIR = "../../output/"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="restricted",
                    help="Tag matching prior steps (default 'restricted').")
    ap.add_argument("--n-clusters", type=int, default=15,
                    help="Number of FOIA clusters (default 15).")
    ap.add_argument("--k", type=int, default=5,
                    help="Top-K neighbors per universe author (default 5).")
    ap.add_argument("--floor", type=float, default=0.05,
                    help="Similarity floor; below this → zero weight (default 0.05).")
    ap.add_argument("--sharpen", type=float, default=2.0,
                    help="Power to raise similarities before normalization (default 2.0).")
    args = ap.parse_args()

    tag = args.tag
    if tag and not tag.startswith("_"):
        tag = "_" + tag

    # Paths
    universe_ids_path = f"{OUT_DIR}universe_ids{tag}.parquet"
    foia_ids_path = f"{OUT_DIR}foia_ids_ordered{tag}.csv"
    foia_clusters_path = f"{OUT_DIR}foia_clusters_K{args.n_clusters}{tag}.csv"
    universe_assignment_path = f"{OUT_DIR}universe_cluster_assignment{tag}.parquet"
    tfidf_universe_path = f"{OUT_DIR}tfidf_universe{tag}.npz"
    tfidf_foia_path = f"{OUT_DIR}tfidf_foia{tag}.npz"

    output_weights_path = f"{OUT_DIR}weight_matrix_within_cluster{tag}.npz"
    output_diag_path = f"{OUT_DIR}match_diagnostics_within_cluster{tag}.parquet"

    # Check inputs
    for p in (universe_ids_path, foia_ids_path, foia_clusters_path,
              universe_assignment_path, tfidf_universe_path, tfidf_foia_path):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")

    print("Loading data...")
    universe_ids = pd.read_parquet(universe_ids_path)
    foia_ids = pd.read_csv(foia_ids_path)
    foia_clusters = pd.read_csv(foia_clusters_path)
    universe_assignment = pd.read_parquet(universe_assignment_path)
    X_universe = scipy.sparse.load_npz(tfidf_universe_path).tocsr().astype(np.float32)
    X_foia = scipy.sparse.load_npz(tfidf_foia_path).tocsr().astype(np.float32)

    n_universe = len(universe_ids)
    n_foia = len(foia_ids)

    print(f"  Universe: {n_universe:,}")
    print(f"  FOIAs: {n_foia}")
    print(f"  Clusters: {args.n_clusters}")
    print(f"Recipe: K={args.k}, floor={args.floor}, sharpen={args.sharpen}")

    # Build FOIA index → cluster map
    foia_to_cluster = dict(zip(range(n_foia), foia_clusters['cluster'].values))

    # Build per-cluster FOIA index lists
    cluster_to_foia_indices = {}
    for c in range(args.n_clusters):
        cluster_to_foia_indices[c] = np.where(foia_clusters['cluster'] == c)[0]

    print(f"\nFOIA distribution by cluster:")
    for c in range(args.n_clusters):
        n_in_cluster = len(cluster_to_foia_indices[c])
        print(f"  cluster {c:2d}: {n_in_cluster:3d} FOIAs")

    # Dense FOIA transpose
    X_foia_T_dense = X_foia.T.toarray().astype(np.float32)

    # Build weight matrix row-by-row
    print("\nBuilding within-cluster weight matrix...")
    rows_list = []
    cols_list = []
    vals_list = []

    max_sim_vec = np.zeros(n_universe, dtype=np.float32)
    mean_topk_vec = np.zeros(n_universe, dtype=np.float32)

    for i in range(n_universe):
        if (i + 1) % 100_000 == 0:
            print(f"  {i+1:,} / {n_universe:,}")

        # Get this author's assigned cluster
        cluster = universe_assignment.iloc[i]['closest_foia_cluster']
        foia_indices_in_cluster = cluster_to_foia_indices[cluster]

        # Compute similarities only to FOIAs in this cluster
        author_vec = X_universe[i:i+1]  # (1, n_features)
        sim_to_cluster = author_vec.dot(X_foia_T_dense[:, foia_indices_in_cluster])  # (1, n_in_cluster)
        sim_to_cluster = sim_to_cluster.ravel().astype(np.float32)

        # Record max sim for this author
        max_sim_vec[i] = sim_to_cluster.max()

        # Top-K within cluster
        k_actual = min(args.k, len(foia_indices_in_cluster))
        if k_actual < 1:
            continue

        topk_local_idx = np.argsort(-sim_to_cluster)[:k_actual]
        topk_foia_idx = foia_indices_in_cluster[topk_local_idx]
        topk_sim = sim_to_cluster[topk_local_idx]

        mean_topk_vec[i] = topk_sim.mean()

        # Apply floor
        topk_sim[topk_sim < args.floor] = 0.0

        # Sharpen
        if args.sharpen != 1.0:
            topk_sim = np.power(topk_sim, args.sharpen)

        # L1 normalize
        row_sum = topk_sim.sum()
        if row_sum > 0:
            topk_sim = topk_sim / row_sum

            # Collect non-zero entries
            nz_mask = topk_sim > 0
            rows_list.append(np.full(nz_mask.sum(), i, dtype=np.int64))
            cols_list.append(topk_foia_idx[nz_mask].astype(np.int32))
            vals_list.append(topk_sim[nz_mask].astype(np.float32))

    # Assemble sparse matrix
    print("Assembling sparse matrix...")
    if rows_list:
        all_rows = np.concatenate(rows_list)
        all_cols = np.concatenate(cols_list)
        all_vals = np.concatenate(vals_list)
    else:
        all_rows = np.array([], dtype=np.int64)
        all_cols = np.array([], dtype=np.int32)
        all_vals = np.array([], dtype=np.float32)

    W = scipy.sparse.coo_matrix(
        (all_vals, (all_rows, all_cols)),
        shape=(n_universe, n_foia)
    ).tocsr()

    print(f"Weight matrix: shape {W.shape}, nnz={W.nnz:,}")
    print(f"  sparsity: {100*(1 - W.nnz/(n_universe*n_foia)):.2f}%")

    # Save weight matrix
    print(f"Saving weight matrix -> {output_weights_path}")
    scipy.sparse.save_npz(output_weights_path, W)

    # Save diagnostics
    diag_df = pd.DataFrame({
        'athr_id': universe_ids['athr_id'].values,
        'assigned_cluster': universe_assignment['closest_foia_cluster'].values,
        'max_sim_to_cluster': max_sim_vec,
        'mean_topk_sim': mean_topk_vec,
    })

    print(f"Saving diagnostics -> {output_diag_path}")
    diag_df.to_parquet(output_diag_path, index=False)

    print("\nNext: python 3_impute_exposure_within_cluster.py --tag " + args.tag)


if __name__ == "__main__":
    main()
