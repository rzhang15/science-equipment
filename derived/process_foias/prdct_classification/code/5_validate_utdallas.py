# 5_validate_utdallas.py
"""
Validates the end-to-end performance of a flexibly chosen pipeline
(gatekeeper + expert model + rule overrides) on the UT Dallas ground truth data.
"""
import pandas as pd
import os
import joblib
import argparse
from sklearn.metrics import classification_report

import config
from rule_based_categorizer import RuleBasedCategorizer
from categorize_items import TfidfItemCategorizer, EmbeddingItemCategorizer

def main(gatekeeper_name: str, expert_model_choice: str):
    print("--- Starting Validation on UT Dallas Data ---")
    print(f"  - Gatekeeper Model:  {gatekeeper_name}")
    print(f"  - Expert Model Choice: {expert_model_choice}")

    # 1. Load Gatekeeper and TF-IDF Vectorizer
    print("\nℹ️ Loading gatekeeper model and vectorizer...")
    try:
        gatekeeper_model_path = os.path.join(config.OUTPUT_DIR, f"hybrid_classifier_{gatekeeper_name}.joblib")
        gatekeeper_model = joblib.load(gatekeeper_model_path)
        vectorizer_path = os.path.join(config.OUTPUT_DIR, "vectorizer_tfidf.joblib")
        tfidf_vectorizer = joblib.load(vectorizer_path)
    except FileNotFoundError as e:
        print(f"❌ A required model file was not found: {e}. Please run previous scripts.")
        return

    # 2. Decompose choice and load the correct Expert Model/Categorizer
    model_type, embedding_type = expert_model_choice.rsplit('_', 1)
    expert_predictor = None

    if model_type == 'parametric':
        model_filename = f"expert_classifier_{embedding_type}.joblib"
        print(f"ℹ️ Loading the parametric expert model ({model_filename})...")
        try:
            expert_model_path = os.path.join(config.OUTPUT_DIR, model_filename)
            expert_predictor = joblib.load(expert_model_path)
        except FileNotFoundError:
            print(f"❌ Expert model not found. Run 2b_train_expert_classifier.py for '{embedding_type}'.")
            return
    elif model_type == 'non_parametric':
        if embedding_type == 'tfidf':
            print("ℹ️ Initializing the non-parametric TF-IDF categorizer...")
            # This will now use a new, simpler data file
            expert_predictor = TfidfItemCategorizer()
        elif embedding_type == 'bert':
            print("ℹ️ Initializing the non-parametric BERT categorizer...")
            expert_predictor = EmbeddingItemCategorizer("bert", "all-MiniLM-L6-v2")
        else:
            print(f"❌ Invalid non-parametric embedding choice: {embedding_type}")
            return

    if expert_predictor is None:
        print(f"\n❌ CRITICAL ERROR: The expert model '{expert_model_choice}' failed to initialize.")
        return

    # 3. Initialize Rule-Based Overrides
    rule_categorizer = RuleBasedCategorizer(config.MARKET_RULES_YAML)

    # 4. Load the clean, ground-truth validation data
    print("\nℹ️ Loading clean ground-truth data for validation...")
    try:
        df_validation = pd.read_parquet(config.UT_DALLAS_MERGED_CLEAN_PATH)
    except FileNotFoundError:
        print(f"❌ Cleaned UT Dallas file not found at: {config.UT_DALLAS_MERGED_CLEAN_PATH}")
        print("   Please run 0_clean_category_file.py first.")
        return
    
    descriptions = df_validation[config.CLEAN_DESC_COL].astype(str).fillna("")

    # 5. Run the full prediction pipeline
    print("  - Step 1: Identifying potential lab items with gatekeeper...")
    text_vectors_tfidf = tfidf_vectorizer.transform(descriptions)
    is_lab_predictions = gatekeeper_model.predict(descriptions)
    is_lab_mask = (is_lab_predictions == 1)
    print(f"  - Gatekeeper found {is_lab_mask.sum()} potential lab items.")

    # Step B: Expert model prediction (only on lab-flagged items)
    print("  - Step 2: Predicting markets for lab items with the expert model...")
    df_validation['predicted_market'] = "Non-Lab" # Set default for all
    if is_lab_mask.any():
        if model_type.strip() == 'parametric':
            lab_vectors = text_vectors_tfidf[is_lab_mask]
            predictions = expert_predictor.predict(lab_vectors)
            df_validation.loc[is_lab_mask, 'predicted_market'] = predictions
        else: # non_parametric (tfidf or bert)
            lab_descriptions = descriptions[is_lab_mask]
            predictions = lab_descriptions.apply(expert_predictor.get_item_category)
            df_validation.loc[is_lab_mask, 'predicted_market'] = predictions

    # Step C: Final rule-based overrides (applied to ALL items)
    print("  - Step 3: Applying rule-based overrides across the entire dataset...")
    # Apply rules to the complete 'descriptions' Series
    overrides = descriptions.apply(rule_categorizer.get_market_override)

    # Find all rows where a rule provided a category
    override_mask = overrides.notna()
    if override_mask.any():
        # Apply the overrides, overwriting any previous prediction
        df_validation.loc[override_mask, 'predicted_market'] = overrides[override_mask]
        print(f"  - Applied {override_mask.sum()} rule-based overrides.")
    else:
        print("  - No rule-based overrides were applied.")
    # 6. Prepare data for reporting
    nonlab_pattern = '|'.join(config.NONLAB_CATEGORIES)
    is_true_nonlab = df_validation[config.UT_CAT_COL].str.contains(nonlab_pattern, case=False, na=False)
    df_validation['true_market_simplified'] = df_validation[config.UT_CAT_COL]
    df_validation.loc[is_true_nonlab, 'true_market_simplified'] = 'Non-Lab'
    
    y_true = df_validation['true_market_simplified']
    y_pred = df_validation['predicted_market']

    # 7. Generate and save the detailed CSV report for ALL categories
    print("\n--- Generating Detailed CSV Report ---")
    report_dict = classification_report(y_true, y_pred, output_dict=True, zero_division=0)
    report_df = pd.DataFrame(report_dict).transpose()
    report_df = report_df[~report_df.index.isin(['accuracy', 'macro avg', 'weighted avg'])]
    report_df.index.name = 'category'
    
    report_suffix = f"gatekeeper_{gatekeeper_name}_expert_{expert_model_choice}"
    csv_report_path = os.path.join(config.OUTPUT_DIR, f"utdallas_full_report_{report_suffix}.csv")
    report_df.to_csv(csv_report_path)
    print(f"✅ Full performance report for all categories saved to: {csv_report_path}")

    # 8. Generate and save the focused TXT report for high-support categories
    print("\n--- Generating Focused Text Report (Support >= 25) ---")
    high_support_labels = report_df[report_df['support'] >= 25].index.tolist()
    
    if 'Non-Lab' in report_df.index and 'Non-Lab' not in high_support_labels:
        high_support_labels.append('Non-Lab')

    txt_report = classification_report(y_true, y_pred, labels=high_support_labels, zero_division=0)
    print("\n--- Model Performance Report (Support >= 25) ---")
    print(txt_report)

    txt_report_path = os.path.join(config.OUTPUT_DIR, f"utdallas_summary_report_{report_suffix}.txt")
    with open(txt_report_path, 'w') as f:
        f.write(f"Summary Performance Report (Support >= 25)\n")
        f.write(f"Gatekeeper: {gatekeeper_name}, Expert: {expert_model_choice}\n")
        f.write("="*70 + "\n")
        f.write(txt_report)
    print(f"✅ Summary text report saved to: {txt_report_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Validate a classification pipeline on UT Dallas data.")
    parser.add_argument("--gatekeeper", type=str, required=True, choices=['tfidf', 'bert'])
    parser.add_argument(
        "--expert_model",
        type=str,
        required=True,
        choices=['parametric_tfidf', 'non_parametric_tfidf', 'non_parametric_bert'],
    )
    args = parser.parse_args()
    main(gatekeeper_name=args.gatekeeper, expert_model_choice=args.expert_model)

