"""
Clean cleaned_static_author_text_pre.parquet by dropping:

1. Scraper boilerplate authors — text contains unmistakable HTML chrome from
   Google Scholar / Oxford Academic page scraping ("googl scholar",
   "oxford academ", "search work", "toolbar"). ~0.7% of the corpus; visible
   as cluster 74 in the K=100 baseline ("search, googl, scholar, oxford,
   pubm, academ, icon, toolbar, ...").

2. Authors with <MIN_CHARS chars of text. Sample diagnostic: 38% of authors
   have <200 chars (median is 440); these low-content rows can't form a
   meaningful TF-IDF direction and bunch into degenerate dump clusters
   (cluster 33 in the baseline; cluster 0/77/52 absorb the rest as soft
   ties).

Output: cleaned_static_author_text_pre_v2.parquet, consumed by 1_vectorize.py.
"""

import sys
import polars as pl

IN_PATH = "../output/cleaned_static_author_text_pre.parquet"
OUT_PATH = "../output/cleaned_static_author_text_pre_v2.parquet"
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
    print(f"Loaded: {n0:,} authors", flush=True)

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
