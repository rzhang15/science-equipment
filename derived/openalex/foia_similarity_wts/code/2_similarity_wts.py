import pandas as pd
import numpy as np
import scipy.sparse

# --- CONFIGURATION ---
UNIVERSE_MATRIX = "../output/tfidf_universe.npz"
FOIA_MATRIX = "../output/tfidf_foia.npz"
OUTPUT_WEIGHTS = "../output/weight_matrix.npz"

BATCH_SIZE = 50000 
SIMILARITY_THRESHOLD = 0.01  # Minimum similarity to even consider (keeps matrix sparse)

K_NEIGHBORS = 5 

# --- LOAD DATA ---
print("Loading TF-IDF Matrices...")
X_univ = scipy.sparse.load_npz(UNIVERSE_MATRIX)
X_foia = scipy.sparse.load_npz(FOIA_MATRIX)

n_users = X_univ.shape[0]
n_pis = X_foia.shape[0]

print(f"Universe Authors: {n_users}")
print(f"FOIA PIs (Targets): {n_pis}")
print(f"Computing weights for {n_users} authors (Batch Size: {BATCH_SIZE})...")

row_ind = []
col_ind = []
data_val = []

for i in range(0, n_users, BATCH_SIZE):
    end = min(i + BATCH_SIZE, n_users)
    
    batch_X = X_univ[i:end]
    batch_sim = batch_X.dot(X_foia.T).toarray()
    
    if K_NEIGHBORS < n_pis:
        for r in range(batch_sim.shape[0]):
            row = batch_sim[r, :]
            if np.count_nonzero(row) > K_NEIGHBORS:
                cutoff_value = np.partition(row, -K_NEIGHBORS)[-K_NEIGHBORS]
                row[row < cutoff_value] = 0
                batch_sim[r, :] = row
    batch_sim[batch_sim < SIMILARITY_THRESHOLD] = 0
    row_sums = batch_sim.sum(axis=1, keepdims=True)
    row_sums[row_sums == 0] = 1.0 
    batch_norm = batch_sim / row_sums
    rows, cols = batch_norm.nonzero()
    row_ind.extend(rows + i)
    col_ind.extend(cols)
    data_val.extend(batch_norm[rows, cols])
    if i % 500000 == 0:
        print(f"Processed {i} authors...")

print("Constructing Final Sparse Weight Matrix...")
W = scipy.sparse.coo_matrix(
    (data_val, (row_ind, col_ind)), 
    shape=(n_users, n_pis)
)

print("Saving to .npz...")
scipy.sparse.save_npz(OUTPUT_WEIGHTS, W)
print("Done. Weights precomputed.")