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
MIN_DF = 150
SAMPLE_SIZE = 500_000  # Cap fit() corpus at this many docs; transform() still runs on the full universe

# --- LOAD DATA ---
print("Loading Universe Data...")
df_universe = pd.read_parquet(UNIVERSE_PATH, columns=['athr_id', 'processed_text'])
print(f"Total authors loaded: {df_universe['athr_id'].nunique()}")

# 1. CLEANING: Ensure string and handle NaNs (single strip pass)
df_universe['processed_text'] = df_universe['processed_text'].fillna("").astype(str).str.strip()

# 2. FILTERING: Drop authors with empty text
print("Filtering empty text...")
initial_count = len(df_universe)
df_universe = df_universe[df_universe['processed_text'].str.len() > 0].reset_index(drop=True)
final_count = len(df_universe)

print(f"Dropped {initial_count - final_count} authors with no text.")
print(f"Final Universe Size: {final_count}")

# Load FOIA Data
print("Loading FOIA Data...")
df_foia = pd.read_csv(FOIA_PATH)
df_foia['processed_text'] = df_foia['processed_text'].fillna("").astype(str)

# --- VECTORIZATION ---
# tokenizer=str.split + token_pattern=None bypasses sklearn's regex tokenizer
# (processed_text is already cleaned/whitespace-tokenized upstream).
print("Vectorizing...")
tfidf = TfidfVectorizer(
    min_df=MIN_DF,
    max_df=0.05,
    max_features=MAX_FEATURES,
    ngram_range=(1, 2),
    dtype=np.float32,
    norm='l2',
    tokenizer=str.split,
    token_pattern=None,
)

# Fit vocabulary on a sample if the universe is huge, then transform the full universe.
# min_df is scaled proportionally so the document-frequency cutoff matches the full-fit behavior.
if final_count > SAMPLE_SIZE:
    sample_min_df = max(1, int(round(MIN_DF * SAMPLE_SIZE / final_count)))
    print(f"Fitting vocabulary on {SAMPLE_SIZE:,}-row sample (min_df={sample_min_df})...")
    tfidf.set_params(min_df=sample_min_df)
    sample_texts = df_universe['processed_text'].sample(n=SAMPLE_SIZE, random_state=42).tolist()
    tfidf.fit(sample_texts)
    del sample_texts
    print("Transforming full universe...")
    matrix_universe = tfidf.transform(df_universe['processed_text'].tolist())
else:
    matrix_universe = tfidf.fit_transform(df_universe['processed_text'].tolist())

print(f"Universe Matrix Shape: {matrix_universe.shape}")

matrix_foia = tfidf.transform(df_foia['processed_text'].tolist())
print(f"FOIA Matrix Shape: {matrix_foia.shape}")

# --- SAVE ARTIFACTS ---
print("Saving Sparse Matrices...")
scipy.sparse.save_npz(f"{OUTPUT_DIR}tfidf_universe.npz", matrix_universe)
scipy.sparse.save_npz(f"{OUTPUT_DIR}tfidf_foia.npz", matrix_foia)

print("Saving ID Lists...")
df_universe[['athr_id']].to_parquet(f"{OUTPUT_DIR}universe_ids.parquet", index=False)
df_foia[['athr_id']].to_csv(f"{OUTPUT_DIR}foia_ids_ordered.csv", index=False)

print("Vectorization Complete.")
print("Saving Feature Names (Vocabulary)...")
with open(f"{OUTPUT_DIR}feature_names.pkl", "wb") as f:
    pickle.dump(tfidf.get_feature_names_out(), f)
