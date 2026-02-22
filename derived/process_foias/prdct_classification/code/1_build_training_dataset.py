# 1_build_training_dataset.py
"""
Loads the pre-cleaned UT Dallas data, combines it with other sources,
and creates the final unified training set with a sophisticated labeling hierarchy.

Uses Aho-Corasick substring matching for all keyword labeling -- the same method
used by the HybridClassifier at inference time (classifier.py).
"""
import pandas as pd
import os
import joblib
from sklearn.feature_extraction.text import TfidfVectorizer, ENGLISH_STOP_WORDS
from tqdm import tqdm
import numpy as np
from scipy.sparse import vstack, csr_matrix

import config
from classifier import (
    load_keywords_and_build_automaton,
    extract_market_keywords_and_build_automaton,
    has_match,
)

def load_ca_data():
    df = pd.read_csv(config.CA_NON_LAB_DTA)
    df['cleaned_description'] = df[config.CLEAN_DESC_COL].fillna('')
    df['label'] = 0
    df['data_source'] = 'ca_non_lab'
    return df

def load_fisher_lab_data():
    df = pd.read_csv(config.FISHER_LAB)
    df['cleaned_description'] = df[config.CLEAN_DESC_COL].fillna('')
    df['label'] = 1
    df['data_source'] = 'fisher_lab'
    return df

def load_fisher_non_lab_data():
    df = pd.read_csv(config.FISHER_NONLAB)
    df['cleaned_description'] = df[config.CLEAN_DESC_COL].fillna('')
    df['label'] = 0
    df['data_source'] = 'fisher_non_lab'
    return df

def prepare_and_save_tfidf_category_vectors(df_lab_only, vectorizer, output_path):
    print("Preparing and saving TF-IDF category vectors...")
    descriptions = df_lab_only[config.CLEAN_DESC_COL]
    categories = pd.Categorical(df_lab_only[config.UT_CAT_COL])
    unique_categories = categories.categories
    batch_size = 5000
    vector_batches = []
    for i in tqdm(range(0, len(descriptions), batch_size), desc="  - Vectorizing descriptions"):
        batch = descriptions.iloc[i:i+batch_size]
        vector_batches.append(vectorizer.transform(batch))
    all_vectors = vstack(vector_batches)
    print("  - Calculating mean category vectors...")
    grouping_matrix = csr_matrix((np.ones(len(categories)), (categories.codes, np.arange(len(categories)))), shape=(len(unique_categories), len(categories)))
    category_sums = grouping_matrix.dot(all_vectors)
    category_counts = np.bincount(categories.codes)[:, np.newaxis]
    mean_category_vectors = category_sums / np.maximum(category_counts, 1)
    category_vector_data = {'category_names': unique_categories.tolist(), 'category_vectors': mean_category_vectors}
    joblib.dump(category_vector_data, output_path)
    print(f"TF-IDF category vectors saved to: {output_path}")

