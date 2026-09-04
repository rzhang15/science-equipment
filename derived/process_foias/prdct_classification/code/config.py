import os
import re

CODE_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = os.path.abspath(os.path.join(CODE_DIR, ".."))

# PIPELINE_VARIANT : baseline | umich_supplier
VARIANT = os.environ.get('PIPELINE_VARIANT', 'baseline')
USE_UMICH = 'umich' in VARIANT
USE_SUPPLIER = 'supplier' in VARIANT

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
FISHER_CHEMICAL = os.path.join(BASE_DIR, "external", "samp", "fisher_chemical_clean.csv")
MARKET_RULES_YAML = os.path.join(CODE_DIR, "market_rules.yml")
GOVSPEND_PANEL_CSV = os.path.join(BASE_DIR, "external", "samp", "govspend_panel_clean.csv")

TEMP_DIR = os.path.join(BASE_DIR, "temp", VARIANT)
os.makedirs(TEMP_DIR, exist_ok=True)

UT_DALLAS_MERGED_CLEAN_PATH = os.path.join(TEMP_DIR, "utdallas_merged_clean.parquet")
UMICH_MERGED_CLEAN_PATH = os.path.join(TEMP_DIR, "umich_merged_clean.parquet")
COMBINED_MERGED_CLEAN_PATH = os.path.join(TEMP_DIR, "combined_merged_clean.parquet")

OUTPUT_DIR = os.path.join(BASE_DIR, "output", VARIANT)
os.makedirs(OUTPUT_DIR, exist_ok=True)

PREPARED_DATA_PATH = os.path.join(OUTPUT_DIR, "prepared_training_data.parquet")
UMICH_EVAL_DATA_PATH = os.path.join(OUTPUT_DIR, "umich_eval_data.parquet")
CATEGORY_MODEL_DATA_PATH = os.path.join(OUTPUT_DIR, "category_vectors_tfidf.joblib")
CATEGORY_VECTORIZER_PATH = os.path.join(OUTPUT_DIR, "category_tfidf_vectorizer.joblib")
CATEGORY_CHAR_VECTORIZER_PATH = os.path.join(OUTPUT_DIR, "category_char_vectorizer.joblib")
CATEGORY_FEATURE_WEIGHTS_PATH = os.path.join(OUTPUT_DIR, "category_feature_weights.joblib")

CLEAN_DESC_COL = "clean_desc"
RAW_DESC_COL = "product_desc"
UT_DALLAS_MERGE_KEYS = ["supplier_id", "sku", "product_desc", "supplier"]
UMICH_MERGE_KEYS = ["supplier_id", "product_desc", "supplier"]
COMBINED_MERGE_KEYS = ["supplier_id", "sku", "product_desc", "supplier", "uni"]
UT_CAT_COL = "category"

SUPPLIER_WEIGHT = 0.15
DESC_WEIGHT = 1.0 - SUPPLIER_WEIGHT

PREDICTION_THRESHOLD = 0.5
CATEGORY_VECTORIZER_MIN_DF = 7
GATEKEEPER_VECTORIZER_MIN_DF = 5

USE_BULK_FILTER = False
BULK_FILTER_THRESHOLD = 0.9

USE_SUPPLIER_PRIOR = True
SUPPLIER_PRIOR_MIN_COUNT = 20
SUPPLIER_PRIOR_LAB_THRESHOLD = 0.05
SUPPLIER_PRIOR_LAB_HIGH_THRESHOLD = 0.99

USE_PRIMER_RULE = True
PRIMER_REGEX = (
    r'_[fr]\d*(?=$|[\s\-])'
    r'|\bcrispr\b'
    r'|sticky[\s_]end'
    r'|\batt[bplr]\d?\b'
    r'|\bsgrna\b|\bgrna\b'
)

USE_CHAR_NGRAMS = True
USE_CONTRASTIVE_WEIGHTS = True
CHAR_NGRAM_RANGE = (3, 5)
CHAR_VECTORIZER_MIN_DF = 5

KEYWORD_OVERRIDE_THRESHOLD = 0.5

