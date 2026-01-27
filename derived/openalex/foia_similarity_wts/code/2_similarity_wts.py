import pandas as pd
import numpy as np
import scipy.sparse
from scipy.sparse import csr_matrix

# --- CONFIGURATION ---
UNIVERSE_MATRIX = "../output/tfidf_universe.npz"
FOIA_MATRIX = "../output/tfidf_foia.npz"
OUTPUT_WEIGHTS = "../output/precomputed_similarity_weights.npz"

BATCH_SIZE = 100_000
SIMILARITY_THRESHOLD = 0.01  # Drop connections < 1% similarity to save massive space

# --- LOAD ---
print("Loading TF-IDF Matrices...")
X_univ = scipy.sparse.load_npz(UNIVERSE_MATRIX)
X_foia = scipy.sparse.load_npz(FOIA_MATRIX)
n_univ = X_univ.shape[0]
n_foia = X_foia.shape[0]

print(f"Dimensions: Universe {X_univ.shape}, FOIA {X_foia.shape}")

# --- COMPUTE & NORMALIZE (Batched) ---
print("Computing Normalized Similarity Matrix...")

# List to hold sparse blocks
sparse_blocks = []

for start in range(0, n_univ, BATCH_SIZE):
    end = min(start + BATCH_SIZE, n_univ)
    
    # 1. Compute Raw Similarity (Batch x 174)
    # Result is dense because 174 is small
    batch_sim = X_univ[start:end].dot(X_foia.T).toarray()
    
    # 2. Thresholding (Make it sparse)
    # If an author is <1% similar to a PI, treat it as 0. 
    # This reduces file size and noise.
    batch_sim[batch_sim < SIMILARITY_THRESHOLD] = 0
    
    # 3. Row-Normalization (The Math Trick)
    # Sum of weights for each author
    row_sums = batch_sim.sum(axis=1, keepdims=True)
    
    # Avoid division by zero (if author has 0 similarity to ALL PIs)
    # We set these rows to 0 temporarily
    row_sums[row_sums == 0] = 1.0 
    
    # Divide by sum so weights add up to 1
    batch_norm = batch_sim / row_sums
    
    # 4. Convert to Sparse and Append
    sparse_blocks.append(scipy.sparse.csr_matrix(batch_norm))
    
    if start % 1_000_000 == 0:
        print(f"Processed {end}/{n_univ}...")

# --- STACK & SAVE ---
print("Stacking blocks...")
W_final = scipy.sparse.vstack(sparse_blocks)

print(f"Saving Weights Matrix ({W_final.shape})...")
scipy.sparse.save_npz(OUTPUT_WEIGHTS, W_final)

print("Done! You can now delete the TF-IDF matrices if you want to save space.")