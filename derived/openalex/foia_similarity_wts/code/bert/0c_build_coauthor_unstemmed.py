import re
import time
import pandas as pd
import polars as pl

EDGES = "/n/home02/cxu75/sci_eq/derived/openalex/cluster_fields/output/bert/author_paper_edges.parquet"
PAPERS = "/n/home02/cxu75/sci_eq/derived/openalex/cluster_fields/output/bert/papers_text.parquet"
FOIA_PAPERS_DTA = "/n/home02/cxu75/sci_eq/derived/openalex/get_coauthors/temp/relevant_pprs.dta"
COAUTHORS_DTA = "../../external/coauthors/coauthors.dta"
OUT_CSV = "../../output/coauthor_text_unstemmed.csv"

REGEX_SPACES = re.compile(r"\s+")


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

    print("Joining and aggregating per coauthor...")
    df = (
        edges.join(papers, on="id", how="inner")
        .group_by("athr_id")
        .agg(pl.col("paper_text").str.join(" ").alias("processed_text"))
        .to_pandas()
    )

    df["processed_text"] = (
        df["processed_text"].fillna("").astype(str)
        .map(lambda s: REGEX_SPACES.sub(" ", s).strip())
    )
    before = len(df)
    df = df[df["processed_text"].str.len() > 50]
    print(f"  authors with usable text: {len(df):,} (dropped {before - len(df):,})")

    print("\nSample:")
    for _, row in df.head(2).iterrows():
        print(f"  {row['athr_id']}: {row['processed_text'][:200]!r}...")

    df[["athr_id", "processed_text"]].to_csv(OUT_CSV, index=False)
    print(f"\nSaved {OUT_CSV}  ({time.time() - t0:.1f}s)")


if __name__ == "__main__":
    main()
