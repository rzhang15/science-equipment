# 5_validate_utdallas.py (Final Version with Prediction Source Tracking)
"""
Validates the end-to-end performance of a pipeline on the ENTIRE
UT Dallas dataset and generates multiple, detailed report files,
including the source of each prediction (model vs. rule).
"""
import pandas as pd
import os
import joblib
import argparse
from sklearn.metrics import classification_report

import config
from rule_based_categorizer import RuleBasedCategorizer
from categorize_items import TfidfItemCategorizer, EmbeddingItemCategorizer

def main(gatekeeper_name: str, expert_model_choice: str, min_support: int = 25):
    print("="*80)
    print("⚠️ WARNING: This script validates on the FULL dataset, including data the")
    print("         gatekeeper was trained on. Results are optimistically biased and")
    print("         should NOT be used for formal performance reporting.")
    print("="*80)
    print(f"\n--- Starting Validation on FULL UT Dallas Data ---")
    print(f"  - Gatekeeper Model:      {gatekeeper_name}")
    print(f"  - Expert Model Choice:   {expert_model_choice}")
    print(f"  - Summary Report Support: >= {min_support} items")

    # 1. Load all models and categorizers
    print("\nℹ️ Loading all necessary models and vectorizers...")
    gatekeeper_model = joblib.load(os.path.join(config.OUTPUT_DIR, f"hybrid_classifier_{gatekeeper_name}.joblib"))
    
    model_type, embedding_type = expert_model_choice.rsplit('_', 1)
    if model_type == 'non_parametric':
        expert_predictor = TfidfItemCategorizer() if embedding_type == 'tfidf' else EmbeddingItemCategorizer("bert", "all-MiniLM-L6-v2")
    else:
        raise NotImplementedError("Parametric model validation not implemented in this version.")

    rule_categorizer = RuleBasedCategorizer(config.MARKET_RULES_YAML)

    # 2. Load the FULL UT Dallas data
    print("\nℹ️ Loading FULL UT Dallas data for validation...")
    df_validation = pd.read_parquet(config.UT_DALLAS_MERGED_CLEAN_PATH)

    # 3. Get true labels and descriptions
    y_true_full = df_validation[config.UT_CAT_COL]
    descriptions = df_validation[config.CLEAN_DESC_COL].astype(str).fillna("")

    # 4. Run the full prediction pipeline
    print("\nℹ️ Running the full prediction pipeline on the full dataset...")
    
    # +++ MODIFIED: Initialize the prediction source column +++
    df_output = df_validation.copy()
    df_output['prediction_source'] = 'Non-Lab' # Default value
    y_pred = pd.Series("Non-Lab", index=df_validation.index)
    
    is_lab_mask = (gatekeeper_model.predict(descriptions) == 1)
    print(f"  - Gatekeeper identified {is_lab_mask.sum()} potential lab items.")

    if is_lab_mask.any():
        lab_descriptions = descriptions[is_lab_mask]
        expert_predictions = lab_descriptions.apply(expert_predictor.get_item_category)
        y_pred.update(expert_predictions)
        # +++ MODIFIED: Track that these predictions came from the expert model +++
        df_output.loc[expert_predictions.index, 'prediction_source'] = 'Expert Model'

    overrides = descriptions.apply(rule_categorizer.get_market_override)
    valid_overrides = overrides.dropna()
    y_pred.update(valid_overrides)
    print(f"  - Applied {len(valid_overrides)} rule-based overrides.")
    # +++ MODIFIED: Track that these predictions came from market rules +++
    if not valid_overrides.empty:
        df_output.loc[valid_overrides.index, 'prediction_source'] = 'Market Rules'

    # 5. Simplify true labels and handle NaNs
    nonlab_pattern = '|'.join(config.NONLAB_CATEGORIES)
    is_true_nonlab = y_true_full.str.contains(nonlab_pattern, case=False, na=False)
    y_true_simplified = y_true_full.copy()
    y_true_simplified.loc[is_true_nonlab] = 'Non-Lab'
    
    y_true_simplified = y_true_simplified.fillna("unclassified")
    y_pred = y_pred.fillna("unclassified")

    # 6. Generate classification report as a dictionary
    print("\nℹ️ Generating full performance report...")
    report_dict = classification_report(y_true_simplified, y_pred, zero_division=0, output_dict=True)
    df_report = pd.DataFrame(report_dict).transpose()
    df_report['support'] = df_report['support'].astype(int)

    # 7. Generate and save the multiple output files
    print("✅ Generating and saving output files...")
    
    # --- Define File Names ---
    base_name_clf = f"classified_with_{expert_model_choice}"
    base_name_report = f"gatekeeper_{gatekeeper_name}_expert_{expert_model_choice}"
    
    path_predictions_csv = os.path.join(config.OUTPUT_DIR, f"utdallas_merged_clean_{base_name_clf}.csv")
    path_full_report_csv = os.path.join(config.OUTPUT_DIR, f"utdallas_full_report_{base_name_report}.csv")
    path_summary_report_txt = os.path.join(config.OUTPUT_DIR, f"utdallas_summary_report_{base_name_report}.txt")

    # --- Save Full Report CSV ---
    df_report.to_csv(path_full_report_csv)
    print(f"  - Full performance report (all categories) saved to: {path_full_report_csv}")
    
    # --- Save Summary Report TXT ---
    df_summary = df_report[df_report['support'] >= min_support]
    with open(path_summary_report_txt, 'w') as f:
        f.write(f"WARNING: RESULTS ARE INFLATED. FOR EXPLORATORY USE ONLY.\n")
        f.write(f"Summary Performance Report on FULL DATASET (Support >= {min_support})\n")
        f.write(f"Gatekeeper: {gatekeeper_name}, Expert: {expert_model_choice}\n")
        f.write("="*70 + "\n")
        f.write(df_summary.to_string())
    print(f"  - Summary report (support >= {min_support}) saved to: {path_summary_report_txt}")
    
    # --- Save Detailed Predictions CSV ---
    df_output['predicted_market_final'] = y_pred
    df_output['true_market_simplified'] = y_true_simplified
    # The 'prediction_source' column is now automatically included here
    df_output.to_csv(path_predictions_csv, index=False)
    print(f"  - Detailed row-by-row predictions saved to: {path_predictions_csv}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Validate a classification pipeline on the FULL UT Dallas dataset.")
    parser.add_argument("--gatekeeper", type=str, required=True, choices=['tfidf', 'bert'])
    parser.add_argument("--expert_model", type=str, required=True, choices=['non_parametric_tfidf', 'non_parametric_bert'])
    parser.add_argument("--min_support", type=int, default=25, help="Minimum support for a category to appear in the summary text report.")
    args = parser.parse_args()
    main(gatekeeper_name=args.gatekeeper, expert_model_choice=args.expert_model, min_support=args.min_support)