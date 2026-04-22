# config.py
"""
Central configuration file for the lab consumables classification pipeline.
"""
import os
import re

# ==============================================================================
# 1. Base Directory Setup & Variant Configuration
# ==============================================================================
CODE_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = os.path.abspath(os.path.join(CODE_DIR, ".."))

# Pipeline variant: controls data sources and features.
#   "baseline"        — UT Dallas only, no supplier features
#   "umich_supplier"  — adds UMich training data + supplier name token
# Set via:  PIPELINE_VARIANT=umich_supplier python <script>.py
VARIANT = os.environ.get('PIPELINE_VARIANT', 'baseline')
USE_UMICH = 'umich' in VARIANT
USE_SUPPLIER = 'supplier' in VARIANT

# ==============================================================================
# 2. Input File Paths
# ==============================================================================
FOIA_INPUT_DIR = os.path.join(BASE_DIR, "external", "samp")
UT_DALLAS_CLEAN_CSV = os.path.join(BASE_DIR, "external", "samp", "utdallas_2011_2024_standardized_clean.csv")
UT_DALLAS_CATEGORIES_XLSX = os.path.join(BASE_DIR, "external", "combined", "combined_nochem.xlsx")
UMICH_CLEAN_CSV = os.path.join(BASE_DIR, "external", "samp", "umich_2010_2019_standardized_clean.csv")
UMICH_CATEGORIES_XLSX = os.path.join(BASE_DIR, "external", "combined", "combined_mich.xlsx")
COMBINED_CATEGORIES_XLSX = os.path.join(BASE_DIR, "external", "combined", "combined_umich_utdallas.xlsx")
CA_NON_LAB_DTA = os.path.join(BASE_DIR, "external", "samp", "non_lab_clean.csv")
SEED_KEYWORD_YAML = os.path.join(CODE_DIR, "initial_seed.yml")
ANTI_SEED_KEYWORD_YAML = os.path.join(CODE_DIR, "anti_seed_keywords.yml")
FISHER_LAB = os.path.join(BASE_DIR, "external", "samp", "fisher_lab_clean.csv")
FISHER_NONLAB = os.path.join(BASE_DIR, "external", "samp", "fisher_nonlab_clean.csv")
MARKET_RULES_YAML = os.path.join(CODE_DIR, "market_rules.yml")
GOVSPEND_PANEL_CSV = os.path.join(BASE_DIR, "external", "govspend", "govspend_panel.csv")

# ==============================================================================
# 3. Intermediate & Output File Paths (variant-specific)
# ==============================================================================
TEMP_DIR = os.path.join(BASE_DIR, "temp", VARIANT)
os.makedirs(TEMP_DIR, exist_ok=True)

UT_DALLAS_MERGED_CLEAN_PATH = os.path.join(TEMP_DIR, "utdallas_merged_clean.parquet")
UMICH_MERGED_CLEAN_PATH = os.path.join(TEMP_DIR, "umich_merged_clean.parquet")
COMBINED_MERGED_CLEAN_PATH = os.path.join(TEMP_DIR, "combined_merged_clean.parquet")

OUTPUT_DIR = os.path.join(BASE_DIR, "output", VARIANT)
os.makedirs(OUTPUT_DIR, exist_ok=True)

PREPARED_DATA_PATH = os.path.join(OUTPUT_DIR, "prepared_training_data.parquet")
# UMich data labeled with the same keyword hierarchy as training, saved under
# baseline so script 2 can evaluate the baseline model on the full UMich
# corpus (fully out-of-sample under baseline).  Unused under umich_supplier,
# where UMich evaluation uses the 20% hold-out slice of PREPARED_DATA_PATH.
UMICH_EVAL_DATA_PATH = os.path.join(OUTPUT_DIR, "umich_eval_data.parquet")
CATEGORY_MODEL_DATA_PATH = os.path.join(OUTPUT_DIR, "category_vectors_tfidf.joblib")
CATEGORY_VECTORIZER_PATH = os.path.join(OUTPUT_DIR, "category_tfidf_vectorizer.joblib")
CATEGORY_CHAR_VECTORIZER_PATH = os.path.join(OUTPUT_DIR, "category_char_vectorizer.joblib")
CATEGORY_FEATURE_WEIGHTS_PATH = os.path.join(OUTPUT_DIR, "category_feature_weights.joblib")

