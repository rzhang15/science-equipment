# categorize_items.py
"""
Defines the non-parametric categorizer classes used for predicting product markets.
Returns both the category and the similarity score.
"""
import joblib
import numpy as np
import os
from sklearn.metrics.pairwise import cosine_similarity
from sentence_transformers import SentenceTransformer

import config

class TfidfItemCategorizer:
    def __init__(self):
        print("  - Initializing TfidfItemCategorizer...")
        try:
            self.vectorizer = joblib.load(config.CATEGORY_VECTORIZER_PATH)
            category_data = joblib.load(config.CATEGORY_MODEL_DATA_PATH)
            self.category_names = category_data['category_names']
            self.category_vectors = category_data['category_vectors']
        except FileNotFoundError as e:
            print(f"\nERROR: TfidfItemCategorizer: required file not found: {e.filename}")
            raise
        except Exception as e:
            print(f"\nERROR: loading TF-IDF category data: {e}")
            raise

    def get_item_category(self, item_description: str):
        if not item_description or not item_description.strip():
            return "No Description", -1.0
        try:
            item_vector = self.vectorizer.transform([item_description])
            sim_scores = cosine_similarity(item_vector, self.category_vectors).flatten()
            best_score_index = np.argmax(sim_scores)
            best_score = sim_scores[best_score_index]
            if best_score < config.TFIDF_MIN_SCORE_THRESHOLD:
                return "unclassified", best_score
            category_name = self.category_names[best_score_index]
            return category_name, best_score
        except Exception as e:
            print(f"  WARNING: Error during TF-IDF prediction for '{item_description[:50]}...': {e}")
            return "Prediction Error", -1.0


class EmbeddingItemCategorizer:
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
            print(f"  - {embedding_name} Categorizer ready.")
        except Exception as e:
            print(f"\nERROR: loading {embedding_name} category data: {e}")
            raise

    def get_item_category(self, description: str):
        if not description or not description.strip():
            return "No Description", -1.0
        try:
            item_vector = self.encoder_model.encode([description])
            sim_scores = cosine_similarity(item_vector, self.category_vectors).flatten()
            best_score_index = np.argmax(sim_scores)
            best_score = sim_scores[best_score_index]
            if best_score < config.BERT_MIN_SCORE_THRESHOLD:
                return "unclassified", best_score
            category_name = self.category_names[best_score_index]
            return category_name, best_score
        except Exception as e:
            print(f"  WARNING: Error during BERT prediction for '{description[:50]}...': {e}")
            return "Prediction Error", -1.0