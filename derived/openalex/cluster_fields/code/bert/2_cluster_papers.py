"""
MiniBatchKMeans on L2-normalized SPECTER embeddings = spherical k-means.

Output:
  ../../output/bert/paper_clusters_K{K}.parquet  (id, cluster_label)
  ../../output/bert/cluster_centroids_K{K}.npy   (float32, [K, D], L2-normalized)
"""
import argparse
import numpy as np
import polars as pl
from sklearn.cluster import MiniBatchKMeans

EMB_PATH = "../../output/bert/paper_embeddings.npy"
IDS_PATH = "../../output/bert/papers_aligned.parquet"
OUT_DIR = "../../output/bert"

parser = argparse.ArgumentParser()
parser.add_argument("--clusters", type=int, required=True)
parser.add_argument("--seed", type=int, default=42)
args = parser.parse_args()

K = args.clusters
print(f"--- PAPER-LEVEL CLUSTER: K={K} ---")

print("Loading embeddings...")
X = np.load(EMB_PATH).astype(np.float32)  # promote fp16 -> fp32 for sklearn
print(f"  shape: {X.shape}")
# Embeddings are already normalized from encode(...), but re-normalize defensively.
norms = np.linalg.norm(X, axis=1, keepdims=True)
norms[norms == 0] = 1.0
X /= norms

ids = pl.read_parquet(IDS_PATH)
assert len(ids) == X.shape[0], "embedding/id length mismatch"

print(f"Clustering into {K}...")
km = MiniBatchKMeans(
    n_clusters=K,
    random_state=args.seed,
    batch_size=16384,
    n_init=10,
    max_iter=200,
    reassignment_ratio=0.005,
)
km.fit(X)

print("Saving labels and centroids...")
out_clusters = ids.with_columns(pl.Series("cluster_label", km.labels_.astype(np.int32)))
out_clusters.write_parquet(f"{OUT_DIR}/paper_clusters_K{K}.parquet")

# Normalize centroids for cosine lookups downstream.
C = km.cluster_centers_.astype(np.float32)
C /= np.linalg.norm(C, axis=1, keepdims=True).clip(min=1e-12)
np.save(f"{OUT_DIR}/cluster_centroids_K{K}.npy", C)

# Cluster size summary.
unique, counts = np.unique(km.labels_, return_counts=True)
print("Cluster sizes (min/median/max):",
      int(counts.min()), int(np.median(counts)), int(counts.max()))
print("Done.")
