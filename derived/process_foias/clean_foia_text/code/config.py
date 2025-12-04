# config.py (Cleaned Version)
"""
Central configuration file for the lab consumables classification pipeline.
Contains consolidated file paths, column names, and key lists/regexes.
Redundant items based on a unified pipeline have been removed.
"""

import os
import re

# ==============================================================================
# 1. Base Directory Setup
# ==============================================================================
CODE_DIR = os.path.dirname(os.path.abspath(__file__))

# ==============================================================================
# 3. Output File Paths
# ==============================================================================
OUTPUT_DIR = os.path.abspath(os.path.join(CODE_DIR, "../output"))
os.makedirs(OUTPUT_DIR, exist_ok=True)

# ==============================================================================
# 4. Column Names
# ==============================================================================
FISHER_DESC_COL = "DESCRIPTION"
CA_DESC_COL = "description"
# ==============================================================================
# 5. Keywords & Filters (Consolidated)
# ==============================================================================

UNIT_TOKENS = [
    "ml", "ul", "dl", "cl", "g", "mg", "kg", "ug", "oz", "fl", "gal",
    "gr", "lb", "mm", "cm", "dm", "m", "um", "pk", "cs", "ea", "dz", "bx",
    "case", "tst", "set", "sets", "kt", "rl", "roll", "sets/pk",
    "rx", "v", "u", "mlgrd", "grams", "pack", "pp", "in", "box",
    "wt", "ass", "gm", "inch", "ft", "grad", "prf", "pc", "liter",
    "microliter", "gallon", "pl"
]
CHEM_FRAGMENTS = [
    "oh", "nh2", "cooh", "sh", "boc", "fmoc", "trt", "cbz",
    "tfa", "hcl", "naoh", "edc", "dcc", "peg", "pnp", "nme2",
    "gly", "ala", "phe", "ser", "tyr", "met", "lys", "asp", "glu", "pro",
    "ile", "leu", "val", "thr", "trp", "his", "gln", "asn", "dmem", "n", "m",
    "pbf", "mtb", "mmtr", "tbs", "edta", "atp", "dna", "rna", "ist",
    "penicillin","streptomycin","glutamine", "imdm", "gim", "mes",
    "na", "pe", "tris", "dibenzylideneacetone", "dipalladium", "divinyl", "tetramet", # Added parts
    "ethylhexyl", "dioxane", "insulin", "transferrin", "selenium", "ethyl", "mono", "hexyl"
]
CHEM_SUFFIX_LIST = [
    "acid", "chloride", "bromide", "iodide", "acetate", "sulfate", "phosphate",
    "hydroxide", "ethanol", "methanol", "propanol", "isopropanol", "acetone",
    "dimethyl", "methyl", "butyl", "amine", "amide"
]

OTHER_STOPWORDS = {
    "item", "qty", "catalog", "sku", "ea", "thermo scientific", "fisher",
    "vwr", "cert", "denville", "debbie", "konichek", "science", "zyppy",
    "ref", "off", "cas", "for", "ref", "cat", "&amp", "quote", "bdh",
    "grade","fisherbrand", "acs", "qiagen", "acs reagent",  "promo", "discount",
    "pf", "ster", "rxns", "nmol", "anhydrous", "a.c.s", "w/", "lts",
    "bdh", "ge healthcare", "acs/hplc", "microflex", "midknight", "hp", "lca", "bd",
    "integra", "amp",
}
KEEP_CHARS = {'(', ')', ',', '+', '-', '.', '/',
              '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
              'l', 'n', 'm', 'o', 'd', 'x', 'b', 'g'
             }
CAS_REGEX = re.compile(r"\b\d{2,7}-\d{2}-\d\b")

SYNONYMS = {
    "polymerase chain reaction": "pcr",
    "quantitative polymerase chain reaction": "qpcr",
    "phosphate buffered saline": "pbs",
    "bovine serum albumin": "bsa",
    "fetal bovine serum": "fbs",
    "tris borate edta": "tbe",
    "microtub": "microtube","antibdy" : "antibody",
    "dnapolym": "dna polymerase",
    "stpr" : "stopper",
    "col": "column",
    "syrflt": "syringe filter",
    "flsk": "flask",
    "cult": "culture",
    "erlenm": "erlenmeyer",
    "mstr mix": "master mix",
    "tbe buffer": "tbe", "lbl": "label",
    "pcr tb": "pcr tube",
    "mct": "microtube",
    "micropipt": "micropipette",
    "rec": "recombinant",
    "deep wl":"deep well",
    "blch": "bleach",
    "glv": "glove", "glvs": "glove", "gloves": "glove", "examglove": "glove",
    "pipet": "pipette", "kt": "kit", "assy": "assay", "cntrfugl": "centrifugal",
    "fltr": "filter", "flt": "filter", "ultraviolet": "uv", "clr": "clear", "syrng": "syringe", "syr":"syringe",
    "alum": "aluminum", "tubes": "tube", "sieves": "sieve"
}
# Create a string of the KEEP_CHARS excluding space, for building the nonalp regex
_ALLOWED_SYMBOLS_IN_NONALP = "".join(c for c in KEEP_CHARS if not c.isspace() and not c.isalnum())
NONALP_REGEX_PATTERN = r"[^a-z0-9\s" + re.escape(_ALLOWED_SYMBOLS_IN_NONALP) + r"]"

