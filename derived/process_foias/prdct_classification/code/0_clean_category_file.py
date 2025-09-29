# 0_clean_category_file.py
"""
Central script for cleaning and merging the UT Dallas data.
This script creates the single source of truth for all downstream processes.
"""
import pandas as pd
import os
import config

def main():
    print("--- Starting Step 0: Cleaning and Merging UT Dallas Data ---")

    # 1. Create the temporary directory if it doesn't exist
    os.makedirs(config.TEMP_DIR, exist_ok=True)

    # 2. Load the raw UT Dallas data and the category mapping file
    print("ℹ️ Loading raw data files...")
    try:
        df_ut = pd.read_csv(config.UT_DALLAS_CLEAN_CSV, low_memory=False)
        df_cat = pd.read_excel(config.UT_DALLAS_CATEGORIES_XLSX, keep_default_na=False, na_values=[''])
        print(f"  - Loaded {len(df_ut)} rows from UT Dallas main file.")
        print(f"  - Loaded {len(df_cat)} rows from category mapping file.")
    except FileNotFoundError as e:
        print(f"❌ Error loading data files: {e}. Make sure paths in config.py are correct.")
        return

    # 3. Standardize category names for consistency
    print("ℹ️ Standardizing category names (lowercase, strip whitespace)...")
    if config.UT_CAT_COL in df_cat.columns:
        df_cat[config.UT_CAT_COL] = df_cat[config.UT_CAT_COL].astype(str).str.lower().str.strip()
    
    if 'old_category' in df_cat.columns:
        df_cat['old_category'] = df_cat['old_category'].astype(str).str.lower().str.strip()
        df_cat[config.UT_CAT_COL] = df_cat[config.UT_CAT_COL].replace('', pd.NA).fillna(df_cat['old_category'])

    # 4. Prepare keys for merging
    for key in config.UT_DALLAS_MERGE_KEYS:
        if key in df_ut.columns and key in df_cat.columns:
            df_ut[key] = df_ut[key].astype(str)
            df_cat[key] = df_cat[key].astype(str)

    # 5. Perform an inner merge to keep only matched rows
    print("ℹ️ Merging files (inner merge to keep only matched rows)...")
    df_merged = pd.merge(df_ut, df_cat, on=config.UT_DALLAS_MERGE_KEYS, how='inner', validate="many_to_one")
    print(f"  - Merge complete. Resulting dataset has {len(df_merged)} rows.")

    # 6. --- Data Hygiene Step: Drop rows with missing crucial data ---
    initial_rows = len(df_merged)
    df_merged.dropna(subset=[config.CLEAN_DESC_COL, config.UT_CAT_COL], inplace=True)
    rows_dropped = initial_rows - len(df_merged)
    if rows_dropped > 0:
        print(f"  - Dropped {rows_dropped} rows due to missing descriptions or categories.")

    # 7. Generate and save category counts for review
    print("ℹ️ Generating and saving category counts...")
    category_counts = df_merged[config.UT_CAT_COL].value_counts().reset_index()
    category_counts.columns = ['category', 'count']
    counts_output_path = os.path.join(config.OUTPUT_DIR, 'utdallas_category_counts.csv')
    category_counts.to_csv(counts_output_path, index=False)
    print(f"  ✅ Category counts saved to: {counts_output_path}")

    # 8. Save the final, clean, merged file
    df_merged.to_parquet(config.UT_DALLAS_MERGED_CLEAN_PATH, index=False)
    print(f"\n✅ Final clean and merged data saved to: {config.UT_DALLAS_MERGED_CLEAN_PATH}")
    print("--- Step 0: Complete ---")

if __name__ == "__main__":
    main()

