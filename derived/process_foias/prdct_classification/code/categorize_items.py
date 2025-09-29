# categorize_items.py
"""
Performs granular item categorization using a hybrid approach.
Always predicts the best-matching category from the full list of lab categories.
"""
import joblib
import numpy as np
import re
import os
import config
from sklearn.metrics.pairwise import cosine_similarity
from sentence_transformers import SentenceTransformer
from scipy.sparse import vstack, csr_matrix
from tqdm import tqdm
import pandas as pd


class TfidfItemCategorizer:
    def __init__(self, category_data_path, vectorizer_path):
        """Initializes the TF-IDF categorizer."""
        print("ℹ️ Initializing TfidfItemCategorizer...")
        try:
            self.vectorizer = joblib.load(vectorizer_path)
            data = joblib.load(category_data_path)
            self.category_names = data['category_names']
            self.category_vectors = data['category_vectors']
            self.category_label_words = data['category_label_words']
            print("✅ TfidfItemCategorizer loaded artifacts successfully.")
        except FileNotFoundError:
            print("❌ Error: Categorizer model data or vectorizer not found. Run relevant prep scripts first.")
            raise

    @staticmethod
    def _get_words(text):
        return set(re.findall(r'\b[a-z0-9]+\b', str(text).lower()))

    def get_item_category(self, item_description: str, sim_weight: float = 0.7, overlap_weight: float = 0.3):
        """Predicts the single best-matching category for an item."""
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
            
        return self.category_names[best_score_index]

    @staticmethod
    def prepare_and_save_category_data(df_ut_dallas, vectorizer, category_col, description_col, output_path):
        # This function remains the same, it correctly builds vectors for all provided categories.
        print("ℹ️ Preparing and saving TF-IDF category data (Optimized)...")
        # ... (implementation is unchanged and correct)
        batch_size=5000
        num_batches = (len(df_ut_dallas) // batch_size) + 1
        vector_batches = []
        for i in tqdm(range(0, len(df_ut_dallas), batch_size), desc="  - Vectorizing"):
            batch = df_ut_dallas[description_col][i:i+batch_size]
            vector_batches.append(vectorizer.transform(batch))
        all_vectors = vstack(vector_batches)
        categories = pd.Categorical(df_ut_dallas[category_col])
        unique_categories = categories.categories
        grouping_matrix = csr_matrix((np.ones(len(categories)), (categories.codes, np.arange(len(categories)))), shape=(len(unique_categories), len(categories)))
        category_sums = grouping_matrix.dot(all_vectors)
        category_counts = np.bincount(categories.codes)[:, np.newaxis]
        mean_category_vectors = category_sums / np.maximum(category_counts, 1)
        category_label_words = [TfidfItemCategorizer._get_words(name) for name in unique_categories]
        category_similarity_data = {'category_names': unique_categories.tolist(), 'category_vectors': mean_category_vectors, 'category_label_words': category_label_words}
        joblib.dump(category_similarity_data, output_path)
        print(f"✅ TF-IDF category data saved to: {output_path}")


class EmbeddingItemCategorizer:
    def __init__(self, embedding_name: str, model_name: str):
        """Initializes the sentence-transformer categorizer."""
        print(f"--- Initializing Categorizer for {embedding_name} ---")
        self.encoder_model = SentenceTransformer(model_name)
        category_data_path = os.path.join(config.OUTPUT_DIR, f"category_vectors_{embedding_name}.joblib")
        try:
            category_data = joblib.load(category_data_path)
            self.category_names = category_data['category_names']
            self.category_vectors = category_data['category_vectors']
            print(f"✅ {embedding_name} Categorizer ready.")
        except FileNotFoundError:
            raise FileNotFoundError(f"Category vectors not found at {category_data_path}. Run 1c... script first.")

    def get_item_category(self, description: str):
        """Predicts the single best-matching category for an item."""
        if not description or not description.strip():
            return "No Description"

        item_vector = self.encoder_model.encode([description])
        sim_scores = cosine_similarity(item_vector, self.category_vectors).flatten()
        best_score_index = np.argmax(sim_scores)
            
        return self.category_names[best_score_index]