USE_MARKET_RULE_GATE = False

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
    "cell culture", "tissue culture",
    "cell line", "cell lines",
    "eppendorf", "corning cellstar",
    "stericup", "steritop",
    "amicon", "vivaspin",
    "restriction enzyme", "restriction digest",
    "competent cell", "competent cells",
    "plasmid",
    "hematoxylin", "eosin",
    "hoechst", "dapi",
    "hplc column", "uplc column", "guard column",
    "sephadex", "sepharose",
    "latex bulb", "rubber bulb",
    "pipet-aid", "pipet controller", "pipette filler", "powerpette",
    "thimble",
    "bicinchoninic",
    "phosphoric acid", "phosporic ac", "ortho-phosphoric",
    "transit lt",
    "centrifugal filter",
    "pes membrane", "pvdf membrane",
    "single channel pipette", "multichannel pipette", "multi-channel pipette",
    "ph paper",
    "supersignal", "supergland",
    "nebuilder",
    "nonidet", "np-40", "np40",
    "lipofectamine",
    "tergazyme", "softcide",
    "mitoview", "mitobrilliant",
    "zymobiomics",
    "cryoloop", "formvar", "laceycarbon",
    "quantum dot",
    "trizma",
    "factor v",
    "deficient plasma",
]

USE_ENGINEERED_FEATURES = True
FEATURE_WEIGHT = 0.10

TFIDF_MIN_SCORE_THRESHOLD = 0.01
BERT_MIN_SCORE_THRESHOLD = 0.1

BERT_MODELS = {
    'minilm':   'sentence-transformers/all-MiniLM-L6-v2',
    'specter2': 'allenai/specter2_base',
}

CATEGORY_CONSOLIDATION = {
    'centrifuge conical tubes': 'centrifuge tubes',
    'filtering funnels': 'funnels',
    'filling funnels': 'funnels',
    'cellular metabolism assay kits': 'metabolism assay kits',
    'human cell lines': 'cell lines',
    'mouse cell lines': 'cell lines',
    'mice cell lines': 'cell lines',
    'rat cell line': 'cell lines',
    'insect cell lines': 'cell lines',
    'dnase/rnase-free & molecular-biology-grade water': 'lab-grade water',
    'general-lab & specialty water': 'lab-grade water',
    'cell culture grade life science water - distilled': 'lab-grade water',
    'pasteur pipettes': 'disposable pipettes',
    'transfer pipettes': 'disposable pipettes',
    'aspirating pipettes': 'disposable pipettes',
    'mohr pipettes': 'disposable pipettes',
    'volumetric pipettes': 'disposable pipettes',
    'manual single channel pipettes': 'manual pipettors',
    'manual multichannel pipettes': 'manual pipettors',
    'electronic multichannel pipettes': 'manual pipettors',
    'pipette kits': 'manual pipettors',
    'pipettors': 'manual pipettors',
    'positive displacement pipettes': 'manual pipettors',
    'glass beakers': 'beakers',
    'plastic beakers': 'beakers',
    'steel beakers': 'beakers',
    'stainless steel beakers': 'beakers',
    'glass graduated cylinders': 'graduated cylinders',
    'plastic graduated cylinders': 'graduated cylinders',
    'fernbach flasks': 'other flasks',
    'volumetric flasks': 'other flasks',
    'recovery flasks': 'other flasks',
    'freeze drying flasks': 'other flasks',
    'kjeldahl flasks': 'other flasks',
    'distilling flasks': 'other flasks',
    'stainless steel flasks': 'other flasks',
    'serum bottles': 'other flasks',
    'separatory funnels': 'funnels',
    'addition funnels': 'funnels',
    'funnel stems': 'funnels',
    'heat resistant gloves': 'specialty gloves',
    'cold resistant gloves': 'specialty gloves',
    'neoprene gloves': 'specialty gloves',
    'cotton gloves': 'specialty gloves',
    'chemical resistant gloves': 'specialty gloves',
    'glove box gloves': 'specialty gloves',
    'cut resistant gloves': 'specialty gloves',
    'vinyl gloves': 'specialty gloves',
    'rubber gloves': 'specialty gloves',
    'glove liners': 'specialty gloves',
    'chloroprene gloves': 'specialty gloves',
    'gloves': 'specialty gloves',
    'nylon membrane filters': 'specialty membrane filters',
    'polycarbonate membrane filters': 'specialty membrane filters',
    'pes membrane filters': 'specialty membrane filters',
    'mce membrane filters': 'specialty membrane filters',
    'membrane filters': 'specialty membrane filters',
    'ptfe membrane filters': 'specialty membrane filters',
    'cellulose acetate membrane filters': 'specialty membrane filters',
    'dispensing needles': 'specialty needles',
    'needles': 'specialty needles',
    'blood collection needles': 'specialty needles',
    'pipetting needles': 'specialty needles',
    'double-tipped needles': 'specialty needles',
    'caps and closures - pcr tube strips': 'pcr tube accessories',
    'pcr strip tubes': 'pcr tube accessories',
    'pcr tube strip caps': 'pcr tube accessories',
    'caps and closures - pcr tubes': 'pcr tube accessories',
    'caps and closures - cryovial': 'caps and closures - vials',
    'autosampler vial caps': 'caps and closures - vials',
    'spectrophotometer cuvettes': 'cuvettes',
    'fluorescence cuvettes': 'cuvettes',
    'electroporation cuvettes': 'cuvettes',
    'polyclonal primary antibodies': 'primary antibodies',
    'monoclonal primary antibodies': 'primary antibodies',
    'polyclonal primary antibody': 'primary antibodies',
    'monoclonal primary antibody': 'primary antibodies',
    'other-host primary antibody': 'primary antibodies',
    'recombinant human protein': 'recombinant proteins',
    'recombinant mouse protein': 'recombinant proteins',
    'recombinant human/mouse/rat protein': 'recombinant proteins',
    'recombinant human/mouse protein': 'recombinant proteins',
    'recombinant human/murine/rat protein': 'recombinant proteins',
    'recombinant cas9 protein': 'recombinant proteins',
    'synthetic mammalian expression plasmids': 'expression plasmids',
    'synthetic bacterial expression plasmids': 'expression plasmids',
    'synthetic plasmids': 'expression plasmids',
    'aav plasmids': 'expression plasmids',
    'non-viral expression plasmids': 'expression plasmids',

    'synthetic dna oligonucleotide - purified': 'synthetic dna oligonucleotide - desalted',

    'pcr tubes': 'pcr tube strips',

    'radiolabeled nucleotides': 'nucleotides',

    'drug - other': 'small molecule inhibitors',
    'sample vials': 'vials',
    'scintillation vials': 'vials',
    'autosampler vials': 'vials',
    'drosophila vials': 'vials',
    'screw cap vials': 'vials',
}

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

