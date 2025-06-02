#!/usr/bin/env python
"""
Step 4 – Reduce 768-d SPECTER-2 embeddings with UMAP and
cluster with HDBSCAN.  Writes ../output/papers_with_clusters.parquet
"""

from pathlib import Path
import numpy as np
import pandas as pd
import umap, hdbscan

# ------------------------------------------------------------------
BASE = Path(__file__).resolve().parent.parent      # …/cluster_fields
OUT  = BASE / "output"
TEXT = OUT / "paper_text.parquet"                  # from step 2
EMB  = OUT / "embeddings.npy"                      # from step 3
DST  = OUT / "papers_with_clusters.parquet"

# ------------------------------------------------------------------
print("Loading embeddings …")
X   = np.load(EMB)                                 # shape (N, 768)
df  = pd.read_parquet(TEXT)                        # has 'id' & 'text'

print("UMAP reducing → 50 d …")
um  = umap.UMAP(n_neighbors=15,
                n_components=50,
                min_dist=0.0,
                metric="cosine",
                random_state=42)
Xr  = um.fit_transform(X)                          # shape (N, 50)

print("HDBSCAN clustering …")
cl = hdbscan.HDBSCAN(min_cluster_size=50,
                     min_samples=10,
                     metric="euclidean",
                     cluster_selection_method="eom")
labels = cl.fit_predict(Xr)                        # −1 = noise

df["cluster"] = labels
df.to_parquet(DST, index=False)

n_clusters = len(set(labels)) - (1 if -1 in labels else 0)
print(f"✓ wrote {DST.name}   clusters={n_clusters}   noise={(labels==-1).sum()}")
