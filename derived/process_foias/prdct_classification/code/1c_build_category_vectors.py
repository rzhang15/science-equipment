# 1c_prepare_category_vectors.py (Corrected for KeyError)
"""
Pre-computes and saves the average embedding vector for each UT Dallas category
for multiple different embedding models (TF-IDF, SciBERT, GTE).
"""
import pandas as pd
import joblib
import os
from sentence_transformers import SentenceTransformer
from gensim.models import Word2Vec
import numpy as np
import config

MODELS_TO_PREPARE = {
    "bert": "all-MiniLM-L6-v2"
#    "scibert": "allenai/scibert_scivocab_uncased",
#    "gte": "thenlper/gte-large"
}

def get_corpus(df, column_name):
    return [doc.split() for doc in df[column_name].fillna('')]

def main():
    print("--- Starting Step 1c: Preparing All Category Vectors ---")

    print("ℹ️ Loading and merging UT Dallas data...")
    try:
        df_ut = pd.read_csv(config.UT_DALLAS_CLEAN_CSV, low_memory=False)
        df_cat = pd.read_excel(config.UT_DALLAS_CATEGORIES_XLSX, keep_default_na=False, na_values=[''])
    except FileNotFoundError as e:
        print(f"❌ Error loading data files: {e}. Make sure paths in config.py are correct.")
        return
    if config.CLEAN_DESC_COL in df_cat.columns:
        df_cat = df_cat.drop(columns=[config.CLEAN_DESC_COL])
    # --- NEW: Safety check for the description column ---
    if config.CLEAN_DESC_COL not in df_ut.columns:
        print(f"⚠️ Warning: Column '{config.CLEAN_DESC_COL}' not found.")
        if config.RAW_DESC_COL in df_ut.columns:
            print(f"  - Found '{config.RAW_DESC_COL}' instead. Using it as the description column.")
            # Rename the raw column to the clean column name for consistency
            df_ut.rename(columns={config.RAW_DESC_COL: config.CLEAN_DESC_COL}, inplace=True)
        else:
            print(f"❌ Critical Error: Cannot find a description column ('{config.CLEAN_DESC_COL}' or '{config.RAW_DESC_COL}').")
            return

    df_merged = pd.merge(df_ut, df_cat, on=config.UT_DALLAS_MERGE_KEYS, how='left', validate="many_to_one")
    df_merged.dropna(subset=[config.CLEAN_DESC_COL, config.UT_CAT_COL], inplace=True)
    print("ℹ️ Calculating observation counts per category...")
    category_counts = df_merged[config.UT_CAT_COL].value_counts()
    dense_categories = category_counts[category_counts >= config.DENSE_CATEGORY_THRESHOLD].index.tolist()
    print(f"  - Found {len(dense_categories)} categories with {config.DENSE_CATEGORY_THRESHOLD} or more observations.")

    # --- 1. Prepare vectors for each transformer model ---
    for short_name, model_name in MODELS_TO_PREPARE.items():
        print(f"\n--- Preparing vectors for: {short_name} ---")
        model = SentenceTransformer(model_name)

        print("  - Generating embeddings for all descriptions...")
        embeddings = model.encode(df_merged[config.CLEAN_DESC_COL].tolist(), show_progress_bar=True)
        df_merged[f'embeddings_{short_name}'] = list(embeddings)

        print("  - Averaging embeddings by category...")
        category_vectors_df = df_merged.groupby(config.UT_CAT_COL)[f'embeddings_{short_name}'].apply(lambda x: np.mean(x.tolist(), axis=0))

        category_data = {
            'category_names': category_vectors_df.index.tolist(),
            'category_vectors': np.vstack(category_vectors_df.values),
            'dense_categories': dense_categories # <-- ADD THIS LINE
        }

        output_path = os.path.join(config.OUTPUT_DIR, f"category_vectors_{short_name}.joblib")
        joblib.dump(category_data, output_path)
        print(f"✅ Saved category vectors to {output_path}")
    print("\n--- Category vector preparation complete. ---")
    # # --- 2. Prepare vectors for Word2Vec ---
    # print("\n--- Preparing vectors for: word2vec ---")
    # try:
    #     w2v_model = Word2Vec.load(os.path.join(config.OUTPUT_DIR, "model_word2vec.model"))
    # except FileNotFoundError:
    #     print("❌ Word2Vec model not found. Run 1b_generate_embeddings.py to train it first.")
    #     return

    # corpus = get_corpus(df_merged, config.CLEAN_DESC_COL)
    # w2v_embeddings = []
    # for doc in corpus:
    #     doc_vectors = [w2v_model.wv[word] for word in doc if word in w2v_model.wv]
    #     if doc_vectors:
    #         w2v_embeddings.append(np.mean(doc_vectors, axis=0))
    #     else:
    #         w2v_embeddings.append(np.zeros(w2v_model.vector_size))

    # df_merged['embeddings_word2vec'] = w2v_embeddings

    # category_vectors_df = df_merged.groupby(config.UT_CAT_COL)['embeddings_word2vec'].apply(lambda x: np.mean(x.tolist(), axis=0))
    # category_data = {
    #     'category_names': category_vectors_df.index.tolist(),
    #     'category_vectors': np.vstack(category_vectors_df.values),
    #     'dense_categories': dense_categories # <-- ADD THIS LINE
    # }
    # output_path = os.path.join(config.OUTPUT_DIR, "category_vectors_word2vec.joblib")
    # joblib.dump(category_data, output_path)
    # print(f"✅ Saved category vectors to {output_path}")

if __name__ == "__main__":
    main()
