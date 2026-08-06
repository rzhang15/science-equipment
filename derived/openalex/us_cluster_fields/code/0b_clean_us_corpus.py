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


def flags(lf):
    return lf.with_columns([
        (pl.col("processed_text").str.len_chars() < MIN_CHARS).alias("too_short"),
        pl.col("processed_text").str.contains(BOILER_RE).alias("is_boiler"),
    ])


def main():
    # Two streaming passes (stats, then write) rather than one collect() that
    # holds the whole corpus in memory before writing.
    print(f"Reading {IN_PATH} ...", flush=True)
    s = flags(pl.scan_parquet(IN_PATH)).select([
        pl.len().alias("n0"),
        pl.col("is_boiler").sum().alias("n_boiler"),
        pl.col("too_short").sum().alias("n_short"),
        (pl.col("is_boiler") & pl.col("too_short")).sum().alias("n_both"),
    ]).collect(engine="streaming").row(0, named=True)

    n0, n_keep = s["n0"], s["n0"] - s["n_boiler"] - s["n_short"] + s["n_both"]
    print(f"Loaded: {n0:,} US authors", flush=True)
    print(f"  scraper-boilerplate authors:  {s['n_boiler']:>10,} ({100*s['n_boiler']/n0:.2f}%)")
    print(f"  short text (<{MIN_CHARS} chars):     {s['n_short']:>10,} ({100*s['n_short']/n0:.2f}%)")
    print(f"  overlap (both):               {s['n_both']:>10,}")
    print(f"  keeping                       {n_keep:>10,} / {n0:,} ({100*n_keep/n0:.1f}%)")

    print(f"Writing {OUT_PATH} ...", flush=True)
    (
        flags(pl.scan_parquet(IN_PATH))
        .filter(~pl.col("is_boiler") & ~pl.col("too_short"))
        .select(["athr_id", "processed_text"])
        .sink_parquet(OUT_PATH, compression="zstd")
    )
    print(f"Done. {n_keep:,} rows.")


if __name__ == "__main__":
    sys.exit(main())
