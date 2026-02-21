# config.py
"""
Central configuration file for the lab consumables classification pipeline.
"""
import os
import re

# ==============================================================================
# 1. Base Directory Setup
# ==============================================================================
CODE_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = os.path.abspath(os.path.join(CODE_DIR, ".."))

# ==============================================================================
# 2. Input File Paths
# ==============================================================================
FOIA_INPUT_DIR = os.path.join(BASE_DIR, "external", "samp")
UT_DALLAS_CLEAN_CSV = os.path.join(BASE_DIR, "external", "samp", "utdallas_2011_2024_standardized_clean.csv")
UT_DALLAS_CATEGORIES_XLSX = os.path.join(BASE_DIR, "external", "combined", "combined_nochem.xlsx")
CA_NON_LAB_DTA = os.path.join(BASE_DIR, "external", "samp", "non_lab_clean.csv")
SEED_KEYWORD_YAML = os.path.join(CODE_DIR, "initial_seed.yml")
ANTI_SEED_KEYWORD_YAML = os.path.join(CODE_DIR, "anti_seed_keywords.yml")
FISHER_LAB = os.path.join(BASE_DIR, "external", "samp", "fisher_lab_clean.csv")
FISHER_NONLAB = os.path.join(BASE_DIR, "external", "samp", "fisher_nonlab_clean.csv")
MARKET_RULES_YAML = os.path.join(CODE_DIR, "market_rules.yml")
GOVSPEND_PANEL_CSV = os.path.join(BASE_DIR, "external", "govspend", "govspend_panel.csv")

# ==============================================================================
# 3. Intermediate & Output File Paths
# ==============================================================================
TEMP_DIR = os.path.join(BASE_DIR, "temp")
os.makedirs(TEMP_DIR, exist_ok=True)

UT_DALLAS_MERGED_CLEAN_PATH = os.path.join(TEMP_DIR, "utdallas_merged_clean.parquet")

OUTPUT_DIR = os.path.join(BASE_DIR, "output")
os.makedirs(OUTPUT_DIR, exist_ok=True)

PREPARED_DATA_PATH = os.path.join(OUTPUT_DIR, "prepared_training_data.parquet")
CATEGORY_MODEL_DATA_PATH = os.path.join(OUTPUT_DIR, "category_vectors_tfidf.joblib")
CATEGORY_VECTORIZER_PATH = os.path.join(OUTPUT_DIR, "category_tfidf_vectorizer.joblib")

# ==============================================================================
# 4. Column Names & Model Parameters
# ==============================================================================
CLEAN_DESC_COL = "clean_desc"
RAW_DESC_COL = "product_desc"
UT_DALLAS_MERGE_KEYS = ["supplier_id", "sku", "product_desc", "supplier"]
UT_CAT_COL = "category"

PREDICTION_THRESHOLD = 0.5
CATEGORY_VECTORIZER_MIN_DF = 7
GATEKEEPER_VECTORIZER_MIN_DF = 5

# When a seed or market-rule keyword matches, the gatekeeper normally labels the
# item as lab.  But if the ML model is confidently non-lab (probability below this
# threshold), trust the ML model instead.  This prevents broad keyword patterns
# (e.g. "ethyl", "chlor") from overriding the ML model for items it was explicitly
# trained on as non-lab (like bulk solvents in "irrelevant chemicals").
KEYWORD_OVERRIDE_THRESHOLD = 0.40

# Strong lab signals: if a description contains ANY of these substrings and also
# matches a seed/market-rule keyword, always classify as lab regardless of ML
# confidence.  These are terms so specific to lab products that the ML override
# should never reject them (e.g. "antibody" is never a non-lab product).
STRONG_LAB_SIGNALS = [
    "antibody", "antibodies",
    "anti-human", "anti-mouse", "anti-rabbit", "anti-rat", "anti-goat",
    "anti-sheep", "anti-chicken", "anti-donkey",
    "monoclonal", "polyclonal",
    "elisa", "immunoassay",
    "sirna", "shrna", "mirna", "mrna",
    "transfection",
    "western blot",
    "pcr master mix",
    "kimwipe", "kim wipe", "kimtech",
    "kaydry", "wypall",
    "propidium iodide", "trypan blue",
    "calcein", "mitotracker",
    "vectashield", "fluoromount",
    "trizol", "tri-reagent", "qiazol",
    "dynabeads",
    "alexa fluor", "irdye",
    "griess reagent", "tetrazolium",
    "anti-histone", "anti-phospho",
    "f4/80",
]

# Expert model similarity thresholds
TFIDF_MIN_SCORE_THRESHOLD = 0.01
BERT_MIN_SCORE_THRESHOLD = 0.1

# ==============================================================================
# 5. Non-Lab Category Definitions
# ==============================================================================
# Prefix patterns: any category STARTING with these strings is non-lab.
# Catches entire families like "fees - shipping", "electronics - cables", etc.
NONLAB_PREFIXES = [
    "fees",
    "electronics",
    "instrument",
    "office",
    "lab furniture",
    "waste disposal",
    "equipment",
    "furniture",
    "software",
    "animal",
    "toolkit",
]

