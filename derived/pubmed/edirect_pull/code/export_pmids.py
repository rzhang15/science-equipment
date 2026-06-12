import pandas as pd
from pathlib import Path

src = Path("../output/pmids.dta")
dst = Path("../temp/pmids.txt")
dst.parent.mkdir(parents=True, exist_ok=True)

df = pd.read_stata(src)
pmids = df["pmid"].dropna().astype("int64").unique()
pmids.sort()

with open(dst, "w") as f:
    f.write("\n".join(str(p) for p in pmids))
    f.write("\n")

print(f"wrote {len(pmids):,} unique pmids to {dst}")
