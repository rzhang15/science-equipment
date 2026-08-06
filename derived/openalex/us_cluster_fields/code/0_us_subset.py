"""
Cut the US authors out of the worldwide stemmed corpus.

Runs as a single streaming pass: scan_parquet -> semi-join -> sink_parquet,
so peak memory stays flat regardless of corpus size. The previous version
called .collect().to_pandas() and then pandas.to_parquet, which held the
whole 3 GB frame in polars, again as Python str objects in pandas, and again
in the parquet writer's buffers.
"""
import os
import pandas as pd
import polars as pl
import pyarrow.parquet as pq

INPUT_PARQUET_PATH = "../external/appended_text/cleaned_static_author_text_pre.parquet"
US_AUTHORS_PATH = "../external/athrs/list_of_us_athrs.dta"
OUTPUT_DIR = "../output/"
OUTPUT_FILENAME = "cleaned_static_author_text_pre_us.parquet"

print("Loading US Author List...", flush=True)
pd_us_athrs = pd.read_stata(US_AUTHORS_PATH, columns=["athr_id"])
df_us_athrs = pl.from_pandas(pd_us_athrs).lazy().select(["athr_id"]).unique()

os.makedirs(OUTPUT_DIR, exist_ok=True)
output_path = os.path.join(OUTPUT_DIR, OUTPUT_FILENAME)

print(f"Streaming {INPUT_PARQUET_PATH} -> {output_path} ...", flush=True)
(
    pl.scan_parquet(INPUT_PARQUET_PATH)
    .join(df_us_athrs, on="athr_id", how="semi")
    .sink_parquet(output_path, compression="zstd")
)

print(f"US Authors Count: {pq.ParquetFile(output_path).metadata.num_rows:,}")
print("Done.")
