# ────────────────────────────────────────────────────────────────────────────────
# 0.  Imports & config
# ────────────────────────────────────────────────────────────────────────────────
import pandas as pd
import numpy as np
import re, string, os, json, random, gc
from pathlib import Path

# text / ML
from sentence_transformers import SentenceTransformer
import umap
import hdbscan
from sklearn.feature_extraction.text import TfidfVectorizer

SEED = 42
rng   = np.random.default_rng(SEED)

# choose an embedding model that is already downloaded or can be pulled
MODEL_NAME = "allenai/specter2_base"     # good for scientific text
# MODEL_NAME = "allenai/scibert_scivocab_uncased"   # lighter fallback

# ────────────────────────────────────────────────────────────────────────────────
# 1.  Load & clean the three data sets
# ────────────────────────────────────────────────────────────────────────────────
DATA_DIR = Path("../external/samp")

def strip_openalex(x):
    return re.sub(r"https?://openalex\.org/", "", str(x))

# publication meta:  author-affiliation-paper level
pub = pd.read_stata(DATA_DIR / "cleaned_all_15jrnls.dta")
pub["id"]   = pub["id"].map(strip_openalex)
pub["year"] = pub["year"].astype("int")

# restrict to ≥ 2001   (year 2000 = baseline pre-treatment window)
pub = pub.loc[pub["year"] > 2000]

# paper titles
titles = pub[["id", "title"]].drop_duplicates()

# MeSH (long)  – contracted_gen_mesh_15jrnls.dta
mesh_long = pd.read_stata(DATA_DIR / "contracted_gen_mesh_15jrnls.dta")
mesh_long["id"] = mesh_long["id"].map(strip_openalex)

# Abstracts
ab = pd.read_csv("../output/combined_abstracts.csv")
ab["id"] = ab["id"].map(strip_openalex)

# ────────────────────────────────────────────────────────────────────────────────
# 2.  Collapse MeSH terms   (long → one string per id)
# ────────────────────────────────────────────────────────────────────────────────
mesh_long["gen_mesh"] = (
    mesh_long["gen_mesh"]
    .str.lower()
    .str.replace(r"\s+", "_", regex=True)  # make multi-word headings one token
    .str.replace(r"[^\w_]", "", regex=True)
)

mesh_per_paper = (
    mesh_long.groupby("id")["gen_mesh"]
    .apply(lambda x: " ".join(sorted(set(x))))
    .reset_index()
)

# ────────────────────────────────────────────────────────────────────────────────
# 3.  Merge title + abstract + mesh into one text field per paper
# ────────────────────────────────────────────────────────────────────────────────
def clean_text(txt):
    txt = str(txt).lower()
    txt = re.sub(r"\s+", " ", txt)
    txt = txt.translate(str.maketrans("", "", string.punctuation))
    return txt.strip()

titles["title_clean"]   = titles["title"].map(clean_text)
ab["abstract_clean"]    = ab["abstract"].map(clean_text)

papers = (
    titles[["id", "title_clean"]]
    .merge(ab[["id", "abstract_clean"]], on="id", how="left")
    .merge(mesh_per_paper,            on="id", how="left")
)

papers["text"] = (
    papers["title_clean"].fillna("")   + " " +
    papers["abstract_clean"].fillna("")+ " " +
    papers["gen_mesh"].fillna("")
).str.strip()

# ────────────────────────────────────────────────────────────────────────────────
# 4.  Embed papers   (768-D vectors)
# ────────────────────────────────────────────────────────────────────────────────
print("Loading embedding model…")
model = SentenceTransformer(MODEL_NAME, device="cuda" if torch.cuda.is_available() else "cpu")

BATCH = 128
embeddings = model.encode(
    papers["text"].tolist(),
    batch_size=BATCH,
    show_progress_bar=True,
    convert_to_numpy=True,
    normalize_embeddings=True,
)

# ────────────────────────────────────────────────────────────────────────────────
# 5.  UMAP dimensionality reduction  (768 ➜ 50 dims)
# ────────────────────────────────────────────────────────────────────────────────
umap_reducer = umap.UMAP(
    n_neighbors=15,
    n_components=50,
    min_dist=0.0,
    metric="cosine",
    random_state=SEED,
)
X_umap = umap_reducer.fit_transform(embeddings)

# ────────────────────────────────────────────────────────────────────────────────
# 6.  HDBSCAN clustering
# ────────────────────────────────────────────────────────────────────────────────
clusterer = hdbscan.HDBSCAN(
    min_cluster_size=50,   # tweak until granularity looks right
    min_samples=10,
    metric="euclidean",
    cluster_selection_method="eom",
)
papers["cluster"] = clusterer.fit_predict(X_umap)

# ────────────────────────────────────────────────────────────────────────────────
# 7.  Characterise clusters with TF-IDF top terms   (for manual labeling)
# ────────────────────────────────────────────────────────────────────────────────
tfidf = TfidfVectorizer(max_df=0.8, stop_words="english", min_df=5)
tfidf_matrix = tfidf.fit_transform(papers["text"])
terms = np.array(tfidf.get_feature_names_out())

def describe_cluster(k):
    idx = np.where(papers["cluster"] == k)[0]
    if len(idx) == 0:
        return []
    centroid = tfidf_matrix[idx].mean(axis=0).A1
    top = centroid.argsort()[-15:][::-1]
    return terms[top]

cluster_labels = {}
for k in sorted(papers["cluster"].unique()):
    if k == -1:
        continue  # -1 = noise
    cluster_labels[k] = ", ".join(describe_cluster(k)[:8])

papers["cluster_label"] = papers["cluster"].map(cluster_labels).fillna("noise")

# ────────────────────────────────────────────────────────────────────────────────
# 8.  Map papers → authors  (post-2000 only)   … then authors → subfield
# ────────────────────────────────────────────────────────────────────────────────
authors = (
    pub[["id", "athr_id"]]
    .drop_duplicates()
    .merge(papers[["id", "cluster"]], on="id", how="left")
)

author_subfield = (
    authors.groupby("athr_id")["cluster"]
    .agg(lambda x: x.value_counts().idxmax())   # dominant subfield per author
    .reset_index()
)

# optional: attach cluster label text
author_subfield["cluster_label"] = author_subfield["cluster"].map(cluster_labels)

# ────────────────────────────────────────────────────────────────────────────────
# 9.  Save outputs
# ────────────────────────────────────────────────────────────────────────────────
papers.to_parquet("../output/papers_with_clusters.parquet", index=False)
author_subfield.to_csv("../output/author_subfield_mapping.csv", index=False)

print("Done.  #clusters (excl. noise):", len(cluster_labels))
