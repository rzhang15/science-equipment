import pandas as pd
import numpy as np
import scipy.sparse
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import r2_score

# --- CONFIGURATION ---
WEIGHTS_FILE = "../output/validation_weights_k50.npz"
UNIVERSE_IDS_FILE = "../output/universe_ids.parquet"
FOIA_IDS_FILE = "../output/foia_ids_ordered.csv"
USER_EXPOSURE_FILE = "../external/exposure_wts/athr_exposure.dta"
VALIDATION_PLOT_FILE = "../output/validation_plot.png"

def validate_imputation():
    print("--- Starting Leave-One-Out Validation ---")

    # 1. Load Data
    print("Loading data...")
    W = scipy.sparse.load_npz(WEIGHTS_FILE) # Shape: (N_universe, 94)
    W = W.tocsr()
    df_univ = pd.read_parquet(UNIVERSE_IDS_FILE) # Shape: (N_universe, 1)
    df_foia = pd.read_csv(FOIA_IDS_FILE) # Shape: (94, 1) - Columns of W
    df_exp = pd.read_stata(USER_EXPOSURE_FILE)

    # 2. Align Actual Exposure (Ground Truth)
    # Ensure E is ordered exactly matching the columns of W (df_foia order)
    df_foia_merged = pd.merge(df_foia, df_exp, on='athr_id', how='left')
    df_foia_merged['exposure'] = df_foia_merged['exposure'].fillna(0)
    E_actual = df_foia_merged['exposure'].values 

    # 3. Locate FOIA Authors within the Universe Rows
    # We need to find which row in W corresponds to which column in W
    print("Mapping Universe Rows to FOIA Columns...")
    
    # Create a map: athr_id -> universe_row_index
    univ_id_to_idx = {id_: idx for idx, id_ in enumerate(df_univ['athr_id'])}
    
    # Find the row indices for our 94 FOIA authors
    foia_row_indices = []
    foia_col_indices = []
    valid_actuals = []
    
    found_count = 0
    for col_idx, row in df_foia.iterrows():
        aid = row['athr_id']
        if aid in univ_id_to_idx:
            row_idx = univ_id_to_idx[aid]
            foia_row_indices.append(row_idx)
            foia_col_indices.append(col_idx) # This author is at this column in W
            valid_actuals.append(E_actual[col_idx])
            found_count += 1
            
    print(f"Found {found_count} of {len(df_foia)} FOIA authors in the Universe dataset.")
    
    if found_count < 10:
        print("ERROR: Too few FOIA authors found in the universe rows to validate.")
        return

    print(f"Matrix shape is: {W.shape}")

    if W.shape[0] < 10000:
        # CASE A: You loaded the small 'validation_weights_k50.npz'
        # The rows are already filtered and ordered exactly as we found them.
        print("Small matrix detected. Using directly as W_sub.")
        W_sub = W.toarray()
    else:
        # CASE B: You loaded the massive 'weight_matrix.npz'
        # We must slice the massive matrix to find our specific rows.
        print(f"Large matrix detected. Slicing using {len(foia_row_indices)} indices...")
        W_sub = W[foia_row_indices, :].toarray()
        
   # 5. Perform Leave-One-Out Prediction with Top-K Filter
    print("Calculating predictions for different K (neighbors)...")
    
    # We will test using all neighbors (current) vs Top 5 vs Top 10
    k_values = [3, 5, 10, 20, 93] 
    results = {}

    for k in k_values:
        E_predicted = []
        
        for i in range(len(W_sub)):
            # Get raw weights
            weights = W_sub[i, :].copy()
            
            # Zero out self
            self_col = foia_col_indices[i]
            weights[self_col] = 0.0
            
            # --- TOP-K FILTERING ---
            if k < len(weights):
                # Find the indices of the top K weights
                # argpartition puts the top K indices at the end
                top_k_indices = np.argpartition(weights, -k)[-k:]
                
                # Create a mask to zero out everything NOT in top K
                mask = np.zeros_like(weights, dtype=bool)
                mask[top_k_indices] = True
                weights[~mask] = 0.0
            # -----------------------

            # Normalize
            w_sum = np.sum(weights)
            if w_sum > 0:
                weights = weights / w_sum
            else:
                weights = np.zeros_like(weights) 
                
            pred = np.dot(weights, E_actual)
            E_predicted.append(pred)
        
        # Calculate score for this K
        corr = np.corrcoef(E_predicted, valid_actuals)[0, 1]
        results[k] = corr
        print(f"K={k} neighbors -> Correlation: {corr:.4f}")

    print("-" * 30)
    best_k = max(results, key=results.get)
    print(f"BEST CONFIGURATION: Top {best_k} neighbors (r={results[best_k]:.4f})")

    # 6. Statistics
    E_predicted = np.array(E_predicted)
    E_target = np.array(valid_actuals)

    correlation = np.corrcoef(E_predicted, E_target)[0, 1]
    r2 = r2_score(E_target, E_predicted)

    print("-" * 30)
    print(f"Validation Results (N={found_count}):")
    print(f"Correlation (r): {correlation:.4f}")
    print(f"R-Squared:       {r2:.4f}")
    print("-" * 30)

    # 7. Visualization
    plt.figure(figsize=(8, 6))
    sns.regplot(x=E_predicted, y=E_target, scatter_kws={'alpha':0.6}, line_kws={'color':'red'})
    plt.title(f'Ground Truth Validation: Text-Implied vs. Actual Exposure\nCorrelation: {correlation:.2f}')
    plt.xlabel('Imputed Exposure (based on Text Similarity only)')
    plt.ylabel('Actual Exposure (based on Spending)')
    plt.grid(True, linestyle='--', alpha=0.5)
    plt.tight_layout()
    plt.savefig(VALIDATION_PLOT_FILE)
    print(f"Plot saved to {VALIDATION_PLOT_FILE}")

if __name__ == "__main__":
    validate_imputation()