# ==============================================================================
# 4. Column Names & Model Parameters
# ==============================================================================
CLEAN_DESC_COL = "clean_desc"
RAW_DESC_COL = "product_desc"
UT_DALLAS_MERGE_KEYS = ["supplier_id", "sku", "product_desc", "supplier"]
UMICH_MERGE_KEYS = ["supplier_id", "product_desc", "supplier"]
COMBINED_MERGE_KEYS = ["supplier_id", "sku", "product_desc", "supplier", "uni"]
UT_CAT_COL = "category"

# Supplier vs description feature weighting (only used when USE_SUPPLIER=True)
SUPPLIER_WEIGHT = 0.15
DESC_WEIGHT = 1.0 - SUPPLIER_WEIGHT  # 0.85

PREDICTION_THRESHOLD = 0.7
CATEGORY_VECTORIZER_MIN_DF = 7
GATEKEEPER_VECTORIZER_MIN_DF = 5

# Second-stage "bulk chemical / instrument part" filter.  Runs only on items
# the primary classifier predicts as lab.  Flips to non-lab when the filter's
# confidence exceeds BULK_FILTER_THRESHOLD.  Keep the threshold high — a false
# positive here directly costs lab recall.
#
# Threshold sweep on umich_supplier (UTD + UMich hold-outs):
#   0.5 — UMich NL precision collapses to 0.574 (too many real lab items flipped)
#   0.7 — UMich NL precision drops to 0.616 (still too aggressive for UMich)
#   0.9 — modest gains on both corpora (UTD NL R +4.4pt, UMich NL R +2.5pt)
# Disabled after the 0.9 rerun flipped ~1400 genuine UMich lab items to non-lab
# (873 synthetic DNA oligos, 260 primary antibodies, 220 small-molecule inhibitors,
# 34 restriction enzymes, ...).  Filter cannot handle short/cryptic primer &
# protein names; keep off until retrained with UMich-style short descriptions.
USE_BULK_FILTER = False
BULK_FILTER_THRESHOLD = 0.9

# Supplier priors as a post-hoc overlay.  At train time we compute per-supplier
# (count, lab_rate) on the training split and stash it on the HybridClassifier.
# At inference, AFTER the ML has decided, items whose supplier is confidently
# lab or non-lab (>= MIN_COUNT items in training) get their prediction flipped
# to match the supplier's dominant class.  Strong-lab and anti-seed matches
# are not overridden.
USE_SUPPLIER_PRIOR = True
SUPPLIER_PRIOR_MIN_COUNT = 20
# Symmetric very-high thresholds: only flip when the supplier is extreme
# in training data (>=95% of items one class).  The 0.05 lower bound means
# "supplier's items are 95%+ non-lab in training → flip lab→non-lab".
SUPPLIER_PRIOR_LAB_THRESHOLD = 0.05       # <=5% lab → flip lab→non-lab
SUPPLIER_PRIOR_LAB_HIGH_THRESHOLD = 0.95  # >=95% lab → flip non-lab→lab

# Primer / oligo name rule.  UMich FN audit showed ~100 synthetic DNA oligos
# being classified non-lab because the descriptions are bare primer names
# ("egl_9_sa307_F", "rcf2confirm", "pPD9577_sticky_end_srh142p_F") with no
# lab vocabulary left after clean_for_model strips them.  Detect the
# structural primer signals: _F/_R direction suffix at end of token, CRISPR
# context, Gateway att sites, sticky-end cloning.  Matches force lab and
# protect from bulk-filter / supplier-prior flips.
USE_PRIMER_RULE = True
PRIMER_REGEX = (
    r'_[fr]\d*(?=$|[\s\-])'        # _F, _R, _F2, _R1 at end of token
    r'|\bcrispr\b'                  # CRISPR primer/guide context
    r'|sticky[\s_]end'              # sticky-end cloning
    r'|\batt[bplr]\d?\b'            # Gateway attB/attP/attL/attR sites
    r'|\bsgrna\b|\bgrna\b'          # guide RNAs
)

