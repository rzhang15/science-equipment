# 3_predict_product_markets.py (UPDATED)
"""
Uses a flexibly chosen pipeline to predict product markets for various data sources.
Applies a gatekeeper, a chosen expert model, prediction veto rules, and final override rules.
"""
import pandas as pd
import glob
import os
import joblib
import argparse
from tqdm import tqdm

import config
from rule_based_categorizer import RuleBasedCategorizer # Assumes this is the updated version
from categorize_items import TfidfItemCategorizer, EmbeddingItemCategorizer

def main(gatekeeper_name: str, expert_model_choice: str, source_abbrev: str = None):
    print(f"--- Starting Prediction Pipeline ---")
    print(f"  - Gatekeeper Model:    {gatekeeper_name}")
    print(f"  - Expert Model Choice:   {expert_model_choice}")
    print(f"  - Data Source:         {source_abbrev or 'All Universities'}")

    # 1. Load all models and categorizers
    print("\nℹ️ Loading necessary models and categorizers...")
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

        # This now loads override rules AND the veto rules
        rule_categorizer = RuleBasedCategorizer(config.MARKET_RULES_YAML)

    except Exception as e:
        print(f"❌ A required model or file was not found: {e}. Please run previous scripts.")
        return

    # 2. Find and load input files
    dataframes_to_process = []
    # (Data loading logic remains the same)
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
    else:
        search_pattern = os.path.join(config.FOIA_INPUT_DIR, f"{source_abbrev}*_standardized_clean.csv" if source_abbrev else "*_standardized_clean.csv")
        input_files = glob.glob(search_pattern)
        if not input_files:
            print(f"❌ No files found for pattern: {search_pattern}")
            return
        print(f"\nℹ️ Found {len(input_files)} file(s) to process.")
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

        # --- REVISED PIPELINE LOGIC ---
        
        # Step A: Start with a default prediction for all rows
        y_pred = pd.Series("Non-Lab", index=df_new.index)

        # Step B: Gatekeeper identifies potential lab items
        print("  - Step 1: Running gatekeeper...")
        is_lab_mask = (gatekeeper_model.predict(descriptions) == 1)
        print(f"  - Gatekeeper identified {is_lab_mask.sum()} potential lab items.")

        if is_lab_mask.any():
            lab_descriptions = descriptions[is_lab_mask]
            
            # Step C: Expert model makes initial predictions
            print(f"  - Step 2: Predicting markets with '{expert_model_choice}' expert...")
            tqdm.pandas(desc="    - Predicting")
            expert_predictions = lab_descriptions.progress_apply(expert_predictor.get_item_category)
            
            # Step D: Apply VETO rules to the expert's predictions
            print("  - Step 3: Applying prediction veto rules...")
            validated_predictions = pd.Series(
                [rule_categorizer.validate_prediction(pred, desc) for pred, desc in zip(expert_predictions, lab_descriptions)],
                index=lab_descriptions.index
            )

            num_vetoed = validated_predictions.isna().sum()
            if num_vetoed > 0:
                print(f"  - ⚠️ Vetoed {num_vetoed} expert predictions that didn't meet required criteria.")

            y_pred.update(validated_predictions)

        # Step E: Final market OVERRIDE rules take precedence over everything
        print("  - Step 4: Applying final market override rules...")
        overrides = descriptions.apply(rule_categorizer.get_market_override)
        y_pred.update(overrides.dropna())
        print(f"  - Applied {overrides.notna().sum()} market override rules.")

        # Step F: Fill any remaining NaNs (from vetoed predictions) with a default label
        y_pred.fillna("unclassified", inplace=True)
        
        # Assign the final, clean predictions to the DataFrame
        df_new['predicted_market'] = y_pred
        
        # --- END OF REVISED LOGIC ---

        # Step G: Save the results
        output_filename = f"{os.path.splitext(filename)[0]}_classified_with_{expert_model_choice}.csv"
        output_path = os.path.join(config.OUTPUT_DIR, output_filename)
        df_new.to_csv(output_path, index=False)
        print(f"✅ Prediction file saved to: {output_path}")

    print("\n--- All files processed. ---")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run product market predictions on new data.")
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