import argparse
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
#
# --keep-authors restricts to a life-science author list before fitting, so
# the vocabulary and IDF weights are refit on the retained corpus rather than
# inherited from a pool that still contains materials/ecology/CS text.
ap = argparse.ArgumentParser()
ap.add_argument("--keep-authors", default=None,
                help="CSV with an athr_id column; restrict the corpus to it.")
ap.add_argument("--suffix", default="",
                help="Appended to output filenames, e.g. _ls.")
args = ap.parse_args()
SUF = args.suffix

print("Loading Parquet data...")
pdf = pd.read_parquet("../output/cleaned_static_author_text_pre_us_v2.parquet")
pdf = pdf.reset_index(drop=True)

if args.keep_authors:
    keep = pd.read_csv(args.keep_authors, dtype={"athr_id": str})["athr_id"].unique()
    n0 = len(pdf)
    pdf = pdf[pdf["athr_id"].astype(str).isin(set(keep))].reset_index(drop=True)
    print(f"Restricted to {args.keep_authors}: {n0:,} -> {len(pdf):,} authors")

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

scipy.sparse.save_npz(f"../output/tfidf_matrix{SUF}.npz", matrix)
with open(f"../output/feature_names{SUF}.pkl", "wb") as f:
    pickle.dump(tfidf.get_feature_names_out(), f)

pdf[['athr_id']].to_parquet(f"../output/author_ids_aligned{SUF}.parquet")
