import pandas as pd
import numpy as np
import scipy.sparse

# --- CONFIGURATION ---
UNIVERSE_IDS_FILE = "../output/universe_ids.parquet"
FOIA_IDS_FILE = "../output/foia_ids_ordered.csv" 
UNIVERSE_MATRIX = "../output/tfidf_universe.npz"
FOIA_MATRIX = "../output/tfidf_foia.npz"
# Save this as a SEPARATE validation file so you don't overwrite your main weights
OUTPUT_VAL_WEIGHTS = "../output/validation_weights_k50.npz" 

K_HIGH = 50  # We keep 50 to allow testing K=10, 20, etc.

# --- LOAD DATA ---
print("Loading IDs...")
df_univ = pd.read_parquet(UNIVERSE_IDS_FILE)
df_foia = pd.read_csv(FOIA_IDS_FILE)

# Find which rows in the Universe matrix correspond to FOIA authors
print("Mapping FOIA authors to Universe rows...")
univ_id_to_idx = {id_: idx for idx, id_ in enumerate(df_univ['athr_id'])}
foia_row_indices = [univ_id_to_idx[aid] for aid in df_foia['athr_id'] if aid in univ_id_to_idx]

print(f"Loading Universe Matrix and slicing {len(foia_row_indices)} FOIA rows...")
X_univ_all = scipy.sparse.load_npz(UNIVERSE_MATRIX)
# Only keep the rows for FOIA authors (very fast)
X_foia_rows = X_univ_all[foia_row_indices, :] 

print("Loading Target Matrix...")
X_targets = scipy.sparse.load_npz(FOIA_MATRIX)

print("Computing Similarity (Dense)...")
# Since 94x94 is tiny, we can compute the dense matrix directly
sim_matrix = X_foia_rows.dot(X_targets.T).toarray()

# --- FILTER TO TOP 50 ---
print(f"Filtering to Top {K_HIGH} neighbors...")
for r in range(sim_matrix.shape[0]):
    row = sim_matrix[r, :]
    if K_HIGH < len(row):
        # Keep top K_HIGH
        cutoff = np.partition(row, -K_HIGH)[-K_HIGH]
        row[row < cutoff] = 0
        sim_matrix[r, :] = row

# Normalize rows to sum to 1
row_sums = sim_matrix.sum(axis=1, keepdims=True)
row_sums[row_sums == 0] = 1.0
W_val = scipy.sparse.csr_matrix(sim_matrix / row_sums)

print(f"Saving validation weights to {OUTPUT_VAL_WEIGHTS}...")
scipy.sparse.save_npz(OUTPUT_VAL_WEIGHTS, W_val)
