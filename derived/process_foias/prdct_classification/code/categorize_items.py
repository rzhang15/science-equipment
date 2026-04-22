# categorize_items.py
"""
Defines the non-parametric categorizer classes used for predicting product markets.
Returns both the category and the similarity score.
"""
import joblib
import numpy as np
import os
import pandas as pd
from scipy.sparse import hstack, diags
from sklearn.metrics.pairwise import cosine_similarity
from sentence_transformers import SentenceTransformer

import config


class _WordCharVectorizer:
    """Thin wrapper exposing a sklearn-like `.transform(X)` over the combined
    word + char TF-IDF space with element-wise contrastive weights applied.
    Present so downstream code (including `3_predict_product_markets.py`) can
    keep using a single `.vectorizer.transform(...)` call unchanged."""

    def __init__(self, word_vec, char_vec=None, feature_weights=None):
        self.word_vec = word_vec
        self.char_vec = char_vec
        self._weights = diags(feature_weights) if feature_weights is not None else None

    def transform(self, X):
        Xw = self.word_vec.transform(X)
        X_all = Xw if self.char_vec is None else hstack([Xw, self.char_vec.transform(X)]).tocsr()
        return X_all @ self._weights if self._weights is not None else X_all

class TfidfItemCategorizer:
    def __init__(self):
        print("  - Initializing TfidfItemCategorizer...")
        try:
            word_vec = joblib.load(config.CATEGORY_VECTORIZER_PATH)
            char_vec = None
            feature_weights = None
            if os.path.exists(config.CATEGORY_CHAR_VECTORIZER_PATH):
                char_vec = joblib.load(config.CATEGORY_CHAR_VECTORIZER_PATH)
            if os.path.exists(config.CATEGORY_FEATURE_WEIGHTS_PATH):
                feature_weights = joblib.load(config.CATEGORY_FEATURE_WEIGHTS_PATH)
            self.vectorizer = _WordCharVectorizer(word_vec, char_vec, feature_weights)

            category_data = joblib.load(config.CATEGORY_MODEL_DATA_PATH)
            self.category_names = category_data['category_names']
            self.category_vectors = category_data['category_vectors']
            n_char = (len(char_vec.vocabulary_) if char_vec else 0)
            print(f"  - Loaded word feats: {len(word_vec.vocabulary_)}, "
                  f"char feats: {n_char}, "
                  f"contrastive weights: {'yes' if feature_weights is not None else 'no'}")
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

    def predict_batch(self, descriptions: pd.Series) -> tuple:
        """Batch-predict categories for an entire Series at once.

        One vectorizer.transform + one cosine_similarity matmul for all
        items, instead of N separate calls via progress_apply.

        Returns (predictions, scores, item_vectors).  item_vectors is the
        sparse TF-IDF matrix aligned to descriptions.index, so the caller
        can reuse it downstream (e.g. to compute final similarity scores
        against assigned category vectors) without re-transforming.
        """
        descs = descriptions.astype(str)
        empty_mask = descs.str.strip() == ''

        item_vectors = self.vectorizer.transform(descs)
        sim_matrix = cosine_similarity(item_vectors, self.category_vectors)  # (n, n_cats)

        best_indices = np.argmax(sim_matrix, axis=1)
        best_scores = sim_matrix[np.arange(len(best_indices)), best_indices]

        cat_array = np.array(self.category_names)
        pred_array = cat_array[best_indices].copy()

        pred_array[best_scores < config.TFIDF_MIN_SCORE_THRESHOLD] = "unclassified"
        pred_array[empty_mask.values] = "No Description"
        best_scores[empty_mask.values] = -1.0

        return (
            pd.Series(pred_array, index=descriptions.index),
            pd.Series(best_scores, index=descriptions.index),
            item_vectors,
        )


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

    def predict_batch(self, descriptions: pd.Series) -> tuple:
        """Batch-predict categories for an entire Series at once.

        One encoder.encode call (batched internally) + one cosine_similarity
        matmul for all items, replacing N per-row encode calls.

        Returns (predictions, scores, item_vectors).  item_vectors is the
        dense (n, d) embedding matrix aligned to descriptions.index, so the
        caller can reuse it downstream (e.g. to compute final similarity
        scores against assigned category vectors) without re-encoding.
        """
        descs = descriptions.astype(str)
        empty_mask = descs.str.strip() == ''

        item_vectors = self.encoder_model.encode(
            descs.tolist(), show_progress_bar=True, batch_size=128
        )
        sim_matrix = cosine_similarity(item_vectors, self.category_vectors)

        best_indices = np.argmax(sim_matrix, axis=1)
        best_scores = sim_matrix[np.arange(len(best_indices)), best_indices]

        cat_array = np.array(self.category_names)
        pred_array = cat_array[best_indices].copy()

        pred_array[best_scores < config.BERT_MIN_SCORE_THRESHOLD] = "unclassified"
        pred_array[empty_mask.values] = "No Description"
        best_scores[empty_mask.values] = -1.0

        return (
            pd.Series(pred_array, index=descriptions.index),
            pd.Series(best_scores, index=descriptions.index),
            item_vectors,
        )