# 1c_build_category_vectors.py
"""
Pre-computes and saves the average embedding vector for each LAB category
from the UT Dallas data. This creates the knowledge base for the BERT expert model.
"""
import pandas as pd
import joblib
import os
from sentence_transformers import SentenceTransformer
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

    for short_name, model_name in MODELS_TO_PREPARE.items():
        print(f"\n--- Preparing vectors for expert model: {short_name} ---")
        model = SentenceTransformer(model_name)

        print("  - Generating embeddings for all lab item descriptions...")

        descriptions_list = df_lab_only[config.CLEAN_DESC_COL].fillna('').tolist()
        embeddings = model.encode(descriptions_list, show_progress_bar=True)

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
