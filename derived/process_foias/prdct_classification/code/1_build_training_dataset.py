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
from sklearn.feature_selection import chi2
from tqdm import tqdm
import numpy as np
from scipy.sparse import vstack, hstack, csr_matrix, diags

import config
from classifier import (
    load_keywords_and_build_automaton,
    extract_market_keywords_and_build_automaton,
    has_match,
    batch_has_match,
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

def _batched_transform(vectorizer, descriptions, batch_size=5000, desc=""):
    vector_batches = []
    for i in tqdm(range(0, len(descriptions), batch_size), desc=desc):
        vector_batches.append(vectorizer.transform(descriptions.iloc[i:i+batch_size]))
    return vstack(vector_batches)


def prepare_and_save_tfidf_category_vectors(df_lab_only, word_vectorizer,
                                            char_vectorizer, output_path):
    """Build category centroids in the combined, contrastively-weighted space.

    The stacked feature space is [word_tfidf | char_tfidf].  Chi-square against
    the category label gives per-feature contrastive weights (sqrt of chi2,
    normalized to mean 1), which are persisted alongside the vectorizers and
    applied element-wise to both item vectors and centroids.
    """
    print("Preparing and saving TF-IDF category vectors...")
    descriptions = df_lab_only[config.CLEAN_DESC_COL].fillna('').astype(str)
    categories = pd.Categorical(df_lab_only[config.UT_CAT_COL])
    unique_categories = categories.categories

    X_word = _batched_transform(word_vectorizer, descriptions,
                                desc="  - Vectorizing (word)")
    blocks = [X_word]
    if char_vectorizer is not None:
        X_char = _batched_transform(char_vectorizer, descriptions,
                                    desc="  - Vectorizing (char)")
        blocks.append(X_char)
    X_all = hstack(blocks).tocsr() if len(blocks) > 1 else X_word

    feature_weights = None
    if config.USE_CONTRASTIVE_WEIGHTS and len(unique_categories) > 1:
        print(f"  - Computing chi-square feature weights across {len(unique_categories)} categories...")
        chi2_scores, _ = chi2(X_all, categories.codes)
        chi2_scores = np.nan_to_num(chi2_scores, nan=0.0, posinf=0.0, neginf=0.0)
        w = np.sqrt(np.clip(chi2_scores, 0.0, None))
        mean_w = w.mean() if w.size and w.mean() > 0 else 1.0
        feature_weights = w / mean_w
        X_all = X_all @ diags(feature_weights)
        n_word = X_word.shape[1]
        n_char = (X_all.shape[1] - n_word)
        print(f"    Feature weights: word={n_word}, char={n_char}, "
              f"weight mean={feature_weights.mean():.3f}, max={feature_weights.max():.2f}")

    print("  - Calculating mean category vectors...")
    grouping_matrix = csr_matrix(
        (np.ones(len(categories)), (categories.codes, np.arange(len(categories)))),
        shape=(len(unique_categories), len(categories)))
    category_sums = grouping_matrix.dot(X_all)
    category_counts = np.bincount(categories.codes)[:, np.newaxis]
    mean_category_vectors = category_sums / np.maximum(category_counts, 1)
    category_vector_data = {
        'category_names': unique_categories.tolist(),
        'category_vectors': mean_category_vectors,
    }
    joblib.dump(category_vector_data, output_path)
    print(f"TF-IDF category vectors saved to: {output_path}")

    if feature_weights is not None:
        joblib.dump(feature_weights, config.CATEGORY_FEATURE_WEIGHTS_PATH)
        print(f"Feature weights saved to: {config.CATEGORY_FEATURE_WEIGHTS_PATH}")
    elif os.path.exists(config.CATEGORY_FEATURE_WEIGHTS_PATH):
        os.remove(config.CATEGORY_FEATURE_WEIGHTS_PATH)

def main():
    print(f"--- Starting Step 1: Data Preparation [Variant: {config.VARIANT}] ---")
    print("Loading and preparing initial data sources...")
    try:
        df_combined_raw = pd.read_parquet(config.COMBINED_MERGED_CLEAN_PATH)
        df_combined_raw['cleaned_description'] = df_combined_raw[config.CLEAN_DESC_COL].fillna('')
        # data_source keeps the legacy naming used across the rest of the
        # pipeline ('ut_dallas' / 'umich') even though the source column is
        # now `uni` ('utdallas' / 'umich') after the step-0 append.
        df_combined_raw['data_source'] = df_combined_raw['uni'].map(
            {'utdallas': 'ut_dallas', 'umich': 'umich'}
        )
        df_combined_raw['label'] = 1

        df_ut_dallas = df_combined_raw[df_combined_raw['uni'] == 'utdallas'].copy()
        print(f"  - Loaded {len(df_ut_dallas)} rows from UT Dallas")

        labeled_frames = [df_ut_dallas]

        if config.USE_UMICH:
            df_umich = df_combined_raw[df_combined_raw['uni'] == 'umich'].copy()
            labeled_frames.append(df_umich)
            print(f"  - Loaded {len(df_umich)} rows from UMich (variant: {config.VARIANT})")

        df_ca_non_lab = load_ca_data()
        df_fisher_lab = load_fisher_lab_data()
        df_fisher_non_lab = load_fisher_non_lab_data()
    except Exception as e:
        print(f"Error loading data: {e}")
        return

    print("- Combining all data sources...")
    df_combined = pd.concat(labeled_frames + [df_ca_non_lab, df_fisher_lab, df_fisher_non_lab], ignore_index=True)

    # Ensure supplier column exists (some sources may not carry it)
    if config.USE_SUPPLIER:
        if 'supplier' not in df_combined.columns:
            df_combined['supplier'] = ''
        else:
            df_combined['supplier'] = df_combined['supplier'].fillna('')

    # --- Build Aho-Corasick automatons (same matching as classifier.py at inference) ---
    seed_automaton = load_keywords_and_build_automaton(config.SEED_KEYWORD_YAML)
    anti_seed_automaton = load_keywords_and_build_automaton(config.ANTI_SEED_KEYWORD_YAML)
    market_rule_automaton = extract_market_keywords_and_build_automaton(config.MARKET_RULES_YAML)

    print("- Applying keyword-based labeling hierarchy...")
    print("  Order (downgrades win): seed (not CA) -> market (UTD/UMich) -> "
          "anti-seed (all) -> non-lab category (UTD/UMich)")

    # 1. Apply general seed keywords, EXCLUDING ca_non_lab data
    if seed_automaton:
        matches = batch_has_match(df_combined['cleaned_description'], seed_automaton)
        not_ca_non_lab_mask = df_combined['data_source'] != 'ca_non_lab'
        final_mask = matches & not_ca_non_lab_mask
        df_combined.loc[final_mask, 'label'] = 1
        print(f"  - Seed keywords: {final_mask.sum()} items labeled as lab")

    # 2. Apply market rule keywords to labeled data (UT Dallas + UMich if enabled)
    if market_rule_automaton:
        labeled_sources = ['ut_dallas'] + (['umich'] if config.USE_UMICH else [])
        is_labeled_mask = df_combined['data_source'].isin(labeled_sources)
        matches = batch_has_match(
            df_combined.loc[is_labeled_mask, 'cleaned_description'],
            market_rule_automaton,
        )
        matched_indices = matches[matches].index

        if not matched_indices.empty:
            df_combined.loc[matched_indices, 'label'] = 1
            print(f"  - Market rule keywords: {len(matched_indices)} labeled-data items labeled as lab")

    # 3. Apply anti-seed keywords — ALWAYS overrides, even market rule matches
    if anti_seed_automaton:
        matches = batch_has_match(df_combined['cleaned_description'], anti_seed_automaton)
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

    # prepared_description is always the clean text (no supplier token).
    # Supplier weighting is handled in step 1b via separate vectorizers.
    df_combined['prepared_description'] = df_combined['cleaned_description']
    if config.USE_SUPPLIER:
        # Dedupe: normalize_supplier is deterministic and there are typically
        # a few hundred unique suppliers across millions of rows.
        supplier_map = {
            s: config.normalize_supplier(s)
            for s in df_combined['supplier'].unique()
        }
        df_combined['supplier_token'] = df_combined['supplier'].map(supplier_map)
    df_prepared = df_combined.drop(columns=['cleaned_description'])

    # 4. Apply FINAL definitive non-lab category override for labeled data
    #    Uses word-boundary regex from config to avoid substring false matches
    if config.UT_CAT_COL in df_prepared.columns:
        labeled_sources = ['ut_dallas'] + (['umich'] if config.USE_UMICH else [])
        is_labeled = df_prepared['data_source'].isin(labeled_sources)
        is_nonlab_category = df_prepared[config.UT_CAT_COL].astype(str).str.contains(config.NONLAB_REGEX, na=False)
        final_nonlab_mask = is_labeled & is_nonlab_category
        df_prepared.loc[final_nonlab_mask, 'label'] = 0
        print(f"  - Non-lab category override: {final_nonlab_mask.sum()} labeled-data items set to non-lab")

    print("\nFinal label distribution for training data:")
    print(df_prepared['label'].value_counts(normalize=True))

    # Fit category vectorizer on clean descriptions (no supplier token)
    # so category similarity matching stays content-based
    print("\nFitting a TF-IDF category vectorizer...")
    category_stops = list(ENGLISH_STOP_WORDS) + config.DOMAIN_STOP_WORDS + config.CATEGORY_STOP_WORDS
    category_vectorizer = TfidfVectorizer(
        ngram_range=(1, 3),
        min_df=config.CATEGORY_VECTORIZER_MIN_DF,
        stop_words=category_stops,
        sublinear_tf=True,
    )
    # Use clean_desc (without supplier token) for category vectors
    cat_fit_col = config.CLEAN_DESC_COL if config.CLEAN_DESC_COL in df_prepared.columns else 'prepared_description'
    cat_fit_text = df_prepared[cat_fit_col].fillna('')
    category_vectorizer.fit(cat_fit_text)
    joblib.dump(category_vectorizer, config.CATEGORY_VECTORIZER_PATH)
    print(f"Category vectorizer saved to: {config.CATEGORY_VECTORIZER_PATH}")

    # Optional char n-gram vectorizer (catches morphological variants like
    # "rack"/"racks"/"racking" that word-level tokens split apart).
    char_vectorizer = None
    if config.USE_CHAR_NGRAMS:
        print("Fitting a char-level TF-IDF vectorizer...")
        char_vectorizer = TfidfVectorizer(
            analyzer='char_wb',
            ngram_range=config.CHAR_NGRAM_RANGE,
            min_df=config.CHAR_VECTORIZER_MIN_DF,
            sublinear_tf=True,
        )
        char_vectorizer.fit(cat_fit_text)
        joblib.dump(char_vectorizer, config.CATEGORY_CHAR_VECTORIZER_PATH)
        print(f"  Char vectorizer saved ({len(char_vectorizer.vocabulary_)} features).")
    elif os.path.exists(config.CATEGORY_CHAR_VECTORIZER_PATH):
        os.remove(config.CATEGORY_CHAR_VECTORIZER_PATH)

    # Filter labeled data to lab-only categories for category vectors
    lab_frames = []
    is_nonlab_ut = df_ut_dallas[config.UT_CAT_COL].astype(str).str.contains(config.NONLAB_REGEX, na=False)
    lab_frames.append(df_ut_dallas[~is_nonlab_ut])
    if config.USE_UMICH:
        is_nonlab_um = df_umich[config.UT_CAT_COL].astype(str).str.contains(config.NONLAB_REGEX, na=False)
        lab_frames.append(df_umich[~is_nonlab_um])
    df_lab_only = pd.concat(lab_frames, ignore_index=True)

    prepare_and_save_tfidf_category_vectors(
        df_lab_only=df_lab_only,
        word_vectorizer=category_vectorizer,
        char_vectorizer=char_vectorizer,
        output_path=os.path.join(config.OUTPUT_DIR, "category_vectors_tfidf.joblib")
    )

    columns_to_save = ['prepared_description', 'label', config.UT_CAT_COL, config.CLEAN_DESC_COL, config.RAW_DESC_COL, 'data_source']
    if config.USE_SUPPLIER:
        columns_to_save.extend(['supplier', 'supplier_token'])
    df_to_save = df_prepared[[col for col in columns_to_save if col in df_prepared.columns]]

    df_to_save.to_parquet(config.PREPARED_DATA_PATH, index=False)
    print(f"\nFinal prepared training data saved to: {config.PREPARED_DATA_PATH}")

    # Under baseline, UMich is never in training.  Produce a labeled UMich
    # dataset (using the same keyword hierarchy as training) so script 2 can
    # evaluate the baseline model on the full, out-of-sample UMich corpus.
    if not config.USE_UMICH and os.path.exists(config.COMBINED_MERGED_CLEAN_PATH):
        build_umich_eval_dataset(seed_automaton, anti_seed_automaton, market_rule_automaton)

    print("--- Step 1: Data Preparation Complete ---")


def build_umich_eval_dataset(seed_automaton, anti_seed_automaton, market_rule_automaton):
    """Label the UMich corpus with the same keyword hierarchy used for training
    and save it to config.UMICH_EVAL_DATA_PATH.  Only called under baseline.
    """
    print("\n--- Building UMich evaluation dataset (baseline out-of-sample) ---")
    df = pd.read_parquet(config.COMBINED_MERGED_CLEAN_PATH)
    df = df[df['uni'] == 'umich'].copy()
    df['cleaned_description'] = df[config.CLEAN_DESC_COL].fillna('')
    df['data_source'] = 'umich'
    df['label'] = 1  # labeled source default (same as training)

    if seed_automaton:
        m = batch_has_match(df['cleaned_description'], seed_automaton)
        df.loc[m, 'label'] = 1
    if market_rule_automaton:
        m = batch_has_match(df['cleaned_description'], market_rule_automaton)
        df.loc[m, 'label'] = 1
    if anti_seed_automaton:
        m = batch_has_match(df['cleaned_description'], anti_seed_automaton)
        df.loc[m, 'label'] = 0

    n_before = len(df)
    df.drop_duplicates(subset=['cleaned_description'], keep='first', inplace=True)
    print(f"  - Dropped {n_before - len(df)} duplicate descriptions, {len(df)} remaining")

    if config.UT_CAT_COL in df.columns:
        is_nonlab_cat = df[config.UT_CAT_COL].astype(str).str.contains(config.NONLAB_REGEX, na=False)
        df.loc[is_nonlab_cat, 'label'] = 0
        print(f"  - Non-lab category override: {int(is_nonlab_cat.sum())} rows set to non-lab")

    df['prepared_description'] = df['cleaned_description']
    if 'supplier' in df.columns:
        df['supplier'] = df['supplier'].fillna('')

    keep_cols = ['prepared_description', 'label', config.UT_CAT_COL,
                 config.CLEAN_DESC_COL, config.RAW_DESC_COL, 'data_source', 'supplier']
    df_out = df[[c for c in keep_cols if c in df.columns]]
    df_out.to_parquet(config.UMICH_EVAL_DATA_PATH, index=False)
    print(f"  - Label distribution: {df_out['label'].value_counts(normalize=True).to_dict()}")
    print(f"  - UMich eval data saved to: {config.UMICH_EVAL_DATA_PATH}")


if __name__ == "__main__":
    main()
