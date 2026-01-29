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
ID_COL_NAME      = 'athr_id'
EXP_COL_NAME     = 'exposure'

# --- LOAD DATA ---
print("Loading Data...")
X_foia = scipy.sparse.load_npz(FOIA_MATRIX_PATH)
df_ids = pd.read_csv(FOIA_IDS_PATH)
df_ids[ID_COL_NAME] = df_ids[ID_COL_NAME].astype(str)
df_truth = pd.read_stata(TRUTH_DTA_PATH)
df_truth[ID_COL_NAME] = df_truth[ID_COL_NAME].astype(str)

df_merged = pd.merge(df_ids, df_truth, on=ID_COL_NAME, how='left')
df_merged[EXP_COL_NAME] = df_merged[EXP_COL_NAME].fillna(df_merged[EXP_COL_NAME].mean())
actual_vals = df_merged[EXP_COL_NAME].values

# --- THE MECHANICS CHECK (NO LEAVE-ONE-OUT) ---
print("\nRunning Prediction WITH Self-Inclusion...")
print("(We are allowing the model to 'cheat' by seeing the author themselves)")

full_sim = X_foia.dot(X_foia.T).toarray()
# Note: We do NOT run np.fill_diagonal(full_sim, 0) here.
# The diagonal remains 1.0 (Perfect Self-Similarity)

predicted_vals = np.zeros(len(actual_vals))

for i in range(len(actual_vals)):
    sim_vector = full_sim[i, :]
    
    # We use the full vector, including index [i]
    if np.sum(sim_vector) > 0:
        predicted_vals[i] = np.dot(sim_vector, actual_vals) / np.sum(sim_vector)
    else:
        predicted_vals[i] = np.mean(actual_vals)

# --- CHECK RESULTS ---
pearson_r, _ = pearsonr(actual_vals, predicted_vals)
reg = LinearRegression().fit(predicted_vals.reshape(-1, 1), actual_vals)
beta = reg.coef_[0]

print("-" * 40)
print(f"MECHANICS CHECK RESULTS:")
print("-" * 40)
print(f"Correlation (r): {pearson_r:.4f}  (Should be very high, e.g. > 0.90)")
print(f"Regression Slope: {beta:.4f}      (Should be close to 1.0)")
print("-" * 40)

if pearson_r > 0.9:
    print(">> SUCCESS: The mechanics work. When the model sees the answer, it gets it right.")
else:
    print(">> FAILURE: Something is wrong. Even with the answer key, the model is missing.")

# --- PLOT ---
plt.figure(figsize=(6, 6))
plt.scatter(predicted_vals, actual_vals, alpha=0.6, color='green')
plt.plot([0, max(actual_vals)], [0, max(actual_vals)], 'k--', label='Perfect Identity')
plt.xlabel("Predicted (With Self)")
plt.ylabel("Actual")
plt.title("Sanity Check: Prediction with Self-Inclusion")
plt.legend()
plt.tight_layout()
plt.savefig("../output/mechanics_check.png")
print("Plot saved to ../output/mechanics_check.png")
