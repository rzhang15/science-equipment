"""
Clean cleaned_static_author_text_pre_us.parquet by dropping:

1. Scraper boilerplate authors — text contains unmistakable HTML chrome from
   Google Scholar / Oxford Academic page scraping.
2. Authors with <MIN_CHARS chars of text — too little content to form a
   meaningful TF-IDF direction; end up in degenerate dump clusters.

Mirrors cluster_fields/00_clean_corpus.py but runs on the US-only subset
so the same population feeds both the clustering (2_cluster.py) and the
foia_similarity_wts tfidf pipeline universe.

Output: cleaned_static_author_text_pre_us_v2.parquet
"""
import sys
import polars as pl

IN_PATH = "../output/cleaned_static_author_text_pre_us.parquet"
OUT_PATH = "../output/cleaned_static_author_text_pre_us_v2.parquet"
MIN_CHARS = 200
BOILER_RE = "googl scholar|oxford academ|search work|toolbar"


def main():
    print(f"Reading {IN_PATH} ...", flush=True)
    df = (
        pl.scan_parquet(IN_PATH)
        .with_columns([
            pl.col("processed_text").str.len_chars().alias("n_chars"),
            pl.col("processed_text").str.contains(BOILER_RE).alias("is_boiler"),
        ])
        .collect(engine="streaming")
    )
    n0 = len(df)
    print(f"Loaded: {n0:,} US authors", flush=True)

    is_boiler = df["is_boiler"]
    too_short = df["n_chars"] < MIN_CHARS
    keep = ~is_boiler & ~too_short

    print(f"  scraper-boilerplate authors:  {is_boiler.sum():>10,} ({100*is_boiler.sum()/n0:.2f}%)")
    print(f"  short text (<{MIN_CHARS} chars):     {too_short.sum():>10,} ({100*too_short.sum()/n0:.2f}%)")
    print(f"  overlap (both):               {(is_boiler & too_short).sum():>10,}")
    print(f"  keeping                       {keep.sum():>10,} / {n0:,} ({100*keep.sum()/n0:.1f}%)")

    out = df.filter(keep).select(["athr_id", "processed_text"])
    print(f"Writing {OUT_PATH} ...", flush=True)
    out.write_parquet(OUT_PATH)
    print(f"Done. {len(out):,} rows.")


if __name__ == "__main__":
    sys.exit(main())
