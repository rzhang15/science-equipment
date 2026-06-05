"""
Build an UN-STEMMED FOIA author corpus for BERT validation.

Reads the pre-stem parquet dumped by cluster_fields/code/0_combine_data.py
(written at the q_static_corpus collect step, before Porter stemming) and
filters it to the 188 FOIA authors. SPECTER/SciBERT tokenize real words, so
we need the unstemmed text.

Input:  ../../../cluster_fields/output/author_text_unstemmed.parquet
        ../../output/foia_author_text_final.csv   (FOIA athr_id list)
Output: ../../output/foia_author_text_unstemmed.csv  (athr_id, processed_text)
"""
import re
import sys
import time
import pandas as pd
import polars as pl

FOIA_CSV = "../../output/foia_author_text_final.csv"
UNSTEMMED_PARQUET = "/n/home02/cxu75/sci_eq/derived/openalex/cluster_fields/output/author_text_unstemmed.parquet"
OUT_CSV = "../../output/foia_author_text_unstemmed.csv"

REGEX_SPACES = re.compile(r"\s+")


def main():
    t0 = time.time()
    foia_ids = set(pd.read_csv(FOIA_CSV)["athr_id"].astype(str).tolist())
    print(f"FOIA authors: {len(foia_ids)}", flush=True)

    print(f"Scanning {UNSTEMMED_PARQUET}...", flush=True)
    df = (
        pl.scan_parquet(UNSTEMMED_PARQUET)
        .with_columns(pl.col("athr_id").cast(pl.Utf8))
        .filter(pl.col("athr_id").is_in(list(foia_ids)))
        .collect()
        .to_pandas()
    )
    print(f"  matched authors: {len(df)} / {len(foia_ids)}", flush=True)

    df = df.rename(columns={"full_text_lifetime": "processed_text"})
    df["processed_text"] = (
        df["processed_text"].fillna("").astype(str)
        .map(lambda s: REGEX_SPACES.sub(" ", s).strip())
    )
    df = df[df["processed_text"].str.len() > 50]
    print(f"  authors with text: {len(df)}", flush=True)

    print("\nSample:")
    for _, row in df.head(2).iterrows():
        snippet = row["processed_text"][:300]
        print(f"  {row['athr_id']}: {snippet!r}")

    df[["athr_id", "processed_text"]].to_csv(OUT_CSV, index=False)
    print(f"\nSaved {OUT_CSV}  ({time.time() - t0:.1f}s)")


if __name__ == "__main__":
    sys.exit(main())
