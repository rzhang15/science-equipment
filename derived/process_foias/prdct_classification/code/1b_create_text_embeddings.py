"""
Generates and saves multiple sets of embeddings from the prepared text data.
Each function creates a file of vectors for a specific model (TF-IDF, BERT, etc.).
Also saves the initialized BERT model for later reuse.

When USE_SUPPLIER is True, description and supplier tokens are vectorized
separately and combined with explicit weights (config.DESC_WEIGHT / SUPPLIER_WEIGHT).
"""
import pandas as pd
import joblib
import os
import argparse
from scipy.sparse import hstack
from sklearn.feature_extraction.text import TfidfVectorizer, ENGLISH_STOP_WORDS
from sklearn.preprocessing import normalize

import config


def generate_tfidf_vectors(df):
    print("--- Generating TF-IDF Vectors for Gatekeeper ---")
    model_text = df['prepared_description'].fillna('')
    custom_stops = list(ENGLISH_STOP_WORDS) + config.DOMAIN_STOP_WORDS
    gatekeeper_vectorizer = TfidfVectorizer(
        ngram_range=(1, 3),
        min_df=config.GATEKEEPER_VECTORIZER_MIN_DF,
        stop_words=custom_stops,
        sublinear_tf=True,
    )
    desc_vectors = gatekeeper_vectorizer.fit_transform(model_text)

    joblib.dump(gatekeeper_vectorizer, os.path.join(config.OUTPUT_DIR, "vectorizer_tfidf.joblib"))
    print(f"  Description vectorizer saved ({desc_vectors.shape[1]} features).")

    if config.USE_SUPPLIER and 'supplier_token' in df.columns:
        supplier_text = df['supplier_token'].fillna('')
        supplier_vectorizer = TfidfVectorizer(
            ngram_range=(1, 1),
            min_df=1,
        )
        supp_vectors = supplier_vectorizer.fit_transform(supplier_text)
        joblib.dump(supplier_vectorizer, os.path.join(config.OUTPUT_DIR, "vectorizer_supplier_tfidf.joblib"))
        print(f"  Supplier vectorizer saved ({supp_vectors.shape[1]} features).")

        # L2-normalize each, apply weights, combine
        desc_norm = normalize(desc_vectors, norm='l2')
        supp_norm = normalize(supp_vectors, norm='l2')
        combined = hstack([desc_norm * config.DESC_WEIGHT, supp_norm * config.SUPPLIER_WEIGHT])
        print(f"  Combined: {config.DESC_WEIGHT:.0%} description + {config.SUPPLIER_WEIGHT:.0%} supplier "
              f"= {combined.shape[1]} total features.")
        joblib.dump(combined, os.path.join(config.OUTPUT_DIR, "embeddings_tfidf.joblib"))
    else:
        joblib.dump(desc_vectors, os.path.join(config.OUTPUT_DIR, "embeddings_tfidf.joblib"))

    print("  TF-IDF vectors saved.")


def generate_transformer_vectors(df, model_name, output_filename):
    from sentence_transformers import SentenceTransformer
    print(f"\n--- Generating Vectors for: {model_name} ---")
    model = SentenceTransformer(model_name)

    desc_vectors = model.encode(df['prepared_description'].fillna('').tolist(), show_progress_bar=True)

    model_object_path = os.path.join(config.OUTPUT_DIR, f"model_object_{model_name.split('/')[-1]}.joblib")
    joblib.dump(model, model_object_path)
    print(f"  Saved reusable {model_name} model object to {model_object_path}")

    if config.USE_SUPPLIER and 'supplier_token' in df.columns:
        # Reuse the supplier vectorizer fit during the TF-IDF step so the
        # token vocabulary is identical across embedding variants.
        supp_vec_path = os.path.join(config.OUTPUT_DIR, "vectorizer_supplier_tfidf.joblib")
        if os.path.exists(supp_vec_path):
            supplier_vectorizer = joblib.load(supp_vec_path)
            supp_vectors = supplier_vectorizer.transform(df['supplier_token'].fillna(''))
        else:
            supplier_vectorizer = TfidfVectorizer(ngram_range=(1, 1), min_df=1)
            supp_vectors = supplier_vectorizer.fit_transform(df['supplier_token'].fillna(''))
            joblib.dump(supplier_vectorizer, supp_vec_path)
            print(f"  Supplier vectorizer saved ({supp_vectors.shape[1]} features).")

        desc_norm = normalize(desc_vectors, norm='l2')
        supp_norm = normalize(supp_vectors, norm='l2')
        combined = hstack([desc_norm * config.DESC_WEIGHT, supp_norm * config.SUPPLIER_WEIGHT])
        print(f"  Combined: {config.DESC_WEIGHT:.0%} BERT + {config.SUPPLIER_WEIGHT:.0%} supplier "
              f"= {combined.shape[1]} total features.")
        joblib.dump(combined, os.path.join(config.OUTPUT_DIR, output_filename))
    else:
        joblib.dump(desc_vectors, os.path.join(config.OUTPUT_DIR, output_filename))

    print(f"  {model_name} vectors saved to {output_filename}")


def main(tfidf_only=False):
    print(f"--- Starting Step 1b: Embedding Generation [Variant: {config.VARIANT}] ---")
    try:
        df = pd.read_parquet(config.PREPARED_DATA_PATH)
    except FileNotFoundError:
        print(f"ERROR: Prepared data not found at '{config.PREPARED_DATA_PATH}'.")
        print("   Please run 1_build_training_dataset.py first.")
        return

    generate_tfidf_vectors(df)

    if tfidf_only:
        print("\n--- Skipping BERT embeddings (--tfidf-only). ---")
    else:
        generate_transformer_vectors(df, model_name='all-MiniLM-L6-v2', output_filename="embeddings_bert.joblib")

    print("\n--- Embedding generation complete. ---")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--tfidf-only", action="store_true",
                        help="Only generate TF-IDF vectors, skip BERT (much faster).")
    args = parser.parse_args()
    main(tfidf_only=args.tfidf_only)
