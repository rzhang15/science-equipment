# categorize_items.py
"""
Performs granular item categorization using a hybrid approach.
"""
import joblib
import numpy as np
import re
import os  # Import the 'os' module
import config  # Import your config file
from sklearn.metrics.pairwise import cosine_similarity
from sentence_transformers import SentenceTransformer
from gensim.models import Word2Vec
import numpy as np
import pandas as pd
from scipy.sparse import csr_matrix
from tqdm import tqdm
from scipy.sparse import vstack
class Word2VecItemCategorizer:
    def __init__(self, embedding_name: str, model_path: str):
        print(f"--- Initializing Categorizer for {embedding_name} ---")
        self.w2v_model = Word2Vec.load(model_path)

        category_data_path = os.path.join(config.OUTPUT_DIR, f"category_vectors_{embedding_name}.joblib")
        try:
            category_data = joblib.load(category_data_path)
            self.category_names = category_data['category_names']
            self.category_vectors = category_data['category_vectors']
            self.dense_categories = set(category_data.get('dense_categories', self.category_names))
        except FileNotFoundError:
            raise FileNotFoundError(f"Category vectors not found at {category_data_path}. Run 1c... script first.")
        print(f"✅ {embedding_name} Categorizer ready.")

    def get_item_category(self, description: str):
        if not description or not description.strip():
            return "No Description"

        # Create item vector by averaging word vectors
        tokens = description.split()
        doc_vectors = [self.w2v_model.wv[word] for word in tokens if word in self.w2v_model.wv]
        if not doc_vectors:
            item_vector = np.zeros((1, self.w2v_model.vector_size))
        else:
            item_vector = np.mean(doc_vectors, axis=0).reshape(1, -1)

        sim_scores = cosine_similarity(item_vector, self.category_vectors).flatten()
        best_score_index = np.argmax(sim_scores)
        predicted_category = self.category_names[best_score_index]
        if predicted_category in self.dense_categories:
            return predicted_category
        else:
            return "Lab - Sparse Category"

class TfidfItemCategorizer:
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
    def prepare_and_save_category_data(df_ut_dallas, vectorizer, category_col, description_col, output_path):
        """
        Pre-computes the category vectors from the UT Dallas data using a fast,
        memory-efficient, batch-processing method with a progress bar.
        """
        print("ℹ️ Preparing and saving category similarity data (Optimized Method)...")

        # 1. Vectorize all descriptions in batches to show progress and save memory
        batch_size = 5000  # Process 5000 descriptions at a time
        num_batches = (len(df_ut_dallas) // batch_size) + 1
        vector_batches = []

        print(f"  - Vectorizing {len(df_ut_dallas)} descriptions in {num_batches} batches...")
        
        # Use tqdm for a live progress bar
        for i in tqdm(range(0, len(df_ut_dallas), batch_size), desc="  - Vectorizing"):
            batch = df_ut_dallas[description_col][i:i+batch_size]
            vector_batches.append(vectorizer.transform(batch))
        
        # Combine the batches into a single large matrix
        all_vectors = vstack(vector_batches)
        print("  - Vectorization complete.")
        
        # The rest of the function is the same as the previous fast version
        print("  - Calculating mean category vectors...")
        categories = pd.Categorical(df_ut_dallas[category_col])
        unique_categories = categories.categories
        
        grouping_matrix = csr_matrix((np.ones(len(categories)), (categories.codes, np.arange(len(categories)))),
                                     shape=(len(unique_categories), len(categories)))
                                     
        category_sums = grouping_matrix.dot(all_vectors)
        category_counts = np.bincount(categories.codes)[:, np.newaxis]
        mean_category_vectors = category_sums / category_counts
        
        category_label_words = [TfidfItemCategorizer._get_words(name) for name in unique_categories]
        category_similarity_data = {
            'category_names': unique_categories.tolist(),
            'category_vectors': mean_category_vectors,
            'category_label_words': category_label_words
        }
        joblib.dump(category_similarity_data, output_path)
        print(f"✅ Category similarity data saved to: {output_path}")

class EmbeddingItemCategorizer:
    def __init__(self, embedding_name: str, model_name: str):
        """
        Initializes the categorizer with a specific sentence-transformer model.

        Args:
            embedding_name (str): The short name for the model (e.g., 'scibert').
            model_name (str): The full Hugging Face name for the model.
        """
        print(f"--- Initializing Categorizer for {embedding_name} ---")
        self.encoder_model = SentenceTransformer(model_name)

        category_data_path = os.path.join(config.OUTPUT_DIR, f"category_vectors_{embedding_name}.joblib")
        try:
            category_data = joblib.load(category_data_path)
            self.category_names = category_data['category_names']
            self.category_vectors = category_data['category_vectors']
            self.dense_categories = set(category_data.get('dense_categories', self.category_names))
        except FileNotFoundError:
            raise FileNotFoundError(f"Category vectors not found at {category_data_path}. Run 1c_prepare_category_vectors.py first.")
        print(f"✅ {embedding_name} Categorizer ready.")

    def get_item_category(self, description: str):
        if not description or not description.strip():
            return "No Description"

        item_vector = self.encoder_model.encode([description])
        sim_scores = cosine_similarity(item_vector, self.category_vectors).flatten()
        best_score_index = np.argmax(sim_scores)
        predicted_category = self.category_names[best_score_index]

        # You can add a min_threshold check here if needed
        # if sim_scores[best_score_index] < 0.5:
        #     return "Uncategorized"

        if predicted_category in self.dense_categories:
            # If it is, return it as the prediction
            return predicted_category
        else:
            # If it's a sparse category, return our special label
            return "Lab - Sparse Category"
