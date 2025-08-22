# config.py
"""
Central configuration file for the lab consumables classification pipeline.
"""
import os
import re # Added to support CAS_REGEX compilation

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
NY_FISHER_CSV = os.path.join(BASE_DIR, "external", "samp", "ny_fisher_desc_clean.csv")
SEED_KEYWORD_YAML = os.path.join(CODE_DIR, "initial_seed.yml")
ANTI_SEED_KEYWORD_YAML = os.path.join(CODE_DIR, "anti_seed_keywords.yml")
FISHER_LAB_XLSX = os.path.join(BASE_DIR, "external", "catalogs", "fisher_lab.xlsx")
FISHER_NONLAB_XLSX = os.path.join(BASE_DIR, "external", "catalogs", "fisher_nonlab.xlsx")

# ==============================================================================
# 3. Output File Paths
# ==============================================================================
OUTPUT_DIR = os.path.join(BASE_DIR, "output")
os.makedirs(OUTPUT_DIR, exist_ok=True)
PREPARED_DATA_PATH = os.path.join(OUTPUT_DIR, "prepared_training_data.parquet")
LAB_MODEL_PATH = os.path.join(OUTPUT_DIR, "lab_binary_classifier.joblib")
CATEGORY_MODEL_DATA_PATH = os.path.join(OUTPUT_DIR, "category_similarity_data.joblib")
CATEGORY_VECTORIZER_PATH = os.path.join(OUTPUT_DIR, "category_tfidf_vectorizer.joblib")
FINAL_OUTPUT_PATH = os.path.join(OUTPUT_DIR, "foia_classified_output.csv")
REVIEW_OUTPUT_PATH = os.path.join(OUTPUT_DIR, "foia_review_items.csv")

# ==============================================================================
# 4. Column Names & Model Parameters
# ==============================================================================
CLEAN_DESC_COL = "clean_desc"
RAW_DESC_COL = "product_desc"
UT_DALLAS_MERGE_KEYS = ["supplier_id", "sku"]
UT_CAT_COL = "category"
CA_DESC_COL = "clean_desc"
FISHER_DESC_COL = "clean_desc"

PREDICTION_THRESHOLD = 0.6
VECTORIZER_MIN_DF = 7 # Ignores tokens that appear in less than this many documents

# Categorization Model Parameters
CATEGORY_SIMILARITY_WEIGHT = 0.7
CATEGORY_OVERLAP_WEIGHT = 0.3
CATEGORY_MIN_SCORE_THRESHOLD = 0.10

# List of categories to be considered 'Non-Lab' for binary labeling
NONLAB_CATEGORIES = [
    "office", "service", "sequencing", "training", "instrument",
    "shipping", "bucket", "biohazard", "sharps", "container",
    "clamp", "bracket", "printer toner", "storage cabinet",
    "organic synthesis reagent", "equipment",
    "furniture", "infrastructure", "tool", "random", "unclear",
    "bin", "subaward", "fee", "electronic", "hardware",
    "fitting", "software", "tubing", "wire", "book",
    "battery", "cart", "timer", "led light", "towel",
    "irrelevant chemicals", "oring", "caps", "cleaning",
    "vacuum pump oil", "gas", "burn", "first-aid", "first aid",
    "3d printing", "desk", "chair", "ladder", "paint",
    "mop", "wiper", "tissue", "trash", "liner",
    "soap", "cleaner", "printer", "toner", "storage lid", "storage bins",
    "storage shelves", "storage bags",
    "cabinet", "trolley", "3d", "printing",
    "fixture", "light", "led", "lamp", "cork",
    "ring", "folder", "label", "gas regulators",
    "sign", "heavy duty", "cap", "tooth",
    "basket", "durac plus", "acs", "usb",
    "adapter", "cable", "high purity", "metal",
    "bench", "vacuum", "notebook", "cotton ball",
    "shppr", "thermo scientific", "tape", "stopper",
    "bundle of products", "labeling tape", "hepa", "clamps",
    "clips", "shelf", "flint", "connectors",
    "batteries", "miscellaneous"
]

# ==============================================================================
# 5. Chemical Identification Parameters
# ==============================================================================
SPACY_MODEL_CHEM = "en_ner_bc5cdr_md"
CAS_REGEX = re.compile(r"\b\d{2,7}-\d{2}-\d\b")
CHEM_FRAGMENTS = [
    "oh", "nh2", "cooh", "sh", "boc", "fmoc", "trt", "cbz",
    "tfa", "hcl", "naoh", "edc", "dcc", "peg", "pnp", "nme2",
    "gly", "ala", "phe", "ser", "tyr", "met", "lys", "asp", "glu", "pro",
    "ile", "leu", "val", "thr", "trp", "his", "gln", "asn", "dmem", "n", "m",
    "pbf", "mtb", "mmtr", "tbs", "edta", "atp", "dna", "rna", "ist",
    "penicillin","streptomycin","glutamine", "imdm", "gim", "mes",
    "na", "pe", "tris", "dibenzylideneacetone", "dipalladium", "divinyl", "tetramet",
    "ethylhexyl", "dioxane", "insulin", "transferrin", "selenium", "ethyl", "mono", "hexyl"
]
CHEM_SUFFIX_LIST = [
    "acid", "chloride", "bromide", "iodide", "acetate", "sulfate", "phosphate",
    "hydroxide", "ethanol", "methanol", "propanol", "isopropanol", "acetone",
    "dimethyl", "methyl", "butyl", "amine", "amide"
]