_prefix_patterns = [r'^' + re.escape(p.strip()) for p in NONLAB_PREFIXES]
_keyword_patterns = [r'\b' + re.escape(k.strip()) + r'\b' for k in NONLAB_KEYWORDS]
_all_patterns = _prefix_patterns + _keyword_patterns
NONLAB_REGEX = re.compile('|'.join(_all_patterns), re.IGNORECASE)

_ANIMALS_LIVE = (
    "mice", "frog", "xenopus", "zebrafish", "drosophila stocks",
    "worm strains", "bone slices",
)
_OFFICE_SUFFIXES = (
    "office supplies", "labels", "tape", "books", "markers and pens",
    "temperature indication tapes and dots",
)
_CLEANING_SUFFIXES = (
    "disposable wipes and towels", "cleaning supplies", "brushes",
    "aluminum foil",
)
_CLEANING_BARE = ("applicators and swabs",)

_LAB_HW_SUFFIXES = (
    "lab furniture", "lab hardware", "hardware", "metal hardware",
    "plumbing", "stands and rings", "clamps and supports",
    "mortars and pestles", "trays", "carts", "storage bins", "belts",
    "fasteners", "pots and pans",
    "toolkit tools", "hand tools", "beakers and measuring",
    "gas cylinder carts",
)
_LAB_HW_BARE = (
    "pipette stands", "flask supports", "vial storage trays",
    "carboy spigots and accessories", "platinum wire and gauze",
    "environmental sampling bottles and accessories",
)

_WASTE_SAFETY_SUFFIXES = (
    "waste disposal", "first aid", "ppe", "personal protective equipment",
    "safety", "safety equipment", "spill kits", "pest control",
)
_WASTE_SAFETY_BARE = ("eye protection accessories",)

_ELECTRONICS_SUFFIXES = ("batteries", "electronic components")

_INSTRUMENTS_BARE = (
    "tissue embedding accessories",
    "pcr tube accessories",
    "spe accessories",
    "ief equilibration trays",
    "random mutagenesis systems",
)

_CLOSURES_NONLAB = ("stoppers and closures", "test strips")

