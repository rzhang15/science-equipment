"""
00_convert_papers_to_parquet.py

One-time chunked conversion of the 59 GB paper-author Stata file to parquet so
the rest of the predict_impact pipeline can stream it with polars/pyarrow.

Input
-----
../external/ls_samp/cleaned_last20yrs_all_jrnls.dta

Outputs
-------
../temp/papers_all.parquet            -- full file, KEEP_COLS only, snappy
../temp/papers_2010_2019.parquet      -- year in [2010, 2019] subset

Why chunked: 59 GB does not fit in RAM. Using pandas.read_stata with
chunksize -- it streams the file with per-chunk memory bounded by
chunksize x n_cols. pyreadstat was rejected here because libreadstat
allocates per-column string buffers proportional to total row count even on
metadataonly reads, which OOMs on this file.

Each chunk is appended through a single ParquetWriter so the destination is
a single file with one snappy footer.

Run once (~1-2 h with pandas; slower than pyreadstat but memory-stable).
All downstream scripts read parquet.
"""

import os
import sys
import time

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

SRC = "../external/ls_samp/cleaned_last20yrs_all_jrnls.dta"
DST_ALL = "../temp/papers_all.parquet"
DST_WIN = "../temp/papers_2010_2019.parquet"

KEEP_COLS = [
    "id",
    "pmid",
    "athr_id",
    "which_athr",
    "year",
    "jrnl",
    "cite_count",
    "avg_cite_yr",
    "affl_wt",
    "cite_affl_wt",
    "inst_id",
]

CHUNK = 5_000_000


def main():
    os.makedirs("../temp", exist_ok=True)

    if not os.path.exists(SRC):
        sys.exit(f"ERROR: source not found: {SRC} (run make.py to set up links)")

    print(f"reading {SRC} via pandas chunked Stata reader", flush=True)

    # pandas.read_stata streams chunks; per-chunk memory is bounded by
    # chunksize x n_cols (no full-file allocation). pyreadstat's metadataonly
    # was OOM-ing on this 59 GB file because libreadstat pre-allocates per-
    # column string buffers proportional to total row count.
    reader = pd.read_stata(
        SRC,
        chunksize=CHUNK,
        columns=KEEP_COLS,
        convert_categoricals=False,
        convert_dates=False,
    )

    writer_all = None
    writer_win = None
    rows_done = 0
    t0 = time.time()

    for df in reader:
        if df.empty:
            break
        # pandas may return columns in a different order; pin to KEEP_COLS.
        df = df[[c for c in KEEP_COLS if c in df.columns]]

        table = pa.Table.from_pandas(df, preserve_index=False)
        if writer_all is None:
            writer_all = pq.ParquetWriter(DST_ALL, table.schema, compression="snappy")
        writer_all.write_table(table)

        win = df[(df["year"] >= 2010) & (df["year"] <= 2019)]
        if not win.empty:
            table_win = pa.Table.from_pandas(win, preserve_index=False)
            if writer_win is None:
                writer_win = pq.ParquetWriter(
                    DST_WIN, table_win.schema, compression="snappy"
                )
            writer_win.write_table(table_win)

        rows_done += len(df)
        rate = rows_done / max(time.time() - t0, 1e-6)
        print(
            f"   wrote {rows_done:,} rows  ({rate:,.0f} rows/s)",
            flush=True,
        )

    if writer_all is not None:
        writer_all.close()
    if writer_win is not None:
        writer_win.close()

    print(f"done in {time.time() - t0:.1f}s", flush=True)
    for path in (DST_ALL, DST_WIN):
        if os.path.exists(path):
            size = os.path.getsize(path) / (1024**3)
            print(f"  - {path}  ({size:.2f} GB)", flush=True)


if __name__ == "__main__":
    main()
