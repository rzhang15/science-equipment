# 5_validate_utdallas.py (REVISED to be a simple evaluator)
"""
Loads the pre-processed validation file (containing both predictions and
true labels) and generates a classification report to evaluate performance.
"""
import pandas as pd
import os
import argparse
from sklearn.metrics import classification_report

import config

def main(expert_name: str):
    print("--- Starting Evaluation of Pre-computed Predictions ---")

    # 1. Load the single, enriched prediction file from the standardized path
    print("\nℹ️ Loading enriched validation file...")
    try:
        validation_file_path = config.UTDALLAS_VALIDATION_PREDICTIONS_CSV
        df_validation = pd.read_csv(validation_file_path, low_memory=False)
        print(f"  - Loaded: {os.path.basename(validation_file_path)}")
    except FileNotFoundError:
        print(f"❌ Validation file not found at: {validation_file_path}")
        print("   Please run 'python 3_predict_product_markets.py utdallas ...' first.")
        return

    # 2. Prepare y_true and y_pred from the columns already in the file
    # The file already contains the true 'category' column from the original merge
    nonlab_pattern = '|'.join(config.NONLAB_CATEGORIES)
    is_true_nonlab = df_validation[config.UT_CAT_COL].str.contains(nonlab_pattern, case=False, na=False)
    df_validation['true_market_simplified'] = df_validation[config.UT_CAT_COL]
    df_validation.loc[is_true_nonlab, 'true_market_simplified'] = 'Non-Lab'
    
    y_true = df_validation['true_market_simplified']
    
    prediction_col = f'market_prediction_{expert_name}'
    if prediction_col not in df_validation.columns:
        print(f"❌ Prediction column '{prediction_col}' not found in the input file!")
        return
    y_pred = df_validation[prediction_col]

    # 3. Generate and save the performance reports
    print("\n--- Generating Performance Report ---")
    high_support_categories = y_true.value_counts()
    high_support_categories = high_support_categories[high_support_categories >= 25].index.tolist()
    text_report = classification_report(y_true, y_pred, labels=high_support_categories, zero_division=0)
    print(text_report)

    report_suffix = f"eval_expert_{expert_name}"
    text_report_path = os.path.join(config.OUTPUT_DIR, f"utdallas_evaluation_summary_{report_suffix}.txt")
    with open(text_report_path, 'w') as f:
        f.write("Evaluation Report of 3-Stage Pipeline Predictions\n" + "="*50 + f"\n{text_report}")
    print(f"\n✅ Evaluation summary report saved to: {text_report_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Evaluate the standardized prediction file.")
    parser.add_argument("--expert", type=str, required=True, choices=['tfidf', 'bert'], help="The expert model predictions to evaluate (e.g., 'tfidf').")
    args = parser.parse_args()
    main(expert_name=args.expert)