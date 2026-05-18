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
GOVSPEND_DIR = ROOT_DIR / "external" / "govspend"
DEFAULT_OUT_DIR = ROOT_DIR / "output"

# -- Greek-letter transliteration ------------------------------------------- #
# The ASCII normalization line below (encode "ascii", "ignore") strips any
# non-ASCII codepoint, which destroys chemistry/biology signal carried by
# Greek letters (`α-amino acid`, `β-lactam`, `µl` micro liters).  Translate
# them to ASCII equivalents BEFORE the destructive normalization step.
# Both the micro sign U+00B5 (`µ`) and Greek small mu U+03BC (`μ`) map to "u"
# so `µl` / `μg` align with the existing SIZE_UNITS vocabulary (ul, ug, ...).
_GREEK_TRANSLITERATION = str.maketrans({
    "α": "alpha",   "Α": "alpha",
    "β": "beta",    "Β": "beta",
    "γ": "gamma",   "Γ": "gamma",
    "δ": "delta",   "Δ": "delta",
    "ε": "epsilon", "Ε": "epsilon",
    "ζ": "zeta",    "Ζ": "zeta",
    "η": "eta",     "Η": "eta",
    "θ": "theta",   "Θ": "theta",
    "ι": "iota",    "Ι": "iota",
    "κ": "kappa",   "Κ": "kappa",
    "λ": "lambda",  "Λ": "lambda",
    "μ": "u",       "Μ": "u",       # Greek mu — used for micro
    "µ": "u",                       # micro sign (separate codepoint)
    "ν": "nu",      "Ν": "nu",
    "ξ": "xi",      "Ξ": "xi",
    "π": "pi",      "Π": "pi",
    "ρ": "rho",     "Ρ": "rho",
    "σ": "sigma",   "Σ": "sigma",
    "ς": "sigma",                   # final-form sigma
    "τ": "tau",     "Τ": "tau",
    "υ": "upsilon", "Υ": "upsilon",
    "φ": "phi",     "Φ": "phi",
    "χ": "chi",     "Χ": "chi",
    "ψ": "psi",     "Ψ": "psi",
    "ω": "omega",   "Ω": "omega",
    # Common scientific symbols that ASCII-encode would drop
    "°": " deg ",
    "±": " plusminus ",
    "·": " ",                       # middle dot in chemistry names
    "→": " to ",
})

# -- Pre-compile regexes & pre-filter keys (once, at import time) ----------- #
# Used for SKU / unit extraction (independent of the cleaning pipeline).
SKU_REGEX_KEYS = [
    "cas_full", "item_ref_full", "sku_multi_hyphen", "sku_num_num",
    "sku_very_long_num", "sku_alpha_hyphen_num", "sku_letters_digits",
]
UNIT_REGEX_KEYS = [
    "num_in_paren_unit_counts", "num_in_paren_quantities", "unitpack",
    "sets_pk", "dimensions", "mult", "trailing_slash_unit", "size_unit_capture",
]

# Ordered pipeline for the full cleaning pass on each description.  Earlier
# rules clean up structured patterns (HTML entities, primer suffixes, admin
# tags) so later rules see canonical text.  Critically, admin-reference
# rules (quote/PO/order/invoice) run BEFORE SKU rules so an entire
# "quote #: 7145-4647-26" is stripped as a unit, not partially eaten by
# `sku_num_num` first.
CLEAN_REGEX_ORDER = [
    # Stage 0 -- encoding artifacts
    "html_entities",
    # Stage 1 -- spacing & symbol normalization
    "comma_space_to_space",
    "percent_ge_symbols", "simple_percent", "stray_math_symbols",
    # Stage 2 -- protect structural primer suffixes (underscore form first,
    # then the space-separated form so "<slug>_F" -> "<slug> fwdprimer"
    # doesn't get re-matched by the space rule).
    "primer_suffix_fwd", "primer_suffix_rev",
    "primer_space_suffix_fwd", "primer_space_suffix_rev",
    # Stage 3 -- hash-enclosed admin tags
    "remove_hash_enclosed", "remove_hash_prefix", "remove_hash_suffix",
    # Stage 4 -- named admin / metadata patterns (BEFORE SKU rules)
    "dr_name", "cas_full", "item_ref_full",
    "actual_price_paren", "dollar_amount", "per_attached_quote",
    "quote_num_full", "offer_num_full", "po_num_full",
    "order_num_full", "invoice_num_full",
    "dna_sequence", "gene_synth_meta", "sequence_field", "catalog_num_short",
    # Stage 5 -- unit / quantity normalization
    "num_in_paren_unit_counts", "num_in_paren_quantities",
    "unitpack", "sets_pk", "dimensions", "mult",
    "trailing_slash_unit", "size_unit_capture",
    # Stage 6 -- SKU patterns (run AFTER admin patterns are cleaned)
    "sku_multi_hyphen", "sku_num_num", "sku_very_long_num",
    "sku_alpha_hyphen_num", "sku_letters_digits",
    # Stage 7 -- general character cleanup
    "nonalp", "trailh", "withslash", "clean_hyphens", "empty_parens",
    "multispc",  # always last
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
_SKU_COMPILED  = _compile_regex_list(SKU_REGEX_KEYS)
_UNIT_COMPILED = _compile_regex_list(UNIT_REGEX_KEYS)
_ALL_COMPILED  = _compile_regex_list(CLEAN_REGEX_ORDER)

# Stopword set -- built once
_ALL_STOPWORDS = STOP_EN | config.OTHER_STOPWORDS | set(config.UNIT_TOKENS)

# -- Core cleaning & extraction --------------------------------------------- #

def get_clean_description(desc) -> str:
    """Normalise and clean a single product description string."""
    if pd.isna(desc):
        return ""

    text = str(desc).lower()
    # Transliterate Greek letters and select scientific symbols BEFORE the
    # ASCII-encode step destroys them.  Without this, `α-amino`, `β-lactam`,
    # `µl` lose all non-ASCII characters silently.
    text = text.translate(_GREEK_TRANSLITERATION)
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
    "fisher_chemical.xlsx": lambda: config.FISHER_DESC_COL.lower(),
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
        search_dirs = [data_dir, CATALOG_DIR, GOVSPEND_DIR, Path.cwd()]
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
            CATALOG_DIR / "fisher_lab.xlsx",
            CATALOG_DIR / "fisher_nonlab.xlsx",
            GOVSPEND_DIR / "govspend_panel.csv",
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
        df.columns = df.columns.str.strip().str.lower()

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

        # -- Save a 2010-2019 subset for umich_1998_2019 --
        if "umich_1998_2019" in fp.stem and "date" in df.columns:
            df_date = pd.to_datetime(df["date"], errors="coerce")
            df_sub = df[(df_date.dt.year >= 2010) & (df_date.dt.year <= 2019)]
            sub_path = out_dir / f"{fp.stem.replace('1998_2019', '2010_2019')}_clean.csv"
            df_sub.to_csv(sub_path, index=False)
            print(f"  -> Saved {sub_path} ({len(df_sub)} rows)")

    print("\nAll targeted workbooks processed.")


if __name__ == "__main__":
    main()
