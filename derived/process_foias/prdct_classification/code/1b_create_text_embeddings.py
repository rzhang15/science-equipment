import pandas as pd
import numpy as np
import joblib
import os
import argparse
from scipy.sparse import hstack
from sklearn.feature_extraction.text import TfidfVectorizer, ENGLISH_STOP_WORDS
from sklearn.preprocessing import normalize

import config
from classifier import compute_engineered_features


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

        desc_norm = normalize(desc_vectors, norm='l2')
        supp_norm = normalize(supp_vectors, norm='l2')
        combined = hstack([desc_norm * config.DESC_WEIGHT, supp_norm * config.SUPPLIER_WEIGHT]).tocsr()
        print(f"  Combined: {config.DESC_WEIGHT:.0%} description + {config.SUPPLIER_WEIGHT:.0%} supplier "
              f"= {combined.shape[1]} total features.")

        if getattr(config, 'USE_ENGINEERED_FEATURES', False):
            extra = compute_engineered_features(model_text)
            combined = hstack([combined, extra]).tocsr()
            print(f"  + {extra.shape[1]} engineered features "
                  f"(weight={config.FEATURE_WEIGHT:.2f}) -> {combined.shape[1]} total.")

        joblib.dump(combined, os.path.join(config.OUTPUT_DIR, "embeddings_tfidf.joblib"))
    else:
        if getattr(config, 'USE_ENGINEERED_FEATURES', False):
            extra = compute_engineered_features(model_text)
            combined = hstack([desc_vectors, extra]).tocsr()
            print(f"  + {extra.shape[1]} engineered features "
                  f"(weight={config.FEATURE_WEIGHT:.2f}) -> {combined.shape[1]} total.")
            joblib.dump(combined, os.path.join(config.OUTPUT_DIR, "embeddings_tfidf.joblib"))
        else:
            joblib.dump(desc_vectors, os.path.join(config.OUTPUT_DIR, "embeddings_tfidf.joblib"))

    print("  TF-IDF vectors saved.")


def _load_encoder(model_id):
    import torch
    from sentence_transformers import SentenceTransformer
    device = 'cuda' if torch.cuda.is_available() else 'cpu'
    print(f"  Loading encoder '{model_id}' on device={device}")
    model = SentenceTransformer(model_id, device=device)
    if device == 'cuda':
        model.half()
    return model, device


def _encode_dedup(model, texts, batch_size=256):
    codes, uniques = pd.factorize(pd.Series(texts), sort=False)
    print(f"    Encoding {len(uniques)} unique texts (from {len(texts)} total, "
          f"{100.0 * (1 - len(uniques)/max(len(texts),1)):.1f}% dedup)")
    uniq_vecs = model.encode(
        list(uniques),
        batch_size=batch_size,
        show_progress_bar=True,
        convert_to_numpy=True,
        normalize_embeddings=True,
    )
    return uniq_vecs[codes].astype(np.float32)


def generate_transformer_vectors(df, short_name, model_id):
    print(f"\n--- Generating Vectors for: {short_name} ({model_id}) ---")
    model, _device = _load_encoder(model_id)

    desc_vectors = _encode_dedup(model, df['prepared_description'].fillna('').tolist())

    output_filename = f"embeddings_{short_name}.joblib"

    if config.USE_SUPPLIER and 'supplier_token' in df.columns:
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
        combined = hstack([desc_norm * config.DESC_WEIGHT, supp_norm * config.SUPPLIER_WEIGHT]).tocsr()
        print(f"  Combined: {config.DESC_WEIGHT:.0%} {short_name} + {config.SUPPLIER_WEIGHT:.0%} supplier "
              f"= {combined.shape[1]} total features.")

        if getattr(config, 'USE_ENGINEERED_FEATURES', False):
            extra = compute_engineered_features(df['prepared_description'].fillna(''))
            combined = hstack([combined, extra]).tocsr()
            print(f"  + {extra.shape[1]} engineered features "
                  f"(weight={config.FEATURE_WEIGHT:.2f}) -> {combined.shape[1]} total.")

        joblib.dump(combined, os.path.join(config.OUTPUT_DIR, output_filename))
    else:
        if getattr(config, 'USE_ENGINEERED_FEATURES', False):
            extra = compute_engineered_features(df['prepared_description'].fillna(''))
            combined = hstack([desc_vectors, extra]).tocsr()
            print(f"  + {extra.shape[1]} engineered features "
                  f"(weight={config.FEATURE_WEIGHT:.2f}) -> {combined.shape[1]} total.")
            joblib.dump(combined, os.path.join(config.OUTPUT_DIR, output_filename))
        else:
            joblib.dump(desc_vectors, os.path.join(config.OUTPUT_DIR, output_filename))

    print(f"  {short_name} vectors saved to {output_filename}")

    del model
    try:
        import torch
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
    except ImportError:
        pass


def main(embedding_name):
    print(f"--- Starting Step 1b: Embedding Generation [Variant: {config.VARIANT}, model: {embedding_name}] ---")
    try:
        df = pd.read_parquet(config.PREPARED_DATA_PATH)
    except FileNotFoundError:
        print(f"ERROR: Prepared data not found at '{config.PREPARED_DATA_PATH}'.")
        print("   Please run 1_build_training_dataset.py first.")
        return

    if embedding_name == 'tfidf':
        generate_tfidf_vectors(df)
    elif embedding_name in config.BERT_MODELS:
        generate_transformer_vectors(df, embedding_name, config.BERT_MODELS[embedding_name])
    else:
        raise ValueError(
            f"Unknown embedding_name '{embedding_name}'. "
            f"Expected 'tfidf' or one of: {list(config.BERT_MODELS)}"
        )

    print("\n--- Embedding generation complete. ---")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    choices = ['tfidf'] + list(config.BERT_MODELS.keys())
    parser.add_argument("embedding_name", type=str, choices=choices,
                        help=f"Which embedding set to generate. One of: {choices}")
    args = parser.parse_args()
    main(args.embedding_name)
