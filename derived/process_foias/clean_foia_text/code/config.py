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
# Size/content units describe the product itself (volume, mass, length) and are
# preserved in clean_desc — a 2 mL tube and a 50 mL tube are different SKUs.
SIZE_UNITS = [
    # volume
    "ml", "ul", "dl", "cl", "fl", "gal", "gallon", "liter", "microliter", "pl",
    # mass
    "g", "mg", "kg", "ug", "oz", "gr", "lb", "grams", "gm",
    # length
    "mm", "cm", "dm", "um", "in", "inch", "ft",
    # compound
    "mlgrd",
]

# Pack/count units describe packaging and are stripped from clean_desc.
PACK_UNITS = [
    "pk", "cs", "ea", "dz", "bx", "case", "tst", "set", "sets", "kt", "rl",
    "roll", "sets/pk", "rx", "v", "u", "pack", "pp", "box",
    "wt", "ass", "grad", "prf", "pc", "m",
]

# Union kept for stopword filtering (bare "ml" with no number is still noise).
UNIT_TOKENS = SIZE_UNITS + PACK_UNITS

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
# Sort by length descending so longer alternatives match first (e.g. "gallon"
# before "gal", "sets/pk" before "sets") — \b alone doesn't always prevent
# shorter prefix matches when followed by a non-word char like "/".
_SIZE_UNIT_RE = "|".join(sorted(SIZE_UNITS, key=len, reverse=True))
_PACK_UNIT_RE = "|".join(sorted(PACK_UNITS, key=len, reverse=True))
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


def _primer_suffix_repl(direction):
    """Rewrite a primer token like AMP_1455_R to "amp1455 revprimer".

    Underscores inside the primer name are stripped so the label survives
    `nonalp` and doesn't decompose into a stopword (e.g. bare `amp`) plus a
    loose numeric fragment.
    """
    def _repl(m):
        prefix = m.group(1).replace("_", "")
        tail = m.group(2) or ""
        return f" {prefix} {direction}primer{tail}"
    return _repl


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
    # Primer-suffix protection.  Tokens like `AMP_1455_R` or `PCR_F1` carry a
    # primer-direction signal in the `_F`/`_R` suffix that would otherwise be
    # destroyed when `nonalp` strips underscores and SpaCy drops single-char
    # tokens.  We capture the whole primer name and strip its underscores so
    # the label survives as a single token (e.g. `amp1455`) and isn't split
    # into a stopword (`amp`) plus a loose numeric fragment.  The `{3,}?`
    # length floor mirrors the market-rules veto at market_rules.yml:833.
    "primer_suffix_fwd": (
        re.compile(r"\b(\w{3,}?)_(?:f|fwd|forward)(\d*)(?=$|[\s\-_])", re.I),
        _primer_suffix_repl("fwd")),
    "primer_suffix_rev": (
        re.compile(r"\b(\w{3,}?)_(?:r|rev|reverse)(\d*)(?=$|[\s\-_])", re.I),
        _primer_suffix_repl("rev")),
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
    # Parenthesized size quantities: preserve content without parens, joined
    # into a single token so "(500 ml)" -> "500ml" survives tokenization.
    "num_in_paren_quantities": (
        re.compile(
            rf"\(\s*(\d+(?:\.\d+)?)\s*({_SIZE_UNIT_RE})\s*\)", re.I), r" \1\2 "),

    # --- Stage 2: Units, quantities, dimensions ---
    # Strip packaging-only patterns ("500/pk", "12 ea"). Size units like
    # "2.0ml" are intentionally excluded — those define the product identity
    # and are handled by size_unit_capture below.
    "unitpack": (
        re.compile(
            rf"\b(\d+(\.\d+)?(\s*-\s*\d+(\.\d+)?)*\s*[-/\s]?\s*"
            rf"(?:{_PACK_UNIT_RE}|for)"
            rf"|(?:{_PACK_UNIT_RE})\s*[-/\s]?\s*\d+)\b",
            re.I | re.X), " "),
    "sets_pk": (
        re.compile(r"\b\d+\s*sets/pk\b", re.I), " "),
    "dimensions": (
        re.compile(r"\b\d+(?:/\d+)?(?:[x\u00d7]\d+(?:/\d+)?)+\b", re.I), " "),
    "mult": (
        re.compile(r"\b\d+\s*[x\u00d7]\s*\d+[a-z]*\b", re.I), " "),
    "trailing_slash_unit": (
        re.compile(rf"/\s*(?:{_PACK_UNIT_RE})\b", re.I), " "),
    # Normalize-and-capture size units. Joins "2.0 ml" -> "2.0ml" so it
    # survives tokenization as one token, and the outer group lets
    # get_potential_unit capture it into the potential_unit column.
    "size_unit_capture": (
        re.compile(
            rf"\b((\d+(?:\.\d+)?)\s*({_SIZE_UNIT_RE}))\b", re.I), r"\2\3"),

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
