# 3_predict.py (Reworked with classification reasoning)
"""
Applies the full multi-stage classification pipeline to new, pre-cleaned data,
incorporating the keyword-first logic and outputting a "reason" for each
classification to allow for workflow and performance verification.
"""
import pandas as pd
import glob
import os
import joblib
import yaml
import re

import config
from categorize_items import ItemCategorizer

def load_keywords_and_compile_regex(filepath: str):
    """Loads keywords from a YAML file and returns a compiled regex pattern."""
    try:
        with open(filepath, 'r') as f:
            data = yaml.safe_load(f)
            keywords = data.get('keywords', [])
            if not keywords:
                print(f"⚠️ No keywords found in {filepath}")
                return None
            # Create a regex pattern: \b(word1|word2|...)\b
            pattern = r'\b(' + '|'.join(re.escape(kw) for kw in keywords) + r')\b'
            return re.compile(pattern, re.IGNORECASE)
    except FileNotFoundError:
        print(f"❌ Keyword file not found: {filepath}")
        return None

def main():
    print("--- Starting Step 3: Classifying New Data ---")

    print("ℹ️ Loading all models and artifacts...")
    try:
        # Load the binary classifier
        lab_model = joblib.load(config.LAB_MODEL_PATH)

        # Initialize the granular categorizer
        categorizer = ItemCategorizer(
            category_data_path=config.CATEGORY_MODEL_DATA_PATH,
            vectorizer_path=config.CATEGORY_VECTORIZER_PATH
        )

        # Load keyword patterns for the pre-classification step
        lab_keyword_pattern = load_keywords_and_compile_regex(config.SEED_KEYWORD_YAML)
        non_lab_keyword_pattern = load_keywords_and_compile_regex(config.ANTI_SEED_KEYWORD_YAML)

    except FileNotFoundError:
        print("❌ Model/artifact files not found. Please run steps 1 and 2 first.")
        return

    foia_files = glob.glob(os.path.join(config.FOIA_INPUT_DIR, "*_standardized_clean.csv"))
    if not foia_files:
        print(f"❌ No standardized clean CSV files found in {config.FOIA_INPUT_DIR}")
        return

    print(f"ℹ️ Found {len(foia_files)} files to process.")

    # --- Process each input file ---
    for file_path in foia_files:
        try:
            print(f"\n--- Processing file: {os.path.basename(file_path)} ---")
            df_new = pd.read_csv(file_path, low_memory=False)

            if df_new.empty or config.CLEAN_DESC_COL not in df_new.columns:
                print("  - Skipping empty or invalid file.")
                continue

            descriptions = df_new[config.CLEAN_DESC_COL].astype(str).fillna("")

            # Create lists to hold the results AND the reasons for verification
            results = []
            reasons = []

            # --- Apply the full, multi-stage logic to each description ---
            for desc in descriptions:
                if not desc.strip():
                    results.append("No Description")
                    reasons.append("No Description Provided")
                    continue

                # 1. Keyword check first
                if non_lab_keyword_pattern and non_lab_keyword_pattern.search(desc):
                    results.append("Non-Lab")
                    reasons.append("Non-Lab Keyword Match")
                    continue

                if lab_keyword_pattern and lab_keyword_pattern.search(desc):
                    category = categorizer.get_item_category(
                        desc,
                        sim_weight=config.CATEGORY_SIMILARITY_WEIGHT,
                        overlap_weight=config.CATEGORY_OVERLAP_WEIGHT,
                        min_threshold=config.CATEGORY_MIN_SCORE_THRESHOLD
                    )
                    results.append(category)
                    reasons.append("Categorized by Lab Keyword")
                    continue

                # 2. If no keywords, use the binary model as a fallback
                lab_probability = lab_model.predict_proba([desc])[0, 1]

                # 3. Route based on model output
                if lab_probability >= config.PREDICTION_THRESHOLD:
                    category = categorizer.get_item_category(
                        desc,
                        sim_weight=config.CATEGORY_SIMILARITY_WEIGHT,
                        overlap_weight=config.CATEGORY_OVERLAP_WEIGHT,
                        min_threshold=config.CATEGORY_MIN_SCORE_THRESHOLD
                    )
                    results.append(category)
                    reasons.append(f"Categorized by Model (Prob: {lab_probability:.2f})")
                else:
                    results.append("Non-Lab")
                    reasons.append(f"Non-Lab by Model (Prob: {lab_probability:.2f})")

            # Add both new columns to the DataFrame for analysis
            df_new['product_market'] = results
            df_new['classification_reason'] = reasons

            # Save the output file
            base_filename = os.path.basename(file_path)
            name_part, ext = os.path.splitext(base_filename)
            output_filename = f"{name_part}_classified{ext}"
            output_path = os.path.join(config.OUTPUT_DIR, output_filename)

            df_new.to_csv(output_path, index=False)
            print(f"  ✅ Classified data saved to: {output_path}")

        except Exception as e:
            print(f"  ❌ An error occurred while processing {os.path.basename(file_path)}: {e}")
            continue

    print("\n--- All files processed. ---")

if __name__ == "__main__":
    main()
