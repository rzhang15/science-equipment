# 3_predict_product_markets.py (REVISED to use ground truth file for validation run)
from tqdm import tqdm
import pandas as pd
import glob
import os
import joblib
import argparse

import config
from classifier import HybridClassifier # Needed for joblib
from categorize_items import TfidfItemCategorizer, EmbeddingItemCategorizer

def main(model_type: str, uni_abbrev: str = None):
    print(f"--- Starting Prediction using '{model_type}' HybridClassifier ---")

    # 1. Load the single, complete HybridClassifier object
    print("ℹ️ Loading the saved HybridClassifier...")
    try:
        hybrid_model_path = os.path.join(config.OUTPUT_DIR, f"hybrid_classifier_{model_type}.joblib")
        hybrid_model = joblib.load(hybrid_model_path)
    except FileNotFoundError:
        print(f"❌ HybridClassifier not found at: {hybrid_model_path}.")
        return
        
    # 2. Initialize the expert categorizers
    print("ℹ️ Initializing expert product market categorizers...")
    expert_categorizers = {
        "tfidf": TfidfItemCategorizer(config.CATEGORY_MODEL_DATA_PATH, config.CATEGORY_VECTORIZER_PATH),
        "bert": EmbeddingItemCategorizer("bert", "all-MiniLM-L6-v2")
    }

    # --- NEW: Special logic to select the input file ---
    df_to_process = None
    if uni_abbrev == 'utdallas':
        print(f"ℹ️ 'utdallas' specified, using ground truth file for validation run: {config.UT_DALLAS_MERGED_CLEAN_PATH}")
        try:
            df_to_process = pd.read_parquet(config.UT_DALLAS_MERGED_CLEAN_PATH)
        except FileNotFoundError:
            print(f"❌ UT Dallas merged file not found. Please run script #0.")
            return
    else:
        # Original logic for processing other university files
        search_pattern = os.path.join(config.FOIA_INPUT_DIR, f"{uni_abbrev or '*'}*_standardized_clean.csv")
        input_files = glob.glob(search_pattern)
        if not input_files:
            print(f"❌ No files found for pattern: {search_pattern}")
            return
        print(f"ℹ️ Found {len(input_files)} file(s) to process. Starting with {os.path.basename(input_files[0])}")
        df_to_process = pd.read_csv(input_files[0], low_memory=False)

    # Perform prediction on the loaded dataframe
    descriptions = df_to_process[config.CLEAN_DESC_COL].astype(str).fillna("")

    # Step 1: Use the HybridClassifier for Lab/Non-Lab decisions
    print("  - Step 1: Identifying lab items with the HybridClassifier...")
    is_lab_prediction = hybrid_model.predict(descriptions).astype(bool)
    
    # Step 2: Run Expert Models on the "Lab" items
    print("  - Step 2: Running expert models on final lab set...")
    final_lab_descriptions = descriptions[is_lab_prediction]
    print(f"    - A total of {len(final_lab_descriptions)} items will be categorized by experts.")

    if not final_lab_descriptions.empty:
        for expert_name, categorizer in expert_categorizers.items():
            col_name = f'market_prediction_{expert_name}'
            df_to_process[col_name] = "Non-Lab"
            
            tqdm.pandas(desc=f"    - Categorizing ({expert_name})")
            predictions = final_lab_descriptions.progress_apply(categorizer.get_item_category)
            predictions_filled = predictions.fillna("Unclassified")
            
            df_to_process.loc[is_lab_prediction, col_name] = predictions_filled
    else:
        for expert_name in expert_categorizers.keys():
            df_to_process[f'market_prediction_{expert_name}'] = "Non-Lab"

    # Save the results
    if uni_abbrev == 'utdallas':
        output_path = config.UTDALLAS_VALIDATION_PREDICTIONS_CSV
    else:
        # Fallback for single file processing, can be improved for loops
        output_filename = f"{os.path.splitext(os.path.basename(input_files[0]))[0]}_classified.csv"
        output_path = os.path.join(config.OUTPUT_DIR, output_filename)
        
    df_to_process.to_csv(output_path, index=False)
    print(f"✅ Final results saved to: {output_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run predictions using a saved HybridClassifier.")
    parser.add_argument("uni_abbrev", type=str, nargs='?', default=None, help="Optional: Abbreviation of a single university to process (e.g., 'utdallas').")
    parser.add_argument("--model", type=str, required=True, choices=['tfidf', 'bert'], help="The type of saved HybridClassifier to use ('tfidf' or 'bert').")
    args = parser.parse_args()
    main(model_type=args.model, uni_abbrev=args.uni_abbrev)