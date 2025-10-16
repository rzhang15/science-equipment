# 1_build_training_dataset.py
"""
Loads the pre-cleaned UT Dallas data, combines it with other sources,
and creates the final unified training set with a sophisticated labeling hierarchy.
"""
import pandas as pd
import os
import joblib
from sklearn.feature_extraction.text import TfidfVectorizer
import yaml
import re
import ahocorasick
from tqdm import tqdm
import numpy as np
from scipy.sparse import vstack, csr_matrix

import config

def extract_keywords_from_market_rules(rules_filepath):
    """
    Parses the market_rules.yml file to extract all keywords that define a lab item.
    """
    keywords = set()
    try:
        with open(rules_filepath, 'r') as f:
            rules = yaml.safe_load(f)

        aliases = {f"${k}": v for k, v in rules.get('keyword_groups', {}).items()}
        market_rules = rules.get('market_rules', [])

        for rule in market_rules:
            for key in ['all_of', 'any_of']:
                if key in rule:
                    for keyword in rule[key]:
                        if keyword in aliases:
                            expanded = aliases[keyword]
                            cleaned_expanded = [re.sub(r'[\*]', '', kw) for kw in expanded]
                            keywords.update(cleaned_expanded)
                        else:
                            cleaned_keyword = re.sub(r'[\*]', '', keyword)
                            keywords.add(cleaned_keyword)
        return list(keywords)
    except Exception as e:
        print(f"❌ Error extracting market rule keywords: {e}")
        return []

def has_exact_word_match(description, keyword_regex):
    """Checks for an exact, whole-word keyword match."""
    if not isinstance(description, str) or not keyword_regex:
        return False
    return bool(keyword_regex.search(description))

def load_keywords_and_build_regex(filepath):
    """Loads keywords from a YAML file and compiles a single regex for exact word matching."""
    try:
        with open(filepath, 'r') as f:
            yaml_content = yaml.safe_load(f)
            keywords = yaml_content.get('keywords', []) if yaml_content else []

            if not keywords:
                return None
            
            pattern = r'\b(' + '|'.join(re.escape(kw) for kw in keywords) + r')\b'
            return re.compile(pattern, re.IGNORECASE)
            
    except FileNotFoundError:
        print(f"⚠️ Keyword file not found: {filepath}")
        return None

def load_ca_data():
    df = pd.read_csv(config.CA_NON_LAB_DTA)
    df['cleaned_description'] = df[config.CA_DESC_COL].fillna('')
    df['label'] = 0
    df['data_source'] = 'ca_non_lab'
    return df

def load_fisher_lab_data():
    df = pd.read_csv(config.FISHER_LAB)
    df['cleaned_description'] = df[config.FISHER_DESC_COL].fillna('')
    df['label'] = 1
    df['data_source'] = 'fisher_lab'
    return df

def load_fisher_non_lab_data():
    df = pd.read_csv(config.FISHER_NONLAB)
    df['cleaned_description'] = df[config.FISHER_DESC_COL].fillna('')
    df['label'] = 0
    df['data_source'] = 'fisher_non_lab'
    return df

def prepare_and_save_tfidf_category_vectors(df_lab_only, vectorizer, output_path):
    print("ℹ️ Preparing and saving TF-IDF category vectors...")
    descriptions = df_lab_only[config.CLEAN_DESC_COL]
    categories = pd.Categorical(df_lab_only[config.UT_CAT_COL])
    unique_categories = categories.categories
    batch_size=5000
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
    print(f"✅ TF-IDF category vectors saved to: {output_path}")

