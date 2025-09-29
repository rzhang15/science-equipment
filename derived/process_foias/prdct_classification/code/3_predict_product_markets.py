# 3_predict.py (Corrected to run all experts on a single gatekeeper's results)
"""
Uses a single, specified gatekeeper model (TF-IDF or BERT) to identify
potential lab items, then runs all expert categorizers on those items for
a side-by-side comparison.
"""
from tqdm import tqdm
import pandas as pd
import glob
import os
import joblib
import sys
import argparse

import config
from categorize_items import TfidfItemCategorizer, EmbeddingItemCategorizer

def main(gatekeeper_name: str, uni_abbrev: str = None):
    print(f"--- Starting Step 3: Prediction using '{gatekeeper_name}' gatekeeper ---")

    # 1. Load the selected Lab/Not-Lab gatekeeper model
    print(f"ℹ️ Loading '{gatekeeper_name}' Lab/Not-Lab model...")
    try:
        model_filename = f"lab_binary_classifier_{gatekeeper_name}.joblib"
        model_path = os.path.join(config.OUTPUT_DIR, model_filename)
        lab_model = joblib.load(model_path)
    except FileNotFoundError:
        print(f"❌ Gatekeeper model not found at: {model_path}. Please run 2_train_model.py first.")
        return

    # 2. Load the TF-IDF vectorizer needed for the gatekeeper
    try:
        vectorizer_path = os.path.join(config.OUTPUT_DIR, "vectorizer_tfidf.joblib")
        tfidf_vectorizer = joblib.load(vectorizer_path)
    except FileNotFoundError:
        print(f"❌ TF-IDF Vectorizer not found at: {vectorizer_path}. Please run 1b_create_text_embeddings.py.")
        return
        
    # 3. Initialize all the expert categorizers you want to compare
    print("ℹ️ Initializing expert product market categorizers...")
    try:
        expert_categorizers = {
            "tfidf": TfidfItemCategorizer(config.CATEGORY_MODEL_DATA_PATH, config.CATEGORY_VECTORIZER_PATH),
            "bert": EmbeddingItemCategorizer("bert", "all-MiniLM-L6-v2")
        }
    except Exception as e:
        print(f"❌ Error initializing expert categorizers: {e}")
        return

    # 4. Find input files to process
    if uni_abbrev:
        search_pattern = os.path.join(config.FOIA_INPUT_DIR, f"{uni_abbrev}*_standardized_clean.csv")
    else:
        search_pattern = os.path.join(config.FOIA_INPUT_DIR, "*_standardized_clean.csv")
    input_files = glob.glob(search_pattern)
    if not input_files:
        print(f"❌ No files found for pattern: {search_pattern}")
        return

    print(f"ℹ️ Found {len(input_files)} file(s) to process.")

    # 5. Process each file
    for file_path in input_files:
        print(f"\n--- Processing file: {os.path.basename(file_path)} ---")
        df_new = pd.read_csv(file_path, low_memory=False)
        descriptions = df_new[config.CLEAN_DESC_COL].astype(str).fillna("")

        # Step A: Use the single gatekeeper to identify all potential lab items
        print("  - Step 1: Identifying potential lab items with the gatekeeper...")
        text_vectors = tfidf_vectorizer.transform(descriptions)
        lab_probabilities = lab_model.predict_proba(text_vectors)[:, 1]
        is_lab_mask = lab_probabilities >= config.PREDICTION_THRESHOLD
        lab_descriptions = descriptions[is_lab_mask]
        print(f"  - Gatekeeper found {len(lab_descriptions)} potential lab items to categorize.")

        # Step B: Run ALL expert categorizers on that single set of lab items
        if not lab_descriptions.empty:
            print("  - Step 2: Running all expert categorizers for comparison...")
            for expert_name, categorizer in expert_categorizers.items():
                col_name = f'market_prediction_{expert_name}'
                df_new[col_name] = "Non-Lab"
                
                tqdm.pandas(desc=f"  - Categorizing ({expert_name})")
                if expert_name == 'tfidf':
                    predictions = lab_descriptions.progress_apply(
                        lambda desc: categorizer.get_item_category(desc, sim_weight=config.CATEGORY_SIMILARITY_WEIGHT, overlap_weight=config.CATEGORY_OVERLAP_WEIGHT)
                    )
                else: # BERT
                    predictions = lab_descriptions.progress_apply(categorizer.get_item_category)
                
                df_new.loc[is_lab_mask, col_name] = predictions
        else: # If no lab items were found, just create the empty columns
            for expert_name in expert_categorizers.keys():
                df_new[f'market_prediction_{expert_name}'] = "Non-Lab"

        # Step C: Save the combined results
        output_filename = f"{os.path.splitext(os.path.basename(file_path))[0]}_classified.csv"
        output_path = os.path.join(config.OUTPUT_DIR, output_filename)
        df_new.to_csv(output_path, index=False)
        print(f"✅ Comparison file with predictions from all experts saved to: {output_path}")

    print("\n--- All files processed. ---")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run product market predictions using a specified gatekeeper model.")
    parser.add_argument(
        "uni_abbrev",
        type=str,
        nargs='?',
        default=None,
        help="Optional: Abbreviation of a single university to process (e.g., 'utdallas')."
    )
    parser.add_argument(
        "--gatekeeper",
        type=str,
        required=True, # Gatekeeper choice is now mandatory
        choices=['tfidf', 'bert'],
        help="The gatekeeper model to use for Lab/Not-Lab classification ('tfidf' or 'bert')."
    )
    args = parser.parse_args()
    main(gatekeeper_name=args.gatekeeper, uni_abbrev=args.uni_abbrev)