# Keyword patterns: categories containing these as whole words are non-lab.
NONLAB_KEYWORDS = [
    "clamp", "clamps", "tool", "random", "unclear",
    "tubing", "wire", "towel", "irrelevant chemicals", "oring",
    "caps", "gas", "first-aid", "first aid", "desk", "chair",
    "brushes", "trash", "cleaner", "cotton ball", "bundle of products",
    "tape", "miscellaneous", "clips", "flint", "accessories", "stands",
    "batteries", "ear protection", "apron", "pots", "pans",
    "stoppers", "closures", "rings", "mortar", "pestle", "supports",
    "trays", "applicators and swabs", "bundle of items",
]

# Build a single compiled regex that handles both prefix and keyword matching.
_prefix_patterns = [r'^' + re.escape(p.strip()) for p in NONLAB_PREFIXES]
_keyword_patterns = [r'\b' + re.escape(k.strip()) + r'\b' for k in NONLAB_KEYWORDS]
_all_patterns = _prefix_patterns + _keyword_patterns
NONLAB_REGEX = re.compile('|'.join(_all_patterns), re.IGNORECASE)

# ==============================================================================
# 6. Supplier-Based Non-Lab Classification
# ==============================================================================
# Suppliers whose names contain these keywords are overwhelmingly non-lab.
# Items from these suppliers are forced to Non-Lab before any classification.
# Uses case-insensitive substring matching against the supplier name.
NONLAB_SUPPLIER_EXACT = [
    # Exact supplier names (matched exactly after lowercasing + stripping)
    "cardinal health 411 inc",
    "henry ford health system",
    "jackson laboratory",
]

# ==============================================================================
# 7. Model Token Filtering
# ==============================================================================
# Domain-specific stop words: tokens that appear frequently in procurement
# descriptions but carry no lab-vs-non-lab classification signal.
DOMAIN_STOP_WORDS = [
    # Units & quantities
    "pk", "cs", "ea", "bx", "bg", "ct", "lb", "oz", "ml", "ul", "mg",
    "kg", "gal", "qt", "pt", "ft", "mm", "cm", "lt",
    # Pack/case descriptors
    "per", "case", "pack", "box", "bag", "each", "unit", "units",
    # Generic commercial terms
    "price", "qty", "quantity", "order", "item", "catalog", "cat",
    "no", "num", "number", "ref", "sku",
]

def clean_for_model(text):
    """Strip non-semantic tokens (part numbers, dimensions, pure numbers)
    from a description before vectorization so the model focuses on
    meaningful product terms."""
    if not isinstance(text, str):
        return ""
    # Remove catalog/part numbers (e.g., "AB-1234", "CAT#12345")
    text = re.sub(r'\b[A-Z]{0,4}[#-]?\d{3,}\b', ' ', text)
    # Remove dimensions (e.g., "12x75mm", "100ml", "4.5in")
    text = re.sub(
        r'\b\d+(\.\d+)?\s*(x\s*\d+(\.\d+)?\s*)*(mm|cm|ml|ul|mg|kg|oz|lb|in|ft|gal)\b',
        ' ', text, flags=re.IGNORECASE
    )
    # Remove pure numbers (standalone integers/decimals)
    text = re.sub(r'\b\d+(\.\d+)?\b', ' ', text)
    # Collapse whitespace
    return re.sub(r'\s+', ' ', text).strip()

NONLAB_SUPPLIER_KEYWORDS = [
    # Service / administrative / office
    "xpedx", "xerox", "acct", "accounting",
    "photography", "music", "graphics",
    "publishing", "productions", "promotional",
    "mailing", "lithographing", "advtsng",
    # Travel / hospitality / events
    "travel", "airline", "aviation", "touring", "airport",
    "hotel", "sheraton", "resort", "centerplate",
    "event", "entertainment",
    # Facilities / construction / industrial services
    "plumbing", "hvac", "seating", "sprinkler", "roofing",
    "construct", "painting", "drainage", "heating",
    "floor", "lumber", "architectural", "bldg",
    "fire protection", "sanitation strategies",
    "american rock salt", "lowes",
    # IT / telecom / electronics
    "cisco systems", "blackboard", "datadirect", "network solutions",
    "backup technology", "cdw government", "verizon",
    "ibm", "lenovo",
    # Automotive / transport / heavy industry
    "tractor", "toyota", "freight", "cargo", "truck",
    "mower", "body shop",
    "thyssenkrupp", "gerdau", "kintetsu", "nortrax",
    # Food / catering
    "foods", "deli", "coffee", "cater",
    # Sports / fitness / apparel
    "athletic", "sport", "sports", "fitness", "golf",
    "team apparel", "fashion", "unifirst", "uniform",
    "trophies", "trophy", "award",
    # Financial / legal / administrative
    "price waterhouse coopers", "insurance", "investments",
    "united healthcare",
    # Education / publishing (non-supplier)
    "college board", "proquest",
    # Specific non-lab companies
    "davol", "atricure", "cbord group", "dimension data", "nwn",
    "somanetics", "neurotune", "tko", "twitchell",
    "flagcraft", "spectroglyph", "stevesongs", "gle associates",
    "3m unitek", "lma north america",
    "hill rom", "henry schein", "practicon",
    "eckert and ziegler", "ferguson enterprise",
    "tiger",
]
