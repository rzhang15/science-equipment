# 5_validate_on_utdallas.py (Corrected)
"""
Validates the end-to-end performance of the entire classification pipeline
by comparing its predictions on the UT Dallas dataset against the original,
manually-coded categories.
"""
import pandas as pd
import os
import joblib
import yaml
import re
from sklearn.metrics import classification_report
import matplotlib.pyplot as plt
import seaborn as sns

import config
from categorize_items import ItemCategorizer

# --- Re-using the logic from our prediction script ---

def load_keywords_and_compile_regex(filepath: str):
    """Loads keywords and returns a compiled regex pattern."""
    try:
        with open(filepath, 'r') as f:
            data = yaml.safe_load(f)
            keywords = data.get('keywords', [])
            if not keywords: return None
            pattern = r'\b(' + '|'.join(re.escape(kw) for kw in keywords) + r')\b'
            return re.compile(pattern, re.IGNORECASE)
    except FileNotFoundError:
        return None

class ProductMarketDefiner:
    """A helper class to encapsulate the full classification logic."""
    def __init__(self):
        self.lab_model = joblib.load(config.LAB_MODEL_PATH)
        self.categorizer = ItemCategorizer(
            category_data_path=config.CATEGORY_MODEL_DATA_PATH,
            vectorizer_path=config.CATEGORY_VECTORIZER_PATH
        )
        self.lab_keyword_pattern = load_keywords_and_compile_regex(config.SEED_KEYWORD_YAML)
        self.non_lab_keyword_pattern = load_keywords_and_compile_regex(config.ANTI_SEED_KEYWORD_YAML)

    def define_market(self, desc: str):
        if not isinstance(desc, str) or not desc.strip():
            return "No Description"
        if self.non_lab_keyword_pattern and self.non_lab_keyword_pattern.search(desc):
            return "Non-Lab" # Simplified for comparison
        if self.lab_keyword_pattern and self.lab_keyword_pattern.search(desc):
            return self.categorizer.get_item_category(**self.get_cat_params(desc))

        lab_probability = self.lab_model.predict_proba([desc])[0, 1]

        if lab_probability >= config.PREDICTION_THRESHOLD:
            return self.categorizer.get_item_category(**self.get_cat_params(desc))
        else:
            return "Non-Lab" # Simplified for comparison

    def get_cat_params(self, desc: str):
        return {
            'item_description': desc,
            'sim_weight': config.CATEGORY_SIMILARITY_WEIGHT,
            'overlap_weight': config.CATEGORY_OVERLAP_WEIGHT,
            'min_threshold': config.CATEGORY_MIN_SCORE_THRESHOLD
        }

def main():
    print("--- Starting Validation on UT Dallas Dataset ---")

    # 1. Load and merge the UT Dallas data to get the true labels
    print("ℹ️ Loading UT Dallas data with true categories...")
    try:
        # Load the two separate files
        df_ut = pd.read_csv(config.UT_DALLAS_CLEAN_CSV, low_memory=False) # **CORRECTED VARIABLE NAME**
        df_cat = pd.read_excel(config.UT_DALLAS_CATEGORIES_XLSX)

        # Prepare merge keys by ensuring they are string type
        for key in config.UT_DALLAS_MERGE_KEYS:
            if key in df_ut.columns and key in df_cat.columns:
                df_ut[key] = df_ut[key].astype(str)
                df_cat[key] = df_cat[key].astype(str)

        # Perform the merge, replicating the logic from 1_prepare_data.py
        df_validation = pd.merge(df_ut, df_cat.drop(columns=['clean_desc'], errors='ignore'), on=config.UT_DALLAS_MERGE_KEYS, how='left')
        df_validation.dropna(subset=[config.CLEAN_DESC_COL, config.UT_CAT_COL], inplace=True)
        print(f"  - Loaded and merged {len(df_validation)} rows with descriptions and categories.")
    except Exception as e:
        print(f"❌ Could not load or merge UT Dallas data: {e}")
        return

    # 2. Get predictions using the full classification logic
    print("ℹ️ Running full classification pipeline on UT Dallas descriptions...")
    market_definer = ProductMarketDefiner()
    df_validation['predicted_market'] = df_validation[config.CLEAN_DESC_COL].apply(market_definer.define_market)
    print("✅ Predictions complete.")

    # 3. Simplify the true labels for a fair comparison
    # The model predicts a general "Non-Lab", so we'll map the specific true non-lab categories to this single label.
    nonlab_pattern = '|'.join(config.NONLAB_CATEGORIES)
    is_true_nonlab = df_validation[config.UT_CAT_COL].str.contains(nonlab_pattern, case=False, na=False)
    df_validation['true_market_simplified'] = df_validation[config.UT_CAT_COL]
    df_validation.loc[is_true_nonlab, 'true_market_simplified'] = 'Non-Lab'

    y_true = df_validation['true_market_simplified']
    y_pred = df_validation['predicted_market']

    # 4. Generate and save the performance metrics
    print("\n--- Overall System Performance on UT Dallas Data ---")
    report = classification_report(y_true, y_pred, zero_division=0)
    print(report)

    report_path = os.path.join(config.OUTPUT_DIR, "utdallas_validation_report.txt")
    with open(report_path, 'w') as f:
        f.write("End-to-End System Performance on UT Dallas Data\n")
        f.write("="*60 + "\n")
        f.write(report)
    print(f"\n✅ Full validation report saved to: {report_path}")

    # 5. Save the detailed results for manual error analysis
    df_validation.to_csv(os.path.join(config.OUTPUT_DIR, "utdallas_validation_results.csv"), index=False)
    print(f"✅ Detailed results saved to utdallas_validation_results.csv for error analysis.")

if __name__ == "__main__":
    main()
