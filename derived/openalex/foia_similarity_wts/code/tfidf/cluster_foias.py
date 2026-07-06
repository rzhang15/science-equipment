"""
Cluster the FOIA PIs using their TF-IDF vectors.

Creates a FOIA-based field structure. Each cluster represents a research subfield.
Clusters the imputation targets themselves, so "field" is defined by what FOIAs
actually do, not external labels.

Usage:
  python cluster_foias.py --tag restricted --n-clusters 15

Output:
  output/foia_clusters_K{n_clusters}_{tag}.csv

  Columns: athr_id, cluster
"""
import argparse
import os
import numpy as np
import pandas as pd
import scipy.sparse
from sklearn.cluster import KMeans

OUT_DIR = "../../output/"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="restricted",
                    help="Tag matching vectorize.py run (default 'restricted').")
    ap.add_argument("--n-clusters", type=int, default=15,
                    help="Number of clusters (default 15).")
    ap.add_argument("--seed", type=int, default=8975,
                    help="Random seed for k-means.")
    args = ap.parse_args()

    tag = args.tag
    if tag and not tag.startswith("_"):
        tag = "_" + tag

    # Paths
    foia_ids_path = f"{OUT_DIR}foia_ids_ordered{tag}.csv"
    tfidf_foia_path = f"{OUT_DIR}tfidf_foia{tag}.npz"

    output_path = f"{OUT_DIR}foia_clusters_K{args.n_clusters}{tag}.csv"

    # Check inputs exist
    if not os.path.exists(foia_ids_path):
        raise SystemExit(f"missing: {foia_ids_path}")
    if not os.path.exists(tfidf_foia_path):
        raise SystemExit(f"missing: {tfidf_foia_path}")

    print(f"Loading FOIA TF-IDF vectors ({tfidf_foia_path})...")
    X_foia = scipy.sparse.load_npz(tfidf_foia_path)
    print(f"  Shape: {X_foia.shape}")

    print(f"Loading FOIA IDs ({foia_ids_path})...")
    foia_ids = pd.read_csv(foia_ids_path)
    n_foia = len(foia_ids)
    print(f"  N = {n_foia}")

    # Dense conversion for k-means
    print("Converting to dense...")
    X_dense = X_foia.toarray().astype(np.float32)

    # K-means clustering
    print(f"Running k-means with K={args.n_clusters}, seed={args.seed}...")
    kmeans = KMeans(n_clusters=args.n_clusters, random_state=args.seed,
                    n_init=10, max_iter=300, verbose=1)
    clusters = kmeans.fit_predict(X_dense)

    # Cluster size distribution
    cluster_counts = pd.Series(clusters).value_counts().sort_index()
    print("\nCluster sizes:")
    print(cluster_counts)
    print(f"  min={cluster_counts.min()}, max={cluster_counts.max()}, "
          f"mean={cluster_counts.mean():.1f}, median={cluster_counts.median():.1f}")

    # Save
    foia_ids['cluster'] = clusters
    print(f"\nSaving -> {output_path}")
    foia_ids.to_csv(output_path, index=False)

    print(f"\nNext: python assign_universe_to_foia_clusters.py --tag {args.tag} "
          f"--n-clusters {args.n_clusters}")


if __name__ == "__main__":
    main()
