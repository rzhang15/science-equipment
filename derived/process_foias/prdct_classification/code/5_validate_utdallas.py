# 5_validate_utdallas.py
"""
Validates the end-to-end performance of a specific combination of a
gatekeeper and expert model on the UT Dallas data and outputs a detailed
CSV report for all categories, plus a summary text report for high-support categories.
"""
import pandas as pd
import os
import joblib
import argparse
from sklearn.metrics import classification_report
from tqdm import tqdm

import config
from categorize_items import TfidfItemCategorizer, EmbeddingItemCategorizer

def main(gatekeeper_name: str, expert_name: str):
    print("--- Starting Validation on UT Dallas Categories ---")
    print(f"  - Gatekeeper Model: {gatekeeper_name}")
    print(f"  - Expert Model:     {expert_name}")

    # 1. Load the specified gatekeeper model and its vectorizer
    print("\nℹ️ Loading gatekeeper model and vectorizer...")
    try:
        model_filename = f"lab_binary_classifier_{gatekeeper_name}.joblib"
        model_path = os.path.join(config.OUTPUT_DIR, model_filename)
        lab_model = joblib.load(model_path)
        vectorizer_path = os.path.join(config.OUTPUT_DIR, "vectorizer_tfidf.joblib")
        tfidf_vectorizer = joblib.load(vectorizer_path)
    except FileNotFoundError as e:
        print(f"❌ A required model file was not found: {e}. Please run previous scripts.")
        return

    # 2. Initialize the specified expert categorizer
    print("ℹ️ Initializing expert categorizer...")
    try:
        if expert_name == 'tfidf':
            expert_categorizer = TfidfItemCategorizer(config.CATEGORY_MODEL_DATA_PATH, config.CATEGORY_VECTORIZER_PATH)
        elif expert_name == 'bert':
            expert_categorizer = EmbeddingItemCategorizer("bert", "all-MiniLM-L6-v2")
        else:
             raise ValueError(f"Invalid expert name: {expert_name}")
    except Exception as e:
        print(f"❌ Error initializing expert categorizer: {e}")
        return

    # 3. REFACTORED: Load the pre-cleaned, pre-merged UT Dallas ground truth data
    print("\nℹ️ Loading pre-cleaned UT Dallas validation data...")
    try:
        # This ensures we are validating against the exact same data used for training.
        df_validation = pd.read_parquet(config.UT_DALLAS_MERGED_CLEAN_PATH)
        print(f"  - Loaded {len(df_validation)} rows for validation.")
    except FileNotFoundError:
        print(f"❌ Cleaned UT Dallas file not found at: {config.UT_DALLAS_MERGED_CLEAN_PATH}")
        print("   Please run 0_clean_category_file.py first.")
        return

    # 4. Run the prediction pipeline
    print("\nℹ️ Running classification pipeline...")
    descriptions = df_validation[config.CLEAN_DESC_COL]
    
    text_vectors = tfidf_vectorizer.transform(descriptions)
    lab_probabilities = lab_model.predict_proba(text_vectors)[:, 1]
    is_lab_mask = lab_probabilities >= config.PREDICTION_THRESHOLD
    lab_descriptions = descriptions[is_lab_mask]
    
    df_validation['predicted_market'] = "Non-Lab"
    if not lab_descriptions.empty:
        tqdm.pandas(desc=f"  - Categorizing with {expert_name}")
        if expert_name == 'tfidf':
            predictions = lab_descriptions.progress_apply(expert_categorizer.get_item_category)
        else: # BERT
            predictions = lab_descriptions.progress_apply(expert_categorizer.get_item_category)
        df_validation.loc[is_lab_mask, 'predicted_market'] = predictions

    # 5. Simplify true labels for a fair comparison
    nonlab_pattern = '|'.join(config.NONLAB_CATEGORIES)
    is_true_nonlab = df_validation[config.UT_CAT_COL].str.contains(nonlab_pattern, case=False, na=False)
    df_validation['true_market_simplified'] = df_validation[config.UT_CAT_COL]
    df_validation.loc[is_true_nonlab, 'true_market_simplified'] = 'Non-Lab'
    
    y_true = df_validation['true_market_simplified']
    y_pred = df_validation['predicted_market']

    # 6. Generate a performance report DataFrame for ALL categories
    print("\n--- Generating Performance Metrics for ALL Categories ---")
    report_dict = classification_report(y_true, y_pred, zero_division=0, output_dict=True)
    df_report = pd.DataFrame(report_dict).transpose().reset_index().rename(columns={'index': 'category'})
    
    df_report = df_report[df_report['support'].notna()].copy()
    df_report['support'] = df_report['support'].astype(int)

    # 7. Save the full, unfiltered report to CSV
    report_suffix = f"gatekeeper_{gatekeeper_name}_expert_{expert_name}"
    output_csv_path = os.path.join(config.OUTPUT_DIR, f"utdallas_validation_report_{report_suffix}.csv")
    final_cols = ['category', 'precision', 'recall', 'f1-score', 'support']
    df_report[final_cols].to_csv(output_csv_path, index=False)
    print(f"\n✅ Full validation report saved to: {output_csv_path}")

    # 8. Generate and save a filtered text report for high-support categories
    print("\n--- Generating Text Report for High-Support Categories (>= 25 observations) ---")
    high_support_categories = df_report[df_report['support'] >= 25]['category'].tolist()
    text_report = classification_report(y_true, y_pred, labels=high_support_categories, zero_division=0)
    print(text_report)

    text_report_path = os.path.join(config.OUTPUT_DIR, f"utdallas_validation_summary_report_{report_suffix}.txt")
    with open(text_report_path, 'w') as f:
        f.write(f"End-to-End Performance on UT Dallas (Categories with >= 25 Support)\n")
        f.write(f"Gatekeeper: {gatekeeper_name}, Expert: {expert_name}\n")
        f.write("="*80 + "\n")
        f.write(text_report)
    print(f"✅ High-support text report saved to: {text_report_path}")

    # 9. Also save the detailed comparison file as before
    output_comparison_path = os.path.join(config.OUTPUT_DIR, f"utdallas_validation_comparison_{report_suffix}.csv")
    df_validation.to_csv(output_comparison_path, index=False)
    print(f"✅ Detailed comparison results saved to: {output_comparison_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Validate a specific pipeline on UT Dallas categories.")
    parser.add_argument("--gatekeeper", type=str, required=True, choices=['tfidf', 'bert'],
                        help="The gatekeeper model to use.")
    parser.add_argument("--expert", type=str, required=True, choices=['tfidf', 'bert'],
                        help="The single expert model to use.")
    args = parser.parse_args()
    main(gatekeeper_name=args.gatekeeper, expert_name=args.expert)

