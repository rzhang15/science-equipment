# 6_inspect_category_tokens.py (Final version with zero-score filtering)
"""
Inspects the trained TF-IDF model to identify and list only the tokens
with the highest weights (score > 0) for each product market category.
"""
import pandas as pd
import os
import joblib
import numpy as np
from sklearn.feature_extraction.text import CountVectorizer

import config

def main():
    print("--- Starting Category Token Inspection ---")

    # 1. Load the pre-trained TF-IDF vectorizer
    print(f"ℹ️ Loading TF-IDF vectorizer from: {config.CATEGORY_VECTORIZER_PATH}")
    try:
        tfidf_vectorizer = joblib.load(config.CATEGORY_VECTORIZER_PATH)
    except FileNotFoundError:
        print(f"❌ TF-IDF vectorizer not found. Please run '1_prepare_data.py' first.")
        return

    # 2. Load and merge the UT Dallas data
    print("ℹ️ Loading and merging UT Dallas data...")
    try:
        df_ut = pd.read_csv(config.UT_DALLAS_CLEAN_CSV, low_memory=False)
        df_cat = pd.read_excel(config.UT_DALLAS_CATEGORIES_XLSX)

        for key in config.UT_DALLAS_MERGE_KEYS:
            if key in df_ut.columns and key in df_cat.columns:
                df_ut[key] = df_ut[key].astype(str)
                df_cat[key] = df_cat[key].astype(str)

        df_merged = pd.merge(df_ut, df_cat.drop(columns=['clean_desc'], errors='ignore'), on=config.UT_DALLAS_MERGE_KEYS, how='left')
        df_merged.dropna(subset=[config.CLEAN_DESC_COL, config.UT_CAT_COL], inplace=True)
    except Exception as e:
        print(f"❌ Could not load or merge UT Dallas data: {e}")
        return

    # Save the merged DataFrame to a temporary file for inspection
    temp_dir = os.path.join(config.BASE_DIR, "temp")
    os.makedirs(temp_dir, exist_ok=True)
    temp_file_path = os.path.join(temp_dir, "merged_utdallas_for_inspection.csv")
    df_merged.to_csv(temp_file_path, index=False)
    print(f"✅ Saved merged UT Dallas file for inspection to: {temp_file_path}")

    # 3. Aggregate descriptions by category
    print("ℹ️ Aggregating descriptions by category...")
    category_docs = df_merged.groupby(config.UT_CAT_COL)[config.CLEAN_DESC_COL].apply(' '.join)

    # 4. Apply vectorizers
    print("ℹ️ Calculating TF-IDF scores and frequencies...")
    tfidf_matrix = tfidf_vectorizer.transform(category_docs)
    feature_names = tfidf_vectorizer.get_feature_names_out()
    count_vectorizer = CountVectorizer(vocabulary=feature_names)
    count_matrix = count_vectorizer.transform(category_docs)

    top_n = 10
    print(f"\n--- Top {top_n} (max) Weighted Tokens per Product Market ---")

    # 5. Loop through each category and find the top tokens
    output_path = os.path.join(config.OUTPUT_DIR, "top_category_tokens_with_counts.txt")
    with open(output_path, "w") as f:
        f.write(f"Top {top_n} (max) Weighted Tokens per Product Market (with Frequencies)\n")

        for i, category_name in enumerate(category_docs.index):
            tfidf_scores = tfidf_matrix[i].toarray().flatten()
            count_scores = count_matrix[i].toarray().flatten()

            print(f"\n## Category: {category_name}")
            f.write(f"\n## Category: {category_name}\n")

            if np.sum(tfidf_scores) == 0:
                message = "  - No tokens found in the model's vocabulary for this category."
                print(message)
                f.write(message + "\n")
                continue

            # Get the indices of the top N scores
            top_indices_unsorted = np.argsort(tfidf_scores)[-top_n:]

            # **NEW**: Filter out any indices that correspond to a zero score
            top_indices_filtered = [idx for idx in top_indices_unsorted if tfidf_scores[idx] > 0]

            # Reverse the filtered list to show the highest score first
            top_indices_final = top_indices_filtered[::-1]

            if not top_indices_final:
                 message = "  - All found tokens were stopwords or too infrequent."
                 print(message)
                 f.write(message + "\n")
                 continue

            for j in top_indices_final:
                token = feature_names[j]
                tfidf_score = tfidf_scores[j]
                count = int(count_scores[j])
                line = f"  - {token:<20} (Score: {tfidf_score:.4f}, Frequency: {count})"
                print(line)
                f.write(line + "\n")

    print(f"\n✅ Full report saved to: {output_path}")

if __name__ == "__main__":
    main()
