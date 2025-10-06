# categorize_items.py
"""
Defines the non-parametric categorizer classes used for predicting product markets.
"""
import joblib
import numpy as np
import os
from sklearn.metrics.pairwise import cosine_similarity
from sentence_transformers import SentenceTransformer

import config

class TfidfItemCategorizer:
    """
    A non-parametric categorizer that uses TF-IDF vectors and cosine similarity.
    """
    def __init__(self):
        print("  - Initializing TfidfItemCategorizer...")
        category_data_path = os.path.join(config.OUTPUT_DIR, "category_vectors_tfidf.joblib")
        vectorizer_path = os.path.join(config.OUTPUT_DIR, "vectorizer_tfidf.joblib")
        try:
            # It tries to load files from paths defined in config
            self.vectorizer = joblib.load(config.CATEGORY_VECTORIZER_PATH)
            category_data = joblib.load(config.CATEGORY_MODEL_DATA_PATH)
            self.category_names = category_data['category_names']
            self.category_vectors = category_data['category_vectors']
        except FileNotFoundError as e:
            print(f"\n❌ FATAL ERROR inside TfidfItemCategorizer: A required file was not found.")
            print(f"   The file it failed to load is: {e.filename}")
            print(f"   Please check the paths in your config.py file.\n")
            raise # THIS LINE IS CRITICAL. IT MUST BE HERE. 
    def get_item_category(self, item_description: str):
        if not item_description or not item_description.strip():
            return "No Description"
        item_vector = self.vectorizer.transform([item_description])
        sim_scores = cosine_similarity(item_vector, self.category_vectors).flatten()
        best_score_index = np.argmax(sim_scores)
        return self.category_names[best_score_index]

class EmbeddingItemCategorizer:
    """
    A non-parametric categorizer that uses sentence-transformer (e.g., BERT)
    embeddings and cosine similarity.
    """
    def __init__(self, embedding_name: str, model_name: str):
        print(f"  - Initializing EmbeddingItemCategorizer ({embedding_name})...")
        self.encoder_model = SentenceTransformer(model_name)
        category_data_path = os.path.join(config.OUTPUT_DIR, f"category_vectors_{embedding_name}.joblib")
        try:
            category_data = joblib.load(category_data_path)
            if 'category_names' not in category_data or 'category_vectors' not in category_data:
                 raise KeyError(f"The '{os.path.basename(category_data_path)}' file has an outdated format.")
            self.category_names = category_data['category_names']
            self.category_vectors = category_data['category_vectors']
            print(f"  - ✅ {embedding_name} Categorizer ready.")
        except Exception as e:
            raise e

    def get_item_category(self, description: str):
        if not description or not description.strip():
            return "No Description"
        item_vector = self.encoder_model.encode([description])
        sim_scores = cosine_similarity(item_vector, self.category_vectors).flatten()
        best_score_index = np.argmax(sim_scores)
        return self.category_names[best_score_index]

