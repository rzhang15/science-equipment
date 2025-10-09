# 3_predict_product_markets.py (REVISED WITH CASCADING VALIDATION AND DATA LOADING FIX)
"""
Uses a flexibly chosen pipeline to predict product markets for various data sources.
Applies a gatekeeper, a chosen expert model with cascading validation, and rule-based overrides.
"""
import pandas as pd
import glob
import os
import joblib
import argparse
from tqdm import tqdm

import config
from rule_based_categorizer import RuleBasedCategorizer
from categorize_items import TfidfItemCategorizer, EmbeddingItemCategorizer

# --- IMPORTANT ASSUMPTION ---
# This script assumes your expert categorizers in 'categorize_items.py' will be
# modified to include a method like 'get_top_n_item_categories(description, n=3)'
# which returns a list of tuples, e.g., [('cat1', score1), ('cat2', score2), ...].
# Until that change is made, this script simulates the behavior by only checking
# the single best prediction from the existing 'get_item_category' method.

def validate_hierarchical_prediction(prediction: str, description: str) -> bool:
    """
    Checks if a hierarchical prediction (e.g., "amino acid - XXX") is valid
    by ensuring the specific item ("XXX") is mentioned in the description text.

    Returns:
        bool: True if the prediction is valid, False otherwise.
    """
    description_lower = description.lower()

    # --- Rule for 'cell culture antibiotics - XXX' ---
    prefix_antibiotic = "cell culture antibiotics - "
    if prediction.startswith(prefix_antibiotic):
        specific_item = prediction.removeprefix(prefix_antibiotic).lower()
        # Normalize item name to match dictionary keys, e.g., 'penicillin-streptomycin' -> 'penicillinstreptomycin'
        normalized_item = specific_item.replace('-', '')

        abbreviations = {
            "penicillinstreptomycin": ["pen-strep", "pen strep"],
        }
        if specific_item in description_lower:
            return True
        if normalized_item in abbreviations and any(abbrev in description_lower for abbrev in abbreviations[normalized_item]):
            return True
        return False # Validation failed: specific antibiotic not mentioned

    # --- Rule for 'amino acid - XXX' (BUG FIXED) ---
    prefix_amino_acid = "amino acid - "
    if prediction.startswith(prefix_amino_acid):
        specific_item = prediction.removeprefix(prefix_amino_acid).lower()
        # Normalize by removing common prefixes to match dictionary keys, e.g., "l-isoleucine" -> "isoleucine"
        normalized_item = specific_item.removeprefix('l-').removeprefix('d-')

        abbreviations = {
            "glutamine": ["gluta", "gln"],
            "glycine": ["gly"],
            "leucine": ["leu"],
            "cysteine": ["cys"],
            "isoleucine": ["ile"]
        }
        if specific_item in description_lower:
            return True
        if normalized_item in abbreviations and any(abbrev in description_lower for abbrev in abbreviations[normalized_item]):
            return True
        return False # Validation failed: specific amino acid not mentioned

    # If the prediction is not a hierarchical type we need to check, it's considered valid by default
    return True

def get_cascading_prediction(description: str, expert_predictor, n_best: int = 3) -> str:
    """
    Gets the most specific, valid prediction by checking the top N results from
    the expert model in order. If the top choice fails validation, it tries the next best.
    """
    try:
        # NOTE: To enable true cascading, modify your expert model to have a
        # 'get_top_n_item_categories' method and call it here.
        # EXAMPLE: top_predictions = expert_predictor.get_top_n_item_categories(description, n=n_best)

        # For now, we simulate the list with just the single best prediction.
        best_prediction = expert_predictor.get_item_category(description)
        if not best_prediction:
            return "unclassified_by_model"
        top_predictions = [(best_prediction, 1.0)] # Simulating a list of [(prediction, score)]

    except Exception:
        return "unclassified_by_model" # Handle cases where the expert model might fail

    # Iterate through the ranked list of predictions
    for prediction, score in top_predictions:
        # If the prediction is valid (either non-hierarchical or passes the text check)
        if validate_hierarchical_prediction(prediction, description):
            return prediction # Accept the first valid prediction we find

    # If none of the top N predictions passed our strict validation, we fall back
    # to the expert's original top choice. It's our best available guess.
    return top_predictions[0][0] if top_predictions else "unclassified_by_model"