NONLAB_BUCKET_RULES = [
    (re.compile(r'^irrelevant chemicals\b', re.IGNORECASE),  'chemicals'),
    (re.compile(r'^fees\b',                  re.IGNORECASE), 'fees'),
    (re.compile(r'^electronics\b',           re.IGNORECASE), 'electronics'),

    (re.compile(r'^nonlab\s*-\s*compressed gases\b', re.IGNORECASE), 'chemicals'),
    (re.compile(r'^argon gas\b',             re.IGNORECASE), 'chemicals'),
    (re.compile(r'^tris-caps transfer buffer\b', re.IGNORECASE), 'chemicals'),

    (re.compile(r'^animal\s*-\s*(?:' + '|'.join(re.escape(x) for x in _ANIMALS_LIVE) + r')\b',
                re.IGNORECASE), 'animals_live'),
    (re.compile(r'^animal\b',                re.IGNORECASE), 'animal_supplies'),

    (re.compile(r'^nonlab\s*-\s*tubing\b',   re.IGNORECASE), 'instruments_and_parts'),
    (re.compile(r'^tubing\b',                re.IGNORECASE), 'instruments_and_parts'),
    (re.compile(r'^caps and closures\b',     re.IGNORECASE), 'instruments_and_parts'),
    (re.compile(r'^nonlab\s*-\s*(?:' + '|'.join(re.escape(x) for x in _CLOSURES_NONLAB) + r')\b',
                re.IGNORECASE), 'instruments_and_parts'),

    (re.compile(r'^nonlab\s*-\s*software\b', re.IGNORECASE), 'software'),

    (re.compile(r'^instrument\b',            re.IGNORECASE), 'instruments_and_parts'),
    (re.compile(r'^sequencing\b',            re.IGNORECASE), 'instruments_and_parts'),
    (re.compile(r'^gas chromatography\b',    re.IGNORECASE), 'instruments_and_parts'),
    (re.compile(r'^hotplate\b',              re.IGNORECASE), 'instruments_and_parts'),
    (re.compile(r'^(?:' + '|'.join(re.escape(x) for x in _INSTRUMENTS_BARE) + r')\b',
                re.IGNORECASE), 'instruments_and_parts'),

    (re.compile(r'^nonlab\s*-\s*surgical tools\b', re.IGNORECASE), 'surgical_tools'),
    (re.compile(r'^nonlab\s*-\s*(?:' + '|'.join(re.escape(x) for x in _OFFICE_SUFFIXES) + r')\b',
                re.IGNORECASE), 'office_supplies'),
    (re.compile(r'^nonlab\s*-\s*(?:' + '|'.join(re.escape(x) for x in _CLEANING_SUFFIXES) + r')\b',
                re.IGNORECASE), 'cleaning_and_disposables'),
    (re.compile(r'^(?:' + '|'.join(re.escape(x) for x in _CLEANING_BARE) + r')\b',
                re.IGNORECASE), 'cleaning_and_disposables'),
    (re.compile(r'^nonlab\s*-\s*(?:' + '|'.join(re.escape(x) for x in _LAB_HW_SUFFIXES) + r')\b',
                re.IGNORECASE), 'lab_furniture_and_hardware'),
    (re.compile(r'^(?:' + '|'.join(re.escape(x) for x in _LAB_HW_BARE) + r')\b',
                re.IGNORECASE), 'lab_furniture_and_hardware'),
    (re.compile(r'^nonlab\s*-\s*(?:' + '|'.join(re.escape(x) for x in _WASTE_SAFETY_SUFFIXES) + r')\b',
                re.IGNORECASE), 'waste_and_safety'),
    (re.compile(r'^(?:' + '|'.join(re.escape(x) for x in _WASTE_SAFETY_BARE) + r')\b',
                re.IGNORECASE), 'waste_and_safety'),
    (re.compile(r'^nonlab\s*-\s*(?:' + '|'.join(re.escape(x) for x in _ELECTRONICS_SUFFIXES) + r')\b',
                re.IGNORECASE), 'electronics'),

    (re.compile(r'^lab furniture\b',         re.IGNORECASE), 'lab_furniture_and_hardware'),
]


def assign_nonlab_bucket(category):
    if not isinstance(category, str) or not category:
        return ''
    if not NONLAB_REGEX.search(category):
        return ''
    for pattern, bucket in NONLAB_BUCKET_RULES:
        if pattern.search(category):
            return bucket
    return 'other_misc'


def assign_nonlab_bucket_series(s):
    import pandas as pd
    return s.fillna('').astype(str).map(assign_nonlab_bucket)


NONLAB_SUPPLIER_EXACT = [
    "cardinal health 411 inc",
    "henry ford health system",
    "jackson laboratory",
]