def main():
    print("--- Starting Step 1: Data Preparation ---")
    print("Loading and preparing initial data sources...")
    try:
        df_ut_dallas = pd.read_parquet(config.UT_DALLAS_MERGED_CLEAN_PATH)
        df_ut_dallas['cleaned_description'] = df_ut_dallas[config.CLEAN_DESC_COL].fillna('')
        df_ut_dallas['data_source'] = 'ut_dallas'
        df_ut_dallas['label'] = 1

        df_ca_non_lab = load_ca_data()
        df_fisher_lab = load_fisher_lab_data()
        df_fisher_non_lab = load_fisher_non_lab_data()
    except Exception as e:
        print(f"Error loading data: {e}")
        return

    print("- Combining all data sources...")
    df_combined = pd.concat([df_ut_dallas, df_ca_non_lab, df_fisher_lab, df_fisher_non_lab], ignore_index=True)

    # --- Build Aho-Corasick automatons (same matching as classifier.py at inference) ---
    seed_automaton = load_keywords_and_build_automaton(config.SEED_KEYWORD_YAML)
    anti_seed_automaton = load_keywords_and_build_automaton(config.ANTI_SEED_KEYWORD_YAML)
    market_rule_automaton = extract_market_keywords_and_build_automaton(config.MARKET_RULES_YAML)

    print("- Applying keyword-based labeling hierarchy (Aho-Corasick matching)...")
    print("  Priority: anti-seed > market rules > seed > default")

    # 1. Apply general seed keywords, EXCLUDING ca_non_lab data
    if seed_automaton:
        matches = df_combined['cleaned_description'].apply(has_match, automaton=seed_automaton)
        not_ca_non_lab_mask = df_combined['data_source'] != 'ca_non_lab'
        final_mask = matches & not_ca_non_lab_mask
        df_combined.loc[final_mask, 'label'] = 1
        print(f"  - Seed keywords: {final_mask.sum()} items labeled as lab")

    # 2. Apply market rule keywords ONLY to UT Dallas data
    if market_rule_automaton:
        is_ut_dallas_mask = df_combined['data_source'] == 'ut_dallas'
        matches = df_combined.loc[is_ut_dallas_mask, 'cleaned_description'].apply(has_match, automaton=market_rule_automaton)
        matched_indices = matches[matches].index

        if not matched_indices.empty:
            df_combined.loc[matched_indices, 'label'] = 1
            print(f"  - Market rule keywords: {len(matched_indices)} UT Dallas items labeled as lab")

    # 3. Apply anti-seed keywords — ALWAYS overrides, even market rule matches
    if anti_seed_automaton:
        matches = df_combined['cleaned_description'].apply(has_match, automaton=anti_seed_automaton)
        df_combined.loc[matches, 'label'] = 0
        print(f"  - Anti-seed keywords: {matches.sum()} items labeled as non-lab (overrides all)")

    # --- Deduplication with logging ---
    n_before = len(df_combined)
    dupes = df_combined[df_combined.duplicated(subset=['cleaned_description'], keep=False)]
    if len(dupes) > 0:
        dupe_groups = dupes.groupby('cleaned_description')
        conflicting = dupe_groups.filter(lambda g: g['label'].nunique() > 1)
        n_conflicting = conflicting['cleaned_description'].nunique()
        print(f"\n  - Deduplication: {dupes['cleaned_description'].nunique()} duplicate descriptions found")
        if n_conflicting > 0:
            print(f"  - WARNING: {n_conflicting} descriptions have conflicting labels across sources (keeping first occurrence)")

    df_combined.drop_duplicates(subset=['cleaned_description'], keep='first', inplace=True)
    print(f"  - Dropped {n_before - len(df_combined)} duplicate rows, {len(df_combined)} remaining")

    df_prepared = df_combined.rename(columns={'cleaned_description': 'prepared_description'})

    # 4. Apply FINAL definitive non-lab category override for UT Dallas data
    #    Uses word-boundary regex from config to avoid substring false matches
    if config.UT_CAT_COL in df_prepared.columns:
        is_ut_dallas = df_prepared['data_source'] == 'ut_dallas'
        is_nonlab_category = df_prepared[config.UT_CAT_COL].astype(str).str.contains(config.NONLAB_REGEX, na=False)
        final_nonlab_mask = is_ut_dallas & is_nonlab_category
        df_prepared.loc[final_nonlab_mask, 'label'] = 0
        print(f"  - Non-lab category override: {final_nonlab_mask.sum()} UT Dallas items set to non-lab")

    print("\nFinal label distribution for training data:")
    print(df_prepared['label'].value_counts(normalize=True))

    print("\nFitting a TF-IDF vectorizer...")
    category_stops = list(ENGLISH_STOP_WORDS) + config.DOMAIN_STOP_WORDS + config.CATEGORY_STOP_WORDS
    category_vectorizer = TfidfVectorizer(
        ngram_range=(1, 3),
        min_df=config.CATEGORY_VECTORIZER_MIN_DF,
        stop_words=category_stops,
        sublinear_tf=True,
    )
    category_vectorizer.fit(df_prepared['prepared_description'])
    joblib.dump(category_vectorizer, config.CATEGORY_VECTORIZER_PATH)
    print(f"Category vectorizer saved to: {config.CATEGORY_VECTORIZER_PATH}")

    # Filter UT Dallas to lab-only categories using word-boundary matching
    is_nonlab = df_ut_dallas[config.UT_CAT_COL].astype(str).str.contains(config.NONLAB_REGEX, na=False)
    df_ut_dallas_lab_only = df_ut_dallas[~is_nonlab]

    prepare_and_save_tfidf_category_vectors(
        df_lab_only=df_ut_dallas_lab_only,
        vectorizer=category_vectorizer,
        output_path=os.path.join(config.OUTPUT_DIR, "category_vectors_tfidf.joblib")
    )

    columns_to_save = ['prepared_description', 'label', config.UT_CAT_COL, config.CLEAN_DESC_COL, config.RAW_DESC_COL, 'data_source']
    df_to_save = df_prepared[[col for col in columns_to_save if col in df_prepared.columns]]

    df_to_save.to_parquet(config.PREPARED_DATA_PATH, index=False)
    print(f"\nFinal prepared training data saved to: {config.PREPARED_DATA_PATH}")
    print("--- Step 1: Data Preparation Complete ---")

if __name__ == "__main__":
    main()
