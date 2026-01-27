import os
import sys
import argparse
import random
import numpy as np
import pandas as pd
import nltk
from nltk.corpus import stopwords
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.cluster import MiniBatchKMeans
import scipy.sparse
import pickle
from nltk.stem import PorterStemmer
from config import stopwords_list

# --- LOAD PRE-SAVED DATA ---
print("Loading Parquet data...")
pdf = pd.read_parquet("../output/cleaned_static_author_text_pre_us.parquet")
pdf = pdf.reset_index(drop=True)

print("Stemming Stopwords to match input data...")
stemmer = PorterStemmer()
stemmed_stopwords = [stemmer.stem(word) for word in stopwords_list]

print("Vectorizing...")
tfidf = TfidfVectorizer(
    stop_words=stemmed_stopwords,
    min_df=15,        
    max_df = 0.1, 
    max_features=30000,
    dtype=np.float32
)

matrix = tfidf.fit_transform(pdf['processed_text'])
print(f"Matrix Shape: {matrix.shape}")

scipy.sparse.save_npz("../output/tfidf_matrix.npz", matrix)
with open("../output/feature_names.pkl", "wb") as f:
    pickle.dump(tfidf.get_feature_names_out(), f)

pdf[['athr_id']].to_parquet("../output/author_ids_aligned.parquet")
