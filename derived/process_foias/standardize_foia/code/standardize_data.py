#!/usr/bin/env python
"""
standardize_foia_data.py ― standardizes raw FOIA purchase-order workbooks
==========================================================================
* Reads raw Excel workbooks from multiple directories.
* Maps university-specific column names to a standard format.
* Converts price, qty, and spend to numeric types.
* Parses dates into a standard YYYY-MM-DD format.
* Creates standardized CSV files as output.
"""
from __future__ import annotations

import argparse
from pathlib import Path
from typing import Dict, List, Mapping

import pandas as pd

# ────────────────────────────── Path Setup ────────────────────────────────── #
CODE_DIR = Path(__file__).resolve().parent
ROOT_DIR = CODE_DIR.parent
DEFAULT_RAW_DIRS = f"{ROOT_DIR / 'external' / 'samp1'},{ROOT_DIR / 'external' / 'samp2'}"
DEFAULT_OUT_DIR = ROOT_DIR / "output" / "standardized"

# ───────────────── Column Maps ────────────────────────────────────────────── #
COLUMN_SPECS: Dict[str, Mapping[str, str]] = {
    "ecu_2006_2024.xlsx": {"product_desc": "DESC", "supplier": "VENDOR_NAME", "supplier_id": "VENDOR_ID", "price": "UNIT_PRICE", "qty": "QTY", "spend": "PO_ITEM_TOTAL", "fund_id": "FED_ID", "purchase_id": "PO", "date": "PO_DATE"},
    "ukansas_2010_2019.xlsx": {"product_desc": "Transaction Description", "supplier": "Supplier Name", "supplier_id": "Supplier ID", "spend": "Expense Amount", "purchaser": "PI", "fund_id": "Sponsor Award Number", "purchase_id": "Transaction ID", "date": "Transaction Date"},
    "utaustin_2012_2019.xlsx": {"product_desc": "Item Description 1", "supplier": "Vendor Name", "supplier_id": "Vendor EID", "qty": "Item Quantity Request", "spend": "Item Subtotal Cost", "purchaser": "Account 1", "purchase_id": "Purchase Order", "date": "Purchase Order Date"},
    "utdallas_2011_2024.xlsx": {"product_desc": "Product Description", "supplier": "Supplier Name", "supplier_id": "Supplier Number", "sku": "SKU/Catalog #", "price": "Unit Price", "qty": "Quantity", "spend": "Extended Price", "fund_id": "Reference Award ID", "purchase_id": "Purchase Order Identifier", "date": "Purchase date"},
    "usf_2003_2025.xlsx": {"product_desc": "More Info", "supplier": "Supplier", "supplier_id": "Supplier ID", "qty": "PO Qty", "spend": "Merchandise Amt", "purchaser": "PO Owner/Buyer", "purchase_id": "PO No.", "date": "PO Date"},
    "uni_florida_2009_2024.xlsx": {"product_desc": "Item Information Line Item Description", "supplier": "Supplier Supplier Name", "supplier_id": "Supplier Supplier Number", "sku": "Item Information SKU", "spend": "Line Level  Extended Price Amount (USD)", "qty": "Line Level Quantity", "purchase_id": "Header Level PO Number", "date": "Dates and Timestamps Created Time and Date"},
    "ttu_2010_2025.xlsx": {"product_desc": "Product Description", "supplier": "Supplier Name", "supplier_id": "Supplier ID", "sku": "SKU/Catalog #", "price": "Unit Price", "qty": "Quantity", "purchaser": "Principal Investigator", "purchase_id": "PO #", "date": "Creation Date", "fund_id" : "Fund - Banner"},
    "oregonstate_2010_2019.xlsx": {"product_desc": "Purchase Line Description", "supplier": "Vendor Last Name", "supplier_id": "VendorID", "price": "Unit Price", "qty": "Item Quantity", "purchase_id": "Unique Purchase Identifier", "date": "Purchase Date"},
    "uomn_2014_2024.xlsx": {"product_desc": "Invoice Detail Description", "supplier": "Supplier Name", "supplier_id": "Supplier Code", "spend": "PO Line Amount", "qty": "PO Line Quantity", "purchase_id": "PO Number", "date": "PO Creation Date"},
    "utarlington_2015_2019.xls": {"product_desc": "Item Info", "supplier": "Vendor Name", "supplier_id": "Vendor ID", "spend": "Merchandise Amt", "qty": "PO Qty", "purchase_id": "PO No.", "date": "PO Date"},
    "utelpaso_2014_2019.xlsx": {"product_desc": "Descr", "supplier": "Vendor", "supplier_id": "Vendor ID", "spend": "Distribution Line Amount", "purchase_id": "PO No.", "date": "Invoice Date"},
    "utsanantonio_2014_2019.xlsx": {"product_desc": "Descr", "supplier": "Vendor Name", "supplier_id": "Vendor ID", "qty": "Quantity", "spend": "Amount", "purchase_id": "PO No.", "date": "Acctg Date", "fund_id": "Fed Awd ID#"},
    "tsu_2015_2023.xlsx": {"product_desc": "Short Text", "supplier": "Vendor Name", "supplier_id": "Vendor Number", "price": "Net Price", "spend": "Gross Price", "purchase_id": "Purchasing Doc Num", "date": "Document Date"},
    "md_anderson_2012_2015.xlsx": {"product_desc": "Descr", "supplier": "VendorName", "supplier_id": "VendorID", "price": "PaidUnitPrice", "qty": "PaidQuantity", "purchase_id": "PO No", "date": "PODate"},
}
STANDARD_COLS: List[str] = ["product_desc", "supplier", "supplier_id", "sku", "price", "qty", "spend", "unit", "purchaser", "fund_id", "purchase_id", "date"]

