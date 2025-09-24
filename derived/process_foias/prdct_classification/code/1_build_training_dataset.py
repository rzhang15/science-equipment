# 1_prepare_data.py
"""
Loads and processes all source data (UT Dallas, CA, fisher) to create a unified training set.
"""
import pandas as pd
import os
import joblib
from sklearn.feature_extraction.text import TfidfVectorizer
import yaml
import re
import ahocorasick

import config
from categorize_items import TfidfItemCategorizer

def load_keywords_and_build_automaton(filepath):
    """
    Loads keywords from a YAML file and builds a highly efficient
    Aho-Corasick automaton for fast multi-keyword matching.
    """
    try:
        with open(filepath, 'r') as f:
            data = yaml.safe_load(f)
            keywords = data.get('keywords', [])
            if not keywords:
                return None
            
            # Build the Aho-Corasick automaton
            A = ahocorasick.Automaton()
            for idx, keyword in enumerate(keywords):
                A.add_word(keyword.lower(), (idx, keyword.lower()))
            A.make_automaton()
            return A
    except FileNotFoundError:
        print(f"⚠️ Keyword file not found: {filepath}")
        return None
SEED_KEYWORD_AUTOMATON = load_keywords_and_build_automaton(config.SEED_KEYWORD_YAML)
ANTI_SEED_KEYWORD_AUTOMATON = load_keywords_and_build_automaton(config.ANTI_SEED_KEYWORD_YAML)
def has_match(description, automaton):
    """
    Checks if any keyword from the automaton exists in the description.
    Returns True if a match is found, False otherwise.
    """
    if not isinstance(description, str) or automaton is None:
        return False
    # Use iter() to find if there's at least one match, which is very fast
    try:
        next(automaton.iter(description.lower()))
        return True
    except StopIteration:
        return False


def load_and_merge_ut_dallas():
    print("ℹ️ Loading and processing UT Dallas data...")
    try:
        df_ut = pd.read_csv(config.UT_DALLAS_CLEAN_CSV, low_memory=False)
        df_cat = pd.read_excel(config.UT_DALLAS_CATEGORIES_XLSX, keep_default_na=False, na_values=[''])
        print("  - Standardizing category names (lowercase, strip whitespace)...")
        if config.UT_CAT_COL in df_cat.columns:
            df_cat[config.UT_CAT_COL] = df_cat[config.UT_CAT_COL].astype(str).str.lower().str.strip()
        # --- Apply fallback logic using 'old_category' if it exists ---
        if 'old_category' in df_cat.columns:
            print("  - Applying fallback: Using 'old_category' where 'category' is missing.")
            df_cat['old_category'] = df_cat['old_category'].astype(str).str.lower().str.strip()
            # This fills NaN/blank values in the 'category' column with values from 'old_category'
            df_cat[config.UT_CAT_COL] = df_cat[config.UT_CAT_COL].fillna(df_cat['old_category'])
        if 'clean_desc' in df_cat.columns:
            df_cat = df_cat.drop(columns=['clean_desc'])
        print("\n--- Validating Keys for 1:m Merge ---")
        merge_keys = config.UT_DALLAS_MERGE_KEYS
        if not all(key in df_ut.columns for key in merge_keys) or not all(key in df_cat.columns for key in merge_keys):
            raise ValueError("One or more merge keys specified in config.py are missing from the data files.")
        if df_cat.duplicated(subset=merge_keys).any():
            print("‼️ ERROR: Duplicate keys found in the category file (df_cat). This violates the 1:m merge condition.")
            # Find and print the duplicate rows to help with debugging
            duplicates = df_cat[df_cat.duplicated(subset=merge_keys, keep=False)].sort_values(by=merge_keys)
            print("   The following rows in your category file are conflicting:")
            print(duplicates)
            raise ValueError("Merge aborted due to duplicate keys in the category file.")
        else:
            print("✅ Keys in category file are unique. Proceeding with 1:m merge.")
        print("--- Validation Complete ---\n")
        for key in config.UT_DALLAS_MERGE_KEYS:
            if key in df_ut.columns and key in df_cat.columns:
                df_ut[key] = df_ut[key].astype(str)
                df_cat[key] = df_cat[key].astype(str)
        df_merged = pd.merge(df_ut, df_cat, on=config.UT_DALLAS_MERGE_KEYS, how='left', validate="many_to_one")
        print("\n--- Observation Counts per Category (Top 15) ---")
        category_counts = df_merged[config.UT_CAT_COL].value_counts()
        print(category_counts.head(15))
        print(f"Total unique categories: {len(category_counts)}")
        
        # Convert the Series to a DataFrame for saving
        category_counts_df = category_counts.reset_index()
        category_counts_df.columns = ['category', 'count']
        
        # Define the output path and save to CSV
        output_path = os.path.join(config.OUTPUT_DIR, 'utdallas_category_counts.csv')
        category_counts_df.to_csv(output_path, index=False)
        print(f"✅ Full list of category counts saved to: {output_path}")
        print("------------------------------------------------\n")
        df_merged[config.UT_CAT_COL] = df_merged[config.UT_CAT_COL].fillna('Uncategorized')
        df_merged['cleaned_description'] = df_merged[config.CLEAN_DESC_COL].fillna('')
        df_merged['data_source'] = 'ut_dallas'
        print("  ✅ UT Dallas data loaded and merged.")
        return df_merged
    except Exception as e:
        print(f"❌ Error loading UT Dallas data: {e}")
        return pd.DataFrame()

