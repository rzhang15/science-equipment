# config_cleaning.py
"""
Central configuration for the FOIA data cleaning pipeline (clean_foia_data.py).

NOTE: This is a SEPARATE config from the classification pipeline's config.py.
They must live in different directories. Rename this to config.py when placing
it alongside clean_foia_data.py.
"""
import os
import re

# ==============================================================================
# 1. Base Directory Setup
# ==============================================================================
CODE_DIR = os.path.dirname(os.path.abspath(__file__))

# ==============================================================================
# 2. Output File Paths
# ==============================================================================
OUTPUT_DIR = os.path.abspath(os.path.join(CODE_DIR, "../output"))
os.makedirs(OUTPUT_DIR, exist_ok=True)

# ==============================================================================
# 3. Column Names
# ==============================================================================
FISHER_DESC_COL = "DESCRIPTION"
CA_DESC_COL = "description"

# ==============================================================================
# 4. Keywords & Filters
# ==============================================================================
UNIT_TOKENS = [
    "ml", "ul", "dl", "cl", "g", "mg", "kg", "ug", "oz", "fl", "gal",
    "gr", "lb", "mm", "cm", "dm", "m", "um", "pk", "cs", "ea", "dz", "bx",
    "case", "tst", "set", "sets", "kt", "rl", "roll", "sets/pk",
    "rx", "v", "u", "mlgrd", "grams", "pack", "pp", "in", "box",
    "wt", "ass", "gm", "inch", "ft", "grad", "prf", "pc", "liter",
    "microliter", "gallon", "pl",
]

CHEM_FRAGMENTS = [
    "oh", "nh2", "cooh", "sh", "boc", "fmoc", "trt", "cbz",
    "tfa", "hcl", "naoh", "edc", "dcc", "peg", "pnp", "nme2",
    "gly", "ala", "phe", "ser", "tyr", "met", "lys", "asp", "glu", "pro",
    "ile", "leu", "val", "thr", "trp", "his", "gln", "asn", "dmem", "n", "m",
    "pbf", "mtb", "mmtr", "tbs", "edta", "atp", "dna", "rna", "ist",
    "penicillin", "streptomycin", "glutamine", "imdm", "gim", "mes",
    "na", "pe", "tris", "dibenzylideneacetone", "dipalladium", "divinyl",
    "tetramet", "ethylhexyl", "dioxane", "insulin", "transferrin",
    "selenium", "ethyl", "mono", "hexyl",
]

CHEM_SUFFIX_LIST = [
    "acid", "chloride", "bromide", "iodide", "acetate", "sulfate",
    "phosphate", "hydroxide", "ethanol", "methanol", "propanol",
    "isopropanol", "acetone", "dimethyl", "methyl", "butyl", "amine", "amide",
]

OTHER_STOPWORDS = {
    "item", "qty", "catalog", "sku", "ea", "thermo scientific", "fisher",
    "vwr", "cert", "denville", "debbie", "konichek", "science", "zyppy",
    "ref", "off", "cas", "for", "cat", "&amp", "quote", "bdh",
    "grade", "fisherbrand", "acs", "qiagen", "acs reagent", "promo",
    "discount", "pf", "ster", "rxns", "nmol", "anhydrous", "a.c.s", "w/",
    "lts", "ge healthcare", "acs/hplc", "microflex", "midknight", "hp",
    "lca", "bd", "integra", "amp",
}

KEEP_CHARS = {
    "(", ")", ",", "+", "-", ".", "/",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    "l", "n", "m", "o", "d", "x", "b", "g",
}

SYNONYMS = {
    "polymerase chain reaction": "pcr",
    "quantitative polymerase chain reaction": "qpcr",
    "phosphate buffered saline": "pbs",
    "bovine serum albumin": "bsa",
    "fetal bovine serum": "fbs",
    "tris borate edta": "tbe",
    "microtub": "microtube",
    "antibdy": "antibody",
    "dnapolym": "dna polymerase",
    "stpr": "stopper",
    "col": "column",
    "syrflt": "syringe filter",
    "flsk": "flask",
    "cult": "culture",
    "erlenm": "erlenmeyer",
    "mstr mix": "master mix",
    "tbe buffer": "tbe",
    "lbl": "label",
    "pcr tb": "pcr tube",
    "mct": "microtube",
    "micropipt": "micropipette",
    "rec": "recombinant",
    "deep wl": "deep well",
    "blch": "bleach",
    "glv": "glove", "glvs": "glove", "gloves": "glove", "examglove": "glove",
    "pipet": "pipette", "kt": "kit", "assy": "assay", "cntrfugl": "centrifugal",
    "fltr": "filter", "flt": "filter", "ultraviolet": "uv", "clr": "clear",
    "syrng": "syringe", "syr": "syringe",
    "alum": "aluminum", "tubes": "tube", "sieves": "sieve",
}

PROTECTED_WORDS = {
    "rneasy", "rnase", "dnase", "dna", "rna", "pcr", "taq", "fbs", "bsa",
    "cryobox", "buffer",
}

# ==============================================================================
# 5. SpaCy / ML Parameters
# ==============================================================================
SPACY_MODEL_SM = "en_core_web_sm"
SPACY_MODEL_CHEM = "en_ner_bc5cdr_md"

# ==============================================================================
# 6. Compiled Regex Patterns
# ==============================================================================

# -- Building blocks for regex patterns --
_UNIT_RE = "|".join(UNIT_TOKENS)
_FRAG_PATTERN = "|".join(map(re.escape, CHEM_FRAGMENTS))
_PLACEHOLDER_PREFIX = "protectedmarker"
_TAG_CONTENT_PATTERN = r"\S*[a-zA-Z0-9]\S*"

