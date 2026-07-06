"""
Filter universe authors to those textually similar to FOIA PIs.

Identifies and removes textual outliers (economists, distant fields) by computing
distance from each universe author to the FOIA centroid. Keeps only authors within
a specified percentile of that distribution.

Usage:
  python 0_filter_universe_by_foia_distance.py --tag restricted --keep-percentile 90

Output:
  output/universe_ids_filtered_{tag}.parquet  (filtered list of athr_id)
  output/universe_filter_audit_{tag}.csv      (distance diagnostics)
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
                    help="Tag matching vectorize.py run (default 'restricted').")
    ap.add_argument("--keep-percentile", type=float, default=90.0,
                    help="Keep universe authors within this percentile of distance "
                         "to FOIA centroid (default 90). Lower = stricter filtering.")
    args = ap.parse_args()

    tag = args.tag
    if tag and not tag.startswith("_"):
        tag = "_" + tag

    # Paths
    universe_ids_path = f"{OUT_DIR}universe_ids{tag}.parquet"
    tfidf_universe_path = f"{OUT_DIR}tfidf_universe{tag}.npz"
    tfidf_foia_path = f"{OUT_DIR}tfidf_foia{tag}.npz"

    output_ids_path = f"{OUT_DIR}universe_ids_filtered{tag}.parquet"
    output_audit_path = f"{OUT_DIR}universe_filter_audit{tag}.csv"

    # Check inputs
    for p in (universe_ids_path, tfidf_universe_path, tfidf_foia_path):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")

    print(f"Loading universe IDs ({universe_ids_path})...")
    universe_ids = pd.read_parquet(universe_ids_path)
    n_universe = len(universe_ids)
    print(f"  N = {n_universe:,}")

    print(f"Loading TF-IDF matrices...")
    X_universe = scipy.sparse.load_npz(tfidf_universe_path)
    X_foia = scipy.sparse.load_npz(tfidf_foia_path)
    print(f"  Universe shape: {X_universe.shape}")
    print(f"  FOIA shape: {X_foia.shape}")

    # Compute FOIA centroid
    print("Computing FOIA centroid...")
    centroid = np.asarray(X_foia.mean(axis=0)).ravel()

    # L2-normalize centroid (for cosine distance with L2-normalized vectors)
    centroid_norm = np.linalg.norm(centroid)
    if centroid_norm > 0:
        centroid = centroid / centroid_norm
    else:
        raise ValueError("Centroid is zero-norm")

    # Compute distance from each universe author to centroid (sparse + efficient)
    print("Computing distance from each universe author to FOIA centroid...")
    print("  Using sparse matrix operations (low memory)...")
    # Cosine similarity = X @ centroid (both L2-normalized)
    # Cosine distance = 1 - similarity
    similarity = X_universe @ centroid
    distances = 1 - np.asarray(similarity).ravel()

    # Determine threshold
    threshold = np.percentile(distances, args.keep_percentile)
    keep_mask = distances <= threshold
    n_keep = keep_mask.sum()
    n_drop = (~keep_mask).sum()

    print(f"Distance statistics:")
    print(f"  min: {distances.min():.4f}, max: {distances.max():.4f}, "
          f"mean: {distances.mean():.4f}, median: {np.median(distances):.4f}")
    print(f"  {args.keep_percentile}th percentile: {threshold:.4f}")
    print(f"\nFiltering results:")
    print(f"  keep: {n_keep:,} authors (≤ {threshold:.4f} distance)")
    print(f"  drop: {n_drop:,} authors (> {threshold:.4f} distance)")
    print(f"  retention: {100*n_keep/n_universe:.1f}%")

    # Build output
    universe_ids_filtered = universe_ids.loc[keep_mask].reset_index(drop=True)

    # Audit: dropped authors with highest distances
    dropped_audit = pd.DataFrame({
        'athr_id': universe_ids.loc[~keep_mask, 'athr_id'].values,
        'textual_distance_to_foia_centroid': distances[~keep_mask]
    }).sort_values('textual_distance_to_foia_centroid', ascending=False)

    print(f"\nTop 20 dropped authors (furthest from FOIA):")
    print(dropped_audit.head(20).to_string(index=False))

    # Save outputs
    print(f"\nSaving filtered universe IDs -> {output_ids_path}")
    universe_ids_filtered.to_parquet(output_ids_path, index=False)

    print(f"Saving audit -> {output_audit_path}")
    dropped_audit.to_csv(output_audit_path, index=False)

    print("\nNext steps:")
    print(f"  1. Review {output_audit_path} to verify dropped authors are outliers")
    print(f"  2. python cluster_foias.py --tag {args.tag} --filtered")
    print(f"  3. python assign_universe_to_foia_clusters.py --tag {args.tag}")
    print(f"  4. python 2_similarity_wts_within_cluster.py --tag {args.tag}")


if __name__ == "__main__":
    main()