def load_ca_data():
    print("\nℹ️ Loading and processing CA Non-Lab data...")
    try:
        df = pd.read_csv(config.CA_NON_LAB_DTA)
        df['cleaned_description'] = df[config.CA_DESC_COL].fillna('')
        df['label'] = 0 # Assume all items in this file are non-lab
        df['data_source'] = 'ca_non_lab'
        print(f"  ✅ Loaded {len(df)} rows from CA data, labeled as non-lab.")
        return df
    except Exception as e:
        print(f"❌ Error loading CA Non-Lab data: {e}")
        return pd.DataFrame()

def load_fisher_lab_data():
    """Loads the curated Fisher lab items and labels them as Lab (1)."""
    print("\nℹ️ Loading and processing Fisher Lab data...")
    try:
        df = pd.read_csv(config.FISHER_LAB)
        df['cleaned_description'] = df[config.FISHER_DESC_COL].fillna('')
        df['label'] = 1  # This is a trusted Lab data source
        df['data_source'] = 'fisher_lab'
        print(f"  ✅ Loaded {len(df)} rows from Fisher Lab catalog.")
        return df
    except Exception as e:
        print(f"❌ Error loading Fisher Lab data: {e}")
        return pd.DataFrame()
def load_fisher_non_lab_data():
    """Loads the curated Fisher non-lab items and labels them as Non-Lab (0)."""
    print("\nℹ️ Loading and processing Fisher Non-Lab data...")
    try:
        df = pd.read_csv(config.FISHER_NONLAB)
        df['cleaned_description'] = df[config.FISHER_DESC_COL].fillna('')
        df['label'] = 0  # This is a trusted Non-Lab data source
        df['data_source'] = 'fisher_non_lab'
        print(f"  ✅ Loaded {len(df)} rows from Fisher Non-Lab catalog.")
        return df
    except Exception as e:
        print(f"❌ Error loading Fisher Non-Lab data: {e}")
        return pd.DataFrame()

def assign_binary_labels_ut(df):
    """
    Assigns preliminary labels to UT Dallas data based on category using a
    fast Aho-Corasick search.
    """
    # 1. Get the list of non-lab category keywords from your config
    nonlab_keywords = config.NONLAB_CATEGORIES

    # 2. Build a highly efficient Aho-Corasick automaton for matching
    A = ahocorasick.Automaton()
    for idx, keyword in enumerate(nonlab_keywords):
        # Ensure keywords are added in lowercase to match the search text
        A.add_word(str(keyword).lower(), (idx, str(keyword).lower()))
    A.make_automaton()

    # 3. Apply the fast search to the category column
    # Ensure the column is string type and lowercase before applying the search
    is_nonlab = df[config.UT_CAT_COL].astype(str).str.lower().apply(has_match, automaton=A)
    
    # 4. Set the labels based on the matches
    df['label'] = 1
    df.loc[is_nonlab, 'label'] = 0
    return df

