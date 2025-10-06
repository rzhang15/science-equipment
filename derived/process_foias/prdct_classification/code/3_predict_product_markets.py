# 3_predict_product_markets.py
"""
Uses a flexibly chosen pipeline to predict product markets for various data sources.
Can process university FOIA files or the GovSpend panel data.
Applies a gatekeeper, a chosen expert model, and rule-based overrides.
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
# In 3_predict_product_markets.py, replace the old function with this one

def apply_prediction_validation_rules(prediction: str, description: str) -> str:
    """
    Applies custom rules to validate a model's prediction against the source text,
    including checks for common abbreviations.

    Args:
        prediction (str): The market category predicted by the expert model.
        description (str): The original clean item description.

    Returns:
        str: The original prediction if it's valid, or a corrected prediction if it's not.
    """
    description_lower = description.lower() # Convert description once for efficiency

    # --- Rule 1: Validate 'cell culture antibiotics - XXX' predictions ---
    prefix = "cell culture antibiotics - "
    if prediction.startswith(prefix):
        specific_antibiotic = prediction.removeprefix(prefix).lower()

        # --- NEW: Abbreviation mapping ---
        # Maps the full name (from the prediction) to a list of possible abbreviations.
        abbreviations = {
            "penicillin-streptomycin": ["pen-strep", "pen strep"],
            # You can add other abbreviations here in the future, for example:
            # "gentamicin": ["genta", "gent"],
            # "dimethyl sulfoxide": ["dmso"]
        }

        # Step 1: Check if the full name is in the description.
        if specific_antibiotic in description_lower:
            return prediction  # It's valid, no more checks needed.

        # Step 2: If the full name isn't there, check for its known abbreviations.
        if specific_antibiotic in abbreviations:
            for abbrev in abbreviations[specific_antibiotic]:
                if abbrev in description_lower:
                    return prediction  # An abbreviation was found, so it's valid.

        # Step 3: If neither the full name nor any abbreviation is found, the prediction is invalid.
        return "cell culture antibiotics - general"

    # --- You can add more 'if/elif' blocks for other rules here ---

    # If no rules were triggered, return the original prediction.
    return prediction
def main(gatekeeper_name: str, expert_model_choice: str, source_abbrev: str = None):
    print(f"--- Starting Prediction Pipeline ---")
    print(f"  - Gatekeeper Model:    {gatekeeper_name}")
    print(f"  - Expert Model Choice:   {expert_model_choice}")
    print(f"  - Data Source:         {source_abbrev or 'All Universities'}")


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

    try:
        if model_type == 'parametric':
            model_filename = f"expert_classifier_{embedding_type}.joblib"
            print(f"ℹ️ Loading the parametric expert model ({model_filename})...")
            expert_model_path = os.path.join(config.OUTPUT_DIR, model_filename)
            expert_predictor = joblib.load(expert_model_path)

        elif model_type == 'non_parametric':
            if embedding_type == 'tfidf':
                print("ℹ️ Initializing the non-parametric TF-IDF categorizer...")
                expert_predictor = TfidfItemCategorizer()
            elif embedding_type == 'bert':
                print("ℹ️ Initializing the non-parametric BERT categorizer...")
                expert_predictor = EmbeddingItemCategorizer("bert", "all-MiniLM-L6-v2")
    except Exception as e:
        print(f"\n❌ CRITICAL ERROR: Failed to initialize the expert model '{expert_model_choice}'.")
        print(f"   The underlying error was: {type(e).__name__}: {e}")
        return

    # 3. Initialize Rule-Based Overrides
    print("ℹ️ Loading rule-based categorizer...")
    rule_categorizer = RuleBasedCategorizer(config.MARKET_RULES_YAML)
    print(f"  ✅ Loaded {len(rule_categorizer.rules)} market rules.")

    # 4. Find and load input files based on the source abbreviation
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

    # 5. Process each loaded dataframe
    for filename, df_new in dataframes_to_process:
        print(f"\n--- Processing file: {filename} ---")
        descriptions = df_new[config.CLEAN_DESC_COL].astype(str).fillna("")

        # Step A: Gatekeeper
        print("  - Step 1: Identifying potential lab items with gatekeeper...")
        is_lab_predictions = gatekeeper_model.predict(descriptions)
        is_lab_mask = (is_lab_predictions == 1)
        print(f"  - Gatekeeper found {is_lab_mask.sum()} potential lab items.")

        # Step B: Expert model prediction
        df_new['predicted_market'] = "Non-Lab"
        if is_lab_mask.any():
            print(f"  - Step 2: Predicting markets with the '{expert_model_choice}' expert...")
            tqdm.pandas(desc="  - Predicting markets")
            if model_type == 'parametric':
                lab_vectors = text_vectors_tfidf[is_lab_mask]
                predictions = expert_predictor.predict(lab_vectors)
                df_new.loc[is_lab_mask, 'predicted_market'] = predictions
            else: # non_parametric
                lab_descriptions = descriptions[is_lab_mask]
                predictions = lab_descriptions.progress_apply(expert_predictor.get_item_category)
                df_new.loc[is_lab_mask, 'predicted_market'] = predictions
            print("  - Step 3: Applying post-prediction validation rules...")
            
            # Get the indices of the items classified as 'Lab' to work on them
            lab_indices = df_new[is_lab_mask].index
            
            # Apply the validation function row-by-row to the lab items,
            # using the prediction we just made and the original description.
            validated_predictions = df_new.loc[lab_indices].apply(
                lambda row: apply_prediction_validation_rules(
                    row['predicted_market'], 
                    row[config.CLEAN_DESC_COL]
                ),
                axis=1
            )
            
            # Check how many predictions were changed by our new rules
            num_corrected = (df_new.loc[lab_indices, 'predicted_market'] != validated_predictions).sum()
            if num_corrected > 0:
                print(f"  - Corrected {num_corrected} overly specific predictions.")

            # Update the DataFrame with the now-validated predictions
            df_new.loc[lab_indices, 'predicted_market'] = validated_predictions

            # Step D: Rule-based overrides (this was the old Step C)
            print("  - Step 4: Applying rule-based overrides...")
            lab_descriptions = descriptions[is_lab_mask]
            overrides = lab_descriptions.apply(rule_categorizer.get_market_override)
            df_new.loc[overrides.dropna().index, 'predicted_market'] = overrides.dropna()
            print(f"  - Applied {overrides.notna().sum()} rule-based overrides.")
        # Step D: Save the results
        output_filename = f"{os.path.splitext(filename)[0]}_classified_with_{expert_model_choice}.csv"
        output_path = os.path.join(config.OUTPUT_DIR, output_filename)
        df_new.to_csv(output_path, index=False)
        print(f"✅ Prediction file saved to: {output_path}")

    print("\n--- All files processed. ---")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run product market predictions on university or GovSpend data.")
    parser.add_argument("source_abbrev", type=str, nargs='?', default=None, help="Abbreviation of a data source (e.g., 'utdallas', 'govspend', or a university prefix). If empty, processes all university files.")
    parser.add_argument("--gatekeeper", type=str, required=True, choices=['tfidf', 'bert'])
    parser.add_argument(
        "--expert_model",
        type=str,
        required=True,
        choices=['parametric_tfidf', 'non_parametric_tfidf', 'non_parametric_bert'],
    )
    args = parser.parse_args()
    main(gatekeeper_name=args.gatekeeper, expert_model_choice=args.expert_model, source_abbrev=args.source_abbrev)

