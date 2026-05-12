"""
Build an UN-STEMMED FOIA author corpus for BERT validation.

Why this exists: the existing foia_author_text_final.csv is Porter-stemmed
(produced by cluster_fields/code/0_combine_data.py). SPECTER/SciBERT tokenize
real words; stems destroy them. This script rebuilds, for the 188 FOIA authors
only, the same abstract+title+MeSH corpus the upstream script aggregates --
but skipping the stemmer.

Sources (all relative to ../../external/):
  appended/openalex_all_jrnls_merged.dta            paper id, athr_id, pub_date, title  (~61GB)
  appended/contracted_gen_mesh_all_jrnls.dta        paper id, qualifier_name, gen_mesh  (~1.6GB)
  ../../../cluster_fields/output/combined_abstracts.csv   paper id, abstract            (~64GB)

Output: ../../output/foia_author_text_unstemmed.csv  (athr_id, processed_text)
"""
import re
import sys
import time
import pandas as pd
import polars as pl

FOIA_CSV = "../../output/foia_author_text_final.csv"
PAPERS_DTA = "../../external/appended/openalex_all_jrnls_merged.dta"
MESH_DTA = "../../external/appended/contracted_gen_mesh_all_jrnls.dta"
ABSTRACTS_CSV = "/n/home02/cxu75/sci_eq/derived/openalex/cluster_fields/output/combined_abstracts.csv"
OUT_CSV = "../../output/foia_author_text_unstemmed.csv"

CUTOFF_YEAR = 2013
DTA_CHUNK = 500_000  # pandas read_stata chunksize


REGEX_CLEAN = re.compile(r"[^a-z0-9\s]")
REGEX_SPACES = re.compile(r"\s+")


def lc_strip(s: str) -> str:
    if not s:
        return ""
    s = s.lower()
    s = REGEX_CLEAN.sub(" ", s)
    s = REGEX_SPACES.sub(" ", s).strip()
    return s