PROTECTED_WORDS = {
    "rneasy", "rnase", "dnase", "dna", "rna", "pcr", "taq", "fbs", "bsa",
    "cryobox", "buffer"
}
# ==============================================================================
# 6. SpaCy / ML Parameters
# ==============================================================================
SPACY_MODEL_SM = "en_core_web_sm"
SPACY_MODEL_CHEM = "en_ner_bc5cdr_md"
# Ensure _UNIT_RE and _FRAG_PATTERN are defined above this dictionary:
_UNIT_RE = "|".join(UNIT_TOKENS)
_FRAG_PATTERN = "|".join(map(re.escape, CHEM_FRAGMENTS))
_PLACEHOLDER_PREFIX = "protectedmarker" # Not strictly needed in regexes if placeholders are all alpha and long
_TAG_CONTENT_PATTERN = r"\S*[a-zA-Z0-9]\S*"
_MONTHS_FULL_STR = r"(?:january|february|march|april|may|june|july|august|september|october|november|december)"
_MONTHS_ABBR_STR = r"(?:jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)"
_MONTHS_PATTERN_STR = rf"(?:{_MONTHS_FULL_STR}|{_MONTHS_ABBR_STR})"
_YEARS_PATTERN_STR = r"(?:200[0-9]|201[0-9]|202[0-5])" # For years 2000-2025
_DAY_PATTERN_STR = r"\d{1,2}(?:st|nd|rd|th)?"
REGEXES_NORMALIZE = {
    # --- Stage 1: Handle problematic spacing, specific symbols/patterns BEFORE general SKUs ---
    "comma_space_to_space": (re.compile(r",\s+"), " "),
    "percent_ge_symbols": (re.compile(r"(?:[><=≤≥±]+\s*)+\d+(?:\.\d+)?\s*%"), " "),
    "simple_percent":     (re.compile(r"\b\d+(?:\.\d+)?\s*%"), " "),
    "stray_math_symbols": (re.compile(r"\s*[>=<≤≥±]+\s*"), " "),
    "remove_hash_enclosed": (re.compile(rf"#({_TAG_CONTENT_PATTERN})#", re.I), " "),
    "remove_hash_prefix":   (re.compile(rf"(?<!\S)#({_TAG_CONTENT_PATTERN})(?!\S)", re.I), " "),
    "remove_hash_suffix":   (re.compile(rf"(?<!\S)({_TAG_CONTENT_PATTERN})#(?!\S)", re.I), " "),

    "dr_name":       (re.compile(r"\b(?:dr|doctor)\.?\s+[a-z]{2,}(?:\s+[a-z]{2,})?\b", re.I), " "),
    "cas_full":      (re.compile(r"\s*\(\s*cas\s*#?\s*\d{2,7}-\d{2}-\d\s*\)\s*", re.I), " "),
    "item_ref_full": (re.compile(r"\b(?:item\s*#?[\s-]*[a-z0-9\-]{3,}|ref\s*#?[\s-]*[a-z0-9\-]{3,})\b", re.I), " "),
    "num_in_paren_unit_counts": (re.compile(r"\(\s*\d+\s*(?:ea|pk|cs|columns|bottles|units)?\s*\)", re.I), " "),
    "num_in_paren_quantities": (re.compile(r"\(\s*\d+(\.\d+)?\s*(?:ml|ul|g|mg|kg|µg)\s*\)", re.I), " "),
    # --- Stage 2: Units, Quantities, Dimensions ---
    "unitpack":      (re.compile(rf"\b(\d+(\.\d+)?(\s*-\s*\d+(\.\d+)?)*\s*[-/\s]?\s*(?:{_UNIT_RE}|for)|(?:{_UNIT_RE})\s*[-/\s]?\s*\d+)\b", re.I | re.X), " "),
    "sets_pk":       (re.compile(r"\b\d+\s*sets/pk\b", re.I), " "),
    "dimensions":    (re.compile(r"\b\d+(?:/\d+)?(?:[x×]\d+(?:/\d+)?)+\b", re.I), " "),
    "mult":          (re.compile(r"\b\d+\s*[x×]\s*\d+[a-z]*\b", re.I), " "),
    "trailing_slash_unit": (re.compile(rf"/\s*(?:{_UNIT_RE})\b", re.I), " "),
    # --- Stage 3: SKU Rules - Using more stable/original forms ---
    "sku_multi_hyphen": (re.compile(
        rf"\b(?!{_PLACEHOLDER_PREFIX})(?!n-[^\s]+)(?![^\s]*-(?:{_FRAG_PATTERN})(?:-|$))[a-z0-9]{2,}(?:-(?!{_PLACEHOLDER_PREFIX})[a-z0-9]{2,}){2,}[a-z0-9]{1,}\b",
        re.I), " "),
    "sku_num_num":   (re.compile(r"\b\d{4,}-\d{3,}\b"), " "),
    # Long standalone numbers
    "sku_very_long_num": (re.compile(r"\b\d{5,}\b"), " "),
    # --- Stage 4: General Character Cleanup & Final Formatting ---
    "nonalp":        (re.compile(NONALP_REGEX_PATTERN), " "), # Uses KEEP_CHARS
    "trailh":        (re.compile(r"\b\d+\s*-\s*"), " "),
    "withslash":     (re.compile(r"\bw/\s*", re.I), " "),
    "clean_hyphens": (re.compile(r"-\s*-+|^-+|-+$|(?<=\s)-(?=\s)"), " "),
    "empty_parens":  (re.compile(r"\(\s*\)"), " "),
    "multispc":      (re.compile(r"\s+"), " "), # Should be last
}
print("✅ Cleaned Configuration loaded successfully.")
