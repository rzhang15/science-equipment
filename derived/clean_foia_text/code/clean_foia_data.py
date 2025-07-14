"""
Clean FOIA purchase‐order data exported from multiple U.S. universities.

Usage
-----
$ python clean_foia_data.py

The script expects raw Excel workbooks under the relative path
`../external/samp/` (relative to this file).  Each workbook belongs to one
university and may have institution-specific column names.  Provide a mapping
from *standard* variable names to the institution-specific names in the
`COLUMN_SPECS` dictionary below.

For every workbook, a cleaned CSV will be written to
`../output/<workbook-stem>_clean.csv` with the 13 standardised columns:

`product_desc, supplier, supplier_id, sku, price, qty, spend, unit, purchaser,
fund_id, purchase_id, date, clean_desc`

Columns that do **not** exist in the raw file are still included with blanks.

String-cleaning rules applied to **`product_desc` → `clean_desc`**
-----------------------------------------------------------------
The pipeline executes **in order**:

1. **#-snippet removal** – delete anything enclosed by `#…#`, hashes included.
2. **Unicode → ASCII + lower-case** – NFKD normalise, strip diacritics, down-case.
3. **Separator harmonisation** – replace `_` and `-` with spaces.
4. **Punctuation purge** – drop every char except `a-z`, `0-9`, and space
   (removes `%`, `&`, etc.).
5. **Standalone-number deletion** – remove tokens that are only digits.
6. **Generic word removal** – drop uninformative words such as `product`,
   `item`, `catalog`, `cat`, `for`, `and`, `the`, `of`, `misc`, `various`,
   `general`, `description`.
7. **Whitespace collapse** – squeeze multiple spaces, trim ends.
8. **Trailing artefact removal** – strip suffixes `ea, each, pkg, pack, cs, case`.
9. **Token de-duplication** – keep only the first occurrence of each token
   (order preserved).

*Units are **retained** exactly as they appear – both stand-alone tokens and
those attached to numbers, e.g. `25ml`, `ml25`, `kg`, `cs100` remain.*

Edit `_clean_description()` to adjust rules as needed.
"""
from __future__ import annotations

import re
import unicodedata
from pathlib import Path
from typing import Dict, List, Mapping

import pandas as pd

###############################################################################
# Configuration                                                               #
###############################################################################

RAW_DIR = Path(__file__).with_suffix("").parent / "../external/samp"
OUT_DIR = Path(__file__).with_suffix("").parent / "../output"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# Mapping raw → standard column names per workbook
COLUMN_SPECS: Dict[str, Mapping[str, str]] = {
    "ecu_2006_2024.xlsx": {
        "product_desc": "DESC",
        "supplier": "VENDOR_NAME",
        "supplier_id": "VENDOR_ID",
        "price": "UNIT_PRICE",
        "qty": "QTY",
        "spend": "PO_ITEM_TOTAL",
        "fund_id": "FED_ID",
        "purchase_id": "PO",
        "date": "PO_DATE",
    },
    "ukansas_2010_2019.xlsx": {
        "product_desc": "Transaction Description",
        "supplier": "Supplier Name",
        "supplier_id": "Supplier ID",
        "spend": "Expense Amount",
        "purchaser": "PI",
        "fund_id": "Sponsor Award Number",
        "purchase_id": "Transaction ID",
        "date": "Transaction Date",
    },
    "utdallas_2011_2024.xlsx": {
        "product_desc": "Product Description",
        "supplier": "Supplier Name",
        "supplier_id": "Supplier Number",
        "sku": "SKU/Catalog #",
        "price": "Unit Price",
        "qty": "Quantity",
        "spend": "Extended Price",
        "fund_id": "Reference Award ID",
        "purchase_id": "Purchase Order Identifier",
        "date": "Purchase date",
    },
    "usf_2003_2025.xlsx": {
        "product_desc": "More Info",
        "supplier": "Supplier",
        "supplier_id": "Supplier ID",
        "qty": "PO Qty",
        "spend": "Merchandise Amt",
        "purchaser": "PO Owner/Buyer",
        "purchase_id": "PO No.",
        "date": "PO Date",
    },
}

STANDARD_COLS: List[str] = [
    "product_desc", "supplier", "supplier_id", "sku", "price", "qty",
    "spend", "unit", "purchaser", "fund_id", "purchase_id", "date",
    "clean_desc",
]

###############################################################################
# Cleaning utilities                                                          #
###############################################################################

HASH_SNIPPET_RE = re.compile(r"#.*?#")
TOKEN_CLEAN_RE = re.compile(r"[^0-9a-z ]+")  # keep only a-z, 0-9, space
NUM_TOKEN_RE = re.compile(r"\b\d+\b")
TRAILING_ARTIFACTS = re.compile(r"\b(?:ea|each|pkg|pack|cs|case)\b$", re.I)

STOPWORDS = {
    "product", "item", "catalog", "cat", "for", "and", "the", "of", "misc",
    "various", "general", "description",
}


def _dedup_tokens(text: str) -> str:
    seen, out = set(), []
    for tok in text.split():
        if tok not in seen:
            seen.add(tok)
            out.append(tok)
    return " ".join(out)


def _remove_stopwords(text: str) -> str:
    return " ".join(tok for tok in text.split() if tok not in STOPWORDS)


def _clean_description(desc):
    if desc is None or (isinstance(desc, float) and pd.isna(desc)):
        return ""
    txt = str(desc).strip()

    # 1. Remove #…# snippets
    txt = HASH_SNIPPET_RE.sub(" ", txt)

    # 2. Unicode → ASCII & lower-case
    txt = unicodedata.normalize("NFKD", txt).encode("ascii", "ignore").decode().lower()

    # 3. Replace separators with space
    txt = txt.replace("_", " ").replace("-", " ")

    # 4. Strip punctuation (drops % &)
    txt = TOKEN_CLEAN_RE.sub(" ", txt)

    # 5. Remove standalone numbers
    txt = NUM_TOKEN_RE.sub(" ", txt)

    # 6. Remove generic stop-words
    txt = _remove_stopwords(txt)

    # 7. Collapse whitespace
    txt = re.sub(r"\s+", " ", txt).strip()

    # 8. Drop trailing artefacts
    txt = TRAILING_ARTIFACTS.sub("", txt).strip()

    # 9. De-duplicate tokens
    txt = _dedup_tokens(txt)

    return txt

###############################################################################
# Processing loop                                                             #
###############################################################################

def _process_workbook(path: Path):
    mapping = COLUMN_SPECS.get(path.name, {})
    print(f"Processing {path.name} …")
    df = pd.read_excel(path, dtype=str).convert_dtypes()

    clean_df = pd.DataFrame(columns=STANDARD_COLS)
    for col in STANDARD_COLS:
        if col == "clean_desc":
            continue
        raw_col = mapping.get(col)
        clean_df[col] = df[raw_col] if raw_col and raw_col in df.columns else ""

    clean_df["clean_desc"] = clean_df["product_desc"].apply(_clean_description)

    out_path = OUT_DIR / f"{path.stem}_clean.csv"
    clean_df.to_csv(out_path, index=False)
    print(f"  → Saved {out_path.relative_to(Path.cwd())}")


def main():
    if not RAW_DIR.exists():
        raise SystemExit(f"RAW_DIR not found: {RAW_DIR.resolve()}")
    for fp in sorted(RAW_DIR.glob("*.xlsx")):
        _process_workbook(fp)
    print("All workbooks processed.")


if __name__ == "__main__":
    main()
