#!/usr/bin/env python
"""model_builder.py — end-to-end classification toolkit (v17.1)
================================================================
* **Enhanced TF-IDF**: Improved preprocessing and vectorization.
* **Refactored**: For robust cross-validation and efficiency.
"""
from __future__ import annotations
__all__ = ["fit_reference_model", "classify_items", "train_model_from_df"]

import re
import numpy as np
import pandas as pd
from pathlib import Path
from typing import Dict, List, Tuple

import spacy
from nltk.stem import WordNetLemmatizer
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
from rapidfuzz.fuzz import partial_ratio, token_set_ratio

# --- NLP and Lemmatization Setup ---
# Consider POS tagging for more accurate lemmatization
try:
    nlp = spacy.load("en_core_web_sm", disable=["parser", "ner"])
except OSError:
    import spacy.cli
    spacy.cli.download("en_core_web_sm")
    nlp = spacy.load("en_core_web_sm", disable=["parser", "ner"])

# --- Constants and Keyword Maps ---
KEYWORD_CATEGORY_MAP = {"mab":"monoclonal antibody","plt":"plate","btl":"bottle","fltr":"filter","taq":"taq polymerase","dynabead":"polymer-based magnetic beads","dynabeads":"polymer-based magnetic beads"}
TRIGGER_TO_TARGET_KEYWORD_MAP = {"dmem":"media","mem":"media","rpmi":"media","elisa":"assay","plate":"plate","dish":"dish","tube":"tube","flask":"flask","polymerase":"polymerase","funnel":"funnel","shipping":"shipping"}
TARGETED_MATCH_THRESHOLD = 95
BUNDLE_CATEGORY = "bundle of products"
BUNDLE_MIN_SCORE = 0.30
BUNDLE_CONFUSION_DELTA = 0.05

def _build_vec(texts: list[str]):
    """
    Build a TF-IDF vectorizer and transform the texts.
    - Increased n-gram range to capture more specific phrases.
    - Adjusted min_df to handle less frequent but potentially important terms.
    - Added max_df to filter out overly common terms that might not be discriminative.
    """
    vec = TfidfVectorizer(
        ngram_range=(1, 4),  # Increased to (1, 4) to capture longer phrases
        sublinear_tf=True,
        min_df=3,            # Adjusted from 5 to 3
        max_df=0.9,          # Added to remove terms that appear in > 90% of documents
        stop_words='english' # Added to remove common English stop words
    )
    return vec, vec.fit_transform(texts)

def train_model_from_df(df: pd.DataFrame) -> Dict:
    """
    Trains a reference model directly from a DataFrame.
    The DataFrame must contain 'category' and 'clean_desc' columns.
    """
    lemmatizer = WordNetLemmatizer()
    df.loc[:, "category"] = df["category"].apply(lambda s: " ".join(lemmatizer.lemmatize(w) for w in str(s).split()))

    safe_join = lambda s: " ".join(s.dropna().astype(str))
    agg = df.groupby("category").agg(clean_desc=("clean_desc", safe_join)).reset_index()

    vec, x_matrix = _build_vec(agg["clean_desc"].tolist())
    categories = agg["category"].values

    category_vectorizer = TfidfVectorizer()
    category_vectorizer.fit(categories)
    word_idf_map = dict(zip(category_vectorizer.get_feature_names_out(), category_vectorizer.idf_))

    category_word_sets = [set(cat.split()) for cat in categories]

    return {
        "vectorizer": vec,
        "matrix": x_matrix,
        "categories": categories,
        "word_idf_map": word_idf_map,
        "category_word_sets": category_word_sets
    }


def fit_reference_model(clean_csv: Path, gt_path: Path) -> Dict:
    """
    Loads data from files, merges them, and trains the reference model.
    """
    cleaned_df = pd.read_csv(clean_csv)
    gt_df = pd.read_excel(gt_path)

    for c in ("supplier_id", "sku"):
        if c in cleaned_df.columns: cleaned_df[c] = cleaned_df[c].astype(str).str.strip()
        if c in gt_df.columns: gt_df[c] = gt_df[c].astype(str).str.strip()

    merged = cleaned_df.merge(gt_df, on=["supplier_id", "sku"], how="inner", suffixes=('', '_gt'))
    merged = merged[merged["category"].notna() & (merged["category"] != "")]
    if merged.empty: raise ValueError("No ground truth rows matched after merge.")

    return train_model_from_df(merged)


