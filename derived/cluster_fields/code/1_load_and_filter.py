"""
Loads the three raw data files, strips OpenAlex URLs from `id`,
and keeps only pre-merger publications (2000‒2013 inclusive).
"""
from pathlib import Path
import pandas as pd, re

RAW = Path("../external/samp")    # adjust if your data live elsewhere
OUT = Path("../output")
OUT.mkdir(exist_ok=True)

strip = lambda x: re.sub(r"https?://openalex\.org/", "", str(x))

print(">>> reading cleaned_all_15jrnls.dta")
pub = pd.read_stata(RAW / "cleaned_all_15jrnls.dta")
pub["id"]   = pub["id"].map(strip)
pub["year"] = pub["year"].astype("int")
pub = pub.loc[(pub["year"] >= 2000) & (pub["year"] <= 2013)]
pub.to_parquet(OUT / "pub_filtered.parquet")
print("   rows kept:", len(pub))

print(">>> reading combined_abstracts.csv")
ab = pd.read_csv("../external/samp/combined_abstracts.csv")
ab["id"] = ab["id"].map(strip)
ab.to_parquet(OUT / "abstracts.parquet")
print("   rows:", len(ab))

print(">>> reading contracted_gen_mesh_15jrnls.dta")
mesh = pd.read_stata(RAW / "contracted_gen_mesh_15jrnls.dta")
mesh["id"] = mesh["id"].map(strip)
mesh.to_parquet(OUT / "mesh_long.parquet")
print("   rows:", len(mesh))
