"""
Cluster US authors into K subfields from the TF-IDF matrix built on
cleaned_static_author_text_pre_us.parquet.

Applies TruncatedSVD + L2-normalize BEFORE K-means. MiniBatchKMeans on the
raw 30k-dim sparse TF-IDF collapses ~all authors into a single mega-cluster
(curse of dimensionality on Euclidean distance). Reducing to ~256 dense
dims and L2-normalizing makes Euclidean K-means approximate spherical
(cosine) K-means, which is what we want for text.

Mirrors cluster_fields/2_cluster.py exactly so US-only vs worldwide
clusterings stay comparable.
"""
import argparse
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
parser.add_argument('--suffix', default="",
                    help="Read/write the _ls variant of the tfidf inputs and "
                         "cluster outputs.")
parser.add_argument('--sil-sample', type=int, default=50000,
                    help="Rows sampled for the silhouette score. 0 skips it.")
args = parser.parse_args()
SUF = args.suffix

NUM_CLUSTERS = args.clusters
SEED = args.seed
np.random.seed(SEED)

print(f"--- CLUSTER JOB (US): K={NUM_CLUSTERS}  svd_dim={args.svd_dim} ---")

print("Loading TF-IDF matrix...")
matrix = scipy.sparse.load_npz(f"../output/tfidf_matrix{SUF}.npz")
print(f"  TF-IDF shape: {matrix.shape}  nnz/row mean: {matrix.nnz / matrix.shape[0]:.1f}")

print("Loading helper files...")
feature_names = pickle.load(open(f"../output/feature_names{SUF}.pkl", "rb"))
pdf_ids = pd.read_parquet(f"../output/author_ids_aligned{SUF}.parquet")

# CSR row nnz straight off the index pointer. (matrix != 0) would build a
# whole second sparse matrix just to count.
row_nnz = np.diff(matrix.indptr)
print(f"  rows with 0 nonzero features:  {(row_nnz == 0).sum():,}")
print(f"  rows with <5 nonzero features: {(row_nnz < 5).sum():,}")

# ---- SVD reduction ----
if args.svd_dim and args.svd_dim > 0:
    print(f"\nReducing to {args.svd_dim} dims via TruncatedSVD...")
    svd = TruncatedSVD(
        n_components=args.svd_dim,
        random_state=SEED,
        algorithm="randomized",
        n_iter=7,
    )
    X = svd.fit_transform(matrix).astype(np.float32)
    print(f"  cumulative explained variance: {svd.explained_variance_ratio_.sum():.3f}")
    print(f"  dense shape: {X.shape}   mem: {X.nbytes / 1e9:.2f} GB")
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
    n_init=3,
    init="k-means++",
    max_iter=300,
    reassignment_ratio=0.01,
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

# ---- K-selection diagnostics ----
# Appended one row per run so a sweep builds the elbow/silhouette curve that
# justifies the chosen K. Silhouette is on a sample: the full pairwise
# computation is O(n^2) and infeasible at 1.8M rows.
import os
sil = float("nan")
if args.sil_sample and args.sil_sample > 0:
    from sklearn.metrics import silhouette_score
    rng = np.random.RandomState(SEED)
    idx = rng.choice(X.shape[0], size=min(args.sil_sample, X.shape[0]), replace=False)
    sil = silhouette_score(X[idx], labels[idx], metric="euclidean")
    print(f"  silhouette (n={len(idx):,}): {sil:.4f}")
print(f"  inertia: {kmeans.inertia_:.2f}")

diag_path = f"../output/k_diagnostics{SUF}.csv"
hdr = not os.path.exists(diag_path)
with open(diag_path, "a") as f:
    if hdr:
        f.write("k,n_authors,svd_dim,seed,inertia,silhouette,"
                "largest_share,median_size,smallest_size\n")
    f.write(f"{NUM_CLUSTERS},{len(labels)},{args.svd_dim},{SEED},"
            f"{kmeans.inertia_:.4f},{sil:.6f},{top_share:.6f},"
            f"{int(sizes.median())},{int(sizes.iloc[-1])}\n")
print(f"  appended diagnostics to {diag_path}")

# ---- save labels ----
print("\nSaving Results...")
pdf_ids['cluster_label'] = labels
pdf_ids.to_csv(f"../output/author_static_clusters_{NUM_CLUSTERS}{SUF}.csv", index=False)

# ---- top-term descriptions ----
# With SVD on, kmeans.cluster_centers_ is in the SVD-reduced space, so we
# can't read top terms off it directly. Recompute per-cluster centroids in
# the original TF-IDF space.
print("Writing cluster top-term descriptions...")
if args.svd_dim and args.svd_dim > 0:
    # One sparse matmul instead of K fancy-index slices. S is (K x n) holding
    # 1/cluster_size, so S @ matrix is the stack of per-cluster mean vectors.
    counts = np.bincount(labels, minlength=NUM_CLUSTERS).astype(np.float32)
    w = np.where(counts > 0, 1.0 / np.maximum(counts, 1), 0.0)[labels]
    S = scipy.sparse.csr_matrix(
        (w, (labels, np.arange(len(labels)))),
        shape=(NUM_CLUSTERS, matrix.shape[0]),
        dtype=np.float32,
    )
    centers = np.asarray((S @ matrix).todense(), dtype=np.float32)
else:
    centers = kmeans.cluster_centers_

out_txt = f"../output/static_cluster_descriptions_{NUM_CLUSTERS}{SUF}.txt"
with open(out_txt, "w") as f:
    for i in range(NUM_CLUSTERS):
        n_i = int(sizes.get(i, 0))
        top_idx = centers[i].argsort()[-15:][::-1]
        top_terms = [feature_names[idx] for idx in top_idx]
        f.write(f"Cluster {i} (n={n_i:,}): {', '.join(top_terms)}\n")

print(f"Saved {out_txt}")
print("Done.")