def classify_items(df: pd.DataFrame, ref_model: Dict, target_lookup: Dict[str, List[Tuple[str, str]]]) -> pd.DataFrame:
    if df.empty:
        df["predicted_category"], df["classification_stage"] = None, None
        return df

    word_idf_map, cats, category_word_sets = ref_model["word_idf_map"], ref_model["categories"], ref_model["category_word_sets"]
    if "clean_desc" not in df.columns: raise ValueError("Input DataFrame must contain 'clean_desc' column.")

    input_text = df["clean_desc"].fillna("").astype(str)
    # Using spaCy for lemmatization which is generally more accurate than WordNetLemmatizer alone
    docs = nlp.pipe(input_text, batch_size=50)
    lemmatized_text = [" ".join([token.lemma_ for token in doc]) for doc in docs]

    x_new = ref_model["vectorizer"].transform(lemmatized_text)
    sim_matrix = cosine_similarity(x_new, ref_model["matrix"])

    df_results = df.copy()
    df_results["tfidf_score"] = np.max(sim_matrix, axis=1)
    df_results["tfidf_cat"] = cats[np.argmax(sim_matrix, axis=1)]

    preds, stages = [], []
    WEIGHTED_MATCH_THRESHOLD, TFIDF_THRESHOLD, FUZZY_THRESHOLD = 2.5, 0.30, 95

    for row in df_results.itertuples():
        pred, stage = None, None
        clean_desc_str = str(row.clean_desc) if pd.notna(row.clean_desc) else ""

        best_match_cat, max_score = None, 0
        if clean_desc_str:
            desc_words = set(clean_desc_str.split())
            for i, cat_words in enumerate(category_word_sets):
                overlap = desc_words.intersection(cat_words)
                if overlap:
                    score = sum(word_idf_map.get(word, 0) for word in overlap)
                    if score > max_score: max_score, best_match_cat = score, cats[i]
        if max_score > WEIGHTED_MATCH_THRESHOLD:
            pred, stage = best_match_cat, "Weighted Word Match"

        if not pred and row.tfidf_score >= TFIDF_THRESHOLD: pred, stage = row.tfidf_cat, "TF-IDF"

        if not pred:
            for kw, cat in KEYWORD_CATEGORY_MAP.items():
                if re.search(rf"\b{re.escape(kw)}\b", clean_desc_str, re.IGNORECASE): pred, stage = cat, "Keyword Fallback"; break

        if not pred:
            for trg, tgt in TRIGGER_TO_TARGET_KEYWORD_MAP.items():
                if re.search(rf"\b{re.escape(trg)}\b", clean_desc_str, re.IGNORECASE):
                    candidate_items = target_lookup.get(tgt, [])
                    if candidate_items:
                        best_score, best_cat = 0, None
                        for desc, cat in candidate_items:
                            score = token_set_ratio(clean_desc_str, desc)
                            if score > best_score: best_score, best_cat = score, cat
                        if best_score >= TARGETED_MATCH_THRESHOLD: pred, stage = best_cat, f"Targeted Fallback {trg}->{tgt}"
                    break

        if not pred:
            best_score, best_cat = 0, None
            for cat in cats:
                score = partial_ratio(cat, clean_desc_str)
                if score > best_score: best_score, best_cat = score, cat
            if best_score >= FUZZY_THRESHOLD: pred, stage = best_cat, "Fuzzy Fallback"

        preds.append(pred or "no match")
        stages.append(stage or "No Match")

    df_results["predicted_category"], df_results["classification_stage"] = preds, stages

    if BUNDLE_CATEGORY in cats:
        top2 = np.argsort(sim_matrix, axis=1)[:, -2:]
        top_scores = np.take_along_axis(sim_matrix, top2[:, [1]], 1).ravel()
        second_scores = np.take_along_axis(sim_matrix, top2[:, [0]], 1).ravel()
        mask = (top_scores > BUNDLE_MIN_SCORE) & ((top_scores - second_scores) < BUNDLE_CONFUSION_DELTA)
        df_results.loc[mask, ["predicted_category", "classification_stage"]] = [BUNDLE_CATEGORY, "Bundle"]

    return df_results
