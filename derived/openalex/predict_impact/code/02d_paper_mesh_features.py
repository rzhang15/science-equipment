"""
02d_paper_mesh_features.py

MeSH-based topic-rarity features per paper. Added because the step 03 gain
diagnostic showed the paper features from step 02 (team_size, junior_share,
etc.) contribute only 2-5% of gain -- the model was almost entirely a PI
classifier. Topic rarity gives paper-level variation that team/composition
features lacked, at negligible extra cost since MeSH is already pulled.

Rarity signal
-------------
For each MeSH term we compute two frequency measures:
  term_year_freq       distinct papers with the term in that year
  term_alltime_freq    distinct papers with the term across all years

For each paper we aggregate across its terms:
  n_mesh_terms
  mean_mesh_year_freq          topic mainstream-ness of the paper's mix
  min_mesh_year_freq           rarest term proxy for niche/novel topic
  log_min_mesh_year_freq       log-transform to tighten the tail
  mean_mesh_alltime_freq       long-run analog

Inputs
------
../external/mesh/contracted_gen_mesh_all_jrnls.dta   (paper x term rows)
../temp/papers_all.parquet                            (id -> year)

Output
------
../temp/paper_mesh_features.parquet
"""

import os
import sys
import time

import pandas as pd
import polars as pl

MESH = "../external/mesh/contracted_gen_mesh_all_jrnls.dta"
PAPERS = "../temp/papers_all.parquet"
DST = "../temp/paper_mesh_features.parquet"

CHUNK = 5_000_000


def load_mesh_chunked(path):
    """Return a polars DataFrame with columns [id, gen_mesh]."""
    print(f"reading {path} via pandas chunked Stata reader", flush=True)
    reader = pd.read_stata(
        path,
        chunksize=CHUNK,
        columns=["id", "gen_mesh"],
        convert_categoricals=False,
        convert_dates=False,
    )
    frames = []
    total = 0
    t0 = time.time()
    for i, df in enumerate(reader):
        total += len(df)
        frames.append(pl.from_pandas(df))
        rate = total / max(time.time() - t0, 1e-6)
        print(
            f"   chunk {i}: {len(df):,} rows  (total {total:,}, {rate:,.0f}/s)",
            flush=True,
        )
    return pl.concat(frames) if frames else pl.DataFrame(schema={"id": pl.String, "gen_mesh": pl.String})


def main():
    for path in (MESH, PAPERS):
        if not os.path.exists(path):
            sys.exit(f"ERROR: missing input {path}")

    t0 = time.time()

    print(f"reading paper years from {PAPERS}", flush=True)
    year_map = (
        pl.read_parquet(PAPERS, columns=["id", "year"])
        .unique(subset=["id"])
    )
    print(f"   {year_map.height:,} distinct papers", flush=True)

    mesh = load_mesh_chunked(MESH)
    print(f"   {mesh.height:,} raw paper-mesh rows", flush=True)

    # dedupe: same (paper, term) may repeat across qualifiers
    mesh = mesh.unique(subset=["id", "gen_mesh"])
    print(f"   {mesh.height:,} distinct (paper, term) pairs", flush=True)

    mesh = mesh.join(year_map, on="id", how="inner")
    print(f"   {mesh.height:,} rows after joining year", flush=True)

    print("computing term-year and term-alltime frequencies", flush=True)
    term_year = mesh.group_by(["gen_mesh", "year"]).agg(
        term_year_freq=pl.col("id").n_unique().cast(pl.Int64)
    )
    term_all = mesh.group_by("gen_mesh").agg(
        term_alltime_freq=pl.col("id").n_unique().cast(pl.Int64)
    )

    print("joining frequencies back to paper-term rows", flush=True)
    mesh = mesh.join(term_year, on=["gen_mesh", "year"], how="left")
    mesh = mesh.join(term_all, on="gen_mesh", how="left")

    print("aggregating per paper", flush=True)
    paper_feat = mesh.group_by("id").agg(
        n_mesh_terms=pl.col("gen_mesh").n_unique().cast(pl.Int32),
        mean_mesh_year_freq=pl.col("term_year_freq").mean(),
        min_mesh_year_freq=pl.col("term_year_freq").min(),
        mean_mesh_alltime_freq=pl.col("term_alltime_freq").mean(),
    ).with_columns(
        log_min_mesh_year_freq=(pl.col("min_mesh_year_freq") + 1).log()
    )

    print(f"   {paper_feat.height:,} papers with MeSH features", flush=True)
    print(paper_feat.describe(), flush=True)

    paper_feat.write_parquet(DST, compression="snappy")
    print(f"done in {time.time() - t0:.1f}s", flush=True)


if __name__ == "__main__":
    main()