def main(gatekeeper_name: str, expert_model_choice: str, source_abbrev: str = None):
    print(f"--- Starting Prediction Pipeline with Cascading Validation ---")
    print(f"  - Gatekeeper Model:    {gatekeeper_name}")
    print(f"  - Expert Model Choice:   {expert_model_choice}")
    print(f"  - Data Source:         {source_abbrev or 'All Universities'}")

    # 1. Load all models and categorizers
    print("\nℹ️ Loading necessary models and vectorizers...")
    try:
        gatekeeper_model = joblib.load(os.path.join(config.OUTPUT_DIR, f"hybrid_classifier_{gatekeeper_name}.joblib"))
        
        model_type, embedding_type = expert_model_choice.rsplit('_', 1)
        if model_type == 'non_parametric':
            if embedding_type == 'tfidf':
                expert_predictor = TfidfItemCategorizer()
            elif embedding_type == 'bert':
                expert_predictor = EmbeddingItemCategorizer("bert", "all-MiniLM-L6-v2")
        else:
            raise NotImplementedError(f"Expert model type '{model_type}' not configured in this script.")

        rule_categorizer = RuleBasedCategorizer(config.MARKET_RULES_YAML)
        print(f"  ✅ Loaded {len(rule_categorizer.rules)} market rules.")

    except Exception as e:
        print(f"❌ A required model or file was not found: {e}. Please run previous scripts.")
        return

    # 2. Find and load input files based on the source abbreviation
    dataframes_to_process = []
    source_lower = source_abbrev.lower() if source_abbrev else ''

    if 'utdallas' in source_lower:
        print(f"\nℹ️ UT Dallas specified. Loading the pre-cleaned and merged file from script 0.")
        try:
            df_utd = pd.read_parquet(config.UT_DALLAS_MERGED_CLEAN_PATH)
            dataframes_to_process.append(('utdallas_merged_clean.parquet', df_utd))
        except FileNotFoundError:
            print(f"❌ Pre-merged UT Dallas file not found. Please run 0_clean_category_file.py first.")
            return
            
    elif 'govspend' in source_lower:
        print(f"\nℹ️ GovSpend specified. Loading the GovSpend panel data.")
        try:
            df_gov = pd.read_csv(config.GOVSPEND_PANEL_CSV, low_memory=False)
            # Handle different possible column names for description in GovSpend data
            source_col_name = 'prdct_description' if 'prdct_description' in df_gov.columns else 'product_desc'
            if source_col_name in df_gov.columns:
                 df_gov.rename(columns={source_col_name: config.CLEAN_DESC_COL}, inplace=True)
            else:
                print(f"❌ Critical Error: Could not find a description column in the GovSpend file.")
                return
            dataframes_to_process.append(('govspend_panel.csv', df_gov))
        except FileNotFoundError:
            print(f"❌ GovSpend file not found at: {config.GOVSPEND_PANEL_CSV}")
            return

    else: # Default to searching the FOIA directory
        if source_abbrev:
            search_pattern = os.path.join(config.FOIA_INPUT_DIR, f"{source_abbrev}*_standardized_clean.csv")
        else:
            search_pattern = os.path.join(config.FOIA_INPUT_DIR, "*_standardized_clean.csv")
        
        input_files = glob.glob(search_pattern)
        if not input_files:
            print(f"❌ No files found for pattern: {search_pattern}")
            return
        
        print(f"ℹ️ Found {len(input_files)} file(s) to process.")
        for file_path in input_files:
            df = pd.read_csv(file_path, low_memory=False)
            dataframes_to_process.append((os.path.basename(file_path), df))

    # 3. Process each loaded dataframe
    for filename, df_new in dataframes_to_process:
        print(f"\n--- Processing file: {filename} ---")
        if config.CLEAN_DESC_COL not in df_new.columns:
            print(f"  - ⚠️ Skipping file: Missing required column '{config.CLEAN_DESC_COL}'")
            continue
        descriptions = df_new[config.CLEAN_DESC_COL].astype(str).fillna("")

        # Step A: Gatekeeper identifies potential lab items
        print("  - Step 1: Running gatekeeper...")
        is_lab_mask = (gatekeeper_model.predict(descriptions) == 1)
        print(f"  - Gatekeeper identified {is_lab_mask.sum()} potential lab items.")

        # Step B: Expert model predicts markets using the new cascading logic
        df_new['predicted_market'] = "Non-Lab"
        if is_lab_mask.any():
            print(f"  - Step 2: Predicting markets with '{expert_model_choice}' expert and cascading validation...")
            lab_descriptions = descriptions[is_lab_mask]
            
            tqdm.pandas(desc="  - Predicting markets")
            predictions = lab_descriptions.progress_apply(
                lambda desc: get_cascading_prediction(desc, expert_predictor)
            )
            df_new.loc[is_lab_mask, 'predicted_market'] = predictions

        # Step C: Final rule-based overrides take precedence over everything
        print("  - Step 3: Applying final rule-based overrides...")
        overrides = descriptions.apply(rule_categorizer.get_market_override)
        df_new.loc[overrides.dropna().index, 'predicted_market'] = overrides.dropna()
        print(f"  - Applied {overrides.notna().sum()} rule-based overrides.")
        
        # Step D: Save the results
        output_filename = f"{os.path.splitext(filename)[0]}_classified_with_{expert_model_choice}.csv"
        output_path = os.path.join(config.OUTPUT_DIR, output_filename)
        df_new.to_csv(output_path, index=False)
        print(f"✅ Prediction file saved to: {output_path}")

    print("\n--- All files processed. ---")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run product market predictions with cascading validation.")
    parser.add_argument("source_abbrev", type=str, nargs='?', default=None, help="Abbreviation of a data source (e.g., 'utdallas', 'govspend', or a university prefix). If empty, processes all university files.")
    parser.add_argument("--gatekeeper", type=str, required=True, choices=['tfidf', 'bert'])
    parser.add_argument(
        "--expert_model",
        type=str,
        required=True,
        choices=['non_parametric_tfidf', 'non_parametric_bert'],
    )
    args = parser.parse_args()
    main(gatekeeper_name=args.gatekeeper, expert_model_choice=args.expert_model, source_abbrev=args.source_abbrev)