LAB_SUPPLIER_KEYWORDS = [
    "integrated dna tech",
    "dharmacon",
    "empire genomics",
    "genscript",
    "abgent",
    "abcam",
    "proteintech",
    "rockland immunochem",
    "chromotek",
    "jackson immunoresearch",
    "cell signaling tech",
    "santa cruz biotech",
    "new england biolabs",
    "takara bio",
    "qiagen",
    "applied biosystems",
    "electron microscopy sciences",
    "ems acquisition",
    "selleck chemical",
    "lc laboratories",
    "enzo life sciences",
    "invivogen",
    "avanti polar lipids",
    "nu-chek-prep",
    "nu-chek prep",
    "echelon biosciences",
    "addgene",
    "origene",
    "genecopoeia",
    "viagen biotech",
    "peprotech",
    "boston biochem",
    "bachem",
    "anaspec",
    "peptide 2.0",
    "peptide 2 0",
    "haematologic technologies",
    "biolog incorporated",
    "biolog inc",
    "gold biotechnology",
    "mp biomedicals",
    "research products international",
    "phenomenex",
    "denville scientific",
    "dot scientific",
    "life science products",
    "millipore",
    "emd chemicals",
]

_lab_supplier_patterns = [re.escape(k.lower()) for k in LAB_SUPPLIER_KEYWORDS]
LAB_SUPPLIER_REGEX = (re.compile('|'.join(_lab_supplier_patterns), re.IGNORECASE)
                      if _lab_supplier_patterns else None)

SUPPLIER_CATEGORY_FORCE = {
    "peprotech": "recombinant proteins",
    "boston biochem": "recombinant proteins",
    "avanti polar lipids": "purified lipids",
    "nu-chek-prep": "purified lipids",
    "nu-chek prep": "purified lipids",
    "dharmacon": "synthetic sirna",
    "addgene": "expression plasmids",
    "origene": "expression plasmids",
    "genecopoeia": "expression plasmids",
    "bachem": "synthetic peptides",
    "anaspec": "synthetic peptides",
    "peptide 2.0": "synthetic peptides",
    "peptide 2 0": "synthetic peptides",
}

_supp_cat_patterns = {}
for _k, _cat in SUPPLIER_CATEGORY_FORCE.items():
    _supp_cat_patterns.setdefault(_cat, []).append(re.escape(_k.lower()))
SUPPLIER_CATEGORY_REGEX = {
    cat: re.compile('|'.join(pats), re.IGNORECASE)
    for cat, pats in _supp_cat_patterns.items()
}

DOMAIN_STOP_WORDS = [
    "pk", "cs", "ea", "bx", "bg", "ct", "lb", "oz", "ml", "ul", "mg",
    "kg", "gal", "qt", "pt", "ft", "mm", "cm", "lt",
    "per", "case", "pack", "box", "bag", "each", "unit", "units",
    "price", "qty", "quantity", "order", "item", "catalog", "cat",
    "no", "num", "number", "ref", "sku",
]

def normalize_supplier(supplier_name):
    if not isinstance(supplier_name, str) or not supplier_name.strip():
        return ''
    name = re.sub(r'[^a-z0-9\s]', ' ', supplier_name.lower())
    name = re.sub(r'\b(inc|llc|corp|co|ltd|lp|dba|the)\b', ' ', name)
    words = [w for w in name.split() if len(w) >= 3][:3]
    if not words:
        return ''
    return 'supp_' + '_'.join(words)


def clean_for_model(text):
    if not isinstance(text, str):
        return ""
    text = re.sub(r'&(?:[a-zA-Z]+|#\d+);', ' ', text)
    text = re.sub(r'\(actual\s+price[^)]*\)', ' ', text, flags=re.IGNORECASE)
    text = re.sub(r'\$[\d,]+(?:\.\d+)?', ' ', text)
    text = re.sub(r'\bper\s+attached\s+quote\w*', ' ', text, flags=re.IGNORECASE)
    text = re.sub(r'\bquote\s*(?:(?:no\.?|number|[#:])\s*)+[\w\-/]{3,}\b', ' ', text, flags=re.IGNORECASE)
    text = re.sub(r'\boffer\s*(?:(?:no\.?|number|[#:])\s*)+[\w\-/]{3,}\b', ' ', text, flags=re.IGNORECASE)
    text = re.sub(r'\bp\.?\s*o\.?\s*(?:(?:no\.?|number|[#:])\s*)+[\w\-/]{3,}\b', ' ', text, flags=re.IGNORECASE)
    text = re.sub(r'\b(?:order|ord)\s*(?:(?:no\.?|number|[#:])\s*)+[\w\-/]{3,}\b', ' ', text, flags=re.IGNORECASE)
    text = re.sub(r'\binvoice\s*(?:(?:no\.?|number|[#:])\s*)+[\w\-/]{3,}\b', ' ', text, flags=re.IGNORECASE)
    text = re.sub(r'\b[ATCGNatcgn]{10,}\b', ' ', text)
    text = re.sub(
        r'\b(?:configurationid|typecode|purification|format|tubes|scale|umo)\s*:\s*\S+',
        ' ', text, flags=re.IGNORECASE
    )
    text = re.sub(r'\bsequence\s*:\s*\S+', ' ', text, flags=re.IGNORECASE)
    text = re.sub(r'\b[a-zA-Z]{1,4}[#-]\d{3,}\b', ' ', text)
    return re.sub(r'\s+', ' ', text).strip()

