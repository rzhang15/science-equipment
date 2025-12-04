#!/usr/bin/env python
import re
import pandas as pd
from pathlib import Path
import argparse
import unicodedata
from typing import List

# --- Import NLTK Stopwords ---
try:
    from nltk.corpus import stopwords
    STOP_EN = set(stopwords.words("english"))
except ImportError:
    print("❌ NLTK library not found. Please install it: pip install nltk")
    print("   You may also need to download the stopwords: python -m nltk.downloader stopwords")
    exit()
except LookupError:
    print("❌ NLTK stopwords not found. Please download them.")
    print("   In a Python interpreter, run: import nltk; nltk.download('stopwords')")
    exit()

# --- Import Central Configuration ---
try:
    import config
except ImportError:
    print("❌ Error: config.py not found. Please place it in the same directory.")
    exit()

# ────────────────────────────── Path Setup ────────────────────────────────── #
CODE_DIR = Path(__file__).resolve().parent
ROOT_DIR = CODE_DIR.parent
DEFAULT_DATA_DIR = ROOT_DIR / "external" / "samp"
CATALOG_DIR = ROOT_DIR / "external" / "catalogs"  # Path for additional files
DEFAULT_OUT_DIR = ROOT_DIR / "output"

# --- Define which regexes from config.py correspond to Entities vs. Noise ---
SKU_REGEX_KEYS = [
    "cas_full", "item_ref_full", "sku_multi_hyphen", "sku_num_num",
    "sku_very_long_num", "sku_alpha_hyphen_num", "sku_letters_digits"
]
UNIT_REGEX_KEYS = [
    "num_in_paren_unit_counts", "num_in_paren_quantities", "unitpack",
    "sets_pk", "dimensions", "mult", "trailing_slash_unit"
]
NOISE_REGEX_KEYS = [k for k in config.REGEXES_NORMALIZE if k not in SKU_REGEX_KEYS and k not in UNIT_REGEX_KEYS]

# ───────────────── Core Cleaning & Extraction Functions ─────────────────── #

def get_extracted_entities(desc: str) -> pd.Series:
    """
    EXTRACTS entities from a description using config.py patterns.
    This is the "cherry on top" path.
    """
    if pd.isna(desc):
        return pd.Series({"potential_sku": "", "potential_unit": ""})

    text = str(desc)
    found_skus, found_units = [], []

    for key in SKU_REGEX_KEYS:
        if key in config.REGEXES_NORMALIZE:
            pattern, _ = config.REGEXES_NORMALIZE[key]
            try:
                matches = re.findall(pattern, text)
                if matches:
                    found_skus.extend(m[0] if isinstance(m, tuple) else m for m in matches)
            except (re.error, TypeError):
                continue

    for key in UNIT_REGEX_KEYS:
        if key in config.REGEXES_NORMALIZE:
            pattern, _ = config.REGEXES_NORMALIZE[key]
            try:
                matches = re.findall(pattern, text)
                if matches:
                    flat_matches = [item for sublist in matches if isinstance(sublist, tuple) for item in sublist if item] if any(isinstance(i, tuple) for i in matches) else matches
                    found_units.extend(flat_matches)
            except (re.error, TypeError):
                continue

    return pd.Series({
        "potential_sku": ", ".join(map(str, found_skus)),
        "potential_unit": ", ".join(map(str, found_units))
    })

def get_clean_description(desc: str) -> str:
    """
    CLEANS a description using config.py patterns.
    This is the primary "cleaning" path.
    """
    if pd.isna(desc):
        return ""

    text = str(desc).lower()
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("utf-8")

    all_cleaning_keys = SKU_REGEX_KEYS + UNIT_REGEX_KEYS + NOISE_REGEX_KEYS
    for key in all_cleaning_keys:
        if key in config.REGEXES_NORMALIZE:
            pattern, repl = config.REGEXES_NORMALIZE[key]
            try:
                text = re.sub(pattern, repl, text)
            except (re.error, TypeError):
                continue

    all_stopwords = STOP_EN | config.OTHER_STOPWORDS | set(config.UNIT_TOKENS)
    tokens = text.split()
    clean_tokens = [t for t in tokens if t not in all_stopwords and len(t) > 1]

    # Join the tokens and deduplicate them while preserving order
    final_string = " ".join(dict.fromkeys(clean_tokens))

    # **FINAL RULE**: Remove a leading hyphen if it exists.
    if final_string.startswith('-'):
        final_string = final_string[1:].lstrip()

    return final_string

