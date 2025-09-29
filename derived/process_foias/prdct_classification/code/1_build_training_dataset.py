# 1_build_training_dataset.py
"""
Loads the pre-cleaned and merged UT Dallas data, combines it with other
data sources (CA, Fisher), and creates the final unified training set.
Also prepares the knowledge base for the TF-IDF expert model using ONLY lab categories.
"""
import pandas as pd
import os
import joblib
from sklearn.feature_extraction.text import TfidfVectorizer
import yaml
import ahocorasick

import config
from categorize_items import TfidfItemCategorizer

def load_keywords_and_build_automaton(filepath):
    """Loads keywords and builds an Aho-Corasick automaton for fast matching."""
    try:
        with open(filepath, 'r') as f:
            keywords = yaml.safe_load(f).get('keywords', [])
            if not keywords: return None
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
    """Checks if a description contains any keyword from the automaton."""
    if not isinstance(description, str) or automaton is None:
        return False
    try:
        next(automaton.iter(description.lower()))
        return True
    except StopIteration:
        return False

def load_ca_data():
    print("\nℹ️ Loading and processing CA Non-Lab data...")
    try:
        df = pd.read_csv(config.CA_NON_LAB_DTA)
        df['cleaned_description'] = df[config.CA_DESC_COL].fillna('')
        df['label'] = 0
        df['data_source'] = 'ca_non_lab'
        print(f"  ✅ Loaded {len(df)} rows from CA data.")
        return df
    except Exception as e:
        print(f"❌ Error loading CA Non-Lab data: {e}")
        return pd.DataFrame()

def load_fisher_lab_data():
    print("\nℹ️ Loading and processing Fisher Lab data...")
    try:
        df = pd.read_csv(config.FISHER_LAB)
        df['cleaned_description'] = df[config.FISHER_DESC_COL].fillna('')
        df['label'] = 1
        df['data_source'] = 'fisher_lab'
        print(f"  ✅ Loaded {len(df)} rows from Fisher Lab catalog.")
        return df
    except Exception as e:
        print(f"❌ Error loading Fisher Lab data: {e}")
        return pd.DataFrame()

def load_fisher_non_lab_data():
    print("\nℹ️ Loading and processing Fisher Non-Lab data...")
    try:
        df = pd.read_csv(config.FISHER_NONLAB)
        df['cleaned_description'] = df[config.FISHER_DESC_COL].fillna('')
        df['label'] = 0
        df['data_source'] = 'fisher_non_lab'
        print(f"  ✅ Loaded {len(df)} rows from Fisher Non-Lab catalog.")
        return df
    except Exception as e:
        print(f"❌ Error loading Fisher Non-Lab data: {e}")
        return pd.DataFrame()

def assign_binary_labels_ut(df):
    """Assigns preliminary labels to UT Dallas data based on category keywords."""
    nonlab_keywords = config.NONLAB_CATEGORIES
    A = ahocorasick.Automaton()
    for idx, keyword in enumerate(nonlab_keywords):
        A.add_word(str(keyword).lower(), (idx, str(keyword).lower()))
    A.make_automaton()
    is_nonlab = df[config.UT_CAT_COL].astype(str).str.lower().apply(has_match, automaton=A)
    df['label'] = 1
    df.loc[is_nonlab, 'label'] = 0
    return df

