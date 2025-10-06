# 1_build_training_dataset.py
"""
Loads the pre-cleaned UT Dallas data, combines it with other sources,
and creates the final unified training set. It also builds the knowledge base
for the non-parametric TF-IDF expert model.
"""
import pandas as pd
import os
import joblib
from sklearn.feature_extraction.text import TfidfVectorizer
import yaml
import ahocorasick
from scipy.sparse import vstack, csr_matrix
from tqdm import tqdm
import numpy as np


import config

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

def prepare_and_save_tfidf_category_vectors(df_lab_only, vectorizer, output_path):
    """
    Pre-computes and saves the average TF-IDF vector for each lab category.
    This creates the knowledge base for the non-parametric TF-IDF expert model.
    """
    print("\nℹ️ Preparing and saving TF-IDF category vectors...")
    
    descriptions = df_lab_only[config.CLEAN_DESC_COL]
    categories = pd.Categorical(df_lab_only[config.UT_CAT_COL])
    unique_categories = categories.categories

    # Vectorize all descriptions efficiently in batches
    batch_size=5000
    vector_batches = []
    for i in tqdm(range(0, len(descriptions), batch_size), desc="  - Vectorizing descriptions"):
        batch = descriptions.iloc[i:i+batch_size]
        vector_batches.append(vectorizer.transform(batch))
    all_vectors = vstack(vector_batches)
    
    # Calculate the mean vector for each category
    print("  - Calculating mean category vectors...")
    grouping_matrix = csr_matrix((np.ones(len(categories)), (categories.codes, np.arange(len(categories)))), shape=(len(unique_categories), len(categories)))
    category_sums = grouping_matrix.dot(all_vectors)
    category_counts = np.bincount(categories.codes)[:, np.newaxis]
    mean_category_vectors = category_sums / np.maximum(category_counts, 1) # Avoid division by zero
    
    # Save the simplified data structure
    category_vector_data = {
        'category_names': unique_categories.tolist(),
        'category_vectors': mean_category_vectors
    }
    joblib.dump(category_vector_data, output_path)
    print(f"✅ TF-IDF category vectors saved to: {output_path}")


def main():
    print("--- Starting Step 1: Data Preparation ---")

    print("ℹ️ Loading pre-cleaned UT Dallas data...")
    try:
        df_ut_dallas = pd.read_parquet(config.UT_DALLAS_MERGED_CLEAN_PATH)
    except FileNotFoundError:
        print(f"❌ Cleaned UT Dallas file not found. Please run 0_clean_category_file.py first.")
        return

    df_ut_dallas['cleaned_description'] = df_ut_dallas[config.CLEAN_DESC_COL].fillna('')
    df_ut_dallas['data_source'] = 'ut_dallas'
    
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
    
    if ANTI_SEED_KEYWORD_AUTOMATON:
        anti_seed_matches = df_combined['cleaned_description'].apply(has_match, automaton=ANTI_SEED_KEYWORD_AUTOMATON)
        df_combined.loc[anti_seed_matches, 'label'] = 0

    df_combined.drop_duplicates(subset=['cleaned_description'], keep='first', inplace=True)
    df_prepared = df_combined.rename(columns={'cleaned_description': 'prepared_description'})

    print("\nFinal label distribution for training data:")
    print(df_prepared['label'].value_counts(normalize=True))

    print("\nℹ️ Fitting a TF-IDF vectorizer (used by Gatekeeper and TF-IDF Expert)...")
    category_vectorizer = TfidfVectorizer(ngram_range=(1, 3), min_df=config.VECTORIZER_MIN_DF, stop_words='english')
    category_vectorizer.fit(df_prepared['prepared_description'])
    joblib.dump(category_vectorizer, config.CATEGORY_VECTORIZER_PATH)
    print(f"✅ Category vectorizer saved to: {config.CATEGORY_VECTORIZER_PATH}")

    nonlab_pattern = '|'.join(config.NONLAB_CATEGORIES)
    df_ut_dallas_lab_only = df_ut_dallas[~df_ut_dallas[config.UT_CAT_COL].str.contains(nonlab_pattern, case=False, na=False)]
    
    prepare_and_save_tfidf_category_vectors(
        df_lab_only=df_ut_dallas_lab_only,
        vectorizer=category_vectorizer,
        output_path=os.path.join(config.OUTPUT_DIR, "category_vectors_tfidf.joblib")
    )

    columns_to_save = ['prepared_description', 'label', config.UT_CAT_COL, config.CLEAN_DESC_COL, config.RAW_DESC_COL, 'data_source']
    df_to_save = df_prepared[[col for col in columns_to_save if col in df_prepared.columns]]
    df_to_save.to_parquet(config.PREPARED_DATA_PATH, index=False)
    print(f"\n✅ Final prepared training data saved to: {config.PREPARED_DATA_PATH}")
    print("--- Step 1: Data Preparation Complete ---")

if __name__ == "__main__":
    main()