def process_row(row: pd.Series) -> pd.Series:
    """
    Applies the decoupled cleaning and extraction process to a single row.
    """
    product_desc = row["product_desc"]
    clean_desc = get_clean_description(product_desc)
    entities = get_extracted_entities(product_desc)

    return pd.Series({
        "clean_desc": clean_desc,
        "potential_sku": entities["potential_sku"],
        "potential_unit": entities["potential_unit"]
    })

def main() -> None:
    """Main execution block."""
    parser = argparse.ArgumentParser(description="Clean FOIA data with a cleaning-first approach using config.py.")
    parser.add_argument("--data-dir", default=str(DEFAULT_DATA_DIR), help="Directory containing raw FOIA csv files.")
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR), help="Directory to save cleaned CSV files.")
    parser.add_argument("--files", default="", help="Optional: Comma-separated list of exact filenames to process.")
    args = parser.parse_args()

    data_dir, out_dir = Path(args.data_dir), Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.files:
        files_to_process = []
        # Check for the file in the primary data, catalog, and current directories
        for f_name in args.files.split(','):
            f_name = f_name.strip()
            found_path = None
            for directory in [data_dir, CATALOG_DIR, Path.cwd()]:
                if (directory / f_name).exists():
                    found_path = directory / f_name
                    break
            if found_path:
                files_to_process.append(found_path)
            else:
                print(f"  ⚠️ Specified file not found in known directories: {f_name}. Skipping.")
    else:
        # Default: Process all CSVs in the default data dir + the two specified files
        files_to_process = sorted(data_dir.glob("*.csv"))
        files_to_process.extend([
            CATALOG_DIR / "non_lab.dta",
            CATALOG_DIR / "ny_fisher_desc.csv"
        ])

    print(f"Found {len(files_to_process)} target workbook(s) to clean...")

    for fp in files_to_process:
        if not fp.exists():
            print(f"  ⚠️ Target file not found: {fp}. Skipping.")
            continue

        print(f"Processing {fp.name} …")
        try:
            df = None
            if fp.suffix == '.csv':
                df = pd.read_csv(fp, dtype=str, on_bad_lines='warn')
            elif fp.suffix in ['.xlsx', '.xls']:
                # Read Excel files directly using pandas
                df = pd.read_excel(fp, dtype=str)
            elif fp.suffix == '.dta':
                # FIX 1: Added encoding="latin-1" to handle special characters.
                df = pd.read_stata(fp)
                # Ensure object columns are strings to prevent errors
                for col in df.select_dtypes(include=['object']).columns:
                    df[col] = df[col].astype(str)
            else:
                print(f"  ⚠️ Unsupported file type: {fp.suffix}. Skipping.")
                continue

            # FIX 2: Make all column lookups case-insensitive.
            df.columns = [col.lower() for col in df.columns]

            # Identify the correct description column based on the file (now using lowercase)
            source_desc_col = ""
            if fp.name == "non_lab.dta":
                source_desc_col = config.CA_DESC_COL.lower()
            elif fp.name == "fisher_lab.xlsx":
                source_desc_col = config.FISHER_DESC_COL.lower()
            elif fp.name == "fisher_nonlab.xlsx":
                source_desc_col = config.FISHER_DESC_COL.lower()
            elif "product_desc" in df.columns:
                source_desc_col = "product_desc"

            if not source_desc_col or source_desc_col not in df.columns:
                print(f"  ⚠️ Could not find a suitable description column in {fp.name}. Searched for '{source_desc_col}'. Skipping.")
                continue

            # Rename original description column to 'product_desc' for standardized processing
            if source_desc_col != "product_desc":
                df.rename(columns={source_desc_col: "product_desc"}, inplace=True)

            processed_data = df.apply(process_row, axis=1)
            clean_df = pd.concat([df, processed_data], axis=1)

            # Define the column order for the output file
            final_cols_order = [
                "product_desc", "clean_desc", "potential_sku", "potential_unit"
            ] + [c for c in df.columns if c not in ["product_desc", "clean_desc", "potential_sku", "potential_unit"]]

            clean_df = clean_df.reindex(columns=[c for c in final_cols_order if c in clean_df.columns])

            out_path = out_dir / f"{fp.stem}_clean.csv"
            clean_df.to_csv(out_path, index=False)
            print(f"  → Saved {out_path}")
        except Exception as e:
            print(f"  ❌ Could not process file {fp.name}: {e}")

    print(f"\n✅ All targeted workbooks processed.")

if __name__ == "__main__":
    main()
