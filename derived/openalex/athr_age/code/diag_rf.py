import glob
import os
import polars as pl

WORKS = "../external/works"
CHUNK = 500

rf_ids = pl.read_csv("../temp/rf_ids.csv", infer_schema=False)["athr_id"].to_list()
files = sorted(glob.glob(os.path.join(WORKS, "openalex_authors*.csv")))
print(f"{len(files)} files, {len(rf_ids)} RF ids", flush=True)

parts = []
for i in range(0, len(files), CHUNK):
    part = (
        pl.scan_csv(files[i:i + CHUNK], infer_schema=False)
        .select("id", "pmid", "jrnl", "pub_date", "which_athr",
                "athr_id", "athr_pos", "pub_type", "paratext")
        .filter(pl.col("athr_id").is_in(rf_ids))
        .collect(engine="streaming")
    )
    parts.append(part)
    print(f"  {min(i + CHUNK, len(files))}/{len(files)}", flush=True)

out = pl.concat(parts)
print(f"{out.height:,} rows, {out['athr_id'].n_unique():,} PIs")
out.write_parquet("../temp/rf_raw_works.parquet")
print("wrote ../temp/rf_raw_works.parquet", flush=True)
