import os
import re
import sys
import time
import multiprocessing as mp
import pandas as pd
import polars as pl
from nltk.stem import PorterStemmer

sys.path.insert(0, "/n/home02/cxu75/sci_eq/derived/openalex/cluster_fields/code")
from config import stopwords_set  # noqa: E402

EDGES = "/n/home02/cxu75/sci_eq/derived/openalex/cluster_fields/output/bert/author_paper_edges.parquet"
PAPERS = "/n/home02/cxu75/sci_eq/derived/openalex/cluster_fields/output/bert/papers_text.parquet"
FOIA_PAPERS_DTA = "/n/home02/cxu75/sci_eq/derived/openalex/get_coauthors/temp/relevant_pprs.dta"
COAUTHORS_DTA = "../external/coauthors/coauthors.dta"
OUT_CSV = "../output/coauthor_text_stemmed.csv"

REGEX_SPACES = re.compile(r"\s+")
_stemmer = PorterStemmer()

def clean_and_stem(text: str) -> str:
    if not text or len(text) < 5:
        return ""
    return " ".join(
        _stemmer.stem(t) for t in text.split()
        if len(t) > 2 and not t.isdigit() and t not in stopwords_set
    )

def main():
    t0 = time.time()

    foia_paper_ids = pd.read_stata(FOIA_PAPERS_DTA)["id"].astype(str).tolist()
    print(f"FOIA papers (to exclude): {len(foia_paper_ids):,}")

    coauthor_ids = (
        pd.read_stata(COAUTHORS_DTA)["coauthor_id"].astype(str).unique().tolist()
    )
    print(f"Unique coauthors: {len(coauthor_ids):,}")

    print("Filtering coauthor edges (excluding FOIA papers)...")
    edges = (
        pl.scan_parquet(EDGES)
        .filter(pl.col("athr_id").is_in(coauthor_ids))
        .filter(~pl.col("id").is_in(foia_paper_ids))
        .select(["athr_id", "id"])
        .unique()
        .collect(streaming=True)
    )
    print(f"  coauthor edges after exclusion: {len(edges):,}")
    print(f"  coauthors with >=1 non-joint paper: {edges['athr_id'].n_unique():,}")

    needed_ids = edges["id"].unique().to_list()
    print(f"Loading paper text for {len(needed_ids):,} papers...")
    papers = (
        pl.scan_parquet(PAPERS)
        .filter(pl.col("id").is_in(needed_ids))
        .collect(streaming=True)
    )
    print(f"  paper texts loaded: {len(papers):,}")

    print("Joining and aggregating raw text per coauthor...")
    df = (
        edges.join(papers, on="id", how="inner")
        .group_by("athr_id")
        .agg(pl.col("paper_text").str.join(" ").alias("raw_text"))
        .to_pandas()
    )
    df["raw_text"] = (
        df["raw_text"].fillna("").astype(str)
        .map(lambda s: REGEX_SPACES.sub(" ", s).strip())
    )
    print(f"  authors before stemming: {len(df):,}")

    n_workers = int(os.environ.get("SLURM_CPUS_PER_TASK", mp.cpu_count() or 1))
    n_workers = max(1, n_workers - 1)
    texts = df["raw_text"].tolist()
    chunksize = max(200, len(texts) // (n_workers * 16))
    print(f"Porter-stemming ({n_workers} workers, chunksize={chunksize:,})...")
    with mp.Pool(n_workers) as pool:
        df["processed_text"] = pool.map(clean_and_stem, texts, chunksize=chunksize)
    del texts

    before = len(df)
    df = df[df["processed_text"].str.len() > 50]
    print(f"  authors with usable stemmed text: {len(df):,} (dropped {before - len(df):,})")

    print("\nSample:")
    for _, row in df.head(2).iterrows():
        print(f"  {row['athr_id']}: {row['processed_text'][:200]!r}...")

    df[["athr_id", "processed_text"]].to_csv(OUT_CSV, index=False)
    print(f"\nSaved {OUT_CSV}  ({time.time() - t0:.1f}s)")

if __name__ == "__main__":
    main()
