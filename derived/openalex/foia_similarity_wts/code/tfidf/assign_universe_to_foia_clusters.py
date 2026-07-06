"""
Assign universe authors to FOIA clusters.

For each universe author, find their closest FOIA neighbor and assign them to
that FOIA's cluster. This creates a universe-level field assignment based on
textual proximity to FOIA research areas.

Usage:
  python assign_universe_to_foia_clusters.py --tag restricted --n-clusters 15

Output:
  output/universe_cluster_assignment_{tag}.parquet

  Columns: athr_id, closest_foia_athr_id, closest_foia_cluster, max_sim_to_cluster
"""
import argparse
import os
import numpy as np
import pandas as pd
import scipy.sparse

OUT_DIR = "../../output/"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="restricted",
                    help="Tag matching prior clustering run (default 'restricted').")
    ap.add_argument("--n-clusters", type=int, default=15,
                    help="Number of FOIA clusters (default 15).")
    args = ap.parse_args()

    tag = args.tag
    if tag and not tag.startswith("_"):
        tag = "_" + tag

    # Paths
    universe_ids_path = f"{OUT_DIR}universe_ids{tag}.parquet"
    foia_ids_path = f"{OUT_DIR}foia_ids_ordered{tag}.csv"
    foia_clusters_path = f"{OUT_DIR}foia_clusters_K{args.n_clusters}{tag}.csv"
    tfidf_universe_path = f"{OUT_DIR}tfidf_universe{tag}.npz"
    tfidf_foia_path = f"{OUT_DIR}tfidf_foia{tag}.npz"

    output_path = f"{OUT_DIR}universe_cluster_assignment{tag}.parquet"

    # Check inputs
    for p in (universe_ids_path, foia_ids_path, foia_clusters_path,
              tfidf_universe_path, tfidf_foia_path):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")

    print("Loading data...")
    universe_ids = pd.read_parquet(universe_ids_path)
    foia_ids = pd.read_csv(foia_ids_path)
    foia_clusters = pd.read_csv(foia_clusters_path)
    X_universe = scipy.sparse.load_npz(tfidf_universe_path).tocsr().astype(np.float32)
    X_foia = scipy.sparse.load_npz(tfidf_foia_path).tocsr().astype(np.float32)

    print(f"  Universe authors: {len(universe_ids):,}")
    print(f"  FOIA PIs: {len(foia_ids)}")
    print(f"  FOIA clusters: {args.n_clusters}")

    # Compute similarities: (n_universe, n_foia)
    print("Computing cosine similarities (universe → FOIAs)...")
    # Dense FOIA transpose for speed
    X_foia_T_dense = X_foia.T.toarray().astype(np.float32)
    similarities = X_universe.dot(X_foia_T_dense)  # sparse @ dense = dense

    # For each universe author, find their closest FOIA
    print("Finding closest FOIA for each universe author...")
    closest_foia_idx = np.argmax(similarities, axis=1)
    max_sim = np.array([similarities[i, closest_foia_idx[i]] for i in range(len(universe_ids))])

    # Map FOIA index to cluster
    foia_to_cluster = dict(zip(
        range(len(foia_ids)),
        foia_clusters['cluster'].values
    ))

    universe_assignments = pd.DataFrame({
        'athr_id': universe_ids['athr_id'].values,
        'closest_foia_idx': closest_foia_idx,
        'closest_foia_athr_id': foia_ids.iloc[closest_foia_idx]['athr_id'].values,
        'closest_foia_cluster': np.array([foia_to_cluster[i] for i in closest_foia_idx]),
        'max_sim_to_closest_foia': max_sim.astype(np.float32)
    })

    # Cluster distribution
    cluster_dist = universe_assignments['closest_foia_cluster'].value_counts().sort_index()
    print("\nUniverse authors per FOIA cluster:")
    print(cluster_dist)
    print(f"  min={cluster_dist.min()}, max={cluster_dist.max()}, "
          f"mean={cluster_dist.mean():.1f}")

    print(f"\nSaving -> {output_path}")
    universe_assignments.to_parquet(output_path, index=False)

    print(f"\nNext: python 2_similarity_wts_within_cluster.py --tag {args.tag} "
          f"--n-clusters {args.n_clusters}")


if __name__ == "__main__":
    main()