NONLAB_SUPPLIER_KEYWORDS = [
    "xpedx", "xerox", "acct", "accounting",
    "photography", "music", "graphics",
    "publishing", "productions", "promotional",
    "mailing", "lithographing", "advtsng",
    "travel", "airline", "aviation", "touring", "airport",
    "hotel", "sheraton", "resort", "centerplate",
    "event", "entertainment",
    "plumbing", "hvac", "seating", "sprinkler", "roofing",
    "construct", "painting", "drainage", "heating",
    "floor", "lumber", "architectural", "bldg",
    "fire protection", "sanitation strategies",
    "american rock salt", "lowes",
    "cisco systems", "blackboard", "datadirect", "network solutions",
    "backup technology", "cdw government", "verizon",
    "ibm", "lenovo",
    "tractor", "toyota", "freight", "cargo", "truck",
    "mower", "body shop",
    "thyssenkrupp", "gerdau", "kintetsu", "nortrax",
    "foods", "deli", "coffee", "cater",
    "athletic", "sport", "sports", "fitness", "golf",
    "team apparel", "fashion", "unifirst", "uniform",
    "trophies", "trophy", "award",
    "price waterhouse coopers", "insurance", "investments",
    "united healthcare",
    "college board", "proquest",
    "davol", "atricure", "cbord group", "dimension data", "nwn",
    "somanetics", "neurotune", "tko", "twitchell",
    "flagcraft", "spectroglyph", "stevesongs", "gle associates",
    "3m unitek", "lma north america",
    "hill rom", "henry schein", "practicon",
    "eckert and ziegler", "ferguson enterprise",
    "tiger",
]


TIER1_CATEGORIES = frozenset([
    "australian fbs",
    "basal medium eagle",
    "canadian fbs",
    "dmem",
    "dmem/f-12",
    "dry basal media, not chemically defined",
    "hams f12",
    "imdm",
    "insect cell media",
    "leibovitz l15 media",
    "mccoys 5a",
    "mem",
    "neurobasal media",
    "new zealand fbs",
    "optimem",
    "rpmi",
    "sirna buffers",
    "sirna transfection medium",
    "sirna transfection reagents",
    "specialty cell culture media",
    "stem cell media",
    "synthetic sirna",
    "us fbs",
])

