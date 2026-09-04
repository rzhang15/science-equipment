import os
import re

CODE_DIR = os.path.dirname(os.path.abspath(__file__))

OUTPUT_DIR = os.path.abspath(os.path.join(CODE_DIR, "../output"))
os.makedirs(OUTPUT_DIR, exist_ok=True)

FISHER_DESC_COL = "DESCRIPTION"
CA_DESC_COL = "description"

SIZE_UNITS = [
    "ml", "ul", "dl", "cl", "fl", "gal", "gallon", "liter", "microliter", "pl",
    "g", "mg", "kg", "ug", "oz", "gr", "lb", "grams", "gm",
    "mm", "cm", "dm", "um", "in", "inch", "ft",
    "mlgrd",
]

PACK_UNITS = [
    "pk", "cs", "ea", "dz", "bx", "case", "tst", "set", "sets", "kt", "rl",
    "roll", "sets/pk", "rx", "v", "u", "pack", "pp", "box",
    "wt", "ass", "grad", "prf", "pc", "m",
]

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
    "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta",
    "iota", "kappa", "lambda", "nu", "xi", "pi", "rho", "sigma", "tau",
    "upsilon", "phi", "chi", "psi", "omega",
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


_SIZE_UNIT_RE = "|".join(sorted(SIZE_UNITS, key=len, reverse=True))
_PACK_UNIT_RE = "|".join(sorted(PACK_UNITS, key=len, reverse=True))
_FRAG_PATTERN = "|".join(map(re.escape, CHEM_FRAGMENTS))
_PLACEHOLDER_PREFIX = "protectedmarker"
_TAG_CONTENT_PATTERN = r"\S*[a-zA-Z0-9]\S*"

_ALLOWED_SYMBOLS = "".join(
    c for c in KEEP_CHARS if not c.isspace() and not c.isalnum()
)
_NONALP_REGEX_PATTERN = r"[^a-z0-9\s" + re.escape(_ALLOWED_SYMBOLS) + r"]"


def _primer_suffix_repl(direction):
    def _repl(m):
        prefix = m.group(1).replace("_", "")
        tail = m.group(2) or ""
        return f" {prefix} {direction}primer{tail}"
    return _repl


REGEXES_NORMALIZE = {
    "html_entities": (
        re.compile(r"&(?:[a-zA-Z]+|#\d+);"), " "),

    "comma_space_to_space": (
        re.compile(r",\s+"), " "),
    "percent_ge_symbols": (
        re.compile(r"(?:[><=\u2264\u2265\u00b1]+\s*)+\d+(?:\.\d+)?\s*%"), " "),
    "simple_percent": (
        re.compile(r"\b\d+(?:\.\d+)?\s*%"), " "),
    "stray_math_symbols": (
        re.compile(r"\s*[>=<\u2264\u2265\u00b1]+\s*"), " "),
    "primer_suffix_fwd": (
        re.compile(r"\b(\w{3,}?)_(?:f|fwd|forward)(\d*)(?=$|[\s\-_])", re.I),
        _primer_suffix_repl("fwd")),
    "primer_suffix_rev": (
        re.compile(r"\b(\w{3,}?)_(?:r|rev|reverse)(\d*)(?=$|[\s\-_])", re.I),
        _primer_suffix_repl("rev")),
    "primer_space_suffix_fwd": (
        re.compile(r"\b(\w{3,}?)\s+(?:f|fwd|forward)\s+primer(\d*)\b", re.I),
        _primer_suffix_repl("fwd")),
    "primer_space_suffix_rev": (
        re.compile(r"\b(\w{3,}?)\s+(?:r|rev|reverse)\s+primer(\d*)\b", re.I),
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

    "actual_price_paren": (
        re.compile(r"\(actual\s+price[^)]*\)", re.I), " "),
    "dollar_amount": (
        re.compile(r"\$[\d,]+(?:\.\d+)?"), " "),
    "per_attached_quote": (
        re.compile(r"\bper\s+attached\s+quote\w*", re.I), " "),
    "quote_num_full": (
        re.compile(r"\bquote\s*(?:(?:no\.?|number|[#:])\s*)+[\w\-/]{3,}\b", re.I), " "),
    "offer_num_full": (
        re.compile(r"\boffer\s*(?:(?:no\.?|number|[#:])\s*)+[\w\-/]{3,}\b", re.I), " "),
    "po_num_full": (
        re.compile(r"\bp\.?\s*o\.?\s*(?:(?:no\.?|number|[#:])\s*)+[\w\-/]{3,}\b", re.I), " "),
    "order_num_full": (
        re.compile(r"\b(?:order|ord)\s*(?:(?:no\.?|number|[#:])\s*)+[\w\-/]{3,}\b", re.I), " "),
    "invoice_num_full": (
        re.compile(r"\binvoice\s*(?:(?:no\.?|number|[#:])\s*)+[\w\-/]{3,}\b", re.I), " "),

    "dna_sequence": (
        re.compile(r"\b[atcgn]{10,}\b", re.I), " "),
    "gene_synth_meta": (
        re.compile(
            r"\b(?:configurationid|typecode|purification|format|tubes|scale|umo)"
            r"\s*:\s*\S+", re.I), " "),
    "sequence_field": (
        re.compile(r"\bsequence\s*:", re.I), " oligoseq "),
    "catalog_num_short": (
        re.compile(r"\b[a-z]{1,4}[#-]\d{3,}\b", re.I), " "),
    "num_in_paren_unit_counts": (
        re.compile(
            r"\(\s*\d+\s*(?:ea|pk|cs|columns|bottles|units)?\s*\)", re.I), " "),
    "num_in_paren_quantities": (
        re.compile(
            rf"\(\s*(\d+(?:\.\d+)?)\s*({_SIZE_UNIT_RE})\s*\)", re.I), r" \1\2 "),

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
    "size_unit_capture": (
        re.compile(
            rf"\b((\d+(?:\.\d+)?)\s*({_SIZE_UNIT_RE}))\b", re.I), r"\2\3"),

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

    "nonalp": (
        re.compile(_NONALP_REGEX_PATTERN), " "),
    "trailh": (
        re.compile(r"(?<![\d,])\b\d{3,}\s*-\s*"), " "),
    "withslash": (
        re.compile(r"\bw/\s*", re.I), " "),
    "clean_hyphens": (
        re.compile(r"-\s*-+|^-+|-+$|(?<=\s)-(?=\s)"), " "),
    "empty_parens": (
        re.compile(r"\(\s*\)"), " "),
    "multispc": (
        re.compile(r"\s+"), " "),
}

print("Cleaning configuration loaded successfully.")
