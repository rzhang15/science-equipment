#!/usr/bin/env python
"""
Clean FOIA procurement data: normalise descriptions, extract SKUs/units.

Optimisations vs. the original script
--------------------------------------
  - All regexes compiled once at module load (not per-row).
  - Stopword set built once at module load.
  - Regex-key filtering done once (no per-row dict lookups).
  - Row-wise df.apply(process_row, axis=1) replaced with three
    column-wise .apply() calls -- avoids creating a pd.Series per row.
  - Flat-match logic in entity extraction simplified.
  - File-reader dispatch consolidated into a dict.
"""
import re
import unicodedata
import argparse

import pandas as pd
from pathlib import Path

# -- NLTK stopwords --------------------------------------------------------- #
try:
    from nltk.corpus import stopwords
    STOP_EN = set(stopwords.words("english"))
except ImportError:
    raise SystemExit(
        "NLTK library not found.  pip install nltk\n"
        "Then: python -m nltk.downloader stopwords"
    )
except LookupError:
    raise SystemExit(
        "NLTK stopwords not found.\n"
        "In Python: import nltk; nltk.download('stopwords')"
    )

# -- Central config (lives alongside this script) --------------------------- #
try:
    import config
except ImportError:
    raise SystemExit("config.py not found. Place it in the same directory.")

# -- Paths ------------------------------------------------------------------ #
CODE_DIR = Path(__file__).resolve().parent
ROOT_DIR = CODE_DIR.parent
DEFAULT_DATA_DIR = ROOT_DIR / "external" / "samp"
CATALOG_DIR = ROOT_DIR / "external" / "catalogs"
DEFAULT_OUT_DIR = ROOT_DIR / "output"

# -- Pre-compile regexes & pre-filter keys (once, at import time) ----------- #
SKU_REGEX_KEYS = [
    "cas_full", "item_ref_full", "sku_multi_hyphen", "sku_num_num",
    "sku_very_long_num", "sku_alpha_hyphen_num", "sku_letters_digits",
]
UNIT_REGEX_KEYS = [
    "num_in_paren_unit_counts", "num_in_paren_quantities", "unitpack",
    "sets_pk", "dimensions", "mult", "trailing_slash_unit",
]
NOISE_REGEX_KEYS = [
    k for k in config.REGEXES_NORMALIZE
    if k not in SKU_REGEX_KEYS and k not in UNIT_REGEX_KEYS
]

def _compile_regex_list(keys):
    """Return [(compiled_pattern, replacement)] for keys present in config.

    Handles both raw pattern strings and already-compiled re.Pattern objects
    (config.REGEXES_NORMALIZE stores compiled patterns).
    """
    out = []
    for key in keys:
        if key in config.REGEXES_NORMALIZE:
            pattern, repl = config.REGEXES_NORMALIZE[key]
            if isinstance(pattern, re.Pattern):
                out.append((pattern, repl))
            else:
                try:
                    out.append((re.compile(pattern), repl))
                except re.error:
                    continue
    return out

# Compiled once -- used in every row without re-parsing
_SKU_COMPILED   = _compile_regex_list(SKU_REGEX_KEYS)
_UNIT_COMPILED  = _compile_regex_list(UNIT_REGEX_KEYS)
_NOISE_COMPILED = _compile_regex_list(NOISE_REGEX_KEYS)
_ALL_COMPILED   = _SKU_COMPILED + _UNIT_COMPILED + _NOISE_COMPILED

# Stopword set -- built once
_ALL_STOPWORDS = STOP_EN | config.OTHER_STOPWORDS | set(config.UNIT_TOKENS)

# -- Core cleaning & extraction --------------------------------------------- #

def get_clean_description(desc) -> str:
    """Normalise and clean a single product description string."""
    if pd.isna(desc):
        return ""

    text = str(desc).lower()
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("utf-8")

    for compiled_re, repl in _ALL_COMPILED:
        text = compiled_re.sub(repl, text)

    tokens = text.split()
    clean_tokens = [t for t in tokens if t not in _ALL_STOPWORDS and len(t) > 1]

    # Deduplicate while preserving order
    final_string = " ".join(dict.fromkeys(clean_tokens))

    # Strip a leading hyphen left over from regex replacements
    if final_string.startswith("-"):
        final_string = final_string[1:].lstrip()

    return final_string


def _extract_matches(text, compiled_list):
    """Run a list of compiled regexes and collect all captured groups."""
    found = []
    for compiled_re, _ in compiled_list:
        for m in compiled_re.finditer(text):
            groups = m.groups()
            if groups:
                # Keep the first non-empty group (or the full match)
                val = next((g for g in groups if g), m.group())
            else:
                val = m.group()
            found.append(val)
    return found