# Expert categorizer: contrastive feature weighting + char n-grams.
# Char n-grams catch morphological variants ("rack"/"racks"/"racking"); chi-square
# weighting up-weights tokens that discriminate between categories (e.g. "rack",
# "cap", "holder") and down-weights domain-common tokens (e.g. "cell", "tube").
USE_CHAR_NGRAMS = True
USE_CONTRASTIVE_WEIGHTS = True
CHAR_NGRAM_RANGE = (3, 5)
CHAR_VECTORIZER_MIN_DF = 5

# When a seed or market-rule keyword matches, the gatekeeper normally labels the
# item as lab.  But if the ML model is confidently non-lab (probability below this
# threshold), trust the ML model instead.  This prevents broad keyword patterns
# (e.g. "ethyl", "chlor") from overriding the ML model for items it was explicitly
# trained on as non-lab (like bulk solvents in "irrelevant chemicals").
KEYWORD_OVERRIDE_THRESHOLD = 0.5

# Market-rule gate at inference time.  Market rules use wildcard fragments
# (e.g. `*ethyl*`) which, after wildcard stripping, become bare substrings
# that match inside thousands of unrelated chemical names.  At training
# they're fine because downgrades (anti-seed + non-lab category) clean them
# up; at inference there's no such cleanup, so they inflate FPs massively.
# Keep market rules for training-data labeling in script 1 but disable the
# inference-time gate.  Flip to True to restore the old behavior.
USE_MARKET_RULE_GATE = False

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
    # Cell culture & tissue culture (always lab, never overridden)
    "cell culture", "tissue culture",
    "cell line", "cell lines",
    # Specific lab brands/products that seed keywords also catch
    "eppendorf", "corning cellstar",
    "stericup", "steritop",
    "amicon", "vivaspin",
    # Molecular biology essentials
    "restriction enzyme", "restriction digest",
    "competent cell", "competent cells",
    "plasmid",
    # Staining & imaging
    "hematoxylin", "eosin",
    "hoechst", "dapi",
    # Chromatography consumables (vs. bulk solvents)
    "hplc column", "uplc column", "guard column",
    "sephadex", "sepharose",
    # Pipette accessories (bulbs/fillers that the ML tends to reject as non-lab)
    "latex bulb", "rubber bulb",
    "pipet-aid", "pipet controller", "pipette filler", "powerpette",
    # Extraction / chromatography / assay chemicals misread as bulk
    "thimble",
    "bicinchoninic",
    "phosphoric acid", "phosporic ac", "ortho-phosphoric",
    # Transfection brand names
    "transit lt",
    # Unambiguous lab-context consumables previously lost to Non-Lab under
    # umich_supplier (Dallas regression analysis: ~200 items recovered).
    "centrifugal filter",
    "pes membrane", "pvdf membrane",
    "single channel pipette", "multichannel pipette", "multi-channel pipette",
    "ph paper",
    # Brand / product names recovered from FN audit.  These are unambiguous
    # lab products that the ML component tends to reject when the surrounding
    # description is short or catalog-number-heavy.  "pelco" and "contrad"
    # were intentionally omitted — the audit showed >50% of matching items
    # in the training set are labeled non-lab.
    "supersignal", "supergland",  # SuperSignal West Femto (typo variants)
    "nebuilder",                  # NEB HiFi DNA assembly
    "nonidet", "np-40", "np40",   # NP-40 detergent
    "lipofectamine",
    "tergazyme", "softcide",      # lab-grade detergents
    "mitoview", "mitobrilliant",  # mito-targeted live-cell dyes
    "zymobiomics",                # Zymo microbiome kits
    "cryoloop", "formvar", "laceycarbon",
    "quantum dot",
    # UMich FN additions: borderline terms kept here (not seed) so they only
    # force lab when ALREADY keyword-matched — minimizes Dallas regression risk
    "trizma",
    "factor v",
    "deficient plasma",
]

