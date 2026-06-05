"""
Aggregate paper-cluster labels into per-author field distributions.

Output:
  ../../output/bert/author_field_dist_K{K}.parquet
    columns: athr_id, n_papers, modal_cluster, modal_share, entropy,
             top1_cluster, top1_share, top2_cluster, top2_share, top3_cluster, top3_share

  ../../output/bert/author_field_shares_K{K}_long.parquet
    columns: athr_id, cluster_label, share        (only nonzero rows)

  ../../output/bert/cluster_descriptions_K{K}.txt
    Top TF-IDF terms over the per-cluster pooled paper text + 5 example titles.
"""
import argparse
import numpy as np
import polars as pl
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer

OUT_DIR = "../../output/bert"

parser = argparse.ArgumentParser()
parser.add_argument("--clusters", type=int, required=True)
args = parser.parse_args()
K = args.clusters

print(f"--- AGGREGATE TO AUTHORS: K={K} ---")

print("Loading edges + clusters...")
edges = pl.read_parquet(f"{OUT_DIR}/author_paper_edges.parquet")
clusters = pl.read_parquet(f"{OUT_DIR}/paper_clusters_K{K}.parquet")

joined = edges.join(clusters, on="id", how="inner")
print(f"  author-paper rows with cluster: {len(joined):,}")

# Per-(author, cluster) counts.
counts = (
    joined.group_by(["athr_id", "cluster_label"])
    .agg(pl.len().alias("n"))
)
author_totals = counts.group_by("athr_id").agg(pl.col("n").sum().alias("n_papers"))
shares = (
    counts.join(author_totals, on="athr_id")
    .with_columns((pl.col("n") / pl.col("n_papers")).alias("share"))
)

shares.select(["athr_id", "cluster_label", "share"]).write_parquet(
    f"{OUT_DIR}/author_field_shares_K{K}_long.parquet"
)

print("Computing per-author summary (modal, entropy, top-3)...")
pdf = shares.to_pandas()

def per_author(g):
    s = g.sort_values("share", ascending=False)
    H = -(s["share"] * np.log(s["share"].clip(lower=1e-12))).sum()
    out = {"n_papers": int(g["n"].sum()), "entropy": float(H)}
    for i in range(3):
        if i < len(s):
            out[f"top{i+1}_cluster"] = int(s.iloc[i]["cluster_label"])
            out[f"top{i+1}_share"]   = float(s.iloc[i]["share"])
        else:
            out[f"top{i+1}_cluster"] = -1
            out[f"top{i+1}_share"]   = 0.0
    out["modal_cluster"] = out["top1_cluster"]
    out["modal_share"]   = out["top1_share"]
    return pd.Series(out)

summary = pdf.groupby("athr_id").apply(per_author).reset_index()
pl.from_pandas(summary).write_parquet(f"{OUT_DIR}/author_field_dist_K{K}.parquet")
print(f"  authors: {len(summary):,}")

# --- Cluster descriptions ---
print("Building cluster descriptions...")
papers_text = pl.read_parquet(f"{OUT_DIR}/papers_text.parquet")
title_proxy = (
    papers_text.with_columns(pl.col("paper_text").str.slice(0, 160).alias("snippet"))
    .join(clusters, on="id", how="inner")
)

# Top TF-IDF terms per cluster (pooled paper_text per cluster).
pooled = (
    papers_text.join(clusters, on="id", how="inner")
    .group_by("cluster_label")
    .agg(pl.col("paper_text").str.concat(" ").alias("blob"))
    .sort("cluster_label")
    .to_pandas()
)
vec = TfidfVectorizer(stop_words="english", min_df=2, max_df=0.6,
                      ngram_range=(1, 2), max_features=50000)
M = vec.fit_transform(pooled["blob"])
features = np.array(vec.get_feature_names_out())

# Example titles per cluster (first 5 papers, by id order).
ex = (
    title_proxy.group_by("cluster_label")
    .agg(pl.col("snippet").head(5).alias("examples"))
    .sort("cluster_label")
    .to_pandas()
)

with open(f"{OUT_DIR}/cluster_descriptions_K{K}.txt", "w") as f:
    for i in range(len(pooled)):
        row = M.getrow(i).toarray().ravel()
        top = features[row.argsort()[-15:][::-1]]
        examples = ex.iloc[i]["examples"] if i < len(ex) else []
        f.write(f"Cluster {i}\n  terms: {', '.join(top)}\n")
        for s in examples[:3]:
            f.write(f"    - {s}\n")
        f.write("\n")

print("Done.")
