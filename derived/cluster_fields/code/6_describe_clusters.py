#!/usr/bin/env python
"""
6_describe_clusters.py
----------------------
Create human-readable summaries for every HDBSCAN cluster:
  • Top TF-IDF tokens (with extended stop‐words)
  • Most-frequent MeSH terms (if available)
  • Up to three distinct representative titles

Output:  ../output/cluster_summaries.txt
"""

from pathlib import Path
import pandas as pd
import numpy as np
import textwrap
from sklearn.feature_extraction.text import TfidfVectorizer, ENGLISH_STOP_WORDS
from sklearn.metrics.pairwise import cosine_distances

# ────────────────────────────────────────────────────────────────────────
#  0.  Define extended stop‐words for TF‐IDF (to remove institutional noise)
# ────────────────────────────────────────────────────────────────────────
EXTRA_STOP = {
    "university", "department", "center", "centre", "school",
    "institute", "college", "hospital", "medicine", "medical",
    "research", "science", "sciences", "google", "scholar",
    "pubmed", "scopus", "usasearch", "caspubmedweb"
}
COMBINED_STOP = set(ENGLISH_STOP_WORDS).union(EXTRA_STOP)

# ────────────────────────────────────────────────────────────────────────
#  1.  Paths & constants
# ────────────────────────────────────────────────────────────────────────
BASE   = Path(__file__).resolve().parent.parent           # …/cluster_fields
OUT    = BASE / "output"
PAPERS = OUT / "papers_with_clusters.parquet"             # step-4 result
MESHF  = OUT / "mesh_long_stripped.parquet"                # IDs already stripped
DEST   = OUT / "cluster_summaries.txt"

# ────────────────────────────────────────────────────────────────────────
#  2.  Load clustered papers and (optionally) MeSH data
# ────────────────────────────────────────────────────────────────────────
papers = pd.read_parquet(PAPERS)
papers["id"] = papers["id"].astype(str)  # ensure 'id' is string

if MESHF.exists():
    mesh_df = pd.read_parquet(MESHF).copy()
    mesh_df["id"] = mesh_df["id"].astype(str)

    # Detect MeSH‐string column name (first non‐id column) and rename to 'gen_mesh'
    mesh_cols = [c for c in mesh_df.columns if c != "id"]
    mesh_df = mesh_df.rename(columns={mesh_cols[0]: "gen_mesh"})

    # Merge MeSH data into papers
    papers = papers.merge(mesh_df[["id", "gen_mesh"]], on="id", how="left")

    # Coalesce any duplicate 'gen_mesh' columns that may have arisen
    mesh_dup_cols = [c for c in papers.columns if c.startswith("gen_mesh")]
    if len(mesh_dup_cols) > 1:
        # Fill NA in gen_mesh_y with gen_mesh_x, then drop both originals
        papers["gen_mesh"] = papers[mesh_dup_cols].bfill(axis=1).iloc[:, 0]
        papers = papers.drop(columns=mesh_dup_cols)
else:
    papers["gen_mesh"] = np.nan

# ────────────────────────────────────────────────────────────────────────
#  3.  DEBUG: confirm MeSH merge
# ────────────────────────────────────────────────────────────────────────
print("DEBUG – columns after merge:", papers.columns.tolist()[-5:])
print("DEBUG – non-NA gen_mesh rows:", int(papers["gen_mesh"].notna().sum()))

# ────────────────────────────────────────────────────────────────────────
#  4.  Summarise each cluster
# ────────────────────────────────────────────────────────────────────────
summaries = {}

for cid, sub in papers.groupby("cluster"):
    if cid == -1:
        continue  # skip the “noise” cluster

    # ---- 4a. Compute TF-IDF over 'text', excluding combined stop‐words ----
    tf = TfidfVectorizer(
        max_df=0.85,
        min_df=5,
        stop_words=list(COMBINED_STOP),
        token_pattern=r"(?u)\b\w\w+\b"
    )
    X = tf.fit_transform(sub["text"])
    feature_names = tf.get_feature_names_out()
    tok_scores = np.asarray(X.sum(axis=0)).ravel()
    top_tokens = [feature_names[i] for i in tok_scores.argsort()[-15:][::-1]]

    # ---- 4b. Extract top MeSH terms (if any) -------------------------
    top_mesh = []
    mesh_vals = sub["gen_mesh"]
    if mesh_vals.notna().any():
        all_mesh = " ".join(mesh_vals.dropna()).split()
        top_mesh = pd.Series(all_mesh).value_counts().head(15).index.tolist()

    # ---- 4c. Find up to 3 distinct representative titles ------------
    #    Use 'title' if present, else 'title_clean'
    title_col = "title" if "title" in sub.columns else "title_clean"

    centre = X.mean(axis=0).A1  # convert from np.matrix to 1D array
    dists = cosine_distances(X, centre.reshape(1, -1)).ravel()

    sub_sorted = sub.assign(_d=dists).sort_values("_d")
    unique_reps = (
        sub_sorted
        .drop_duplicates(subset=[title_col])
        .head(3)[title_col]
        .apply(lambda t: textwrap.shorten(str(t), width=120))
        .tolist()
    )

    summaries[int(cid)] = {
        "n_papers": len(sub),
        "tokens": top_tokens,
        "mesh": top_mesh,
        "repr_titles": unique_reps
    }

# ────────────────────────────────────────────────────────────────────────
#  5.  Write the summaries to file
# ────────────────────────────────────────────────────────────────────────
with open(DEST, "w") as f:
    for cid in sorted(summaries.keys()):
        info = summaries[cid]
        f.write(f"\n=== Cluster {cid}  (n={info['n_papers']}) ===\n")
        f.write("tokens : " + ", ".join(info["tokens"]) + "\n")
        if info["mesh"]:
            f.write("MeSH   : " + ", ".join(info["mesh"]) + "\n")
        for t in info["repr_titles"]:
            f.write(" • " + t + "\n")

print("✓ wrote", DEST.relative_to(BASE))
