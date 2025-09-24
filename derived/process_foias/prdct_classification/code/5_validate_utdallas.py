# 5_validate_on_utdallas.py (Updated for Dense Category Validation)
"""
Validates the end-to-end performance of all classification models by first
filtering the UT Dallas dataset to only include categories with sufficient data,
then comparing predictions against the original, manually-coded categories.
"""
import pandas as pd
import os
import joblib
from sklearn.metrics import classification_report
from tqdm import tqdm


import config
from categorize_items import TfidfItemCategorizer, EmbeddingItemCategorizer, Word2VecItemCategorizer

def main():
    print("--- Starting Validation on UT Dallas Dense Categories ---")

    # 1. Load the TF-IDF Binary Classifier (The "Gatekeeper")
    print("ℹ️ Loading TF-IDF Lab/Not-Lab model...")
    try:
        lab_model = joblib.load(config.LAB_MODEL_PATH)
    except FileNotFoundError:
        print("❌ Lab/Not-Lab model not found. Please run relevant scripts first.")
        return
    print("ℹ️ Initializing product market categorizers...")
    try:
        categorizers = {
            "tfidf": TfidfItemCategorizer(config.CATEGORY_MODEL_DATA_PATH, config.CATEGORY_VECTORIZER_PATH),
            "bert": EmbeddingItemCategorizer("bert", "all-MiniLM-L6-v2")
        }
    except Exception as e:
        print(f"❌ Error initializing categorizers: {e}")
        return
    # 3. Load and merge the full UT Dallas ground truth data
    print("ℹ️ Loading and merging full UT Dallas dataset...")
    try:
        df_ut = pd.read_csv(config.UT_DALLAS_CLEAN_CSV, engine='pyarrow')
        feather_path = config.UT_DALLAS_CATEGORIES_FEATHER
        excel_path = config.UT_DALLAS_CATEGORIES_XLSX
        if os.path.exists(feather_path):
            df_cat = pd.read_feather(feather_path)
        else: # Fallback to create feather file if it doesn't exist
            df_cat = pd.read_excel(excel_path, keep_default_na=False, na_values=[''])
            df_cat.to_feather(feather_path)

        if 'clean_desc' in df_cat.columns:
            df_cat = df_cat.drop(columns=['clean_desc'])
        for key in config.UT_DALLAS_MERGE_KEYS:
            if key in df_ut.columns and key in df_cat.columns:
                df_ut[key] = df_ut[key].astype(str)
                df_cat[key] = df_cat[key].astype(str)

        df_full_truth = pd.merge(df_ut, df_cat, on=config.UT_DALLAS_MERGE_KEYS, how='left', validate="many_to_one")
        df_full_truth.dropna(subset=[config.CLEAN_DESC_COL, config.UT_CAT_COL], inplace=True)
        df_full_truth['cleaned_description'] = df_full_truth[config.CLEAN_DESC_COL].fillna('')
    except Exception as e:
        print(f"❌ Could not load or merge UT Dallas data: {e}")
        return
        print(f"\nℹ️ Filtering validation data for dense categories (>= {config.DENSE_CATEGORY_THRESHOLD} observations)...")
    category_counts = df_full_truth[config.UT_CAT_COL].value_counts()
    dense_categories = category_counts[category_counts >= config.DENSE_CATEGORY_THRESHOLD].index.tolist()
    
    df_validation = df_full_truth[df_full_truth[config.UT_CAT_COL].isin(dense_categories)].copy()
    print(f"  - Original items: {len(df_full_truth)}")
    print(f"  - Items for validation (in {len(dense_categories)} dense categories): {len(df_validation)}")

    # PERFORMANCE FIX: Run predictions in batches instead of a slow loop
    print("\nℹ️ Running classification pipeline on the filtered validation set...")
    descriptions = df_validation['cleaned_description']
    
    # Step 1: Run the fast "gatekeeper" model on all descriptions at once
    lab_probabilities = lab_model.predict_proba(descriptions)[:, 1]
    is_lab_mask = lab_probabilities >= config.PREDICTION_THRESHOLD
    lab_descriptions = descriptions[is_lab_mask]
    
    # Step 2: Run the expert models only on the items flagged as "Lab"
    for model_name, categorizer in categorizers.items():
        print(f"  - Predicting with {model_name}...")
        
        # Start with a default prediction of "Non-Lab"
        df_validation[f'predicted_market_{model_name}'] = "Non-Lab"
        
        # Use .progress_apply for a progress bar on the subset of lab items
        tqdm.pandas(desc=f"  - Categorizing with {model_name}")
        if model_name == 'tfidf':
            predictions = lab_descriptions.progress_apply(
                lambda desc: categorizer.get_item_category(desc, sim_weight=config.CATEGORY_SIMILARITY_WEIGHT, overlap_weight=config.CATEGORY_OVERLAP_WEIGHT)
            )
        else:
            predictions = lab_descriptions.progress_apply(categorizer.get_item_category)
        
        # Place the expert predictions into the correct rows
        df_validation.loc[is_lab_mask, f'predicted_market_{model_name}'] = predictions

    # 7. Generate and save a report for each model
    print("\n--- Model Performance Reports (on Dense Categories) ---")
    y_true = df_validation['true_market_simplified']
    for model_name in categorizers.keys():
        print(f"\n--- Report for: {model_name} ---")
        y_pred = df_validation[f'predicted_market_{model_name}']
        
        # Get all unique labels from both true and predicted values for the report
        report_labels = sorted(list(pd.unique(y_true.tolist() + y_pred.tolist())))

        report = classification_report(y_true, y_pred, labels=report_labels, zero_division=0)
        print(report)

        report_path = os.path.join(config.OUTPUT_DIR, f"utdallas_validation_report_{model_name}.txt")
        with open(report_path, 'w') as f:
            f.write(f"End-to-End System Performance on UT Dallas (Dense Categories Only)\n")
            f.write("="*60 + "\n")
            f.write(report)
        print(f"✅ Validation report for {model_name} saved to: {report_path}")

    # 8. Save the detailed results for manual error analysis
    output_csv_path = os.path.join(config.OUTPUT_DIR, "utdallas_validation_dense_comparison.csv")
    df_validation.to_csv(output_csv_path, index=False)
    print(f"\n✅ Detailed dense comparison results saved to: {output_csv_path}")


if __name__ == "__main__":
    main()