# Expert model similarity thresholds
TFIDF_MIN_SCORE_THRESHOLD = 0.01
BERT_MIN_SCORE_THRESHOLD = 0.1

# Additional stop words for the CATEGORY vectorizer only.
# These terms appear across dozens of lab categories and inflate similarity
# scores without helping distinguish between them.  NOT used by the gatekeeper
# (where e.g. "kit" may carry lab-vs-non-lab signal).
CATEGORY_STOP_WORDS = [
    "kit", "kits",
    "set", "sets",
    "system", "systems",
    "assay", "assays",
    "reagent", "reagents",
    "based",
    "detection",
    "purification",
    "quantitation", "quantification",
]

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
    "nonlab",
    "non-lab",
    "sequencing",
    "unclear",
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
    "trays", "applicators and swabs", "bundle of items", "unclear", 
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

# Lab-only suppliers.  At inference, if the supplier name contains any of
# these substrings (case-insensitive), force label=1 regardless of item
# description.  Anti-seed still wins (a "shipping fee" from Dharmacon is
# still non-lab).
#
# Complements the learned supplier priors: priors require ≥ MIN_COUNT
# training items and only cover suppliers seen in training, whereas this
# allowlist works deterministically for any supplier-name match.  Keep
# strings long enough to avoid false matches (e.g. "ems" would match
# "systems").
LAB_SUPPLIER_KEYWORDS = [
    # Oligo / siRNA / DNA synthesis
    "integrated dna tech",
    "dharmacon",
    "empire genomics",
    "genscript",
    # Antibodies / immunochemistry
    "abgent",
    "abcam",
    "proteintech",
    "rockland immunochem",
    "chromotek",
    "jackson immunoresearch",
    "cell signaling tech",
    "santa cruz biotech",
    # Enzymes / molecular biology
    "new england biolabs",
    "takara bio",
    "qiagen",
    "applied biosystems",
    # Electron microscopy
    "electron microscopy sciences",
    "ems acquisition",
    # Small molecules / inhibitors
    "cayman chemical",
    "selleck chemical",
    "lc laboratories",
    "enzo life sciences",
    "invivogen",
    # Lipids
    "avanti polar lipids",
    "nu-chek-prep",
    "nu-chek prep",
    "echelon biosciences",
    # Plasmids / cell culture specialty
    "addgene",
    "viagen biotech",
    # Blood / coagulation reagents
    "haematologic technologies",
    # Microbial phenotyping
    "biolog incorporated",
    "biolog inc",
    # General lab reagents (reagent-only catalogs)
    "gold biotechnology",
    "mp biomedicals",
    "research products international",
    "phenomenex",
    "revvity health sciences",
    # Plasticware / labware specialists
    "usa scientific",
    "denville scientific",
    "dot scientific",
    "life science products",
    # Filtration / bioprocessing
    "millipore",
    "emd chemicals",
]

_lab_supplier_patterns = [re.escape(k.lower()) for k in LAB_SUPPLIER_KEYWORDS]
LAB_SUPPLIER_REGEX = (re.compile('|'.join(_lab_supplier_patterns), re.IGNORECASE)
                      if _lab_supplier_patterns else None)

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
    # NOTE: fee/service/repair tokens (quote, invoice, estimate, repair,
    # service, maintenance, shipping, freight, labor, eval, subscription,
    # renewal, serial) are intentionally NOT stripped.  UMich FP audit showed
    # these are the single strongest non-lab signals — stripping them made
    # "Repair fee (Pipet-Aid)" look like a lab item to the vectorizer.
]