def main():
    print("--- Starting Step 1: Data Preparation ---")
    print("ℹ️ Loading and preparing initial data sources...")
    try:
        df_ut_dallas = pd.read_parquet(config.UT_DALLAS_MERGED_CLEAN_PATH)
        df_ut_dallas['cleaned_description'] = df_ut_dallas[config.CLEAN_DESC_COL].fillna('')
        df_ut_dallas['data_source'] = 'ut_dallas'
        df_ut_dallas['label'] = 1
        
        df_ca_non_lab = load_ca_data()
        df_fisher_lab = load_fisher_lab_data()
        df_fisher_non_lab = load_fisher_non_lab_data()
    except Exception as e:
        print(f"❌ Error loading data: {e}")
        return

    print("- Combining all data sources...")
    df_combined = pd.concat([df_ut_dallas, df_ca_non_lab, df_fisher_lab, df_fisher_non_lab], ignore_index=True)
    df_combined['is_market_rule_match'] = False # Flag to protect market rule matches

    print("- Applying keyword-based labeling hierarchy...")
    # 1. Apply general seed keywords, EXCLUDING ca_non_lab data
    SEED_KEYWORD_REGEX = load_keywords_and_build_regex(config.SEED_KEYWORD_YAML)
    if SEED_KEYWORD_REGEX:
        matches = df_combined['cleaned_description'].apply(has_exact_word_match, keyword_regex=SEED_KEYWORD_REGEX)
        not_ca_non_lab_mask = df_combined['data_source'] != 'ca_non_lab'
        final_mask = matches & not_ca_non_lab_mask
        df_combined.loc[final_mask, 'label'] = 1

    # 2. Apply market rule keywords ONLY to UT Dallas data
    market_rule_keywords = extract_keywords_from_market_rules(config.MARKET_RULES_YAML)
    if market_rule_keywords:
        market_rule_pattern = r'\b(' + '|'.join(re.escape(kw) for kw in market_rule_keywords) + r')\b'
        market_rule_regex = re.compile(market_rule_pattern, re.IGNORECASE)
        
        is_ut_dallas_mask = df_combined['data_source'] == 'ut_dallas'
        matches = df_combined.loc[is_ut_dallas_mask, 'cleaned_description'].apply(has_exact_word_match, keyword_regex=market_rule_regex)
        matched_indices = matches[matches].index
        
        if not matched_indices.empty:
            df_combined.loc[matched_indices, 'label'] = 1
            df_combined.loc[matched_indices, 'is_market_rule_match'] = True # Set the protection flag

    # 3. Apply general anti-seed keywords, IGNORING protected market rule matches
    ANTI_SEED_KEYWORD_REGEX = load_keywords_and_build_regex(config.ANTI_SEED_KEYWORD_YAML)
    if ANTI_SEED_KEYWORD_REGEX:
        matches = df_combined['cleaned_description'].apply(has_exact_word_match, keyword_regex=ANTI_SEED_KEYWORD_REGEX)
        is_not_protected_mask = df_combined['is_market_rule_match'] == False
        final_mask = matches & is_not_protected_mask
        df_combined.loc[final_mask, 'label'] = 0

    df_combined.drop_duplicates(subset=['cleaned_description'], keep='first', inplace=True)
    df_prepared = df_combined.rename(columns={'cleaned_description': 'prepared_description'})
    
    # 4. Apply FINAL definitive non-lab category override for UT Dallas data
    if config.NONLAB_CATEGORIES:
        non_lab_cat_automaton = ahocorasick.Automaton()
        for idx, keyword in enumerate(config.NONLAB_CATEGORIES):
            non_lab_cat_automaton.add_word(str(keyword).lower(), (idx, str(keyword).lower()))
        non_lab_cat_automaton.make_automaton()

        def has_substring_match(description, automaton):
            if not isinstance(description, str) or automaton is None: return False
            try:
                next(automaton.iter(description.lower())); return True
            except StopIteration: return False
        
        if config.UT_CAT_COL in df_prepared.columns:
            is_ut_dallas = df_prepared['data_source'] == 'ut_dallas'
            is_nonlab_category = df_prepared[config.UT_CAT_COL].astype(str).str.lower().apply(has_substring_match, automaton=non_lab_cat_automaton)
            final_nonlab_mask = is_ut_dallas & is_nonlab_category
            df_prepared.loc[final_nonlab_mask, 'label'] = 0

    print("\nFinal label distribution for training data:")
    print(df_prepared['label'].value_counts(normalize=True))

    print("\nℹ️ Fitting a TF-IDF vectorizer...")
    category_vectorizer = TfidfVectorizer(ngram_range=(1, 3), min_df=config.VECTORIZER_MIN_DF, stop_words='english')
    category_vectorizer.fit(df_prepared['prepared_description'])
    joblib.dump(category_vectorizer, config.CATEGORY_VECTORIZER_PATH)
    print(f"✅ Category vectorizer saved to: {config.CATEGORY_VECTORIZER_PATH}")

    nonlab_pattern = '|'.join(config.NONLAB_CATEGORIES)
    df_ut_dallas_lab_only = df_ut_dallas[~df_ut_dallas[config.UT_CAT_COL].astype(str).str.contains(nonlab_pattern, case=False, na=False)]
    
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