# Add this entire block to the end of your 1_tfidf.py script
import glob
from pathlib import Path
import os

if __name__ == "__main__":
    # --- 1. DEFINE FILE PATHS ---
    ground_truth_data_path = Path("../external/samp/utdallas_2011_2024_standardized_clean.csv")
    category_data_path = Path("../external/combined/combined_nochem.xlsx")
    classification_files_dir = Path("../external/samp/")

    # New output directory
    output_dir = Path("../output/")
    # Create the output directory if it doesn't exist
    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        # --- 2. PREPARE AND TRAIN THE MODEL ---
        print("➡️ Loading and merging training data...")

        # Load the two data sources
        desc_df = pd.read_csv(ground_truth_data_path)
        category_df = pd.read_excel(category_data_path)

        # Prepare for the merge by ensuring keys are matching string types
        for col in ["supplier_id", "sku"]:
            desc_df[col] = desc_df[col].astype(str).str.strip()
            category_df[col] = category_df[col].astype(str).str.strip()

        # Merge the two dataframes to link descriptions with categories
        training_df = pd.merge(
            desc_df,
            category_df[['supplier_id', 'sku', 'category']],
            on=["supplier_id", "sku"],
            how="inner"
        )

        # Clean up the training data
        training_df = training_df.dropna(subset=['category', 'clean_desc'])
        training_df = training_df[training_df['category'] != '']

        if training_df.empty:
            raise ValueError("Merge failed to produce data. Check 'supplier_id' and 'sku' columns in your files.")

        print("✅ Training data prepared successfully.")
        print("🤖 Training reference model...")

        # Train the model directly from the newly created DataFrame
        reference_model = train_model_from_df(training_df)
        print("✅ Model training complete.")

        # --- 3. FIND AND CLASSIFY ALL .CSV FILES IN THE DIRECTORY ---
        csv_files_to_process = list(classification_files_dir.glob("*.csv"))

        if not csv_files_to_process:
             print(f"\n⚠️ WARNING: No .csv files found in {classification_files_dir}")

        target_lookup_data = {}

        for file_path in csv_files_to_process:
            print(f"\n\n--- 🚀 Processing file: {file_path.name} ---")
            items_to_classify_df = pd.read_csv(file_path)

            if 'clean_desc' not in items_to_classify_df.columns:
                print(f"⚠️ SKIPPING: File {file_path.name} is missing the required 'clean_desc' column.")
                continue

            # Classify the items
            results_df = classify_items(
                df=items_to_classify_df,
                ref_model=reference_model,
                target_lookup=target_lookup_data
            )

            # --- 4. CALCULATE AND PRINT SUMMARY STATISTICS ---
            total_rows = len(results_df)
            if total_rows > 0:
                # Calculate "no match" percentage
                no_match_count = (results_df['predicted_category'] == 'no match').sum()
                no_match_percent = (no_match_count / total_rows) * 100

                # Calculate top 5 categories by percentage
                top_5_cats = (results_df['predicted_category'].value_counts(normalize=True) * 100).nlargest(5)

                # Calculate average TF-IDF score
                avg_tfidf_score = results_df['tfidf_score'].mean()

                print("\n📊 Summary Statistics:")
                print(f"  - No Match: {no_match_percent:.2f}%")
                print(f"  - Avg. TF-IDF Score: {avg_tfidf_score:.4f}")
                print("  - Top 5 Categories:")
                for cat, perc in top_5_cats.items():
                    print(f"    - {cat}: {perc:.2f}%")

            # --- 5. SAVE THE OUTPUT FILE ---
            # Save the full results to the new output directory
            output_path = output_dir / f"classified_{file_path.name}"
            results_df.to_csv(output_path, index=False)
            print(f"\n✅ Results for {file_path.name} saved to: {output_path}")

    except FileNotFoundError as e:
        print(f"\n❌ ERROR: File not found -> {e.filename}")
        print("Please ensure all file paths at the top of the script are correct.")
    except Exception as e:
        print(f"\n❌ An error occurred: {e}")
