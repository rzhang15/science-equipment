import pandas as pd
import numpy as np
import scipy.sparse
import os

WEIGHTS_FILE = "../output/weight_matrix.npz"
UNIVERSE_IDS_FILE = "../output/universe_ids.parquet"
FOIA_IDS_FILE = "../output/foia_ids_ordered.csv"
USER_EXPOSURE_FILE = "../external/exposure_wts/athr_exposure.dta" 

OUTPUT_FILE = "../output/final_imputed_exposure.csv"

if not os.path.exists(USER_EXPOSURE_FILE):
    print("Please create your exposure CSV first!")
    exit()

print("Loading Pre-Computed Weights...")
W = scipy.sparse.load_npz(WEIGHTS_FILE) # Shape: (15M, 174)
print("Loading IDs...")
df_univ_ids = pd.read_parquet(UNIVERSE_IDS_FILE)
df_foia_ids = pd.read_csv(FOIA_IDS_FILE) # Must be the exact order used in Step 1

print("Aligning Exposure Data...")
df_values = pd.read_stata(USER_EXPOSURE_FILE)

df_aligned = pd.merge(df_foia_ids, df_values, on='athr_id', how='left')
df_aligned['exposure'] = df_aligned['exposure'].fillna(0)
E = df_aligned['exposure'].values

print("Calculating...")
imputed_exposure = W.dot(E)

df_univ_ids['exposure'] = imputed_exposure
df_univ_ids.to_csv(OUTPUT_FILE, index=False)

print(f"Done! Saved to {OUTPUT_FILE}")
print(f"Quick check - Mean Exposure: {np.mean(imputed_exposure):.5f}")
