# 4_predict_govspend.py (Updated to mirror 3_predict with separate expert selection)
"""
Runs a full prediction pipeline on the GovSpend panel data.
Requires the user to specify BOTH a gatekeeper model for Lab/Not-Lab
classification and a single expert model for product market categorization.
"""
import pandas as pd
import os
import joblib
import argparse
from tqdm import tqdm

import config
from categorize_items import TfidfItemCategorizer, EmbeddingItemCategorizer

def main(gatekeeper_name: str, expert_name: str):
    print(f"--- Starting Prediction on GovSpend Panel ---")
    print(f"  - Gatekeeper Model: {gatekeeper_name}")
    print(f"  - Expert Model:     {expert_name}")

    # --- 1. Load the selected Lab/Not-Lab gatekeeper model ---
    print("\nℹ️ Loading gatekeeper model...")
    try:
        model_filename = f"lab_binary_classifier_{gatekeeper_name}.joblib"
        model_path = os.path.join(config.OUTPUT_DIR, model_filename)
        lab_model = joblib.load(model_path)
    except FileNotFoundError:
        print(f"❌ Gatekeeper model not found at: {model_path}. Please run 2_train_model.py first.")
        return

    # --- 2. Load the TF-IDF vectorizer (needed for both gatekeepers) ---
    try:
        vectorizer_path = os.path.join(config.OUTPUT_DIR, "vectorizer_tfidf.joblib")
        tfidf_vectorizer = joblib.load(vectorizer_path)
    except FileNotFoundError:
        print(f"❌ TF-IDF Vectorizer not found at: {vectorizer_path}. Please run 1b_create_text_embeddings.py.")
        return
        
    # --- 3. Initialize the single selected expert categorizer ---
    print("ℹ️ Initializing expert product market categorizer...")
    try:
        if expert_name == 'tfidf':
            expert_categorizer = TfidfItemCategorizer(config.CATEGORY_MODEL_DATA_PATH, config.CATEGORY_VECTORIZER_PATH)
        elif expert_name == 'bert':
            expert_categorizer = EmbeddingItemCategorizer("bert", "all-MiniLM-L6-v2")
        else: # This case should be prevented by argparse choices
            raise ValueError(f"Invalid expert name: {expert_name}")
    except Exception as e:
        print(f"❌ Error initializing expert categorizer: {e}")
        return

    # --- 4. Load and prepare the GovSpend data ---
    # (File path logic is kept from your original script)
    CODE_DIR = os.path.dirname(os.path.abspath(__file__))
    BASE_DIR = os.path.abspath(os.path.join(CODE_DIR, ".."))
    DERIVED_DIR = os.path.abspath(os.path.join(BASE_DIR, "..", ".."))
    INPUT_CSV_PATH = os.path.join(DERIVED_DIR, "govspend", "make_panel", "output", "govspend_panel.csv")
    
    print(f"\nℹ️ Loading data from {os.path.basename(INPUT_CSV_PATH)}...")
    df_govspend = pd.read_csv(INPUT_CSV_PATH, low_memory=False)

    source_col_name = 'prdct_description' if 'prdct_description' in df_govspend.columns else 'product_desc'
    if source_col_name not in df_govspend.columns:
        print("❌ Critical Error: Could not find 'prdct_description' or 'product_desc' in the input file.")
        return
        
    df_govspend.rename(columns={source_col_name: config.CLEAN_DESC_COL}, inplace=True)
    descriptions = df_govspend[config.CLEAN_DESC_COL].astype(str).fillna("")

    # --- 5. Run the two-step prediction process ---
    # Step A: Use the gatekeeper to identify all potential lab items
    print("  - Step 1: Identifying potential lab items with the gatekeeper...")
    text_vectors = tfidf_vectorizer.transform(descriptions)
    lab_probabilities = lab_model.predict_proba(text_vectors)[:, 1]
    is_lab_mask = lab_probabilities >= config.PREDICTION_THRESHOLD
    lab_descriptions = descriptions[is_lab_mask]
    print(f"  - Gatekeeper found {len(lab_descriptions)} potential lab items to categorize.")

    # Step B: Run the single expert categorizer on that set of lab items
    df_govspend['market_prediction'] = "Non-Lab"
    if not lab_descriptions.empty:
        print(f"  - Step 2: Running the '{expert_name}' expert categorizer...")
        tqdm.pandas(desc=f"  - Categorizing ({expert_name})")
        
        if expert_name == 'tfidf':
            predictions = lab_descriptions.progress_apply(
                lambda desc: expert_categorizer.get_item_category(desc, sim_weight=config.CATEGORY_SIMILARITY_WEIGHT, overlap_weight=config.CATEGORY_OVERLAP_WEIGHT)
            )
        else: # BERT
            predictions = lab_descriptions.progress_apply(expert_categorizer.get_item_category)
        
        df_govspend.loc[is_lab_mask, 'market_prediction'] = predictions

    # --- 6. Save the final output with a descriptive name ---
    output_suffix = f"classified_gatekeeper_{gatekeeper_name}_expert_{expert_name}.csv"
    output_filename = f"govspend_panel_{output_suffix}"
    output_path = os.path.join(config.OUTPUT_DIR, output_filename)
    
    df_govspend.to_csv(output_path, index=False)
    print(f"\n✅ Prediction complete. File saved to: {output_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run a prediction pipeline on the GovSpend panel.")
    parser.add_argument(
        "--gatekeeper",
        type=str,
        required=True,
        choices=['tfidf', 'bert'],
        help="The gatekeeper model to use for Lab/Not-Lab classification."
    )
    parser.add_argument(
        "--expert",
        type=str,
        required=True,
        choices=['tfidf', 'bert'],
        help="The single expert model to use for product market categorization."
    )
    args = parser.parse_args()
    main(gatekeeper_name=args.gatekeeper, expert_name=args.expert)