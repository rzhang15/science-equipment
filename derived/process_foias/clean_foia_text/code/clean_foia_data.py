#!/usr/bin/env python
import re
import unicodedata
import argparse

import pandas as pd
from pathlib import Path

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

try:
    import config
except ImportError:
    raise SystemExit("config.py not found. Place it in the same directory.")

CODE_DIR = Path(__file__).resolve().parent
ROOT_DIR = CODE_DIR.parent
DEFAULT_DATA_DIR = ROOT_DIR / "external" / "samp"
CATALOG_DIR = ROOT_DIR / "external" / "catalogs"
GOVSPEND_DIR = ROOT_DIR / "external" / "govspend"
DEFAULT_OUT_DIR = ROOT_DIR / "output"

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
    "μ": "u",       "Μ": "u",
    "µ": "u",                       # micro sign, distinct from Greek mu
    "ν": "nu",      "Ν": "nu",
    "ξ": "xi",      "Ξ": "xi",
    "π": "pi",      "Π": "pi",
    "ρ": "rho",     "Ρ": "rho",
    "σ": "sigma",   "Σ": "sigma",
    "ς": "sigma",
    "τ": "tau",     "Τ": "tau",
    "υ": "upsilon", "Υ": "upsilon",
    "φ": "phi",     "Φ": "phi",
    "χ": "chi",     "Χ": "chi",
    "ψ": "psi",     "Ψ": "psi",
    "ω": "omega",   "Ω": "omega",
    "°": " deg ",
    "±": " plusminus ",
    "·": " ",
    "→": " to ",
})

SKU_REGEX_KEYS = [
    "cas_full", "item_ref_full", "sku_multi_hyphen", "sku_num_num",
    "sku_very_long_num", "sku_alpha_hyphen_num", "sku_letters_digits",
]
UNIT_REGEX_KEYS = [
    "num_in_paren_unit_counts", "num_in_paren_quantities", "unitpack",
    "sets_pk", "dimensions", "mult", "trailing_slash_unit", "size_unit_capture",
]

CLEAN_REGEX_ORDER = [
    "html_entities",
    "comma_space_to_space",
    "percent_ge_symbols", "simple_percent", "stray_math_symbols",
    "primer_suffix_fwd", "primer_suffix_rev",
    "primer_space_suffix_fwd", "primer_space_suffix_rev",
    "remove_hash_enclosed", "remove_hash_prefix", "remove_hash_suffix",
    "dr_name", "cas_full", "item_ref_full",
    "actual_price_paren", "dollar_amount", "per_attached_quote",
    "quote_num_full", "offer_num_full", "po_num_full",
    "order_num_full", "invoice_num_full",
    "dna_sequence", "gene_synth_meta", "sequence_field", "catalog_num_short",
    "num_in_paren_unit_counts", "num_in_paren_quantities",
    "unitpack", "sets_pk", "dimensions", "mult",
    "trailing_slash_unit", "size_unit_capture",
    "sku_multi_hyphen", "sku_num_num", "sku_very_long_num",
    "sku_alpha_hyphen_num", "sku_letters_digits",
    "nonalp", "trailh", "withslash", "clean_hyphens", "empty_parens",
    "multispc",
]


def _compile_regex_list(keys):
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

_SKU_COMPILED  = _compile_regex_list(SKU_REGEX_KEYS)
_UNIT_COMPILED = _compile_regex_list(UNIT_REGEX_KEYS)
_ALL_COMPILED  = _compile_regex_list(CLEAN_REGEX_ORDER)

_ALL_STOPWORDS = STOP_EN | config.OTHER_STOPWORDS | set(config.UNIT_TOKENS)


def get_clean_description(desc) -> str:
    if pd.isna(desc):
        return ""

    text = str(desc).lower()
    text = text.translate(_GREEK_TRANSLITERATION)
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("utf-8")

    for compiled_re, repl in _ALL_COMPILED:
        text = compiled_re.sub(repl, text)

    tokens = text.split()
    clean_tokens = [t for t in tokens if t not in _ALL_STOPWORDS and len(t) > 1]

    final_string = " ".join(dict.fromkeys(clean_tokens))

    if final_string.startswith("-"):
        final_string = final_string[1:].lstrip()

    return final_string


def _extract_matches(text, compiled_list):
    found = []
    for compiled_re, _ in compiled_list:
        for m in compiled_re.finditer(text):
            groups = m.groups()
            if groups:
                val = next((g for g in groups if g), m.group())
            else:
                val = m.group()
            found.append(val)
    return found


def get_potential_sku(desc) -> str:
    if pd.isna(desc):
        return ""
    return ", ".join(_extract_matches(str(desc), _SKU_COMPILED))


def get_potential_unit(desc) -> str:
    if pd.isna(desc):
        return ""
    return ", ".join(_extract_matches(str(desc), _UNIT_COMPILED))

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


_FILENAME_DESC_COL = {
    "non_lab.dta":       lambda: config.CA_DESC_COL.lower(),
    "fisher_lab.xlsx":   lambda: config.FISHER_DESC_COL.lower(),
    "fisher_nonlab.xlsx": lambda: config.FISHER_DESC_COL.lower(),
    "fisher_chemical.xlsx": lambda: config.FISHER_DESC_COL.lower(),
}


def _resolve_desc_column(df, filename):
    if filename in _FILENAME_DESC_COL:
        col = _FILENAME_DESC_COL[filename]()
        return col if col in df.columns else None

    for candidate in ["product_desc", "prdct_description"]:
        if candidate in df.columns:
            return candidate
    return None


def _find_file(name, search_dirs):
    for d in search_dirs:
        candidate = d / name
        if candidate.exists():
            return candidate
    return None

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

        reader = _FILE_READERS.get(fp.suffix)
        if reader is None:
            print(f"  Warning: unsupported file type: {fp.suffix}. Skipping.")
            continue
        try:
            df = reader(fp)
        except Exception as e:
            print(f"  Error: could not read {fp.name}: {e}")
            continue

        df.columns = df.columns.str.strip().str.lower()

        desc_col = _resolve_desc_column(df, fp.name)
        if desc_col is None:
            print(f"  Warning: no description column found in {fp.name}. Skipping.")
            continue

        if desc_col != "product_desc":
            df.rename(columns={desc_col: "product_desc"}, inplace=True)

        raw = df["product_desc"]
        df["clean_desc"]     = raw.apply(get_clean_description)
        df["potential_sku"]  = raw.apply(get_potential_sku)
        df["potential_unit"] = raw.apply(get_potential_unit)

        priority = ["product_desc", "clean_desc", "potential_sku", "potential_unit"]
        rest = [c for c in df.columns if c not in priority]
        df = df[priority + rest]

        out_path = out_dir / f"{fp.stem}_clean.csv"
        df.to_csv(out_path, index=False)
        print(f"  -> Saved {out_path}")

        if "umich_1998_2019" in fp.stem and "date" in df.columns:
            df_date = pd.to_datetime(df["date"], errors="coerce")
            df_sub = df[(df_date.dt.year >= 2010) & (df_date.dt.year <= 2019)]
            sub_path = out_dir / f"{fp.stem.replace('1998_2019', '2010_2019')}_clean.csv"
            df_sub.to_csv(sub_path, index=False)
            print(f"  -> Saved {sub_path} ({len(df_sub)} rows)")

    print("\nAll targeted workbooks processed.")


if __name__ == "__main__":
    main()
