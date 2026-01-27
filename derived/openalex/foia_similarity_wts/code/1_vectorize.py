import pandas as pd
import numpy as np
import scipy.sparse
import pickle
from sklearn.feature_extraction.text import TfidfVectorizer
from nltk.stem import PorterStemmer
from config import stopwords_list

# --- CONFIGURATION ---
UNIVERSE_PATH = "../external/appended_text/cleaned_static_author_text_pre.parquet"
FOIA_PATH = "../output/foia_author_text_final.csv"

OUTPUT_DIR = "../output/"
MAX_FEATURES = 30000

# --- LOAD DATA ---
print("Loading Universe Data (15M Authors)...")
df_universe = pd.read_parquet(UNIVERSE_PATH)
# Ensure string type
df_universe['processed_text'] = df_universe['processed_text'].astype(str).fillna("")

print("Loading FOIA Data (Training PIs)...")
df_foia = pd.read_csv(FOIA_PATH)
df_foia['processed_text'] = df_foia['processed_text'].astype(str).fillna("")

tfidf = TfidfVectorizer(
    min_df=15, 
    max_df=0.1, 
    max_features=MAX_FEATURES, 
    dtype=np.float32,
    norm='l2' 
)
matrix_universe = tfidf.fit_transform(df_universe['processed_text'])
print(f"Universe Matrix Shape: {matrix_universe.shape}")

matrix_foia = tfidf.transform(df_foia['processed_text'])
print(f"FOIA Matrix Shape: {matrix_foia.shape}")

# --- SAVE ARTIFACTS ---
print("Saving Sparse Matrices...")
scipy.sparse.save_npz(f"{OUTPUT_DIR}tfidf_universe.npz", matrix_universe)
scipy.sparse.save_npz(f"{OUTPUT_DIR}tfidf_foia.npz", matrix_foia)

print("Saving ID Lists...")
# We need these to map the matrix rows back to actual IDs later
df_universe[['athr_id']].to_parquet(f"{OUTPUT_DIR}universe_ids.parquet", index=False)
df_foia[['athr_id']].to_csv(f"{OUTPUT_DIR}foia_ids_ordered.csv", index=False)

print("Vectorization Complete.")