_MONTHS_FULL = (
    r"(?:january|february|march|april|may|june"
    r"|july|august|september|october|november|december)"
)
_MONTHS_ABBR = r"(?:jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)"
_MONTHS_PATTERN = rf"(?:{_MONTHS_FULL}|{_MONTHS_ABBR})"
_YEARS_PATTERN = r"(?:200[0-9]|201[0-9]|202[0-5])"
_DAY_PATTERN = r"\d{1,2}(?:st|nd|rd|th)?"

# -- Build the non-alphanumeric cleanup regex from KEEP_CHARS --
_ALLOWED_SYMBOLS = "".join(
    c for c in KEEP_CHARS if not c.isspace() and not c.isalnum()
)
_NONALP_REGEX_PATTERN = r"[^a-z0-9\s" + re.escape(_ALLOWED_SYMBOLS) + r"]"

CAS_REGEX = re.compile(r"\b\d{2,7}-\d{2}-\d\b")

# -- Main regex dictionary: (compiled_pattern, replacement) --
# Applied in order by clean_foia_data.py.  Keys are grouped by stage.
REGEXES_NORMALIZE = {
    # --- Stage 1: Spacing, symbols, specific patterns (before SKUs) ---
    "comma_space_to_space": (
        re.compile(r",\s+"), " "),
    "percent_ge_symbols": (
        re.compile(r"(?:[><=\u2264\u2265\u00b1]+\s*)+\d+(?:\.\d+)?\s*%"), " "),
    "simple_percent": (
        re.compile(r"\b\d+(?:\.\d+)?\s*%"), " "),
    "stray_math_symbols": (
        re.compile(r"\s*[>=<\u2264\u2265\u00b1]+\s*"), " "),
    "remove_hash_enclosed": (
        re.compile(rf"#({_TAG_CONTENT_PATTERN})#", re.I), " "),
    "remove_hash_prefix": (
        re.compile(rf"(?<!\S)#({_TAG_CONTENT_PATTERN})(?!\S)", re.I), " "),
    "remove_hash_suffix": (
        re.compile(rf"(?<!\S)({_TAG_CONTENT_PATTERN})#(?!\S)", re.I), " "),
    "dr_name": (
        re.compile(r"\b(?:dr|doctor)\.?\s+[a-z]{2,}(?:\s+[a-z]{2,})?\b", re.I), " "),
    "cas_full": (
        re.compile(r"\s*\(\s*cas\s*#?\s*\d{2,7}-\d{2}-\d\s*\)\s*", re.I), " "),
    "item_ref_full": (
        re.compile(
            r"\b(?:item\s*#?[\s-]*[a-z0-9\-]{3,}"
            r"|ref\s*#?[\s-]*[a-z0-9\-]{3,})\b", re.I), " "),
    "num_in_paren_unit_counts": (
        re.compile(
            r"\(\s*\d+\s*(?:ea|pk|cs|columns|bottles|units)?\s*\)", re.I), " "),
    "num_in_paren_quantities": (
        re.compile(
            r"\(\s*\d+(\.\d+)?\s*(?:ml|ul|g|mg|kg|\xb5g)\s*\)", re.I), " "),

    # --- Stage 2: Units, quantities, dimensions ---
    "unitpack": (
        re.compile(
            rf"\b(\d+(\.\d+)?(\s*-\s*\d+(\.\d+)?)*\s*[-/\s]?\s*"
            rf"(?:{_UNIT_RE}|for)"
            rf"|(?:{_UNIT_RE})\s*[-/\s]?\s*\d+)\b",
            re.I | re.X), " "),
    "sets_pk": (
        re.compile(r"\b\d+\s*sets/pk\b", re.I), " "),
    "dimensions": (
        re.compile(r"\b\d+(?:/\d+)?(?:[x\u00d7]\d+(?:/\d+)?)+\b", re.I), " "),
    "mult": (
        re.compile(r"\b\d+\s*[x\u00d7]\s*\d+[a-z]*\b", re.I), " "),
    "trailing_slash_unit": (
        re.compile(rf"/\s*(?:{_UNIT_RE})\b", re.I), " "),

    # --- Stage 3: SKU patterns ---
    "sku_multi_hyphen": (
        re.compile(
            rf"\b(?!{_PLACEHOLDER_PREFIX})"
            rf"(?!n-[^\s]+)"
            rf"(?![^\s]*-(?:{_FRAG_PATTERN})(?:-|$))"
            rf"[a-z0-9]{{2,}}(?:-(?!{_PLACEHOLDER_PREFIX})[a-z0-9]{{2,}}){{2,}}"
            rf"[a-z0-9]{{1,}}\b",
            re.I), " "),
    "sku_num_num": (
        re.compile(r"\b\d{4,}-\d{3,}\b"), " "),
    "sku_very_long_num": (
        re.compile(r"\b\d{5,}\b"), " "),

    # --- Stage 4: General character cleanup & formatting ---
    "nonalp": (
        re.compile(_NONALP_REGEX_PATTERN), " "),
    "trailh": (
        re.compile(r"\b\d+\s*-\s*"), " "),
    "withslash": (
        re.compile(r"\bw/\s*", re.I), " "),
    "clean_hyphens": (
        re.compile(r"-\s*-+|^-+|-+$|(?<=\s)-(?=\s)"), " "),
    "empty_parens": (
        re.compile(r"\(\s*\)"), " "),
    "multispc": (
        re.compile(r"\s+"), " "),  # should be last
}

print("Cleaning configuration loaded successfully.")