def main():
    print("--- Starting Step 1: Data Preparation ---")

    print("ℹ️ Loading pre-cleaned UT Dallas data...")
    try:
        df_ut_dallas = pd.read_parquet(config.UT_DALLAS_MERGED_CLEAN_PATH)
        df_ut_dallas['cleaned_description'] = df_ut_dallas[config.CLEAN_DESC_COL].fillna('')
        df_ut_dallas['data_source'] = 'ut_dallas'
        print("  ✅ UT Dallas clean data loaded.")
    except FileNotFoundError:
        print(f"❌ Cleaned UT Dallas file not found at: {config.UT_DALLAS_MERGED_CLEAN_PATH}")
        print("   Please run 0_clean_category_file.py first.")
        return

    df_ca_non_lab = load_ca_data()
    df_fisher_lab = load_fisher_lab_data()
    df_fisher_non_lab = load_fisher_non_lab_data()

    df_ut_dallas = assign_binary_labels_ut(df_ut_dallas)

    print("\n- Combining all data sources...")
    df_combined = pd.concat([df_ut_dallas, df_ca_non_lab, df_fisher_lab, df_fisher_non_lab], ignore_index=True)
    
    print("\n- Applying definitive keyword-based labels...")
    if SEED_KEYWORD_AUTOMATON:
        seed_matches = df_combined['cleaned_description'].apply(has_match, automaton=SEED_KEYWORD_AUTOMATON)
        df_combined.loc[seed_matches, 'label'] = 1
        print(f"  - Labeled {seed_matches.sum()} items as 'Lab' based on seed keywords.")
    
    if ANTI_SEED_KEYWORD_AUTOMATON:
        anti_seed_matches = df_combined['cleaned_description'].apply(has_match, automaton=ANTI_SEED_KEYWORD_AUTOMATON)
        df_combined.loc[anti_seed_matches, 'label'] = 0
        print(f"  - Labeled {anti_seed_matches.sum()} items as 'Not Lab' based on anti-seed keywords.")

    initial_rows = len(df_combined)
    df_combined.drop_duplicates(subset=['cleaned_description'], keep='first', inplace=True)
    print(f"  - Combined all sources into {len(df_combined)} unique rows (removed {initial_rows - len(df_combined)} duplicates).")

    df_prepared = df_combined.rename(columns={'cleaned_description': 'prepared_description'})

    print("\nFinal label distribution for training data:")
    print(df_prepared['label'].value_counts(normalize=True))

    print("\nℹ️ Fitting a TF-IDF vectorizer for the expert model...")
    category_vectorizer = TfidfVectorizer(ngram_range=(1, 3), min_df=config.VECTORIZER_MIN_DF, stop_words='english')
    category_vectorizer.fit(df_prepared['prepared_description'])
    joblib.dump(category_vectorizer, config.CATEGORY_VECTORIZER_PATH)
    print(f"✅ Category vectorizer saved to: {config.CATEGORY_VECTORIZER_PATH}")

    # --- NEW: Filter UT Dallas data to ONLY lab categories before building the expert model ---
    print("\nℹ️ Filtering out non-lab categories to build TF-IDF expert's knowledge base...")
    nonlab_pattern = '|'.join(config.NONLAB_CATEGORIES)
    is_nonlab_mask = df_ut_dallas[config.UT_CAT_COL].str.contains(nonlab_pattern, case=False, na=False)
    df_ut_dallas_lab_only = df_ut_dallas[~is_nonlab_mask].copy()
    print(f"  - Using {len(df_ut_dallas_lab_only)} lab-only items to build TF-IDF expert's knowledge base.")

    TfidfItemCategorizer.prepare_and_save_category_data(
        df_ut_dallas=df_ut_dallas_lab_only.rename(columns={'cleaned_description': 'prepared_description'}),
        vectorizer=category_vectorizer,
        category_col=config.UT_CAT_COL,
        description_col='prepared_description',
        output_path=config.CATEGORY_MODEL_DATA_PATH
    )

    columns_to_save = ['prepared_description', 'label', config.UT_CAT_COL, config.CLEAN_DESC_COL, config.RAW_DESC_COL, 'data_source']
    df_to_save = df_prepared[[col for col in columns_to_save if col in df_prepared.columns]]
    df_to_save.to_parquet(config.PREPARED_DATA_PATH, index=False)
    print(f"✅ Final prepared training data saved to: {config.PREPARED_DATA_PATH}")
    print("--- Step 1: Data Preparation Complete ---")

if __name__ == "__main__":
    main()

