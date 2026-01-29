import pandas as pd
import numpy as np
import scipy.sparse
import pickle
from sklearn.feature_extraction.text import TfidfVectorizer
from config import stopwords_list

# --- CONFIGURATION ---
UNIVERSE_PATH = "../external/us_appended_text/cleaned_static_author_text_pre_us.parquet"
FOIA_PATH = "../output/foia_author_text_final.csv"
OUTPUT_DIR = "../output/"
MAX_FEATURES = 5000

# --- LOAD DATA ---
print("Loading Universe Data...")
df_universe = pd.read_parquet(UNIVERSE_PATH)
print(f"Total authors loaded: {df_universe['athr_id'].nunique()}")

# 1. CLEANING: Ensure string and handle NaNs
df_universe['processed_text'] = df_universe['processed_text'].astype(str).fillna("")

# 2. FILTERING: Drop authors with empty text
# We strip() to remove text that is just spaces like " "
print("Filtering empty text...")
initial_count = len(df_universe)
df_universe = df_universe[df_universe['processed_text'].str.strip() != ""]
final_count = len(df_universe)

print(f"Dropped {initial_count - final_count} authors with no text.")
print(f"Final Universe Size: {final_count}")

# Load FOIA Data
print("Loading FOIA Data...")
df_foia = pd.read_csv(FOIA_PATH)
df_foia['processed_text'] = df_foia['processed_text'].astype(str).fillna("")

# --- VECTORIZATION ---
print("Vectorizing...")
tfidf = TfidfVectorizer(
    min_df=150, 
    max_df=0.05, 
    max_features=MAX_FEATURES, 
    ngram_range=(1, 5), 
    dtype=np.float32,
    norm='l2' 
)

# Fit on the universe (now only valid authors)
matrix_universe = tfidf.fit_transform(df_universe['processed_text'])
print(f"Universe Matrix Shape: {matrix_universe.shape}")

matrix_foia = tfidf.transform(df_foia['processed_text'])
print(f"FOIA Matrix Shape: {matrix_foia.shape}")

# --- SAVE ARTIFACTS ---
print("Saving Sparse Matrices...")
scipy.sparse.save_npz(f"{OUTPUT_DIR}tfidf_universe.npz", matrix_universe)
scipy.sparse.save_npz(f"{OUTPUT_DIR}tfidf_foia.npz", matrix_foia)

print("Saving ID Lists...")
# CRITICAL: This now saves only the IDs of the authors who survived the filter
df_universe[['athr_id']].to_parquet(f"{OUTPUT_DIR}universe_ids.parquet", index=False)
df_foia[['athr_id']].to_csv(f"{OUTPUT_DIR}foia_ids_ordered.csv", index=False)

print("Vectorization Complete.")