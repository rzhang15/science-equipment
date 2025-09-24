# 4_predict_govspend.py (Corrected with robust column finding and model selection)
"""
Runs a selectable classification model on the govspend_panel.csv file.
Example Usage:
  python 4_predict_govspend.py --gte
  python 4_predict_govspend.py --tfidf --word2vec
  python 4_predict_govspend.py --all
"""
import pandas as pd
import os
import joblib
import argparse
from tqdm import tqdm

try:
    import config
    from categorize_items import TfidfItemCategorizer, EmbeddingItemCategorizer, Word2VecItemCategorizer
except ImportError:
    print("❌ Error: Make sure this script is in the same directory as config.py and categorize_items.py")
    exit()

def main():
    parser = argparse.ArgumentParser(description="Run selected classification models on the GovSpend panel.")
    parser.add_argument('--tfidf', action='store_true', help='Run the TF-IDF model.')
    parser.add_argument('--word2vec', action='store_true', help='Run the Word2Vec model.')
    parser.add_argument('--bert', action='store_true', help='Run the BERT model.')
    parser.add_argument('--scibert', action='store_true', help='Run the SciBERT model.')
    parser.add_argument('--gte', action='store_true', help='Run the GTE model.')
    parser.add_argument('--all', action='store_true', help='Run all available models.')
    args = parser.parse_args()

    models_to_run = []
    if args.tfidf or args.all: models_to_run.append('tfidf')
    if args.word2vec or args.all: models_to_run.append('word2vec')
    if args.bert or args.all: models_to_run.append('bert')
    if args.scibert or args.all: models_to_run.append('scibert')
    if args.gte or args.all: models_to_run.append('gte')

    if not models_to_run:
        parser.print_help()
        print("\n❌ Error: Please specify at least one model to run (e.g., --gte) or use --all.")
        return

    print(f"--- Starting Prediction on GovSpend Panel for model(s): {', '.join(models_to_run)} ---")

    # --- 1. Set up file paths ---
    CODE_DIR = os.path.dirname(os.path.abspath(__file__))
    BASE_DIR = os.path.abspath(os.path.join(CODE_DIR, ".."))
    DERIVED_DIR = os.path.abspath(os.path.join(BASE_DIR, "..", ".."))
    INPUT_CSV_PATH = os.path.join(DERIVED_DIR, "govspend", "make_panel", "output", "govspend_panel.csv")

    suffix = "_" + "_".join(sorted(models_to_run))
    OUTPUT_CSV_PATH = os.path.join(config.OUTPUT_DIR, f"govspend_panel_classified{suffix}.csv")

    # --- 2. Load base model and initialize selected categorizers ---
    print("ℹ️ Loading models...")
    categorizers = {}
    try:
        lab_model = joblib.load(config.LAB_MODEL_PATH)
        if 'tfidf' in models_to_run:
            categorizers['tfidf'] = TfidfItemCategorizer(config.CATEGORY_MODEL_DATA_PATH, config.CATEGORY_VECTORIZER_PATH)
        if 'word2vec' in models_to_run:
            categorizers['word2vec'] = Word2VecItemCategorizer("word2vec", os.path.join(config.OUTPUT_DIR, "model_word2vec.model"))
        if 'bert' in models_to_run:
            categorizers['bert'] = EmbeddingItemCategorizer("bert", "all-MiniLM-L6-v2")
        if 'scibert' in models_to_run:
            categorizers['scibert'] = EmbeddingItemCategorizer("scibert", "allenai/scibert_scivocab_uncased")
        if 'gte' in models_to_run:
            categorizers['gte'] = EmbeddingItemCategorizer("gte", "thenlper/gte-large")
    except Exception as e:
        print(f"❌ Error initializing models: {e}")
        return
    print("✅ Models loaded successfully.")

    # --- 3. Load and prepare the GovSpend data ---
    print(f"ℹ️ Loading data from {os.path.basename(INPUT_CSV_PATH)}...")
    df_govspend = pd.read_csv(INPUT_CSV_PATH, low_memory=False)

    # --- THIS IS THE CORRECTED SECTION ---
    # Determine which description column exists in the CSV
    source_col_name = None
    if 'prdct_description' in df_govspend.columns:
        source_col_name = 'prdct_description'
    elif 'product_desc' in df_govspend.columns:
        source_col_name = 'product_desc'

    if source_col_name is None:
        print("❌ Critical Error: Could not find 'prdct_description' or 'product_desc' in the input file.")
        return

    print(f"  - Found description column: '{source_col_name}'")
    # Rename the column that was found to what the model expects
    df_govspend.rename(columns={source_col_name: config.CLEAN_DESC_COL}, inplace=True)
    descriptions = df_govspend[config.CLEAN_DESC_COL].astype(str).fillna("")
    # --- END OF CORRECTION ---

    # --- 4. Run the two-step prediction process ---
    print("  - Step 1: Predicting Lab/Not-Lab for all rows...")
    lab_probabilities = lab_model.predict_proba(descriptions)[:, 1]
    is_lab_mask = lab_probabilities >= config.PREDICTION_THRESHOLD
    lab_descriptions = descriptions[is_lab_mask]
    print(f"  - Found {len(lab_descriptions)} potential lab items to categorize.")

    if not lab_descriptions.empty:
        print("  - Step 2: Categorizing lab items with selected model(s)...")
        for model_name, categorizer in categorizers.items():
            col_name = f'market_prediction_{model_name}'
            df_govspend[col_name] = "Non-Lab"

            tqdm.pandas(desc=model_name.upper())
            if model_name == 'tfidf':
                predictions = lab_descriptions.progress_apply(
                    lambda desc: categorizer.get_item_category(desc, sim_weight=config.CATEGORY_SIMILARITY_WEIGHT, overlap_weight=config.CATEGORY_OVERLAP_WEIGHT)
                )
            else:
                predictions = lab_descriptions.progress_apply(categorizer.get_item_category)

            df_govspend.loc[is_lab_mask, col_name] = predictions

    # --- 5. Save the final output ---
    print(f"ℹ️ Saving classified output...")
    df_govspend.to_csv(OUTPUT_CSV_PATH, index=False)
    print(f"✅ Success! Classified file saved to: {OUTPUT_CSV_PATH}")

if __name__ == "__main__":
    main()
