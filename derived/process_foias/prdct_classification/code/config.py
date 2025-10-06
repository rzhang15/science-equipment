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
# Raw Data Inputs
FOIA_INPUT_DIR = os.path.join(BASE_DIR, "external", "samp")
UT_DALLAS_CLEAN_CSV = os.path.join(BASE_DIR, "external", "samp", "utdallas_2011_2024_standardized_clean.csv")
UT_DALLAS_CATEGORIES_XLSX = os.path.join(BASE_DIR, "external", "combined", "combined_nochem.xlsx")
CA_NON_LAB_DTA = os.path.join(BASE_DIR, "external", "samp", "non_lab_clean.csv")
SEED_KEYWORD_YAML = os.path.join(CODE_DIR, "initial_seed.yml")
ANTI_SEED_KEYWORD_YAML = os.path.join(CODE_DIR, "anti_seed_keywords.yml")
FISHER_LAB = os.path.join(BASE_DIR, "external", "samp", "fisher_lab_clean.csv")
FISHER_NONLAB = os.path.join(BASE_DIR, "external", "samp", "fisher_nonlab_clean.csv")
MARKET_RULES_YAML = os.path.join(CODE_DIR, "market_rules.yml") # <-- NEW
GOVSPEND_PANEL_CSV = os.path.join(BASE_DIR, "external", "govspend", "govspend_panel.csv")

# ==============================================================================
# 3. Intermediate & Output File Paths
# ==============================================================================
# NEW: Temp directory for cleaned, intermediate files
TEMP_DIR = os.path.join(BASE_DIR, "temp")
os.makedirs(TEMP_DIR, exist_ok=True)

# Path to the clean, merged file created by 0_clean_category_file.py
UT_DALLAS_MERGED_CLEAN_PATH = os.path.join(TEMP_DIR, "utdallas_merged_clean.parquet")

# Main output directory
OUTPUT_DIR = os.path.join(BASE_DIR, "output")
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Final prepared data and model artifacts
PREPARED_DATA_PATH = os.path.join(OUTPUT_DIR, "prepared_training_data.parquet")
CATEGORY_MODEL_DATA_PATH = os.path.join(OUTPUT_DIR, "category_vectors_tfidf.joblib")
CATEGORY_VECTORIZER_PATH = os.path.join(OUTPUT_DIR, "category_tfidf_vectorizer.joblib")
UTDALLAS_VALIDATION_PREDICTIONS_CSV = os.path.join(OUTPUT_DIR, "utdallas_predictions_for_validation.csv")


# ==============================================================================
# 4. Column Names & Model Parameters
# ==============================================================================
CLEAN_DESC_COL = "clean_desc"
RAW_DESC_COL = "product_desc"
UT_DALLAS_MERGE_KEYS = ["supplier_id", "sku", "product_desc", "supplier"]
UT_CAT_COL = "category"
CA_DESC_COL = "clean_desc"
FISHER_DESC_COL = "clean_desc"

PREDICTION_THRESHOLD = 0.7
VECTORIZER_MIN_DF = 7 # Ignores tokens that appear in less than this many documents
# Categorization Model Parameters
CATEGORY_SIMILARITY_WEIGHT = 0.7
CATEGORY_OVERLAP_WEIGHT = 0.3

# List of categories to be considered 'Non-Lab' for binary labeling
NONLAB_CATEGORIES = [
    "office", "instrument", "waste disposal", "clamp", "equipment", "furniture", "tool", "random", "unclear",
    "fee", "electronic", "software", "tubing", "wire", "towel", "irrelevant chemicals", "oring", "caps",
    "gas ", "first-aid", "first aid", "desk", "chair", "brushes", "trash", "cleaner", "cotton ball",
    "bundle of products", "tape", "clamps", "miscellaneous", "clips", "flint", "accessories", "stands",
    "batteries", "miscellaneous", "ear protection", "apron", "pots", "pans", "stoppers" , "closures", "rings", 
    "mortor", "pestle", "supports", "trays", "applicators and swabs", "bundle of items"
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
