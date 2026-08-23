"""Career and lab start dates for every author in the scraped works.

Reads the raw OpenAlex works pull (~146GB, 20k csv files): every paper each
author ever published, with no journal, institution or country filter, and
with OpenAlex's own first/middle/last author designation.

  first_pub    first publication year, any position
  first_last   first year as last author
  n_ppr        papers observed
  n_last_ppr   last-author papers observed

Run: python build.py [n_workers]
"""
import sys
import glob
import os
import pandas as pd
from multiprocessing import Pool

WORKS  = "../external/works"
OUT    = "../output/athr_age.dta"
COLS   = ["pub_date", "athr_id", "athr_pos"]
YR_MIN, YR_MAX = 1930, 2025
REDUCE_EVERY = 250


def scan(path):
    try:
        d = pd.read_csv(path, usecols=COLS, low_memory=False,
                        dtype={"athr_id": "string", "athr_pos": "string",
                               "pub_date": "string"})
    except Exception as e:
        print(f"  SKIP {os.path.basename(path)}: {e}", flush=True)
        return None
    d = d.dropna(subset=["athr_id", "pub_date"])
    d = d[d.athr_id.ne("A9999999999")]
    d["yr"] = pd.to_numeric(d.pub_date.str.slice(0, 4), errors="coerce")
    d = d[d.yr.between(YR_MIN, YR_MAX)]
    if d.empty:
        return None
    last = d[d.athr_pos.eq("last")]
    g = d.groupby("athr_id")
    out = pd.DataFrame({"first_pub": g.yr.min(), "n_ppr": g.yr.size()})
    if not last.empty:
        gl = last.groupby("athr_id")
        out["first_last"] = gl.yr.min()
        out["n_last_ppr"] = gl.yr.size()
    else:
        out["first_last"] = pd.NA
        out["n_last_ppr"] = 0
    return out


def reduce(parts):
    d = pd.concat(parts)
    return d.groupby(level=0).agg(first_pub=("first_pub", "min"),
                                  first_last=("first_last", "min"),
                                  n_ppr=("n_ppr", "sum"),
                                  n_last_ppr=("n_last_ppr", "sum"))


if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 8
    files = sorted(glob.glob(os.path.join(WORKS, "openalex_authors*.csv")))
    if not files:
        sys.exit(f"no csv files under {WORKS} -- run make.py to build external/")
    print(f"{len(files)} files, {n} workers", flush=True)

    acc, buf = None, []
    with Pool(n) as p:
        for i, r in enumerate(p.imap_unordered(scan, files, chunksize=8), 1):
            if r is not None:
                buf.append(r)
            if len(buf) >= REDUCE_EVERY:
                acc = reduce(buf if acc is None else [acc] + buf)
                buf = []
            if i % 1000 == 0:
                nauth = 0 if acc is None else len(acc)
                print(f"  {i}/{len(files)} files, {nauth:,} authors", flush=True)
    if buf:
        acc = reduce(buf if acc is None else [acc] + buf)

    acc = acc.reset_index().rename(columns={"index": "athr_id"})
    for c in ["first_pub", "first_last", "n_ppr", "n_last_ppr"]:
        acc[c] = pd.to_numeric(acc[c], errors="coerce").astype("float64")
    acc["athr_id"] = acc.athr_id.astype(str)
    print(f"\n{len(acc):,} authors")
    print(acc[["first_pub", "first_last", "n_ppr", "n_last_ppr"]]
          .describe(percentiles=[.1, .5, .9]).round(1).to_string())
    print("with a last-author paper:", int(acc.first_last.notna().sum()))
    acc.to_stata(OUT, write_index=False)
    print("wrote", OUT, flush=True)
