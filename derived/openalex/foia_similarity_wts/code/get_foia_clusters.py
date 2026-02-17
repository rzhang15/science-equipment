import pandas as pd
import numpy as np
import scipy.sparse
import pickle
from sklearn.cluster import KMeans

# --- CONFIGURATION ---
FOIA_MATRIX_PATH = "../output/tfidf_foia.npz"
FOIA_IDS_PATH = "../output/foia_ids_ordered.csv"
FEATURE_NAMES_PATH = "../output/feature_names.pkl" # Created in Step 1

def analyze_foia():
    print("Loading Data...")
    try:
        X_foia = scipy.sparse.load_npz(FOIA_MATRIX_PATH)
        df_ids = pd.read_csv(FOIA_IDS_PATH)
        with open(FEATURE_NAMES_PATH, "rb") as f:
            feature_names = pickle.load(f)
    except FileNotFoundError:
        print("ERROR: feature_names.pkl not found. Did you re-run the vectorizer script?")
        return

    # 1. OVERALL TOP KEYWORDS
    # We sum the TF-IDF scores for each word across all 94 authors
    print("\n" + "="*40)
    print("TOP 15 KEYWORDS (Entire FOIA Sample)")
    print("="*40)
    
    mean_scores = np.array(X_foia.mean(axis=0)).flatten()
    # Get indices of the top 15 words
    top_indices = mean_scores.argsort()[::-1][:15]
    
    for i, idx in enumerate(top_indices):
        print(f"{i+1:2d}. {feature_names[idx]} (Score: {mean_scores[idx]:.4f})")

    # 2. CLUSTERING (K-MEANS)
    # We choose 6 clusters to capture broad fields (Neuro, Immuno, Cell Bio, etc.)
    k = 6
    print("\n" + "="*40)
    print(f"CLUSTERING AUTHORS INTO {k} GROUPS")
    print("="*40)
    
    kmeans = KMeans(n_clusters=k, random_state=42, n_init=20)
    clusters = kmeans.fit_predict(X_foia)
    df_ids['cluster'] = clusters
    
    # Analyze each cluster
    for cluster_id in range(k):
        # Find authors in this cluster
        mask = clusters == cluster_id
        n_authors = np.sum(mask)
        
        # Calculate the centroid (average profile) of this cluster
        centroid = kmeans.cluster_centers_[cluster_id]
        
        # Get top 8 words for this specific cluster
        top_k_indices = centroid.argsort()[::-1][:8]
        keywords = [feature_names[idx] for idx in top_k_indices]
        
        print(f"\n### Cluster {cluster_id} (N={n_authors} PIs) ###")
        print(f"Top Terms: {', '.join(keywords)}")
        
        # Optional: Save results to inspect later
        # df_ids[df_ids['cluster'] == cluster_id].to_csv(f"../output/cluster_{cluster_id}_ids.csv")

if __name__ == "__main__":
    analyze_foia()
