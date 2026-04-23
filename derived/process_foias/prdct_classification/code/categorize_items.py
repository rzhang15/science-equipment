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
from sklearn.preprocessing import normalize
from sentence_transformers import SentenceTransformer

import config


def _normalize_suppliers(suppliers):
    """Return a list of normalized supplier tokens aligned with descriptions.
    Missing / None entries become the empty string (same as training)."""
    if suppliers is None:
        return None
    if isinstance(suppliers, pd.Series):
        suppliers = suppliers.tolist()
    return [config.normalize_supplier(str(s)) if s is not None else '' for s in suppliers]


class _WordCharVectorizer:
    """Thin wrapper over the combined word + char TF-IDF space with
    element-wise contrastive weights applied.  When a supplier vectorizer is
    present, `.transform(X, suppliers)` additionally L2-normalizes desc and
    supplier blocks and concats them with config.DESC_WEIGHT / SUPPLIER_WEIGHT
    (mirroring the gatekeeper's treatment in classifier.py)."""

    def __init__(self, word_vec, char_vec=None, feature_weights=None,
                 supplier_vec=None):
        self.word_vec = word_vec
        self.char_vec = char_vec
        self._weights = diags(feature_weights) if feature_weights is not None else None
        self.supplier_vec = supplier_vec

    def _transform_desc(self, X):
        Xw = self.word_vec.transform(X)
        X_all = Xw if self.char_vec is None else hstack([Xw, self.char_vec.transform(X)]).tocsr()
        return X_all @ self._weights if self._weights is not None else X_all

    def transform(self, X, suppliers=None):
        X_desc = self._transform_desc(X)
        if self.supplier_vec is None:
            return X_desc
        # Category vectors carry a supplier block, so item vectors must too --
        # even if suppliers weren't passed (e.g. a file without a supplier
        # column).  Fall back to empty strings so the supplier block is all
        # zeros and cosine similarity reflects desc-only agreement.
        if suppliers is None:
            supp_tokens = [''] * X_desc.shape[0]
        else:
            supp_tokens = _normalize_suppliers(suppliers)
        X_supp = self.supplier_vec.transform(supp_tokens)
        X_desc_n = normalize(X_desc, norm='l2')
        X_supp_n = normalize(X_supp, norm='l2')
        return hstack([X_desc_n * config.DESC_WEIGHT,
                       X_supp_n * config.SUPPLIER_WEIGHT]).tocsr()