TIER2_CATEGORIES = frozenset([
    "acrylamide/bis solution",
    "antibody labeling kits",
    "bacterial transformation reagents",
    "bioconjugation reagents",
    "blunt-end cloning kits",
    "bovine adult serum",
    "bovine calf serum",
    "chemically competent cells",
    "chemiluminescent substrates",
    "chemiluminescent western blot detection",
    "column-based dna and rna extraction kits",
    "column-based dna genomic purification kits",
    "column-based dna plasmid gigaprep",
    "column-based dna plasmid maxiprep",
    "column-based dna plasmid megaprep",
    "column-based dna plasmid midiprep",
    "column-based dna plasmid miniprep",
    "column-based dna purification kits",
    "column-based gel dna extraction kits",
    "column-based gel rna extraction kits",
    "column-based microbial dna purification kits",
    "column-based pcr and gel purification kit",
    "column-based pcr purification kits",
    "column-based pcr purification reagent",
    "column-based plant dna purification kits",
    "column-based plant rna purification kits",
    "column-based protein purification kit",
    "column-based rna purification kits",
    "column-based yeast dna purification kits",
    "crosslinking reagents",
    "directional topo cloning kits",
    "dnase i",
    "donkey serum",
    "dulbecco's phosphate-buffered saline (dpbs) buffer",
    "dye-based qpcr systems",
    "dye-based rt-qpcr systems",
    "earle's balanced salt solution (ebss) buffer",
    "electrocompetent cells",
    "expression plasmids",
    "first-strand cdna synthesis systems",
    "fluorophore - bioconjugate dyes",
    "gateway cloning kits",
    "gene-specific rnai reagents",
    "goat serum",
    "hanks' balanced salt solution (hbss) buffer",
    "high-fidelity dna polymerase",
    "high-fidelity hot start dna polymerase",
    "high-fidelity hot start pcr systems",
    "high-fidelity pcr systems",
    "horizontal electrophoresis systems",
    "horse serum",
    "hot start pcr systems",
    "hot start taq polymerase",
    "liquid-based dna plasmid purification kit",
    "long template pcr systems",
    "magnetic bacterial rna purification kit",
    "magnetic bead-based mrna selection kit",
    "magnetic-bead based purification kit",
    "microrna reverse transcription kit",
    "mouse serum",
    "nitrocellulose blotting membranes",
    "nuclease enzymes",
    "nucleic acid gel stains",
    "nucleic acid modifying enzymes - alkaline phosphatases",
    "nucleic acid modifying enzymes - dna fragmentases",
    "nucleic acid modifying enzymes - dna methylases",
    "nucleic acid modifying enzymes - end repair enzymes",
    "nucleic acid modifying enzymes - endonucleases",
    "nucleic acid modifying enzymes - exonucleases",
    "nucleic acid modifying enzymes - klenow fragment",
    "nucleic acid modifying enzymes - other",
    "nucleic acid modifying enzymes - other dna polymerases",
    "nucleic acid modifying enzymes - other nucleases",
    "nucleic acid modifying enzymes - poly(a) polymerases",
    "nucleic acid modifying enzymes - pyrophosphatases",
    "nucleic acid modifying enzymes - recombinases",
    "nucleic acid modifying enzymes - single-stranded dna binding proteins",
    "nucleic acid modifying enzymes - t4 dna ligase",
    "nucleic acid modifying enzymes - t4 dna ligase buffer",
    "nucleic acid modifying enzymes - t4 dna polymerase",
    "nucleic acid modifying enzymes - t4 polynucleotide kinase",
    "nucleic acid modifying enzymes - t4 polynucleotide kinase buffer",
    "nucleic acid modifying enzymes - t4 rna ligase",
    "nucleic acid modifying enzymes - t4 rna ligase buffer",
    "nucleic acid modifying enzymes - t7 dna ligase",
    "nucleic acid modifying enzymes - taq dna ligase",
    "nucleic acid modifying enzymes - terminal transferase",
    "nucleic acid modifying enzymes - topoisomerases",
    "nucleic acid modifying enzymes - transposases",
    "nz bovine calf serum",
    "pcr systems",
    "phosphate-buffered saline (pbs) buffer",
    "plasmid vectors",
    "polyacrylamide gels casting kit",
    "pre amplification kits",
    "pre-cast bis-tris gels",
    "pre-cast tbe gels",
    "pre-cast tris-acetate gels",
    "pre-cast tris-glycine gels",
    "pre-cast tris-hcl gels",
    "pre-cast tris-tricine gels",
    "pre-stained dna ladders",
    "pre-stained protein molecular-weight ladder",
    "pre-stained rna ladders",
    "precut nitrocellulose transfer blotting packs",
    "precut pvdf transfer blotting packs",
    "probe-based qpcr systems",
    "probe-based rt-qpcr systems",
    "protein and antibody labeling kits",
    "protein gel stains",
    "protein ladders",
    "protein modifying enzymes",
    "pvdf blotting membranes",
    "qrt-pcr titration kit",
    "rabbit serum",
    "radiolabeled protein molecular-weight ladder",
    "random mutagenesis systems",
    "rapid dna ligation kits",
    "rat serum",
    "restriction enzymes",
    "reverse transcriptase",
    "rna extraction reagents",
    "rna ladder",
    "rna polymerases",
    "rna stabilization reagent",
    "rnase",
    "rnase inhibitors",
    "rt-pcr systems",
    "seamless cloning kits",
    "sheep serum",
    "silica bead based gel purification kit",
    "site-directed mutagenesis kits",
    "site-directed mutagenesis systems",
    "spin columns",
    "synthetic shrna",
    "ta cloning kits",
    "taq dna ligases",
    "taq polymerases",
    "tissue pcr systems",
    "topo ta cloning kits",
    "transfection reagents",
    "transfection reagents - cellfectin (insect cell)",
    "transfection reagents - electroporation kits",
    "transfection reagents - electroporation reagent",
    "transfection reagents - in vivo delivery reagents",
    "transfection reagents - lentiviral packaging kits",
    "transfection reagents - other",
    "transfection reagents - polybrene (viral transduction)",
    "transfection reagents - protein transfection reagents",
    "transposon mutagenesis kits",
    "tris-edta (te) buffer",
    "unstained dna ladders",
    "unstained protein molecular-weight ladder",
    "unstained rna ladders",
    "vertical electrophoresis systems",
    "western blot boxes",
    "zero blunt topo cloning kits",
])

