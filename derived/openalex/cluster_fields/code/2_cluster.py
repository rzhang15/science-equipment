import argparse
import numpy as np
import pandas as pd
import scipy.sparse
import pickle
from sklearn.cluster import MiniBatchKMeans

# --- ARGUMENT PARSING ---
parser = argparse.ArgumentParser()
parser.add_argument('--clusters', type=int, required=True)
args = parser.parse_args()

NUM_CLUSTERS = args.clusters
SEED = 42
np.random.seed(SEED)

print(f"--- STARTING FAST CLUSTER JOB: {NUM_CLUSTERS} ---")

# --- LOAD PRE-COMPUTED DATA ---
print("Loading Matrix...")
matrix = scipy.sparse.load_npz("../output/tfidf_matrix.npz")

print("Loading Helper Files...")
feature_names = pickle.load(open("../output/feature_names.pkl", "rb"))
pdf_ids = pd.read_parquet("../output/author_ids_aligned.parquet")

# --- CLUSTERING ---
print(f"Clustering into {NUM_CLUSTERS}...")
# Increased batch_size and n_init slightly for better stability
kmeans = MiniBatchKMeans(
    n_clusters=NUM_CLUSTERS,
    random_state=SEED,
    batch_size=16384, 
    n_init=10 
)
kmeans.fit(matrix)

# --- RESULTS ---
print("Saving Results...")
# Assign labels back to the author IDs
pdf_ids['cluster_label'] = kmeans.labels_
pdf_ids.to_csv(f"../output/author_static_clusters_{NUM_CLUSTERS}.csv", index=False)

# Get Topic Keywords
print("Writing Descriptions...")
centers = kmeans.cluster_centers_
output_txt = f"../output/static_cluster_descriptions_{NUM_CLUSTERS}.txt"

with open(output_txt, 'w') as f:
    for i, center in enumerate(centers):
        # Top 15 words per cluster
        top_idx = center.argsort()[-15:][::-1]
        top_terms = [feature_names[idx] for idx in top_idx]
        desc = f"Cluster {i}: {', '.join(top_terms)}"
        f.write(desc + "\n")

print("Done.")