def get_potential_sku(desc) -> str:
    """Extract potential SKU / catalog numbers from the raw description."""
    if pd.isna(desc):
        return ""
    return ", ".join(_extract_matches(str(desc), _SKU_COMPILED))


def get_potential_unit(desc) -> str:
    """Extract potential unit / quantity strings from the raw description."""
    if pd.isna(desc):
        return ""
    return ", ".join(_extract_matches(str(desc), _UNIT_COMPILED))


# -- File I/O helpers ------------------------------------------------------- #

_FILE_READERS = {
    ".csv":  lambda fp: pd.read_csv(fp, dtype=str, on_bad_lines="warn"),
    ".xlsx": lambda fp: pd.read_excel(fp, dtype=str),
    ".xls":  lambda fp: pd.read_excel(fp, dtype=str),
    ".dta":  lambda fp: _read_stata(fp),
}

def _read_stata(fp):
    df = pd.read_stata(fp)
    for col in df.select_dtypes(include=["object"]).columns:
        df[col] = df[col].astype(str)
    return df


# Map specific filenames to their description column in config
_FILENAME_DESC_COL = {
    "non_lab.dta":       lambda: config.CA_DESC_COL.lower(),
    "fisher_lab.xlsx":   lambda: config.FISHER_DESC_COL.lower(),
    "fisher_nonlab.xlsx": lambda: config.FISHER_DESC_COL.lower(),
}


def _resolve_desc_column(df, filename):
    """Return the description column name to use, or None if not found."""
    if filename in _FILENAME_DESC_COL:
        col = _FILENAME_DESC_COL[filename]()
        return col if col in df.columns else None

    # Try common description column names in priority order
    for candidate in ["product_desc", "prdct_description"]:
        if candidate in df.columns:
            return candidate
    return None


def _find_file(name, search_dirs):
    """Return the first existing path for *name* across *search_dirs*."""
    for d in search_dirs:
        candidate = d / name
        if candidate.exists():
            return candidate
    return None


# -- Main ------------------------------------------------------------------- #

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Clean FOIA data using regex patterns from config.py."
    )
    parser.add_argument(
        "--data-dir", default=str(DEFAULT_DATA_DIR),
        help="Directory containing raw FOIA csv files.",
    )
    parser.add_argument(
        "--files", default="",
        help="Comma-separated list of exact filenames to process.",
    )
    args = parser.parse_args()

    data_dir = Path(args.data_dir)
    out_dir = DEFAULT_OUT_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    # -- Resolve file list --
    if args.files:
        search_dirs = [data_dir, CATALOG_DIR, Path.cwd()]
        files_to_process = []
        for name in args.files.split(","):
            name = name.strip()
            fp = _find_file(name, search_dirs)
            if fp:
                files_to_process.append(fp)
            else:
                print(f"  Warning: file not found in known directories: {name}. Skipping.")
    else:
        files_to_process = sorted(data_dir.glob("*.csv"))
        files_to_process.extend([
            CATALOG_DIR / "non_lab.dta",
            CATALOG_DIR / "ny_fisher_desc.csv",
        ])

    print(f"Found {len(files_to_process)} target workbook(s) to clean...")

    for fp in files_to_process:
        if not fp.exists():
            print(f"  Warning: target file not found: {fp}. Skipping.")
            continue

        print(f"Processing {fp.name} ...")

        # -- Read --
        reader = _FILE_READERS.get(fp.suffix)
        if reader is None:
            print(f"  Warning: unsupported file type: {fp.suffix}. Skipping.")
            continue
        try:
            df = reader(fp)
        except Exception as e:
            print(f"  Error: could not read {fp.name}: {e}")
            continue

        # -- Standardise columns --
        df.columns = df.columns.str.lower()

        desc_col = _resolve_desc_column(df, fp.name)
        if desc_col is None:
            print(f"  Warning: no description column found in {fp.name}. Skipping.")
            continue

        if desc_col != "product_desc":
            df.rename(columns={desc_col: "product_desc"}, inplace=True)

        # -- Clean & extract (column-wise, not row-wise) --
        raw = df["product_desc"]
        df["clean_desc"]     = raw.apply(get_clean_description)
        df["potential_sku"]  = raw.apply(get_potential_sku)
        df["potential_unit"] = raw.apply(get_potential_unit)

        # -- Reorder columns --
        priority = ["product_desc", "clean_desc", "potential_sku", "potential_unit"]
        rest = [c for c in df.columns if c not in priority]
        df = df[priority + rest]

        # -- Write --
        out_path = out_dir / f"{fp.stem}_clean.csv"
        df.to_csv(out_path, index=False)
        print(f"  -> Saved {out_path}")

    print("\nAll targeted workbooks processed.")


if __name__ == "__main__":
    main()
