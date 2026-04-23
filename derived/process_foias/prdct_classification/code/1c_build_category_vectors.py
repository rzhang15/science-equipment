# 1c_build_category_vectors.py
"""
Pre-computes and saves the average embedding vector for each LAB category
from the UT Dallas data. This creates the knowledge base for the BERT expert model.
"""
import pandas as pd
import joblib
import os
from sentence_transformers import SentenceTransformer
from sklearn.preprocessing import normalize
from scipy.sparse import hstack
import numpy as np
import config

MODELS_TO_PREPARE = {
    "bert": "all-MiniLM-L6-v2"
}

def main():
    print(f"--- Starting Step 1c: Preparing BERT Expert Category Vectors [Variant: {config.VARIANT}] ---")

    print("Loading pre-cleaned and merged data...")
    frames = []
    try:
        df_ut = pd.read_parquet(config.UT_DALLAS_MERGED_CLEAN_PATH)
        print(f"  - Loaded {len(df_ut)} rows from UT Dallas.")
        frames.append(df_ut)
    except FileNotFoundError:
        print(f"ERROR: Cleaned UT Dallas file not found at: {config.UT_DALLAS_MERGED_CLEAN_PATH}")
        print("   Please run 0_clean_category_file.py first.")
        return

    if config.USE_UMICH:
        try:
            df_um = pd.read_parquet(config.UMICH_MERGED_CLEAN_PATH)
            print(f"  - Loaded {len(df_um)} rows from UMich.")
            frames.append(df_um)
        except FileNotFoundError:
            print(f"WARNING: UMich file not found at: {config.UMICH_MERGED_CLEAN_PATH}")
            print("   Continuing with UT Dallas only.")

    df_merged = pd.concat(frames, ignore_index=True)

    initial_rows = len(df_merged)
    df_merged.dropna(subset=[config.CLEAN_DESC_COL, config.UT_CAT_COL], inplace=True)
    rows_dropped = initial_rows - len(df_merged)
    if rows_dropped > 0:
        print(f"  - Dropped {rows_dropped} rows due to missing descriptions or categories.")

    # Filter data to ONLY lab categories using word-boundary matching
    print("\nFiltering data to include only lab categories...")
    is_nonlab = df_merged[config.UT_CAT_COL].str.contains(config.NONLAB_REGEX, na=False)
    df_lab_only = df_merged[~is_nonlab].copy()
    print(f"  - Kept {len(df_lab_only)} items from {df_lab_only[config.UT_CAT_COL].nunique()} unique lab categories.")

    # Optional supplier block (mirrors the gatekeeper's combined representation).
    supplier_vectorizer = None
    supp_vec_path = os.path.join(config.OUTPUT_DIR, "vectorizer_supplier_tfidf.joblib")
    if config.USE_SUPPLIER and 'supplier' in df_lab_only.columns and os.path.exists(supp_vec_path):
        supplier_vectorizer = joblib.load(supp_vec_path)
        unique_supp = df_lab_only['supplier'].fillna('').unique()
        supp_map = {s: config.normalize_supplier(str(s)) for s in unique_supp}
        df_lab_only['supplier_token'] = df_lab_only['supplier'].fillna('').map(supp_map)

    for short_name, model_name in MODELS_TO_PREPARE.items():
        print(f"\n--- Preparing vectors for expert model: {short_name} ---")
        model = SentenceTransformer(model_name)

        print("  - Generating embeddings for all lab item descriptions...")

        descriptions_list = df_lab_only[config.CLEAN_DESC_COL].fillna('').tolist()
        embeddings = model.encode(descriptions_list, show_progress_bar=True)

        if supplier_vectorizer is not None:
            supp_tokens = df_lab_only['supplier_token'].fillna('').astype(str).tolist()
            X_supp = supplier_vectorizer.transform(supp_tokens)
            desc_n = normalize(embeddings, norm='l2')
            supp_n = normalize(X_supp, norm='l2')
            item_vectors = hstack([desc_n * config.DESC_WEIGHT,
                                   supp_n * config.SUPPLIER_WEIGHT]).tocsr()
            print(f"  - Combined: {config.DESC_WEIGHT:.0%} BERT + {config.SUPPLIER_WEIGHT:.0%} supplier"
                  f" = {item_vectors.shape[1]} feats")

            print("  - Averaging combined vectors by category...")
            categories = pd.Categorical(df_lab_only[config.UT_CAT_COL])
            from scipy.sparse import csr_matrix
            G = csr_matrix(
                (np.ones(len(categories)), (categories.codes, np.arange(len(categories)))),
                shape=(len(categories.categories), len(categories)),
            )
            cat_sums = G.dot(item_vectors)
            cat_counts = np.bincount(categories.codes)[:, np.newaxis]
            cat_vectors = cat_sums / np.maximum(cat_counts, 1)
            category_data = {
                'category_names': categories.categories.tolist(),
                'category_vectors': cat_vectors,
            }
        else:
            df_lab_only[f'embeddings_{short_name}'] = list(embeddings)
            print("  - Averaging embeddings by category...")
            category_vectors_df = df_lab_only.groupby(config.UT_CAT_COL)[f'embeddings_{short_name}'].apply(lambda x: np.mean(x.tolist(), axis=0))
            category_data = {
                'category_names': category_vectors_df.index.tolist(),
                'category_vectors': np.vstack(category_vectors_df.values)
            }

        output_path = os.path.join(config.OUTPUT_DIR, f"category_vectors_{short_name}.joblib")
        joblib.dump(category_data, output_path)
        print(f"  Saved '{short_name}' expert knowledge base to {output_path}")

    print("\n--- BERT expert category vector preparation complete. ---")

if __name__ == "__main__":
    main()
