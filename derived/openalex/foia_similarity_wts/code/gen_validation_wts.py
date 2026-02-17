import pandas as pd
import numpy as np
import scipy.sparse

# --- CONFIGURATION ---
# We use the same inputs, but we will filter the rows to ONLY FOIA authors
UNIVERSE_IDS_FILE = "../output/universe_ids.parquet"
FOIA_IDS_FILE = "../output/foia_ids_ordered.csv" 
UNIVERSE_MATRIX = "../output/tfidf_universe.npz"
FOIA_MATRIX = "../output/tfidf_foia.npz"
OUTPUT_VAL_WEIGHTS = "../output/validation_weights_k50.npz"

K_HIGH = 50  # Keep 50 so we can test K=5, 10, 20, etc. later

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
X_foia_rows = X_univ_all[foia_row_indices, :] # Only keep the rows we need for validation

print("Loading Target Matrix...")
X_targets = scipy.sparse.load_npz(FOIA_MATRIX)

print("Computing Similarity...")
# This will be small (94 x 94), so we can do it in one shot without batches
sim_matrix = X_foia_rows.dot(X_targets.T).toarray()

# --- APPLY K_HIGH FILTER ---
print(f"Filtering to Top {K_HIGH} neighbors...")
for r in range(sim_matrix.shape[0]):
    row = sim_matrix[r, :]
    if K_HIGH < len(row):
        # Keep top K_HIGH
        cutoff = np.partition(row, -K_HIGH)[-K_HIGH]
        row[row < cutoff] = 0
        sim_matrix[r, :] = row

# Normalize
row_sums = sim_matrix.sum(axis=1, keepdims=True)
row_sums[row_sums == 0] = 1.0
W_val = scipy.sparse.csr_matrix(sim_matrix / row_sums)

print(f"Saving validation weights to {OUTPUT_VAL_WEIGHTS}...")
scipy.sparse.save_npz(OUTPUT_VAL_WEIGHTS, W_val)