# ───────────────── Processing Loop ────────────────────────
def _process_workbook(path: Path, out_dir: Path) -> None:
    """
    Reads a raw workbook, standardizes its columns and data types, and saves it as a CSV.
    """
    mapping = COLUMN_SPECS.get(path.name)
    if not mapping:
        print(f"  ⚠️ No column mapping found for {path.name}. Skipping.")
        return

    print(f"Processing {path.name} …")
    try:
        df = pd.read_excel(path, dtype=str).convert_dtypes()
    except Exception as e:
        print(f"  ⚠️ Could not read Excel file: {e}")
        return

    standard_df = pd.DataFrame()
    for col in STANDARD_COLS:
        raw = mapping.get(col)
        # Use None for missing columns to make type conversion more reliable
        standard_df[col] = df[raw] if raw and raw in df.columns else None

    # --- NEW: Data Type Conversion & Date Formatting ---
    print(f"  → Standardizing data types and formats...")
    numeric_cols = ['price', 'qty', 'spend']

    for col in standard_df.columns:
        if col in numeric_cols:
            # Convert to numeric, turning errors into blank/null (NaN)
            standard_df[col] = pd.to_numeric(standard_df[col], errors='coerce')
        elif col == 'date':
            # Use pandas' powerful to_datetime to smartly detect format
            # Coerce errors to NaT (Not a Time), then extract just the date part
            # This strips away hours/minutes/seconds
            standard_df[col] = pd.to_datetime(standard_df[col], errors='coerce').dt.date
        else:
            # For all other columns, ensure they are strings
            # Fill any blank/null values with an empty string
            standard_df[col] = standard_df[col].astype(str).fillna('')


    out_path = out_dir / f"{path.stem}_standardized.csv"
    standard_df.to_csv(out_path, index=False)
    print(f"  → Saved {out_path.relative_to(ROOT_DIR.parent)}")

# ───────────────────────── Main Execution ──────────────────────────
def main() -> None:
    """
    Main function to run the script.
    """
    parser = argparse.ArgumentParser(description="Standardize FOIA purchase-order data from one or more directories.")
    parser.add_argument("--raw-dirs", default=str(DEFAULT_RAW_DIRS), help="Comma-separated list of directories containing raw Excel files.")
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR), help="Directory to save standardized CSV files.")
    parser.add_argument("--unis", default="", help="Optional: Comma-separated list of filename prefixes to process.")
    args = parser.parse_args()

    raw_dirs = [Path(d.strip()) for d in args.raw_dirs.split(',')]
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    prefixes = {p.strip().lower() for p in args.unis.split(',') if p.strip()}

    files_to_process = []
    for raw_dir in raw_dirs:
        if not raw_dir.exists():
            print(f"Warning: Directory not found and will be skipped: {raw_dir.resolve()}")
            continue
        print(f"Searching for workbooks in: {raw_dir.resolve()}")
        files_to_process.extend(
            sorted(f for ext in ("*.xlsx", "*.xls") for f in raw_dir.glob(ext))
        )

    if not files_to_process:
        print("No Excel files found in any of the specified directories.")
        return

    if prefixes:
        print(f"Targeting universities: {', '.join(prefixes)}")

    processed_count = 0
    for fp in files_to_process:
        if prefixes and not any(fp.name.lower().startswith(p) for p in prefixes):
            continue
        _process_workbook(fp, out_dir)
        processed_count += 1

    if processed_count == 0:
        print("No matching workbooks found to process.")
    else:
        print(f"\nAll targeted workbooks ({processed_count}) processed.")

if __name__ == "__main__":
    main()
