"""
Build per-paper text for SPECTER embedding.

Avoids OOM by:
  - Reading the per-shard .dta files (not the 58GB appended file).
  - Streaming each shard via pd.read_stata(..., chunksize=...) into parquet.
  - Lazy-scanning parquet for the join/dedupe step.

Output:
  ../../output/bert/papers_text.parquet         (id, paper_text)
  ../../output/bert/author_paper_edges.parquet  (athr_id, id, publication_year)
  ../../output/bert/_tmp/<shard>.parquet        (intermediate converted shards)
"""
import os
import glob
import pandas as pd
import polars as pl
import pyarrow as pa
import pyarrow.parquet as pq

CUTOFF_YEAR = 2013
OUT_DIR = "../../output/bert"
TMP_DIR = f"{OUT_DIR}/_tmp"
os.makedirs(TMP_DIR, exist_ok=True)

WORKS_SHARDS = "../../external/appended/openalex_all_jrnls_merged_*.dta"
MESH_SHARDS  = "../../external/appended/contracted_gen_mesh_all_jrnls_*.dta"
WORKS_COLS   = ["id", "athr_id", "pub_date", "title"]
MESH_COLS    = ["id", "qualifier_name", "gen_mesh"]

CHUNK_ROWS = 500_000

REGEX_CLEAN = r"[^a-z0-9\s\-]"
REGEX_SPACES = r"\s+"


def convert_dta_shards(pattern: str, cols: list[str], tag: str) -> list[str]:
    """Convert each .dta shard to a parquet file, streaming in chunks. Idempotent."""
    out_paths = []
    for src in sorted(glob.glob(pattern)):
        base = os.path.basename(src).replace(".dta", "")
        dst = f"{TMP_DIR}/{tag}__{base}.parquet"
        out_paths.append(dst)
        if os.path.exists(dst):
            print(f"  skip (exists): {dst}")
            continue
        print(f"  converting {src} -> {dst}")
        writer = None
        with pd.read_stata(src, chunksize=CHUNK_ROWS, columns=cols) as reader:
            for i, chunk in enumerate(reader):
                table = pa.Table.from_pandas(chunk[cols], preserve_index=False)
                if writer is None:
                    writer = pq.ParquetWriter(dst, table.schema, compression="snappy")
                writer.write_table(table)
                print(f"    chunk {i}: {len(chunk):,} rows", flush=True)
        if writer:
            writer.close()
    return out_paths


print("Converting works shards (id, athr_id, pub_date, title)...")
works_paths = convert_dta_shards(WORKS_SHARDS, WORKS_COLS, "works")

print("Converting mesh shards (id, qualifier_name, gen_mesh)...")
mesh_paths = convert_dta_shards(MESH_SHARDS, MESH_COLS, "mesh")

# ---------------- assemble paper text ----------------

print("Scanning converted works parquet...")
q_works = (
    pl.scan_parquet(works_paths)
    .with_columns(
        pl.col("pub_date").str.slice(0, 4).cast(pl.Int32, strict=False).alias("publication_year")
    )
    .filter(pl.col("publication_year") <= CUTOFF_YEAR)
)

print("Writing author-paper edges...")
edges = (
    q_works.select(["athr_id", "id", "publication_year"]).unique().collect(streaming=True)
)
edges.write_parquet(f"{OUT_DIR}/author_paper_edges.parquet")
print(f"  edges: {len(edges):,}")

q_title = (
    q_works
    .select(["id", "title"])
    .unique(subset=["id"])
    .with_columns(
        pl.col("title").fill_null("").str.to_lowercase()
          .str.replace_all(REGEX_CLEAN, " ")
          .str.replace_all(REGEX_SPACES, " ")
          .str.strip_chars()
          .alias("cleaned_title")
    )
    .select(["id", "cleaned_title"])
)

print("Loading abstracts (streamed)...")
q_abs = (
    pl.scan_csv("../../output/combined_abstracts.csv")
    .with_columns(
        pl.col("id").str.replace("https://openalex.org/", ""),
        pl.col("abstract").fill_null("").str.to_lowercase()
          .str.replace_all(REGEX_CLEAN, " ")
          .str.replace_all(REGEX_SPACES, " ")
          .str.strip_chars()
          .alias("cleaned_abstract")
    )
    .select(["id", "cleaned_abstract"])
    .unique(subset=["id"])
)

print("Aggregating MeSH per paper...")
q_mesh = (
    pl.scan_parquet(mesh_paths)
    .with_columns([
        pl.col("qualifier_name").fill_null("").str.to_lowercase().str.replace_all(r"[^a-z0-9\s]", " "),
        pl.col("gen_mesh").fill_null("").str.to_lowercase().str.replace_all(r"[^a-z0-9\s]", " "),
    ])
    .group_by("id")
    .agg([
        pl.col("qualifier_name").str.concat(" ").alias("paper_qualifiers"),
        pl.col("gen_mesh").str.concat(" ").alias("paper_mesh"),
    ])
)

print("Joining and assembling per-paper text...")
papers_ids = q_works.select("id").unique()

q_paper_text = (
    papers_ids
    .join(q_title, on="id", how="left")
    .join(q_abs, on="id", how="left")
    .join(q_mesh, on="id", how="left")
    .with_columns(
        (
            pl.col("cleaned_title").fill_null("") + ". " +
            pl.col("cleaned_abstract").fill_null("") + " " +
            pl.col("paper_mesh").fill_null("") + " " +
            pl.col("paper_qualifiers").fill_null("")
        ).str.replace_all(REGEX_SPACES, " ").str.strip_chars().alias("paper_text")
    )
    .select(["id", "paper_text"])
    .filter(pl.col("paper_text").str.len_chars() > 30)
)

print("Collecting (streamed)...")
papers = q_paper_text.collect(streaming=True)
print(f"  papers with usable text: {len(papers):,}")
papers.write_parquet(f"{OUT_DIR}/papers_text.parquet")
print(f"Wrote {OUT_DIR}/papers_text.parquet")
