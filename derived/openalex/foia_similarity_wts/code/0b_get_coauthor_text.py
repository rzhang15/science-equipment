import os
import pandas as pd
import polars as pl

# --- PATHS ---
coauthors_path = '../external/coauthors/coauthors.dta'
text_data_path = '../external/us_appended_text/cleaned_static_author_text_pre_us.parquet'
output_path = '../output/coauthor_text_final.csv'
mapping_path = '../output/foia_coauthor_map.csv'

print("Loading FOIA-author -> coauthor map...")
df_map = pd.read_stata(coauthors_path)
df_map['athr_id'] = df_map['athr_id'].astype(str)
df_map['coauthor_id'] = df_map['coauthor_id'].astype(str)
print(f"(FOIA author, coauthor) pairs: {len(df_map)}")
print(f"  unique FOIA authors: {df_map['athr_id'].nunique()}")
print(f"  unique coauthors:    {df_map['coauthor_id'].nunique()}")

coauthor_ids = set(df_map['coauthor_id'].tolist())

if not os.path.exists(text_data_path):
    raise FileNotFoundError(f"Text parquet not found: {text_data_path}")

# Predicate-pushdown via polars lazy scan: stream the parquet, filter to
# coauthor IDs, then collect — avoids loading the full 3GB file into memory.
print("Filtering text parquet to coauthor IDs (lazy scan)...")
df_text = (
    pl.scan_parquet(text_data_path)
    .select(['athr_id', 'processed_text'])
    .with_columns(pl.col('athr_id').cast(pl.Utf8))
    .filter(pl.col('athr_id').is_in(list(coauthor_ids)))
    .collect(streaming=True)
    .to_pandas()
)
print(f"Matched text rows: {len(df_text)} / {len(coauthor_ids)} unique coauthor IDs")

# Output 1: one row per unique coauthor with text — drop-in for the existing
# vectorize/similarity algo (which keys on `athr_id`). Here `athr_id` holds
# the coauthor's OpenAlex id.
missing_ids = coauthor_ids - set(df_text['athr_id'].tolist())
if missing_ids:
    print(f"WARNING: {len(missing_ids)} coauthors have no text data.")
    sample = sorted(missing_ids)[:20]
    print(f"  missing coauthor_ids: {sample}{'...' if len(missing_ids) > 20 else ''}")

df_text.to_csv(output_path, index=False)
print(f"Saved coauthor text to: {output_path}  ({len(df_text)} rows)")

# Output 2: the FOIA-author <-> coauthor mapping carried forward so the
# similarity-share aggregation can join on it after the algo runs.
df_map.to_csv(mapping_path, index=False)
print(f"Saved FOIA->coauthor map to: {mapping_path}  ({len(df_map)} rows)")
