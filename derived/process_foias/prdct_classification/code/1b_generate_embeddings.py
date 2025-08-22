# 1b_generate_embeddings.py
"""
Generates and saves multiple sets of embeddings from the prepared text data.
Each function creates a file of vectors for a specific model (TF-IDF, Word2Vec, BERT, etc.).
"""
import pandas as pd
import numpy as np
import joblib
import os
from sklearn.feature_extraction.text import TfidfVectorizer
from gensim.models import Word2Vec
from sentence_transformers import SentenceTransformer

import config

# Helper function to get the corpus
def get_corpus(df):
    """Prepares the text corpus for training vector models."""
    # Simple tokenization
    return [doc.split() for doc in df['prepared_description'].fillna('')]

def generate_tfidf_vectors(df):
    """Generates and saves TF-IDF vectors."""
    print("--- Generating TF-IDF Vectors ---")
    tfidf_vectorizer = TfidfVectorizer(ngram_range=(1, 3), min_df=5, stop_words='english')
    tfidf_vectors = tfidf_vectorizer.fit_transform(df['prepared_description'].fillna(''))
    
    # Save both the vectors and the fitted vectorizer
    joblib.dump(tfidf_vectors, os.path.join(config.OUTPUT_DIR, "embeddings_tfidf.joblib"))
    joblib.dump(tfidf_vectorizer, os.path.join(config.OUTPUT_DIR, "vectorizer_tfidf.joblib"))
    print("✅ TF-IDF vectors and vectorizer saved.")

def generate_word2vec_vectors(df):
    """Trains a Word2Vec model and saves the resulting document vectors."""
    print("\n--- Generating Word2Vec Vectors ---")
    corpus = get_corpus(df)
    
    # Train a new Word2Vec model on our specific corpus
    print("  - Training Word2Vec model...")
    w2v_model = Word2Vec(sentences=corpus, vector_size=100, window=5, min_count=5, workers=4)
    w2v_model.save(os.path.join(config.OUTPUT_DIR, "model_word2vec.model"))
    print("  - Word2Vec model trained and saved.")

    # Create document vectors by averaging the word vectors for each description
    vectors = []
    for doc in corpus:
        doc_vectors = [w2v_model.wv[word] for word in doc if word in w2v_model.wv]
        if doc_vectors:
            vectors.append(np.mean(doc_vectors, axis=0))
        else:
            vectors.append(np.zeros(w2v_model.vector_size)) # Use a zero vector for empty descriptions

    joblib.dump(np.array(vectors), os.path.join(config.OUTPUT_DIR, "embeddings_word2vec.joblib"))
    print("✅ Word2Vec document vectors saved.")

def generate_transformer_vectors(df, model_name, output_filename):
    """Generates and saves vectors using a pre-trained SentenceTransformer model."""
    print(f"\n--- Generating Vectors for: {model_name} ---")
    model = SentenceTransformer(model_name)
    
    # The `encode` method efficiently converts all sentences to vectors
    vectors = model.encode(df['prepared_description'].fillna('').tolist(), show_progress_bar=True)
    
    joblib.dump(vectors, os.path.join(config.OUTPUT_DIR, output_filename))
    print(f"✅ {model_name} vectors saved.")


def main():
    print("--- Starting Step 1b: Embedding Generation ---")
    try:
        df = pd.read_parquet(config.PREPARED_DATA_PATH)
    except FileNotFoundError:
        print(f"❌ Prepared data not found. Run 1_prepare_data.py first.")
        return

    # Generate and save each type of embedding
    #generate_tfidf_vectors(df)
    #generate_word2vec_vectors(df)
    
    # Using a popular, high-performance BERT model
    #generate_transformer_vectors(df, model_name='all-MiniLM-L6-v2', output_filename="embeddings_bert.joblib")

    # Using the General Text Embeddings (GTE) model
    generate_transformer_vectors(df, model_name='thenlper/gte-large', output_filename="embeddings_gte.joblib")
    
    print("\n--- All embeddings generated successfully. ---")


if __name__ == "__main__":
    main()