TIER3_CATEGORIES = frozenset([
    "affinity resins - activated coupling matrices (magnetic)",
    "affinity resins - anti-ig secondary (magnetic)",
    "affinity resins - biotin/avidin (magnetic)",
    "affinity resins - epitope tags (flag/ha/myc/v5) (magnetic)",
    "affinity resins - glycoprotein (lectin-immobilized) (magnetic)",
    "affinity resins - gst-tag (magnetic)",
    "affinity resins - his-tag (imac) (magnetic)",
    "affinity resins - mbp-tag (magnetic)",
    "affinity resins - other (magnetic)",
    "affinity resins - protein a (magnetic)",
    "affinity resins - protein a/g (magnetic)",
    "affinity resins - protein g (magnetic)",
    "affinity resins - strep-tag (magnetic)",
    "affinity resins - streptavidin/avidin (magnetic)",
    "bovine serum albumin",
    "capped mrna synthesis kits",
    "cell culture dissociation reagents",
    "cell culture nutritional supplements - amino acids",
    "cell culture nutritional supplements - b27",
    "cell culture nutritional supplements - casamino acids",
    "cell culture nutritional supplements - glucose",
    "cell culture nutritional supplements - insulin",
    "cell culture nutritional supplements - its-g",
    "cell culture nutritional supplements - l-glutamine",
    "cell culture nutritional supplements - lif",
    "cell culture nutritional supplements - other",
    "cell culture nutritional supplements - peptone",
    "cell culture nutritional supplements - sodium pyruvate",
    "cell culture nutritional supplements - sugars",
    "cell culture nutritional supplements - tryptone",
    "cell culture nutritional supplements - vitamins",
    "cell culture nutritional supplements - yeast",
    "direct pcr lysis reagents",
    "gel blotting papers",
    "growth medium supplement",
    "immunomagnetic cell separation beads",
    "immunomagnetic cell separation columns",
    "in vitro transcription kit",
    "laemmli sample buffer",
    "lds sample buffer",
    "magnetic beads - other",
    "magnetic cell separation kits",
    "magnetic ip kit",
    "mes-sds buffer",
    "mops-sds buffer",
    "native page running buffers",
    "native-page sample buffer",
    "reducing agents - bme",
    "tbe buffer",
    "tris-aceate-sds running buffer",
    "tris-acetate-edta (tae) buffer",
    "tris-glycine buffer",
    "tris-glycine-sds (tgs) buffer",
    "tris-tricine-sds buffer",
    "western blot transfer buffers",
])

TREATED_CATEGORIES = TIER1_CATEGORIES | TIER2_CATEGORIES | TIER3_CATEGORIES

SOURCE_WEIGHTS = {
    'ca_non_lab':     0.5,
    'fisher_non_lab': 3.0,
    'ut_dallas':      2.0,
    'umich':          2.0,
    'fisher_lab':     0.5,
    'fisher_chemical': 1.5,
}


def get_sample_weights(data_sources, labels):
    import numpy as np
    import pandas as pd

    src = pd.Series(data_sources).astype(str).reset_index(drop=True)
    lab = pd.Series(labels).astype(int).reset_index(drop=True)

    src_only = {k: float(v) for k, v in SOURCE_WEIGHTS.items() if isinstance(k, str)}
    weights = src.map(src_only).fillna(1.0).to_numpy(dtype=float)

    for key, w in SOURCE_WEIGHTS.items():
        if isinstance(key, tuple) and len(key) == 2:
            s, l = key
            mask = (src.values == s) & (lab.values == int(l))
            weights[mask] = float(w)
    return weights
