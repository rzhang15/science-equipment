"""Career and lab start dates for every author in the scraped works.

Reads the raw OpenAlex works pull (~146GB, 20k csv files): every paper each
author ever published, with no journal, institution or country filter. OpenAlex
codes solo papers as position "first", never "last", so first_last is the first
multi-author last-authorship. Research articles only (pub_type "article").

  first_pub    first publication year, any position
  first_last   first year as last author

Run: python build.py
"""
import glob
import os
import sys
import polars as pl

WORKS = "../external/works"
OUT = "../output/athr_age.dta"
YR_MIN, YR_MAX = 1930, 2025
KEEP_TYPES = ["article"]
CHUNK = 500


def scan(files):
    return (
        pl.scan_csv(files, infer_schema=False)
        .select("pub_date", "athr_id", "athr_pos", "pub_type", "paratext")
        .filter(
            pl.col("athr_id").is_not_null(),
            pl.col("athr_id") != "A9999999999",
            pl.col("pub_type").is_in(KEEP_TYPES),
            pl.col("paratext") != "TRUE",
        )
        .with_columns(yr=pl.col("pub_date").str.slice(0, 4).cast(pl.Int32, strict=False))
        .filter(pl.col("yr").is_between(YR_MIN, YR_MAX))
        .group_by("athr_id")
        .agg(
            first_pub=pl.col("yr").min(),
            first_last=pl.col("yr").filter(pl.col("athr_pos") == "last").min(),
        )
        .collect(engine="streaming")
    )


if __name__ == "__main__":
    files = sorted(glob.glob(os.path.join(WORKS, "openalex_authors*.csv")))
    if not files:
        sys.exit(f"no csv files under {WORKS} -- run make.py to build external/")
    print(f"{len(files)} files", flush=True)

    parts = []
    for i in range(0, len(files), CHUNK):
        chunk = files[i:i + CHUNK]
        try:
            parts.append(scan(chunk))
        except Exception:
            for f in chunk:
                try:
                    parts.append(scan([f]))
                except Exception as e:
                    print(f"  SKIP {os.path.basename(f)}: {e}", flush=True)
        print(f"  {min(i + CHUNK, len(files))}/{len(files)} files", flush=True)

    acc = (
        pl.concat(parts)
        .group_by("athr_id")
        .agg(first_pub=pl.col("first_pub").min(), first_last=pl.col("first_last").min())
        .sort("athr_id")
    )
    n_last = acc["first_last"].is_not_null().sum()
    print(f"\n{acc.height:,} authors; {n_last:,} with a last-author paper")
    print(acc.select("first_pub", "first_last").describe())
    acc.to_pandas().to_stata(OUT, write_index=False)
    print("wrote", OUT, flush=True)
