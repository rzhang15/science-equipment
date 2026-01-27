import os
import re
import random
import numpy as np
import pandas as pd
import polars as pl
import nltk
from nltk.corpus import stopwords
from nltk.stem import PorterStemmer
from config import stopwords_set
# --- SETUP ---
nltk.download("stopwords", quiet=True)
SEED = 42
random.seed(SEED)
np.random.seed(SEED)
stemmer = PorterStemmer()

# --- CONFIGURATION ---
REGEX_CLEAN = r"[^a-z0-9\s]" 
REGEX_SPACES = r"\s+"
CUTOFF_YEAR = 2013

# --- LOAD DATA ---
print("Loading Master ID List...")
pd_samp = pd.read_stata("../external/appended/openalex_all_jrnls_merged.dta")

df_base = pl.from_pandas(pd_samp).lazy()

q_master_list = (
    df_base
    .select(["id", "athr_id", "pub_date"])
    .with_columns(
        pl.col("pub_date")
        .str.slice(0, 4)                 # Take "1991" from "1991-09-23"
        .cast(pl.Int32, strict=False)    # Convert to Number
        .alias("publication_year")       # Rename to your target column
    )
    .filter(pl.col("publication_year") <= CUTOFF_YEAR)
    .select(["id", "athr_id"])           # Keep only what we need for the join
    .unique()
)

print("Configuring Abstracts...")
q_abstracts = (
    pl.scan_csv("../output/combined_abstracts.csv")
    .with_columns(
        pl.col("id").str.replace("https://openalex.org/", ""),
        pl.col("abstract").str.to_lowercase()
        .str.replace_all(REGEX_CLEAN, " ")
        .str.replace_all(REGEX_SPACES, " ")
        .str.strip_chars()
        .alias("cleaned_abstract")
    )
    .select(["id", "cleaned_abstract"]) 
)

print("Configuring Titles...")
q_titles = (
    df_base
    .select(["id", "title"])
    .unique()
    .with_columns(
        pl.col("title").str.to_lowercase()
        .str.replace_all(REGEX_CLEAN, " ")
        .str.replace_all(REGEX_SPACES, " ")
        .str.strip_chars()
        .alias("cleaned_title")
    )
    .select(["id", "cleaned_title"])
)

print("Configuring MeSH Sets...")
pd_mesh = pd.read_stata("../external/appended/contracted_gen_mesh_all_jrnls.dta")
q_mesh_raw = pl.from_pandas(pd_mesh).lazy()

q_mesh_agg = (
    q_mesh_raw
    .with_columns([
        pl.col("qualifier_name").str.to_lowercase().str.replace_all(REGEX_CLEAN, "_").fill_null(""),
        pl.col("gen_mesh").str.to_lowercase().str.replace_all(REGEX_CLEAN, "_").fill_null("")
    ])
    .group_by("id")
    .agg([
        pl.col("qualifier_name").str.concat(" ").alias("paper_qualifiers"),
        pl.col("gen_mesh").str.concat(" ").alias("paper_mesh")
    ])
)

print("Merging all text data onto Master List...")

q_full_data = (
    q_master_list
    .join(q_abstracts, on="id", how="left")  
    .join(q_titles, on="id", how="left")     
    .join(q_mesh_agg, on="id", how="left")   
)

print("Aggregating TOTAL career text by Author (Static Measure)...")

q_static_corpus = (
    q_full_data
    .group_by("athr_id")
    .agg([
        (
            pl.col("cleaned_abstract").fill_null("") + " " +
            pl.col("cleaned_title").fill_null("") + " " +
            pl.col("paper_qualifiers").fill_null("") + " " +
            pl.col("paper_mesh").fill_null("")
        ).str.concat(" ").alias("full_text_lifetime")
    ])
)

df_lifetime = q_static_corpus.collect(streaming=True)
print(f"Total Unique Authors to Cluster: {len(df_lifetime)}")

pdf = df_lifetime.to_pandas()

print("Applying Stemming (Single Core)...")
def clean_and_stem(text):
    if not text or len(text) < 5: return ""
    tokens = text.split()
    tokens = [
        stemmer.stem(t) for t in tokens 
        if len(t) > 2 and not t.isdigit() and t not in custom_stopwords_set
    ]
    return " ".join(tokens)

pdf['processed_text'] = pdf['full_text_lifetime'].apply(clean_and_stem)

pdf = pdf[pdf['processed_text'].str.len() > 50] 

print("Saving pre-clustered text data (Parquet)...")
pdf[['athr_id', 'processed_text']].to_parquet("../output/cleaned_static_author_text_pre.parquet", index=False)