# 3_predict.py (Final version with file looping and model comparison)
"""
Loops through all input files, uses the TF-IDF model for Lab/Not-Lab classification,
then runs multiple embedding models in parallel to assign product markets and saves
a separate, detailed comparison file for each input.

Can be run in two ways:
1. To process all files: python 3_predict.py
2. To process a single university's file: python 3_predict.py <university_abbreviation>
   (e.g., python 3_predict.py utdallas) - This will match files like 'utdallas_2011_2024_standardized_clean.csv'.
"""
from tqdm import tqdm
import pandas as pd
import glob
import os
import joblib
import sys # Import sys to access command-line arguments
import config
from categorize_items import TfidfItemCategorizer, EmbeddingItemCategorizer, Word2VecItemCategorizer

def main():
    print("--- Starting Step 3: Prediction and Model Comparison ---")

    # 1. Load the TF-IDF Binary Classifier (The "Gatekeeper")
    print("ℹ️ Loading TF-IDF Lab/Not-Lab model...")
    try:
        lab_model = joblib.load(config.LAB_MODEL_PATH)
    except FileNotFoundError:
        print("❌ Lab/Not-Lab model not found. Run relevant scripts first.")
        return

    # 2. Initialize all Granular Categorizers
    print("ℹ️ Initializing all product market categorizers...")
    try:
        tfidf_categorizer = TfidfItemCategorizer(
            category_data_path=config.CATEGORY_MODEL_DATA_PATH,
            vectorizer_path=config.CATEGORY_VECTORIZER_PATH
        )
        #word2vec_categorizer = Word2VecItemCategorizer(embedding_name="word2vec", model_path="../output/model_word2vec.model")
        bert_categorizer = EmbeddingItemCategorizer(embedding_name="bert", model_name="all-MiniLM-L6-v2")
        #scibert_categorizer = EmbeddingItemCategorizer(embedding_name="scibert", model_name="allenai/scibert_scivocab_uncased")
        #gte_categorizer = EmbeddingItemCategorizer(embedding_name="gte", model_name="thenlper/gte-large")
    except Exception as e:
        print(f"❌ Error initializing categorizers: {e}")
        return

    # --- 3. Find input files to process based on command-line arguments ---
    input_files = []
    # Check if a command-line argument (e.g., 'utdallas') was provided
    if len(sys.argv) > 1:
        uni_abbrev = sys.argv[1]
        print(f"ℹ️ Specific university requested: {uni_abbrev}")
        # Construct a search pattern to find the file, accommodating for years in the name
        search_pattern = os.path.join(config.FOIA_INPUT_DIR, f"{uni_abbrev}*_standardized_clean.csv")
        found_files = glob.glob(search_pattern)

        # Check if any matching file was found
        if found_files:
            if len(found_files) > 1:
                print(f"⚠️  Warning: Found multiple files for '{uni_abbrev}'. Using the first one found: {os.path.basename(found_files[0])}")
            input_files = [found_files[0]]
        else:
            print(f"❌ No file found for '{uni_abbrev}' with pattern '{os.path.basename(search_pattern)}'")
            return # Exit if no matching file is found
    else:
        # If no argument is given, find all relevant files as before
        print("ℹ️ No specific university requested, searching for all files...")
        input_files = glob.glob(os.path.join(config.FOIA_INPUT_DIR, "*_standardized_clean.csv"))

    if not input_files:
        print(f"❌ No standardized clean CSV files found to process in {config.FOIA_INPUT_DIR}")
        return

    print(f"ℹ️ Found {len(input_files)} file(s) to process.")

    # --- Loop through each file, process it, and save a unique output ---
    for file_path in input_files:
        print(f"\n--- Processing file: {os.path.basename(file_path)} ---")
        try:
            df_new = pd.read_csv(file_path, low_memory=False)
            if df_new.empty or config.CLEAN_DESC_COL not in df_new.columns:
                print("  - Skipping empty or invalid file.")
                continue

            descriptions = df_new[config.CLEAN_DESC_COL].astype(str).fillna("")

            # === BATCH PROCESSING START ===
            print("  - Step 1: Predicting Lab/Not-Lab for all rows...")
            # Predict all descriptions at once
            lab_probabilities = lab_model.predict_proba(descriptions)[:, 1]

            # Create a boolean "mask" to identify rows that are likely "Lab" items
            is_lab_mask = lab_probabilities >= config.PREDICTION_THRESHOLD

            # Get just the subset of descriptions that need detailed categorization
            lab_descriptions = descriptions[is_lab_mask]
            print(f"  - Found {len(lab_descriptions)} potential lab items to categorize.")

            # Initialize all new columns with the default "Non-Lab" value
            df_new['market_prediction_tfidf'] = "Non-Lab"
            #df_new['market_prediction_word2vec'] = "Non-Lab"
            df_new['market_prediction_bert'] = "Non-Lab"
            #df_new['market_prediction_scibert'] = "Non-Lab"
            #df_new['market_prediction_gte'] = "Non-Lab"

            # If there are any lab items, run the detailed models ONLY on them
            if not lab_descriptions.empty:
                print("  - Step 2: Categorizing lab items with all models...")

                # The tqdm wrapper adds a progress bar for each model!
                tqdm.pandas(desc="TF-IDF")
                df_new.loc[is_lab_mask, 'market_prediction_tfidf'] = lab_descriptions.progress_apply(
                    lambda desc: tfidf_categorizer.get_item_category(desc, sim_weight=config.CATEGORY_SIMILARITY_WEIGHT, overlap_weight=config.CATEGORY_OVERLAP_WEIGHT)
                )
                #tqdm.pandas(desc="Word2Vec")
                #df_new.loc[is_lab_mask, 'market_prediction_word2vec'] = lab_descriptions.progress_apply(word2vec_categorizer.get_item_category)
                tqdm.pandas(desc="BERT")
                df_new.loc[is_lab_mask, 'market_prediction_bert'] = lab_descriptions.progress_apply(bert_categorizer.get_item_category)
                #tqdm.pandas(desc="SciBERT")
                #df_new.loc[is_lab_mask, 'market_prediction_scibert'] = lab_descriptions.progress_apply(scibert_categorizer.get_item_category)
                #tqdm.pandas(desc="GTE")
                #df_new.loc[is_lab_mask, 'market_prediction_gte'] = lab_descriptions.progress_apply(gte_categorizer.get_item_category)

            # === BATCH PROCESSING END ===

            # Create a new filename for the classified output
            base_filename = os.path.basename(file_path)
            name_part, ext = os.path.splitext(base_filename)
            output_filename = f"{name_part}_classified{ext}"
            output_path = os.path.join(config.OUTPUT_DIR, output_filename)

            df_new.to_csv(output_path, index=False)
            print(f"✅ Comparison file saved to: {output_path}")

        except Exception as e:
            print(f"❌ An error occurred while processing {os.path.basename(file_path)}: {e}")
            continue

    print("\n--- All files processed. ---")

if __name__ == "__main__":
    main()
