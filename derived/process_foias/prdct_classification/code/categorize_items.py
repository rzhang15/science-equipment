# categorize_items.py
"""
Performs granular item categorization using a hybrid approach.
"""
import pandas as pd
import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
import joblib
import re

class ItemCategorizer:
    def __init__(self, category_data_path, vectorizer_path):
        """
        Initializes the categorizer by loading pre-computed category data and the vectorizer.
        """
        print("ℹ️ Initializing ItemCategorizer...")
        try:
            self.vectorizer = joblib.load(vectorizer_path)
            data = joblib.load(category_data_path)
            self.category_names = data['category_names']
            self.category_vectors = data['category_vectors']
            self.category_label_words = data['category_label_words']
            print("✅ ItemCategorizer loaded artifacts successfully.")
        except FileNotFoundError:
            print("❌ Error: Categorizer model data or vectorizer not found. Run 1_prepare_data.py first.")
            raise
        except Exception as e:
            print(f"❌ Error loading categorizer artifacts: {e}")
            raise

    @staticmethod
    def _get_words(text):
        return set(re.findall(r'\b[a-z0-9]+\b', str(text).lower()))

    def get_item_category(self, item_description: str, sim_weight: float = 0.7, overlap_weight: float = 0.3, min_threshold: float = 0.1):
        if not item_description:
            return "No Description"
        item_vector = self.vectorizer.transform([item_description])
        sim_scores = cosine_similarity(item_vector, self.category_vectors).flatten()
        item_words = self._get_words(item_description)
        overlap_scores = np.array([
            len(item_words.intersection(label_words)) / len(item_words.union(label_words) or {1})
            for label_words in self.category_label_words
        ])
        final_scores = (sim_scores * sim_weight) + (overlap_scores * overlap_weight)
        best_score_index = np.argmax(final_scores)
        best_score = final_scores[best_score_index]
        best_category = self.category_names[best_score_index]

        if best_score >= min_threshold:
            return best_category
        else:
            return "Uncategorized"

    @staticmethod
    def prepare_and_save_category_data(df_ut_dallas, vectorizer, category_col, description_col, output_path):
        """
        Pre-computes the category vectors and label words from the UT Dallas data.
        """
        print("ℹ️ Preparing and saving category similarity data...")
        category_docs = df_ut_dallas.groupby(category_col)[description_col].apply(lambda x: ' '.join(x)).reset_index()
        category_vectors = vectorizer.transform(category_docs[description_col])
        category_label_words = [ItemCategorizer._get_words(name) for name in category_docs[category_col]]
        category_similarity_data = {
            'category_names': category_docs[category_col].tolist(),
            'category_vectors': category_vectors,
            'category_label_words': category_label_words
        }
        joblib.dump(category_similarity_data, output_path)
        print(f"✅ Category similarity data saved to: {output_path}")