def normalize_supplier(supplier_name):
    """Convert a supplier name to a short prefix token suitable for prepending
    to item descriptions before vectorization.

    Examples:
        'Sigma-Aldrich'               -> 'supp_sigma_aldrich'
        'CDW Government LLC'          -> 'supp_cdw_government'
        'Integrated DNA Technologies' -> 'supp_integrated_dna'
        None / NaN / ''               -> ''

    The 'supp_' prefix prevents collisions with ordinary product terms.
    Stop-word suffixes (inc, llc, corp, co, ltd, lp) are stripped so
    'Fisher Scientific Inc' and 'Fisher Scientific' map to the same token.
    """
    if not isinstance(supplier_name, str) or not supplier_name.strip():
        return ''
    name = re.sub(r'[^a-z0-9\s]', ' ', supplier_name.lower())
    name = re.sub(r'\b(inc|llc|corp|co|ltd|lp|dba|the)\b', ' ', name)
    words = [w for w in name.split() if len(w) >= 3][:3]
    if not words:
        return ''
    return 'supp_' + '_'.join(words)


def clean_for_model(text):
    """Strip non-semantic tokens from a description before vectorization.

    Handles both data that has already been through clean_foia_data.py
    (where most of these are no-ops) and raw data that has not been
    upstream-cleaned (e.g. raw GovSpend).

    Strips:
      - HTML entities and XML escape sequences (&amp;, &#153;, etc.)
      - Price / cost references ($300.00, (actual price $xx))
      - Quote / offer / PO number references embedded in descriptions
      - DNA/RNA nucleotide sequences (10+ consecutive base characters)
      - Gene-synthesis order metadata (configurationid, sequence:, etc.)
      - Catalog/part numbers (AB-1234, cat#12345)
      - Dimensions (12x75mm, 100ml, 4.5in)
      - Pure standalone numbers
    """
    if not isinstance(text, str):
        return ""
    # Remove HTML entities (&amp; &#153; &lt; etc.)
    text = re.sub(r'&(?:[a-zA-Z]+|#\d+);', ' ', text)
    # Remove price references: "$300.00", "(actual price $xx)", "price $xx"
    text = re.sub(r'\(actual\s+price[^)]*\)', ' ', text, flags=re.IGNORECASE)
    text = re.sub(r'\$[\d,]+(?:\.\d+)?', ' ', text)
    # Remove quote/offer/PO number references
    # e.g. "quote #: 7145-4647-26", "Quote # COVQ32522", "offer #EQ1409000026",
    #      "per attached quoteJSKYQ3711", "Quote No: 1163184"
    text = re.sub(r'\bper\s+attached\s+quote\w*', ' ', text, flags=re.IGNORECASE)
    text = re.sub(r'\b(?:quote|offer|po)\s*[#:no.]+\s*[\w/-]+', ' ', text, flags=re.IGNORECASE)
    text = re.sub(r'\bquote\s+no\.?\s*[\w/-]+', ' ', text, flags=re.IGNORECASE)
    # Remove DNA/RNA nucleotide sequences (10+ consecutive base chars)
    text = re.sub(r'\b[ATCGNatcgn]{10,}\b', ' ', text)
    # Remove gene-synthesis order metadata fields and their values
    # e.g. "configurationid: 1391711", "typecode: STANDARD", "sequence: ATCG..."
    text = re.sub(
        r'\b(?:configurationid|typecode|purification|format|tubes|scale|umo)\s*:\s*\S+',
        ' ', text, flags=re.IGNORECASE
    )
    text = re.sub(r'\bsequence\s*:\s*\S+', ' ', text, flags=re.IGNORECASE)
    # Remove catalog/part numbers (e.g., "AB-1234", "cat#12345")
    # Requires a separator (# or -) so drug names like CHIR99021, AZD6244 survive
    text = re.sub(r'\b[a-zA-Z]{1,4}[#-]\d{3,}\b', ' ', text)
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
