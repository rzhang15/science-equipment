# 1b_create_text_embeddings.py
"""
Generates and saves multiple sets of embeddings from the prepared text data.
Each function creates a file of vectors for a specific model (TF-IDF, BERT, etc.).
"""
import pandas as pd
import numpy as np
import joblib
import os
from sklearn.feature_extraction.text import TfidfVectorizer
from sentence_transformers import SentenceTransformer

import config

def generate_tfidf_vectors(df):
    """Generates and saves TF-IDF vectors for the gatekeeper model."""
    print("--- Generating TF-IDF Vectors for Gatekeeper---")
    # This vectorizer is for the gatekeeper model. It can be different from the expert model's vectorizer.
    # It's trained on the full vocabulary of both lab and non-lab items.
    gatekeeper_vectorizer = TfidfVectorizer(ngram_range=(1, 3), min_df=5, stop_words='english')
    tfidf_vectors = gatekeeper_vectorizer.fit_transform(df['prepared_description'].fillna(''))

    # Save both the vectors and the fitted vectorizer
    joblib.dump(tfidf_vectors, os.path.join(config.OUTPUT_DIR, "embeddings_tfidf.joblib"))
    joblib.dump(gatekeeper_vectorizer, os.path.join(config.OUTPUT_DIR, "vectorizer_tfidf.joblib"))
    print("✅ TF-IDF vectors and gatekeeper vectorizer saved.")


def generate_transformer_vectors(df, model_name, output_filename):
    """Generates and saves vectors using a pre-trained SentenceTransformer model."""
    print(f"\n--- Generating Vectors for: {model_name} ---")
    model = SentenceTransformer(model_name)

    # The `encode` method efficiently converts all sentences to vectors
    vectors = model.encode(df['prepared_description'].fillna('').tolist(), show_progress_bar=True)

    joblib.dump(vectors, os.path.join(config.OUTPUT_DIR, output_filename))
    print(f"✅ {model_name} vectors saved to {output_filename}")

def main():
    print("--- Starting Step 1b: Embedding Generation ---")
    try:
        df = pd.read_parquet(config.PREPARED_DATA_PATH)
    except FileNotFoundError:
        print(f"❌ Prepared data not found at '{config.PREPARED_DATA_PATH}'.")
        print("   Please run 1_build_training_dataset.py first.")
        return

    # Generate and save each type of embedding for the gatekeeper models
    generate_tfidf_vectors(df)
    
    # Using a popular, high-performance BERT model for the BERT-based gatekeeper
    generate_transformer_vectors(df, model_name='all-MiniLM-L6-v2', output_filename="embeddings_bert.joblib")

    print("\n--- All embeddings generated successfully. ---")
    
if __name__ == "__main__":
    main()
