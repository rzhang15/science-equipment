# 4_predict_govspend_markets.py
"""
Runs a full prediction pipeline on the GovSpend panel data, now with a
flexibly chosen expert model and a final rule-based override layer.
"""
import pandas as pd
import os
import joblib
import argparse
from tqdm import tqdm

import config
from rule_based_categorizer import RuleBasedCategorizer
from categorize_items import TfidfItemCategorizer, EmbeddingItemCategorizer

def main(gatekeeper_name: str, expert_model_choice: str):
    print(f"--- Starting Prediction on GovSpend Panel ---")
    print(f"  - Gatekeeper Model:  {gatekeeper_name}")
    print(f"  - Expert Model Choice: {expert_model_choice}")

    # 1. Load Gatekeeper and TF-IDF Vectorizer
    print("\nℹ️ Loading gatekeeper model and vectorizer...")
    try:
        gatekeeper_model_path = os.path.join(config.OUTPUT_DIR, f"lab_binary_classifier_{gatekeeper_name}.joblib")
        gatekeeper_model = joblib.load(gatekeeper_model_path)
        vectorizer_path = os.path.join(config.OUTPUT_DIR, "vectorizer_tfidf.joblib")
        tfidf_vectorizer = joblib.load(vectorizer_path)
    except FileNotFoundError as e:
        print(f"❌ A required model file was not found: {e}. Please run previous scripts.")
        return

    # 2. Decompose choice and load the correct Expert Model/Categorizer
    model_type, embedding_type = expert_model_choice.split('_', 1)
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
            expert_predictor = TfidfItemCategorizer(config.CATEGORY_MODEL_DATA_PATH, config.CATEGORY_VECTORIZER_PATH)
        elif embedding_type == 'bert':
            print("ℹ️ Initializing the non-parametric BERT categorizer...")
            expert_predictor = EmbeddingItemCategorizer("bert", "all-MiniLM-L6-v2")

    # 3. Initialize Rule-Based Overrides
    rule_categorizer = RuleBasedCategorizer(config.MARKET_RULES_YAML)

    # 4. Load and prepare the GovSpend data
    # (Using a more robust relative path)
    INPUT_CSV_PATH = os.path.join(config.BASE_DIR, "external", "govspend", "govspend_panel.csv")
    print(f"\nℹ️ Loading data from {os.path.basename(INPUT_CSV_PATH)}...")
    try:
        df_govspend = pd.read_csv(INPUT_CSV_PATH, low_memory=False)
    except FileNotFoundError:
        print(f"❌ GovSpend panel file not found at: {INPUT_CSV_PATH}")
        return

    # Standardize description column
    source_col = 'prdct_description' if 'prdct_description' in df_govspend.columns else 'product_desc'
    if source_col not in df_govspend.columns:
        print(f"❌ Critical Error: Could not find a description column in the input file.")
        return
    df_govspend.rename(columns={source_col: config.CLEAN_DESC_COL}, inplace=True)
    descriptions = df_govspend[config.CLEAN_DESC_COL].astype(str).fillna("")

    # 5. Run the full prediction pipeline
    # Step A: Gatekeeper
    print("  - Step 1: Identifying potential lab items with gatekeeper...")
    text_vectors_tfidf = tfidf_vectorizer.transform(descriptions)
    lab_probabilities = gatekeeper_model.predict_proba(text_vectors_tfidf)[:, 1]
    is_lab_mask = lab_probabilities >= config.PREDICTION_THRESHOLD
    print(f"  - Gatekeeper found {is_lab_mask.sum()} potential lab items.")

    # Step B: Expert model prediction
    df_govspend['market_prediction'] = "Non-Lab"
    if is_lab_mask.any():
        print(f"  - Step 2: Predicting markets with the '{expert_model_choice}' expert...")
        if model_type == 'parametric':
            if embedding_type == 'tfidf':
                lab_vectors = text_vectors_tfidf[is_lab_mask]
                predictions = expert_predictor.predict(lab_vectors)
                df_govspend.loc[is_lab_mask, 'market_prediction'] = predictions
            else:
                raise NotImplementedError("Parametric BERT expert is not yet implemented.")
        else: # non_parametric
            lab_descriptions = descriptions[is_lab_mask]
            tqdm.pandas(desc=f"  - Categorizing ({expert_model_choice})")
            predictions = lab_descriptions.progress_apply(expert_predictor.get_item_category)
            df_govspend.loc[is_lab_mask, 'market_prediction'] = predictions

        # Step C: Rule-based overrides
        print("  - Step 3: Applying rule-based overrides...")
        lab_descriptions = descriptions[is_lab_mask]
        overrides = lab_descriptions.apply(rule_categorizer.get_market_override)
        df_govspend.loc[overrides.dropna().index, 'market_prediction'] = overrides.dropna()
        print(f"  - Applied {overrides.notna().sum()} rule-based overrides.")

    # 6. Save the final output
    output_suffix = f"classified_gatekeeper_{gatekeeper_name}_expert_{expert_model_choice}.csv"
    output_filename = f"govspend_panel_{output_suffix}"
    output_path = os.path.join(config.OUTPUT_DIR, output_filename)
    df_govspend.to_csv(output_path, index=False)
    print(f"\n✅ Prediction complete. File saved to: {output_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run a prediction pipeline on the GovSpend panel.")
    parser.add_argument("--gatekeeper",type=str,required=True,choices=['tfidf', 'bert'],help="The gatekeeper model to use.")
    parser.add_argument(
        "--expert_model",
        type=str,
        required=True,
        choices=['parametric_tfidf', 'non_parametric_tfidf', 'non_parametric_bert'],
        help="The type of expert model to use (approach_embedding)."
    )
    args = parser.parse_args()
    main(gatekeeper_name=args.gatekeeper, expert_model_choice=args.expert_model)