class TfidfItemCategorizer:
    def __init__(self):
        print("  - Initializing TfidfItemCategorizer...")
        try:
            word_vec = joblib.load(config.CATEGORY_VECTORIZER_PATH)
            char_vec = None
            feature_weights = None
            supplier_vec = None
            if os.path.exists(config.CATEGORY_CHAR_VECTORIZER_PATH):
                char_vec = joblib.load(config.CATEGORY_CHAR_VECTORIZER_PATH)
            if os.path.exists(config.CATEGORY_FEATURE_WEIGHTS_PATH):
                feature_weights = joblib.load(config.CATEGORY_FEATURE_WEIGHTS_PATH)
            if getattr(config, 'USE_SUPPLIER', False):
                supp_vec_path = os.path.join(config.OUTPUT_DIR, "vectorizer_supplier_tfidf.joblib")
                if os.path.exists(supp_vec_path):
                    supplier_vec = joblib.load(supp_vec_path)
            self.vectorizer = _WordCharVectorizer(word_vec, char_vec,
                                                  feature_weights, supplier_vec)

            category_data = joblib.load(config.CATEGORY_MODEL_DATA_PATH)
            self.category_names = category_data['category_names']
            self.category_vectors = category_data['category_vectors']
            n_char = (len(char_vec.vocabulary_) if char_vec else 0)
            n_supp = (len(supplier_vec.vocabulary_) if supplier_vec else 0)
            print(f"  - Loaded word feats: {len(word_vec.vocabulary_)}, "
                  f"char feats: {n_char}, supplier feats: {n_supp}, "
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

    def predict_batch(self, descriptions: pd.Series, suppliers=None) -> tuple:
        """Batch-predict categories for an entire Series at once.

        One vectorizer.transform + one cosine_similarity matmul for all
        items, instead of N separate calls via progress_apply.

        Returns (predictions, scores, item_vectors).  item_vectors is the
        combined desc+supplier matrix aligned to descriptions.index, so the
        caller can reuse it downstream (e.g. to compute final similarity
        scores against assigned category vectors) without re-transforming.
        """
        descs = descriptions.astype(str)
        empty_mask = descs.str.strip() == ''

        item_vectors = self.vectorizer.transform(descs, suppliers=suppliers)

        # Chunk the (N, K) dense similarity matrix so peak memory is
        # (CHUNK, K) instead of (N, K).  Large-file predictions used to
        # allocate ~1.3 GB at this step for 300k rows x ~550 categories.
        CHUNK_SIZE = 20_000
        n_items = item_vectors.shape[0]
        best_indices = np.empty(n_items, dtype=np.int64)
        best_scores = np.empty(n_items, dtype=np.float64)
        for start in range(0, n_items, CHUNK_SIZE):
            end = min(start + CHUNK_SIZE, n_items)
            sim_chunk = cosine_similarity(item_vectors[start:end], self.category_vectors)
            chunk_best = np.argmax(sim_chunk, axis=1)
            best_indices[start:end] = chunk_best
            best_scores[start:end] = sim_chunk[np.arange(end - start), chunk_best]
            del sim_chunk

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
            self.supplier_vec = None
            if getattr(config, 'USE_SUPPLIER', False):
                supp_vec_path = os.path.join(config.OUTPUT_DIR, "vectorizer_supplier_tfidf.joblib")
                if os.path.exists(supp_vec_path):
                    self.supplier_vec = joblib.load(supp_vec_path)
            print(f"  - {embedding_name} Categorizer ready "
                  f"(supplier feats: {len(self.supplier_vec.vocabulary_) if self.supplier_vec else 0}).")
        except Exception as e:
            print(f"\nERROR: loading {embedding_name} category data: {e}")
            raise

    def _encode_with_supplier(self, descs, suppliers):
        """Encode descriptions with BERT, optionally concat supplier TF-IDF.
        Mirrors the combined-vector layout built in 1b_create_text_embeddings.py.
        If suppliers is None but the model was trained with a supplier block,
        fall back to zero-vector supplier columns so shapes still match.
        """
        desc_vectors = self.encoder_model.encode(
            descs, show_progress_bar=True, batch_size=128
        )
        if self.supplier_vec is None:
            return desc_vectors
        if suppliers is None:
            supp_tokens = [''] * len(descs)
        else:
            supp_tokens = _normalize_suppliers(suppliers)
        X_supp = self.supplier_vec.transform(supp_tokens)
        desc_n = normalize(desc_vectors, norm='l2')
        supp_n = normalize(X_supp, norm='l2')
        return hstack([desc_n * config.DESC_WEIGHT,
                       supp_n * config.SUPPLIER_WEIGHT]).tocsr()

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

    def predict_batch(self, descriptions: pd.Series, suppliers=None) -> tuple:
        """Batch-predict categories for an entire Series at once.

        One encoder.encode call (batched internally) + one cosine_similarity
        matmul for all items, replacing N per-row encode calls.

        Returns (predictions, scores, item_vectors).  item_vectors is the
        combined desc+supplier matrix aligned to descriptions.index.
        """
        descs = descriptions.astype(str)
        empty_mask = descs.str.strip() == ''

        item_vectors = self._encode_with_supplier(descs.tolist(), suppliers)

        # Chunk the (N, K) dense similarity matrix so peak memory is
        # (CHUNK, K) instead of (N, K).  Each chunk is still a single
        # vectorized matmul; we just never hold the full thing at once.
        CHUNK_SIZE = 20_000
        n_items = item_vectors.shape[0]
        best_indices = np.empty(n_items, dtype=np.int64)
        best_scores = np.empty(n_items, dtype=np.float64)
        for start in range(0, n_items, CHUNK_SIZE):
            end = min(start + CHUNK_SIZE, n_items)
            sim_chunk = cosine_similarity(item_vectors[start:end], self.category_vectors)
            chunk_best = np.argmax(sim_chunk, axis=1)
            best_indices[start:end] = chunk_best
            best_scores[start:end] = sim_chunk[np.arange(end - start), chunk_best]
            del sim_chunk

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