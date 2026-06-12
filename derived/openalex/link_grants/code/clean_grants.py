"""
Clean PubMed grant_ids and deduplicate.

NIH grant numbers have the structure:
    [type 1d][activity 3c][IC 2L][serial 5-7d][-yy][suffix]
e.g. 5R01HL088243-03A1. The "core" identifier (same grant across years,
amendments, and application types) is IC + serial -> "HL088243".

For each row from ../output/pi_grants.dta we produce:
    clean_grant_id  - dedup key: NIH core (IC + 6-digit serial) when parseable,
                      otherwise an alnum-stripped uppercase form
    activity_code   - R01, K23, P01, ... when present
    nih_ic          - HL, CA, MH, ...
    nih_serial      - 6-digit zero-padded serial

We then collapse rows that only differed in formatting.
"""
import re
import pandas as pd
from pathlib import Path

SRC = Path("../output/pi_grants.dta")
OUT = Path("../output/pi_grants_clean.dta")

# pattern A: [opt 1-digit type][3-char activity, e.g. R01/U01/K23][2L IC][5-7 digit serial][rest]
PAT_A = re.compile(r"^[0-9]?([A-Z][0-9A-Z]{2})([A-Z]{2})([0-9]{5,7})")
# pattern B: bare [IC][serial] with optional support-year/suffix tail
PAT_B = re.compile(r"^([A-Z]{2})([0-9]{5,7})(?:[0-9]{2}[A-Z]?[0-9]?)?$")

PHS_TOKENS = ("NIH", "HHS", "CDC", "FDA", "AHRQ")


def is_us_phs(agency: str, country: str) -> bool:
    if country != "United States":
        return False
    return any(tok in agency for tok in PHS_TOKENS)


def parse_nih(norm: str):
    """Return (activity_code, ic, serial) or ('', '', '')."""
    m = PAT_A.match(norm)
    if m:
        return m.group(1), m.group(2), m.group(3)
    m = PAT_B.match(norm)
    if m:
        return "", m.group(1), m.group(2)
    return "", "", ""


def main():
    df = pd.read_stata(SRC, convert_categoricals=False)
    print(f"read {len(df):,} rows from {SRC}")

    # normalize: upper, strip all non-alnum
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

    by = ["athr_id", "year", "clean_grant_id", "agency", "country"]
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
    print(f"collapsed {before:,} -> {len(df):,} unique (athr_id, year, clean_grant_id, agency, country)")

    df.to_stata(OUT, write_index=False, version=118)
    print(f"wrote {len(df):,} rows to {OUT}")


if __name__ == "__main__":
    main()
