"""
Generates and saves multiple sets of embeddings from the prepared text data.
Each function creates a file of vectors for a specific model (TF-IDF, BERT, etc.).
Also saves the initialized BERT model for later reuse.
"""
import pandas as pd
import joblib
import os
from sklearn.feature_extraction.text import TfidfVectorizer, ENGLISH_STOP_WORDS
from sentence_transformers import SentenceTransformer

import config

def generate_tfidf_vectors(df):
    print("--- Generating TF-IDF Vectors for Gatekeeper ---")
    # Data is already cleaned upstream by clean_foia_data.py -- no need for
    # additional clean_for_model preprocessing on TF-IDF (the remaining
    # alphanumeric tokens and dimensions carry lab-vs-non-lab signal).
    model_text = df['prepared_description'].fillna('')
    # Combined stop words: sklearn English defaults + domain-specific (A)
    custom_stops = list(ENGLISH_STOP_WORDS) + config.DOMAIN_STOP_WORDS
    gatekeeper_vectorizer = TfidfVectorizer(
        ngram_range=(1, 3),
        min_df=config.GATEKEEPER_VECTORIZER_MIN_DF,
        stop_words=custom_stops,                            # (A) domain stop words
        sublinear_tf=True,                                  # (D) dampen repeated terms
    )
    tfidf_vectors = gatekeeper_vectorizer.fit_transform(model_text)
    joblib.dump(tfidf_vectors, os.path.join(config.OUTPUT_DIR, "embeddings_tfidf.joblib"))
    joblib.dump(gatekeeper_vectorizer, os.path.join(config.OUTPUT_DIR, "vectorizer_tfidf.joblib"))
    print("  TF-IDF vectors and gatekeeper vectorizer saved.")


def generate_transformer_vectors(df, model_name, output_filename):
    print(f"\n--- Generating Vectors for: {model_name} ---")
    model = SentenceTransformer(model_name)

    vectors = model.encode(df['prepared_description'].fillna('').tolist(), show_progress_bar=True)
    joblib.dump(vectors, os.path.join(config.OUTPUT_DIR, output_filename))
    print(f"  {model_name} vectors saved to {output_filename}")

    model_object_path = os.path.join(config.OUTPUT_DIR, f"model_object_{model_name.split('/')[-1]}.joblib")
    joblib.dump(model, model_object_path)
    print(f"  Saved reusable {model_name} model object to {model_object_path}")


def main():
    print("--- Starting Step 1b: Embedding Generation ---")
    try:
        df = pd.read_parquet(config.PREPARED_DATA_PATH)
    except FileNotFoundError:
        print(f"ERROR: Prepared data not found at '{config.PREPARED_DATA_PATH}'.")
        print("   Please run 1_build_training_dataset.py first.")
        return

    generate_tfidf_vectors(df)
    generate_transformer_vectors(df, model_name='all-MiniLM-L6-v2', output_filename="embeddings_bert.joblib")

    print("\n--- All embeddings generated successfully. ---")

if __name__ == "__main__":
    main()
