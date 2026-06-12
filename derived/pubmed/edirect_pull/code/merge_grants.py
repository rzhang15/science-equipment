import pandas as pd
from pathlib import Path

src = Path("../temp/grants_all.tsv")
out = Path("../output/grants.dta")
out.parent.mkdir(parents=True, exist_ok=True)

cols = ["pmid", "grant_id", "acronym", "agency", "country"]

# quoting=3 = csv.QUOTE_NONE: treat " as a literal char (our TSV uses no quoting)
df = pd.read_csv(src, sep="\t", names=cols, dtype=str,
                 quoting=3, na_filter=False, engine="c", low_memory=False)
print(f"read {len(df):,} rows from {src}")

df["pmid"] = pd.to_numeric(df["pmid"], errors="coerce").astype("Int64")
before = len(df)
df = df.drop_duplicates(subset=["pmid", "grant_id", "agency"])
print(f"deduped {before:,} -> {len(df):,}")

df.to_stata(out, write_index=False, version=118)
print(f"wrote {len(df):,} rows to {out}")
