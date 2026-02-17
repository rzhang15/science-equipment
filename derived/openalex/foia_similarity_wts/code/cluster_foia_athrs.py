import pandas as pd
import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.cluster import KMeans

# --- CONFIGURATION ---
INPUT_FILE = '../output/foia_author_text_final.csv'
N_CLUSTERS = 5  # Start with 5 broad fields
TOP_TERMS  = 15 # How many descriptive words to show per cluster

# --- 1. LOAD DATA ---
print("Loading FOIA dataset...")
df = pd.read_csv(INPUT_FILE)

# Drop anyone with missing text to avoid errors
original_len = len(df)
df = df.dropna(subset=['processed_text'])
df = df[df['processed_text'].str.strip() != ""]
print(f"Clustering {len(df)} authors (Dropped {original_len - len(df)} empty rows).")

# --- 2. VECTORIZE TEXT ---
print("Vectorizing text...")
# We use max_features=1000 to focus on the most important scientific words
tfidf = TfidfVectorizer(
    max_features=1000, 
    stop_words='english', 
    ngram_range=(1, 2) # Use 1-2 word phrases (e.g., "cell culture")
)
X = tfidf.fit_transform(df['processed_text'])
feature_names = np.array(tfidf.get_feature_names_out())

# --- 3. RUN K-MEANS CLUSTERING ---
print(f"Running K-Means with {N_CLUSTERS} clusters...")
kmeans = KMeans(n_clusters=N_CLUSTERS, random_state=42, n_init=10)
kmeans.fit(X)

# Assign cluster labels back to the dataframe
df['cluster_id'] = kmeans.labels_

# --- 4. INTERPRET CLUSTERS ---
print("\n" + "="*60)
print("CLUSTER ANALYSIS: SUBFIELD COVERAGE")
print("="*60)

# Calculate size of each cluster
cluster_sizes = df['cluster_id'].value_counts().sort_index()

# Get cluster centers (the "average" text of that group)
centroids = kmeans.cluster_centers_

for i in range(N_CLUSTERS):
    # Find the top indices for this cluster center
    top_indices = centroids[i].argsort()[-TOP_TERMS:][::-1]
    top_terms = feature_names[top_indices]
    
    # Print nice report
    size = cluster_sizes[i]
    pct = (size / len(df)) * 100
    
    print(f"\nCLUSTER {i+1}: {size} Authors ({pct:.1f}%)")
    print("-" * 30)
    print(", ".join(top_terms))
    
    # Optional: Print 1-2 Example Titles/IDs if you have them, 
    # otherwise just looking at words is usually enough.

print("\n" + "="*60)

# --- 5. CHECK FOR "ORPHAN" CLUSTERS ---
# If a cluster has only 1-2 people, it means they are outliers 
# (e.g., the only physicist in a room of biologists).
small_clusters = cluster_sizes[cluster_sizes < 3]
if not small_clusters.empty:
    print(f"\nWARNING: Clusters {list(small_clusters.index)} are tiny (<3 authors).")
    print("These might be outliers or mismatches.")

# --- 6. SAVE RESULTS ---
output_path = "../output/foia_clusters.csv"
df[['athr_id', 'cluster_id']].to_csv(output_path, index=False)
print(f"\nCluster assignments saved to: {output_path}")