def main():
    print("--- Starting Step 1: Data Preparation ---")

    df_ut_dallas = load_and_merge_ut_dallas()
    df_ca_non_lab = load_ca_data()
    df_fisher_lab = load_fisher_lab_data()
    df_fisher_non_lab = load_fisher_non_lab_data()
    if df_ut_dallas.empty:
        return

    df_ut_dallas = assign_binary_labels_ut(df_ut_dallas)

    print("\n- Combining all data sources...")
    df_combined = pd.concat([
        df_ut_dallas,
        df_ca_non_lab,
        df_fisher_lab,
        df_fisher_non_lab
    ], ignore_index=True)
    print("\n- Applying definitive keyword-based labels to combined dataset...")
    if SEED_KEYWORD_AUTOMATON:
        print("  - Applying lab keywords (this will be fast)...")
        seed_matches = df_combined['cleaned_description'].apply(has_match, automaton=SEED_KEYWORD_AUTOMATON)
        df_combined.loc[seed_matches, 'label'] = 1
        print(f"  - Labeled {seed_matches.sum()} items as 'Lab' based on initial_seed.yml")
    
    if ANTI_SEED_KEYWORD_AUTOMATON:
        print("  - Applying non-lab keywords (this will be fast)...")
        anti_seed_matches = df_combined['cleaned_description'].apply(has_match, automaton=ANTI_SEED_KEYWORD_AUTOMATON)
        df_combined.loc[anti_seed_matches, 'label'] = 0
        print(f"  - Labeled {anti_seed_matches.sum()} items as 'Not Lab' based on anti_seed_keywords.yml")
    # --- END OF MODIFICATION ---
    initial_rows = len(df_combined)
    df_combined.drop_duplicates(subset=['cleaned_description'], keep='first', inplace=True)
    print(f"  - Combined all sources into {len(df_combined)} unique rows (removed {initial_rows - len(df_combined)} duplicates).")

    df_prepared = df_combined.rename(columns={'cleaned_description': 'prepared_description'})

    print("\nFinal label distribution for combined training data:")
    print(df_prepared['label'].value_counts(normalize=True))

    print("\nℹ️ Fitting a TF-IDF vectorizer...")
    category_vectorizer = TfidfVectorizer(
        ngram_range=(1, 3),
        min_df=config.VECTORIZER_MIN_DF, # Use the new config parameter
        stop_words='english'
    )
    category_vectorizer.fit(df_prepared['prepared_description'])
    joblib.dump(category_vectorizer, config.CATEGORY_VECTORIZER_PATH)
    print(f"✅ Category vectorizer saved to: {config.CATEGORY_VECTORIZER_PATH}")

    TfidfItemCategorizer.prepare_and_save_category_data(
        df_ut_dallas=df_ut_dallas.rename(columns={'cleaned_description': 'prepared_description'}),
        vectorizer=category_vectorizer,
        category_col=config.UT_CAT_COL,
        description_col='prepared_description',
        output_path=config.CATEGORY_MODEL_DATA_PATH
    )

    columns_to_save = [
        'prepared_description', 'label', config.UT_CAT_COL,
        config.CLEAN_DESC_COL, config.RAW_DESC_COL, 'data_source'
    ]
    df_to_save = df_prepared[[col for col in columns_to_save if col in df_prepared.columns]]
    df_to_save.to_parquet(config.PREPARED_DATA_PATH, index=False)
    print(f"✅ Final prepared training data saved to: {config.PREPARED_DATA_PATH}")
    print("--- Step 1: Data Preparation Complete ---")

if __name__ == "__main__":
    main()
