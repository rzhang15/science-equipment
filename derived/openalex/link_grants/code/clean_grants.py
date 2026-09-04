import re
import pandas as pd
from pathlib import Path

JOBS = [
    {
        "src": Path("../output/pi_grants.dta"),
        "out": Path("../output/pi_grants_clean.dta"),
        "by": ["athr_id", "year", "clean_grant_id", "agency", "country"],
    },
    {
        "src": Path("../output/pi_ppr_grants.dta"),
        "out": Path("../output/pi_ppr_grants_clean.dta"),
        "by": ["pmid", "athr_id", "year", "clean_grant_id", "agency", "country"],
    },
]

PAT_A = re.compile(r"^[0-9]?([A-Z][0-9A-Z]{2})([A-Z]{2})([0-9]{5,7})")
PAT_B = re.compile(r"^([A-Z]{2})([0-9]{5,7})(?:[0-9]{2}[A-Z]?[0-9]?)?$")

PHS_TOKENS = ("NIH", "HHS", "CDC", "FDA", "AHRQ")


def is_us_phs(agency: str, country: str) -> bool:
    if country != "United States":
        return False
    return any(tok in agency for tok in PHS_TOKENS)


def parse_nih(norm: str):
    m = PAT_A.match(norm)
    if m:
        return m.group(1), m.group(2), m.group(3)
    m = PAT_B.match(norm)
    if m:
        return "", m.group(1), m.group(2)
    return "", "", ""


def clean_file(src: Path, out: Path, by: list):
    df = pd.read_stata(src, convert_categoricals=False)
    print(f"read {len(df):,} rows from {src}")

    norm = (df["grant_id"].astype(str)
            .str.upper()
            .str.replace(r"[^A-Z0-9]", "", regex=True))

    agency = df["agency"].astype(str)
    country = df["country"].astype(str)
    us_phs = [is_us_phs(a, c) for a, c in zip(agency, country)]

    activity = [""] * len(df)
    ic = [""] * len(df)
    serial = [""] * len(df)
    for i, (n, ok) in enumerate(zip(norm, us_phs)):
        if ok and n:
            activity[i], ic[i], serial[i] = parse_nih(n)

    df["activity_code"] = activity
    df["nih_ic"] = ic
    df["nih_serial"] = [s.zfill(6) if s else "" for s in serial]

    df["clean_grant_id"] = [
        (i + s.zfill(6)) if (i and s) else n
        for i, s, n in zip(ic, serial, norm)
    ]

    n_parsed = sum(1 for x in ic if x)
    print(f"NIH-parsed: {n_parsed:,} / {len(df):,} rows ({n_parsed/len(df):.1%})")

    df["orig_grant_id"] = df["grant_id"]
    df["_one"] = 1

    agg = {
        "orig_grant_id": "first",
        "activity_code": "first",
        "nih_ic": "first",
        "nih_serial": "first",
        "acronym": "first",
        "_one": "sum",
    }
    before = len(df)
    df = df.groupby(by, dropna=False, as_index=False, sort=False).agg(agg)
    df = df.rename(columns={"_one": "n_records"})
    print(f"collapsed {before:,} -> {len(df):,} unique ({', '.join(by)})")

    df.to_stata(out, write_index=False, version=118)
    print(f"wrote {len(df):,} rows to {out}")


def main():
    for job in JOBS:
        if not job["src"].exists():
            print(f"skipping {job['src']} (not found)")
            continue
        clean_file(job["src"], job["out"], job["by"])


if __name__ == "__main__":
    main()
