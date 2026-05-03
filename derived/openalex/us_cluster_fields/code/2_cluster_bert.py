"""
K-means cluster authors using dense BERT/SciBERT embeddings.

Cluster descriptions are written as the 10 authors closest to each centroid.
(Dense embeddings have no readable feature names, unlike TF-IDF.)
"""
import argparse
import numpy as np
import pandas as pd
from sklearn.cluster import MiniBatchKMeans
from sklearn.metrics.pairwise import cosine_similarity

EMB_PATH = "../output/scibert_embeddings.npy"
IDS_PATH = "../output/author_ids_aligned.parquet"

parser = argparse.ArgumentParser()
parser.add_argument("--clusters", type=int, required=True)
args = parser.parse_args()

NUM_CLUSTERS = args.clusters
SEED = 42
np.random.seed(SEED)

print(f"--- BERT-CLUSTER JOB: {NUM_CLUSTERS} ---")
print("Loading embeddings...")
X = np.load(EMB_PATH)
print(f"  shape: {X.shape}")
pdf_ids = pd.read_parquet(IDS_PATH)
assert len(pdf_ids) == X.shape[0], "Embeddings and IDs length mismatch"

print(f"Clustering into {NUM_CLUSTERS}...")
kmeans = MiniBatchKMeans(
    n_clusters=NUM_CLUSTERS,
    random_state=SEED,
    batch_size=16384,
    n_init=10,
)
kmeans.fit(X)

print("Saving cluster labels...")
pdf_ids["cluster_label"] = kmeans.labels_
pdf_ids.to_csv(
    f"../output/author_static_clusters_bert_{NUM_CLUSTERS}.csv", index=False
)

print("Writing cluster descriptions (nearest authors to each centroid)...")
out_txt = f"../output/static_cluster_descriptions_bert_{NUM_CLUSTERS}.txt"
with open(out_txt, "w") as f:
    for i, center in enumerate(kmeans.cluster_centers_):
        in_cluster = np.where(kmeans.labels_ == i)[0]
        if len(in_cluster) == 0:
            f.write(f"Cluster {i}: (empty)\n")
            continue
        sims = cosine_similarity(center.reshape(1, -1), X[in_cluster])[0]
        top_local = in_cluster[sims.argsort()[-10:][::-1]]
        top_authors = pdf_ids.iloc[top_local]["athr_id"].tolist()
        f.write(
            f"Cluster {i} (n={len(in_cluster)}): representative authors = "
            f"{top_authors}\n"
        )

print("Done.")