def main():
    t0 = time.time()
    foia_ids = set(pd.read_csv(FOIA_CSV)["athr_id"].astype(str).tolist())
    print(f"FOIA authors: {len(foia_ids)}", flush=True)

    # 1. Stream the merged papers file, keep only FOIA authors + pre-2014 papers.
    print(f"\n[1] Streaming {PAPERS_DTA}...", flush=True)
    keep_rows: list[pd.DataFrame] = []
    rows_seen = 0
    rows_kept = 0
    reader = pd.read_stata(PAPERS_DTA, chunksize=DTA_CHUNK,
                            columns=["id", "athr_id", "pub_date", "title"])
    for chunk in reader:
        rows_seen += len(chunk)
        chunk["athr_id"] = chunk["athr_id"].astype(str)
        mask = chunk["athr_id"].isin(foia_ids)
        if not mask.any():
            elapsed = time.time() - t0
            print(f"  scanned {rows_seen:,}  kept {rows_kept:,}  "
                  f"({rows_seen/elapsed:,.0f}/s)", flush=True)
            continue
        sub = chunk.loc[mask, ["id", "athr_id", "pub_date", "title"]].copy()
        # filter to pub_year <= CUTOFF_YEAR
        years = sub["pub_date"].astype(str).str.slice(0, 4)
        years = pd.to_numeric(years, errors="coerce")
        sub = sub.loc[years <= CUTOFF_YEAR]
        if len(sub):
            keep_rows.append(sub)
            rows_kept += len(sub)
        elapsed = time.time() - t0
        print(f"  scanned {rows_seen:,}  kept {rows_kept:,}  "
              f"({rows_seen/elapsed:,.0f}/s)", flush=True)

    papers = pd.concat(keep_rows, ignore_index=True)
    print(f"  total kept rows: {len(papers):,}   "
          f"unique paper ids: {papers['id'].nunique():,}   "
          f"unique authors: {papers['athr_id'].nunique()}", flush=True)
    paper_ids = set(papers["id"].astype(str).tolist())

    # 2. Stream abstracts CSV, keep only matching paper ids.
    print(f"\n[2] Streaming {ABSTRACTS_CSV}...", flush=True)
    # Use polars batched CSV reader -- much faster than pandas for huge CSVs.
    abs_rows: list[pl.DataFrame] = []
    n_scanned = 0
    t_abs = time.time()
    reader = pl.read_csv_batched(ABSTRACTS_CSV, batch_size=500_000)
    while True:
        batches = reader.next_batches(1)
        if batches is None:
            break
        for b in batches:
            n_scanned += b.height
            # combined_abstracts uses "id" like "https://openalex.org/W123"
            b = b.with_columns(
                pl.col("id").str.replace("https://openalex.org/", "")
            )
            kept = b.filter(pl.col("id").is_in(list(paper_ids)))
            if kept.height:
                abs_rows.append(kept)
        elapsed = time.time() - t_abs
        print(f"  scanned {n_scanned:,} abstracts  "
              f"({n_scanned/elapsed:,.0f}/s)", flush=True)

    abs_df = pl.concat(abs_rows).to_pandas() if abs_rows else pd.DataFrame(columns=["id", "abstract"])
    print(f"  matched abstracts: {len(abs_df):,}", flush=True)

    # 3. Load MeSH (1.6GB is manageable in one read).
    print(f"\n[3] Loading {MESH_DTA}...", flush=True)
    mesh = pd.read_stata(MESH_DTA, columns=["id", "qualifier_name", "gen_mesh"])
    mesh["id"] = mesh["id"].astype(str)
    mesh = mesh[mesh["id"].isin(paper_ids)]
    print(f"  matched mesh rows: {len(mesh):,}", flush=True)
    mesh["qualifier_name"] = mesh["qualifier_name"].fillna("").astype(str)
    mesh["gen_mesh"] = mesh["gen_mesh"].fillna("").astype(str)
    mesh_agg = (mesh.groupby("id", as_index=False)
                    .agg(paper_qualifiers=("qualifier_name", lambda x: " ".join(x)),
                         paper_mesh=("gen_mesh", lambda x: " ".join(x))))

    # 4. Merge per paper, then aggregate per author.
    print("\n[4] Merging and aggregating per author...", flush=True)
    papers["id"] = papers["id"].astype(str)
    papers["title"] = papers["title"].fillna("").astype(str)
    abs_df["id"] = abs_df["id"].astype(str)
    abs_df["abstract"] = abs_df["abstract"].fillna("").astype(str)

    merged = (papers.merge(abs_df, on="id", how="left")
                    .merge(mesh_agg, on="id", how="left"))
    for c in ["title", "abstract", "paper_qualifiers", "paper_mesh"]:
        if c not in merged:
            merged[c] = ""
        merged[c] = merged[c].fillna("").astype(str)

    # combine title+abstract+qualifiers+mesh and lowercase/strip-punct only.
    merged["paper_text"] = (
        merged["title"] + " " + merged["abstract"] + " "
        + merged["paper_qualifiers"] + " " + merged["paper_mesh"]
    ).map(lc_strip)

    author_text = (merged.groupby("athr_id")["paper_text"]
                          .apply(lambda s: " ".join(t for t in s if t))
                          .reset_index()
                          .rename(columns={"paper_text": "processed_text"}))
    author_text = author_text[author_text["processed_text"].str.len() > 50]
    print(f"  authors with text: {len(author_text)} / {len(foia_ids)}", flush=True)

    # report a sample so user can eyeball it
    print("\nSample:")
    for _, row in author_text.head(2).iterrows():
        snippet = row["processed_text"][:300]
        print(f"  {row['athr_id']}: {snippet!r}")

    author_text.to_csv(OUT_CSV, index=False)
    elapsed = time.time() - t0
    print(f"\nSaved {OUT_CSV}  (total {elapsed/60:.1f} min)")


if __name__ == "__main__":
    sys.exit(main())
