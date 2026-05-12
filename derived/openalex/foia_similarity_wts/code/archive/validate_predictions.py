import pandas as pd
import numpy as np
import scipy.sparse
from scipy.stats import pearsonr
import matplotlib.pyplot as plt
from sklearn.linear_model import LinearRegression

# --- CONFIGURATION ---
FOIA_MATRIX_PATH = "../output/tfidf_foia.npz"
FOIA_IDS_PATH    = "../output/foia_ids_ordered.csv"
TRUTH_DTA_PATH   = "../external/exposure_wts/athr_exposure.dta"
PLOT_PATH        = "../output/mechanics_check_topk.png"

# --- TUNING PARAMETERS ---
K_NEIGHBORS = 5  # <--- Test this with 5

# Variable Names
ID_COL_NAME  = 'athr_id'
EXP_COL_NAME = 'exposure'

# --- 1. LOAD DATA ---
print(f"Loading Data (Mechanics Check, K={K_NEIGHBORS})...")
X_foia = scipy.sparse.load_npz(FOIA_MATRIX_PATH)
df_ids = pd.read_csv(FOIA_IDS_PATH)
df_ids[ID_COL_NAME] = df_ids[ID_COL_NAME].astype(str)

try:
    df_truth = pd.read_stata(TRUTH_DTA_PATH)
    df_truth[ID_COL_NAME] = df_truth[ID_COL_NAME].astype(str)
except FileNotFoundError:
    print(f"Error: Could not find {TRUTH_DTA_PATH}")
    exit()

# Merge and align
df_merged = pd.merge(df_ids, df_truth, on=ID_COL_NAME, how='left')
df_merged[EXP_COL_NAME] = df_merged[EXP_COL_NAME].fillna(df_merged[EXP_COL_NAME].mean())
actual_vals = df_merged[EXP_COL_NAME].values

# --- 2. RUN "CHEAT" PREDICTION (Self-Included + Top K) ---
print("Running Prediction (Self-Included)...")
predicted_vals = np.zeros(len(actual_vals))

full_sim = X_foia.dot(X_foia.T).toarray()
# NOTE: We DO NOT set diagonal to 0 here. We let the author see themselves.

for i in range(len(actual_vals)):
    sim_vector = full_sim[i, :]
    
    # --- TOP-K FILTER ---
    # Even when "cheating," we only want to listen to the K best matches.
    # Since self-similarity is 1.0, "Self" will always be in this Top K group.
    if len(sim_vector) > K_NEIGHBORS:
        top_k_indices = np.argsort(sim_vector)[-K_NEIGHBORS:]
        mask = np.zeros_like(sim_vector)
        mask[top_k_indices] = 1
        sim_vector = sim_vector * mask
    # --------------------

    sum_weights = np.sum(sim_vector)
    
    if sum_weights > 0:
        predicted_vals[i] = np.dot(sim_vector, actual_vals) / sum_weights
    else:
        predicted_vals[i] = np.mean(actual_vals)

# --- 3. METRICS ---
pearson_r, _ = pearsonr(actual_vals, predicted_vals)
reg = LinearRegression().fit(predicted_vals.reshape(-1, 1), actual_vals)
beta = reg.coef_[0]

print("-" * 50)
print(f"MECHANICS CHECK RESULTS (K={K_NEIGHBORS})")
print("-" * 50)
print(f"Correlation (r): {pearson_r:.4f}")
print(f"Regression Slope: {beta:.4f}")
print("-" * 50)

if pearson_r > 0.98:
    print(">> PERFECT: The model is prioritizing the 'Self' match correctly.")
    print("   With K=5, the 'Self' weight dominates the neighbors.")
elif pearson_r > 0.90:
    print(">> GOOD: The mechanics work, though neighbors still have some influence.")
else:
    print(">> WARNING: Something is diluting the self-match too much.")

# --- 4. PLOT ---
plt.figure(figsize=(6, 6))
plt.scatter(predicted_vals, actual_vals, alpha=0.6, color='green')
plt.plot([0, max(actual_vals)], [0, max(actual_vals)], 'k--', label='Perfect Identity')
plt.title(f"Mechanics Check (Top-{K_NEIGHBORS}): R={pearson_r:.3f}")
plt.xlabel("Predicted (With Self)")
plt.ylabel("Actual")
plt.tight_layout()
plt.savefig(PLOT_PATH)
print(f"Plot saved to {PLOT_PATH}")