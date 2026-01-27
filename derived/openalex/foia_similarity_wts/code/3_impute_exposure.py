import pandas as pd
import numpy as np
import scipy.sparse
import os

# --- CONFIGURATION ---
WEIGHTS_FILE = "../output/precomputed_similarity_weights.npz"
UNIVERSE_IDS_FILE = "../output/universe_ids.parquet"
FOIA_IDS_FILE = "../output/foia_ids_ordered.csv"

# INPUT: Your small CSV with columns ['athr_id', 'exposure']
USER_EXPOSURE_FILE = "../output/foia_exposure_values.csv" 

# OUTPUT
OUTPUT_FILE = "../output/final_imputed_exposure.csv"

# --- CHECK FILES ---
if not os.path.exists(USER_EXPOSURE_FILE):
    print("Please create your exposure CSV first!")
    exit()

print("Loading Pre-Computed Weights...")
W = scipy.sparse.load_npz(WEIGHTS_FILE) # Shape: (15M, 174)

print("Loading IDs...")
df_univ_ids = pd.read_parquet(UNIVERSE_IDS_FILE)
df_foia_ids = pd.read_csv(FOIA_IDS_FILE) # Must be the exact order used in Step 1

# --- ALIGN EXPOSURE VECTOR ---
print("Aligning Exposure Data...")
# Load user values
df_values = pd.read_csv(USER_EXPOSURE_FILE)

# Merge onto the ORDERED list of FOIA IDs to ensure vector alignment
# We use 'left' to keep the order of df_foia_ids intact
df_aligned = pd.merge(df_foia_ids, df_values, on='athr_id', how='left')

# Fill missing (if you dropped a PI from your stats) with 0 or mean
df_aligned['exposure'] = df_aligned['exposure'].fillna(0)

# Create the Vector E (174 x 1)
E = df_aligned['exposure'].values

# --- THE ONE-STEP CALCULATION ---
print("Calculating...")
# Matrix (15M x 174) dot Vector (174 x 1) -> Result (15M x 1)
imputed_exposure = W.dot(E)

# --- SAVE ---
df_univ_ids['exposure'] = imputed_exposure
df_univ_ids.to_csv(OUTPUT_FILE, index=False)

print(f"Done! Saved to {OUTPUT_FILE}")
print(f"Quick check - Mean Exposure: {np.mean(imputed_exposure):.5f}")
