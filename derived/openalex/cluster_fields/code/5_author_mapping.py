#!/usr/bin/env python
"""
Step 5 – Collapse paper clusters to one modal sub-field per author
using only 2000-2013 publications.  Output:
../output/author_subfield_mapping.csv
"""

from pathlib import Path
import pandas as pd

# ------------------------------------------------------------------
BASE = Path(__file__).resolve().parent.parent
OUT  = BASE / "output"
PAPERS = OUT / "papers_with_clusters.parquet"     # from step 4
META   = OUT / "pub_filtered.parquet"             # columns id, athr_id
DST    = OUT / "author_subfield_mapping.csv"

# ------------------------------------------------------------------
print("Loading …")
papers = pd.read_parquet(PAPERS)[["id", "cluster"]]
meta   = pd.read_parquet(META)  [["id", "athr_id"]].drop_duplicates()

print("Merging and aggregating …")
auth = (meta.merge(papers, on="id")               # keep only clustered papers
             .groupby("athr_id")["cluster"]
             .agg(lambda s: s.value_counts().idxmax())
             .reset_index())

auth.to_csv(DST, index=False)
print(f"✓ wrote {DST.name}   authors={len(auth)}")
