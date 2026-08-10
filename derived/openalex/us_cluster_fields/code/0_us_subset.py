import os
import pandas as pd
import polars as pl

# --- CONFIGURATION ---
INPUT_PARQUET_PATH = "../external/appended_text/cleaned_static_author_text_pre.parquet" 

US_AUTHORS_PATH = "../external/athrs/list_of_us_athrs.dta"

# 3. Where to save the US-only file
OUTPUT_DIR = "../output/"
OUTPUT_FILENAME = "cleaned_static_author_text_pre_us.parquet"

# --- EXECUTION ---
print("Loading US Author List...")
pd_us_athrs = pd.read_stata(US_AUTHORS_PATH)
df_us_athrs = pl.from_pandas(pd_us_athrs).lazy().select(["athr_id"]).unique()

print(f"Loading Cleaned Text Parquet from: {INPUT_PARQUET_PATH}...")
df_text_all = pl.scan_parquet(INPUT_PARQUET_PATH)

print("Filtering for US Authors...")
df_text_us = (
    df_text_all
    .join(df_us_athrs, on="athr_id", how="inner")
)

print("Executing Filter...")
pdf_us = df_text_us.collect().to_pandas()

print(f"Original Count (Approx): (Unknown, scan mode)")
print(f"US Authors Count: {len(pdf_us)}")

# --- SAVING ---
os.makedirs(OUTPUT_DIR, exist_ok=True)
output_path = os.path.join(OUTPUT_DIR, OUTPUT_FILENAME)

print(f"Saving US-only Parquet to: {output_path}")
pdf_us.to_parquet(output_path, index=False)

print("Done.")