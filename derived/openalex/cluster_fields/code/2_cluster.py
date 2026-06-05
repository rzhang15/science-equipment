"""
Cluster authors into K subfields from the TF-IDF matrix.

Default pipeline now applies TruncatedSVD + L2-normalize BEFORE K-means.
Reason: MiniBatchKMeans on raw 30k-dim sparse TF-IDF collapses ~all
authors into a single mega-cluster (curse of dimensionality on Euclidean
distance). Reducing to ~256 dense dims and L2-normalizing makes Euclidean
K-means approximate spherical (cosine) K-means, which is what you want
for text. To compare against the old behavior, pass --svd-dim 0.
"""
import argparse
import os
import numpy as np
import pandas as pd
import scipy.sparse
import pickle
from sklearn.cluster import MiniBatchKMeans
from sklearn.decomposition import TruncatedSVD
from sklearn.preprocessing import normalize

parser = argparse.ArgumentParser()
parser.add_argument('--clusters', type=int, required=True)
parser.add_argument('--svd-dim', type=int, default=256,
                    help="Reduce to this many dims via TruncatedSVD before K-means. "
                         "0 = skip (old behavior). Default 256 is the LSI/text-clustering "
                         "convention.")
parser.add_argument('--seed', type=int, default=42)
args = parser.parse_args()

NUM_CLUSTERS = args.clusters
SEED = args.seed
np.random.seed(SEED)

print(f"--- CLUSTER JOB: K={NUM_CLUSTERS}  svd_dim={args.svd_dim} ---")

print("Loading TF-IDF matrix...")
matrix = scipy.sparse.load_npz("../output/tfidf_matrix.npz")
print(f"  TF-IDF shape: {matrix.shape}  nnz/row mean: {matrix.nnz / matrix.shape[0]:.1f}")

print("Loading helper files...")
feature_names = pickle.load(open("../output/feature_names.pkl", "rb"))
pdf_ids = pd.read_parquet("../output/author_ids_aligned.parquet")

# Quick health check on TF-IDF rows -- empty/near-empty rows pull every
# cluster centroid toward the origin and produce mega-cluster degeneracy.
row_nnz = np.asarray((matrix != 0).sum(axis=1)).ravel()
print(f"  rows with 0 nonzero features: {(row_nnz == 0).sum():,}")
print(f"  rows with <5 nonzero features: {(row_nnz < 5).sum():,}")

# ---- SVD reduction ----
if args.svd_dim and args.svd_dim > 0:
    print(f"\nReducing to {args.svd_dim} dims via TruncatedSVD...")
    svd = TruncatedSVD(
        n_components=args.svd_dim,
        random_state=SEED,
        # 'randomized' is fast and accurate enough for clustering use
        algorithm="randomized",
        n_iter=7,
    )
    X = svd.fit_transform(matrix).astype(np.float32)
    print(f"  cumulative explained variance: {svd.explained_variance_ratio_.sum():.3f}")
    print(f"  dense shape: {X.shape}   mem: {X.nbytes / 1e9:.2f} GB")
    # L2 normalize -> Euclidean distance in K-means approximates cosine.
    X = normalize(X, norm="l2", axis=1).astype(np.float32)
    print(f"  L2-normalized; ready for spherical K-means semantics.")
else:
    print("\nSkipping SVD (--svd-dim 0). Running K-means on raw sparse TF-IDF.")
    X = matrix

# ---- K-means ----
print(f"\nClustering into {NUM_CLUSTERS} clusters with MiniBatchKMeans...")
kmeans = MiniBatchKMeans(
    n_clusters=NUM_CLUSTERS,
    random_state=SEED,
    batch_size=16384,
    n_init=10,
    init="k-means++",
    max_iter=300,
    reassignment_ratio=0.01,  # aggressively reseed empty/near-empty clusters
)
kmeans.fit(X)
labels = kmeans.labels_

# ---- diagnostic: cluster size distribution ----
sizes = pd.Series(labels).value_counts().sort_values(ascending=False)
top_share = sizes.iloc[0] / len(labels)
print(f"\n--- CLUSTER SIZE DISTRIBUTION ---")
print(f"  largest cluster: {sizes.iloc[0]:,} authors ({top_share*100:.2f}% of pool)")
print(f"  median size: {int(sizes.median()):,}    smallest: {int(sizes.iloc[-1]):,}")
print(f"  size pctiles: 10%={int(sizes.quantile(.1)):,}  "
      f"25%={int(sizes.quantile(.25)):,}  "
      f"75%={int(sizes.quantile(.75)):,}  "
      f"90%={int(sizes.quantile(.9)):,}")
if top_share > 0.5:
    print(f"  WARNING: largest cluster holds {top_share*100:.1f}% of the pool -- "
          f"the clustering looks degenerate. Try increasing --svd-dim or K.")

# ---- save labels ----
print("\nSaving Results...")
pdf_ids['cluster_label'] = labels
pdf_ids.to_csv(f"../output/author_static_clusters_{NUM_CLUSTERS}.csv", index=False)

# ---- top-term descriptions ----
# When SVD is on, kmeans.cluster_centers_ is in the SVD-reduced space, so
# we can't read top terms off it directly. Instead, compute per-cluster
# centroids back in the original TF-IDF space.
print("Writing cluster top-term descriptions...")
if args.svd_dim and args.svd_dim > 0:
    # Mean TF-IDF vector per cluster in the original sparse space.
    centers = np.zeros((NUM_CLUSTERS, matrix.shape[1]), dtype=np.float32)
    for c in range(NUM_CLUSTERS):
        rows = np.where(labels == c)[0]
        if len(rows) == 0:
            continue
        # Mean of sparse rows -> dense vector of length n_features
        centers[c] = np.asarray(matrix[rows].mean(axis=0)).ravel()
else:
    centers = kmeans.cluster_centers_

out_txt = f"../output/static_cluster_descriptions_{NUM_CLUSTERS}.txt"
with open(out_txt, "w") as f:
    for i in range(NUM_CLUSTERS):
        n_i = int(sizes.get(i, 0))
        top_idx = centers[i].argsort()[-15:][::-1]
        top_terms = [feature_names[idx] for idx in top_idx]
        f.write(f"Cluster {i} (n={n_i:,}): {', '.join(top_terms)}\n")

print(f"Saved {out_txt}")
print("Done.")
