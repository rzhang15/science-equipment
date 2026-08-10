import numpy as np
import pandas as pd
import scipy.sparse
import pickle
from sklearn.feature_extraction.text import TfidfVectorizer
from nltk.stem import PorterStemmer
from config import stopwords_list

# --- LOAD PRE-SAVED DATA ---
# Reads the cleaned US corpus (v2) written by 0b_clean_us_corpus.py:
#   - scraper-boilerplate authors dropped
#   - authors with <200 chars of text dropped
# The tfidf pipeline in foia_similarity_wts reads the same v2 file so the
# clustering universe and the tfidf universe are identical.
print("Loading Parquet data...")
pdf = pd.read_parquet("../output/cleaned_static_author_text_pre_us_v2.parquet")
pdf = pdf.reset_index(drop=True)

print("Stemming Stopwords to match input data...")
stemmer = PorterStemmer()
stemmed_stopwords = [stemmer.stem(word) for word in stopwords_list]

print("Vectorizing...")
# Text is already whitespace-tokenized, lowercased, and Porter-stemmed by
# cluster_fields/0_combine_data.py. Skipping sklearn's default regex
# tokenizer (via tokenizer=str.split + token_pattern=None + lowercase=False)
# cuts this step ~2-3x. Mirrors cluster_fields/1_vectorize.py.
tfidf = TfidfVectorizer(
    tokenizer=str.split,
    token_pattern=None,
    lowercase=False,
    stop_words=stemmed_stopwords,
    min_df=15,
    max_df=0.1,
    max_features=30000,
    dtype=np.float32,
)

matrix = tfidf.fit_transform(pdf['processed_text'])
print(f"Matrix Shape: {matrix.shape}")

scipy.sparse.save_npz("../output/tfidf_matrix.npz", matrix)
with open("../output/feature_names.pkl", "wb") as f:
    pickle.dump(tfidf.get_feature_names_out(), f)

pdf[['athr_id']].to_parquet("../output/author_ids_aligned.parquet")
