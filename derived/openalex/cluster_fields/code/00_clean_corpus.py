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

3. Non-English authors — text lacks the minimum count of English anchor
   stems (may, would, howev, althoug, within, ...). Surfaced as cluster 34
   in the K=100 baseline (Portuguese: pacient, foi, foram, rio, estudo,
   uma, ano, ...). Anchor list is English-only connective / quantifier /
   modal stems that survive PorterStemmer and that NLTK's stopword list
   does not strip. Hits are counted as total word-boundary occurrences in
   the already-stemmed processed_text.

Output: cleaned_static_author_text_pre_v2.parquet, consumed by 1_vectorize.py.
"""

import sys
import polars as pl

IN_PATH = "../output/cleaned_static_author_text_pre.parquet"
OUT_PATH = "../output/cleaned_static_author_text_pre_v2.parquet"
MIN_CHARS = 200
BOILER_RE = "googl scholar|oxford academ|search work|toolbar"

# English anchor stems (post-PorterStemmer). Curated to be:
#   - not in NLTK English stopwords (so they survive 0_combine_data cleaning)
#   - not in academic/clinical/quantitative/bio_scaffolding/unit lists in
#     config.py (which would strip them pre-stem)
#   - high-frequency English connectives/modals/quantifiers that virtually
#     every English-language author text contains multiple times
#   - distinct from common Portuguese/Spanish/French/German tokens
ENGLISH_ANCHOR_STEMS = [
    "may", "might", "could", "would", "should", "well",
    "howev", "althoug", "thu", "henc",
    "much", "mani", "made", "make",
    "long", "old",
    "within", "without", "around",
    "like", "also", "yet", "even", "still",
    "found", "find",
    "non", "show",
]
ANCHOR_RE = r"\b(?:" + "|".join(sorted(set(ENGLISH_ANCHOR_STEMS))) + r")\b"
MIN_ANCHOR_HITS = 2


def main():
    print(f"Reading {IN_PATH} ...", flush=True)
    df = (
        pl.scan_parquet(IN_PATH)
        .with_columns([
            pl.col("processed_text").str.len_chars().alias("n_chars"),
            pl.col("processed_text").str.contains(BOILER_RE).alias("is_boiler"),
            pl.col("processed_text").str.count_matches(ANCHOR_RE).alias("n_anchors"),
        ])
        .collect(engine="streaming")
    )
    n0 = len(df)
    print(f"Loaded: {n0:,} authors", flush=True)

    is_boiler = df["is_boiler"]
    too_short = df["n_chars"] < MIN_CHARS
    non_english = df["n_anchors"] < MIN_ANCHOR_HITS
    keep = ~is_boiler & ~too_short & ~non_english

    print(f"  scraper-boilerplate authors:  {is_boiler.sum():>10,} ({100*is_boiler.sum()/n0:.2f}%)")
    print(f"  short text (<{MIN_CHARS} chars):     {too_short.sum():>10,} ({100*too_short.sum()/n0:.2f}%)")
    print(f"  non-English (<{MIN_ANCHOR_HITS} anchor hits): {non_english.sum():>10,} ({100*non_english.sum()/n0:.2f}%)")
    print(f"  overlap (boiler & short):     {(is_boiler & too_short).sum():>10,}")
    print(f"  overlap (short & non-Eng):    {(too_short & non_english).sum():>10,}")
    print(f"  keeping                       {keep.sum():>10,} / {n0:,} ({100*keep.sum()/n0:.1f}%)")

    # anchor-hit distribution for tuning MIN_ANCHOR_HITS later
    q = df["n_anchors"].quantile
    print(f"  anchor-hit pctiles: 1%={q(0.01):.0f}  5%={q(0.05):.0f}  10%={q(0.10):.0f}  "
          f"25%={q(0.25):.0f}  50%={q(0.50):.0f}  75%={q(0.75):.0f}", flush=True)

    out = df.filter(keep).select(["athr_id", "processed_text"])
    print(f"Writing {OUT_PATH} ...", flush=True)
    out.write_parquet(OUT_PATH)
    print(f"Done. {len(out):,} rows.")


if __name__ == "__main__":
    sys.exit(main())
