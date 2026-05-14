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
FISHER_CHEMICAL = os.path.join(BASE_DIR, "external", "samp", "fisher_chemical_clean.csv")
MARKET_RULES_YAML = os.path.join(CODE_DIR, "market_rules.yml")
GOVSPEND_PANEL_CSV = os.path.join(BASE_DIR, "external", "samp", "govspend_panel_clean.csv")

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

PREDICTION_THRESHOLD = 0.5
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
# Tightened from 0.95 → 0.99 after FP audit: Invitrogen-style high-lab-rate
# vendors were flipping non-lab predictions to lab too aggressively (~43
# Invitrogen FPs on umich_supplier UMich hold-out).  At 0.99 the supplier
# prior only acts as a safety net for truly mono-class suppliers.
SUPPLIER_PRIOR_LAB_HIGH_THRESHOLD = 0.99  # >=99% lab → flip non-lab→lab

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

# Engineered features (description-level numeric features appended to the
# TF-IDF + supplier matrix in 1b / classifier).  Targets the commodity-FN
# cluster from the bake-off audit (pipette tips / microcentrifuge tubes /
# weigh boats) — these items have short, vocabulary-anchored descriptions
# that the TF-IDF channel struggles with.
#
# Set USE_ENGINEERED_FEATURES = False to drop them (e.g. when running an
# A/B comparison against the no-features baseline).  When changing
# FEATURE_WEIGHT or toggling USE_ENGINEERED_FEATURES, you must rerun 1b
# AND 2 so the LR sees the correct feature dimensionality.
USE_ENGINEERED_FEATURES = True
FEATURE_WEIGHT = 0.10

# Expert model similarity thresholds
TFIDF_MIN_SCORE_THRESHOLD = 0.01
BERT_MIN_SCORE_THRESHOLD = 0.1

# Transformer-encoder registry.  Short name -> HuggingFace model id.
# Scripts 1b / 1c / 2 / 3 look up the model id by short name so the
# pipeline can A/B-test encoders without touching code.
#
# NOTE on specter2: `allenai/specter2_base` loads via sentence-transformers
# with default mean pooling, which is a usable approximation.  The full
# SPECTER2 pipeline expects the AllenAI `adapters` library to attach the
# proximity adapter on top of the base encoder; if the bake-off shows
# promise, switch to the adapter for the production run.
BERT_MODELS = {
    'minilm':   'sentence-transformers/all-MiniLM-L6-v2',
    'specter2': 'allenai/specter2_base',
}

# ------------------------------------------------------------------
# Sibling-category consolidation.  Applied at data-ingest time (step 0)
# so every downstream artifact (training labels, category vectors,
# validation reports) sees the already-merged taxonomy.  Keys get
# consolidated INTO the value.
#
# Only merge pairs whose distinction is not reliably expressed in the
# item description (e.g. "centrifuge conical tubes" vs. "centrifuge
# tubes" -- the word "conical" rarely appears; ATCC CRL numbers don't
# reveal species).
# ------------------------------------------------------------------
CATEGORY_CONSOLIDATION = {
    'centrifuge conical tubes': 'centrifuge tubes',
    'filtering funnels': 'funnels',
    'filling funnels': 'funnels',
    'cellular metabolism assay kits': 'metabolism assay kits',
    # Cell lines: species rarely appears in the description (items are
    # often just an ATCC CRL / HTB number).
    'human cell lines': 'cell lines',
    'mouse cell lines': 'cell lines',
    'mice cell lines': 'cell lines',
    'rat cell line': 'cell lines',
    'insect cell lines': 'cell lines',
    # Lab-grade water: the three generic lab-water buckets collapse into
    # one.  (Leaves heavy water, chromatography-grade water, and all
    # instrument-part water entries alone.)
    'dnase/rnase-free & molecular-biology-grade water': 'lab-grade water',
    'general-lab & specialty water': 'lab-grade water',
    'cell culture grade life science water - distilled': 'lab-grade water',
    # Disposable pipettes (generic brands — Corning, VWR, Falcon).
    'pasteur pipettes': 'disposable pipettes',
    'transfer pipettes': 'disposable pipettes',
    'aspirating pipettes': 'disposable pipettes',
    'mohr pipettes': 'disposable pipettes',
    'volumetric pipettes': 'disposable pipettes',
    # Manual pipettors (Rainin/Eppendorf/Gilson territory).
    'manual single channel pipettes': 'manual pipettors',
    'manual multichannel pipettes': 'manual pipettors',
    'electronic multichannel pipettes': 'manual pipettors',
    'pipette kits': 'manual pipettors',
    'pipettors': 'manual pipettors',
    'positive displacement pipettes': 'manual pipettors',
    # Beakers (Pyrex/Kimax — material distinction not in descriptions).
    'glass beakers': 'beakers',
    'plastic beakers': 'beakers',
    'steel beakers': 'beakers',
    'stainless steel beakers': 'beakers',
    # Graduated cylinders.
    'glass graduated cylinders': 'graduated cylinders',
    'plastic graduated cylinders': 'graduated cylinders',
    # Other flasks — erlenmeyer and boiling flasks kept separate.
    'fernbach flasks': 'other flasks',
    'volumetric flasks': 'other flasks',
    'recovery flasks': 'other flasks',
    'freeze drying flasks': 'other flasks',
    'kjeldahl flasks': 'other flasks',
    'distilling flasks': 'other flasks',
    'stainless steel flasks': 'other flasks',
    'serum bottles': 'other flasks',
    # Funnels — funnel adapters kept separate.
    'separatory funnels': 'funnels',
    'addition funnels': 'funnels',
    'funnel stems': 'funnels',
    # Specialty gloves — nitrile and latex kept separate.
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
    # Specialty membrane filters (Millipore/Whatman tail — syringe and
    # bottle-top filters kept separate).
    'nylon membrane filters': 'specialty membrane filters',
    'polycarbonate membrane filters': 'specialty membrane filters',
    'pes membrane filters': 'specialty membrane filters',
    'mce membrane filters': 'specialty membrane filters',
    'membrane filters': 'specialty membrane filters',
    'ptfe membrane filters': 'specialty membrane filters',
    'cellulose acetate membrane filters': 'specialty membrane filters',
    # Specialty needles — hypodermic needles kept separate.
    'dispensing needles': 'specialty needles',
    'needles': 'specialty needles',
    'blood collection needles': 'specialty needles',
    'pipetting needles': 'specialty needles',
    'double-tipped needles': 'specialty needles',
    # PCR tube accessories — pcr tubes and pcr tube strips kept separate.
    'caps and closures - pcr tube strips': 'pcr tube accessories',
    'pcr strip tubes': 'pcr tube accessories',
    'pcr tube strip caps': 'pcr tube accessories',
    'caps and closures - pcr tubes': 'pcr tube accessories',
    # Cryovial caps and autosampler vial caps roll into the vials bucket.
    'caps and closures - cryovial': 'caps and closures - vials',
    'autosampler vial caps': 'caps and closures - vials',
    # Cuvettes — spectrophotometer / fluorescence / electroporation sub-types.
    # The application (UV/Vis vs. fluorescence vs. electroporation) is often
    # in the description, but the item itself is a cuvette; grouping keeps
    # sibling similarity scores from splitting the cuvette bucket.
    'spectrophotometer cuvettes': 'cuvettes',
    'fluorescence cuvettes': 'cuvettes',
    'electroporation cuvettes': 'cuvettes',
    # Primary antibodies — polyclonal / monoclonal / other-host distinction
    # is rarely expressed in descriptions (host species is often omitted, and
    # the poly-vs-mono cue is inconsistent across vendors).  The expert model
    # gets 0 P/R on the sub-labels on UMich eval — rolling them up gives the
    # expert one well-populated bucket it can actually learn.
    'polyclonal primary antibodies': 'primary antibodies',
    'monoclonal primary antibodies': 'primary antibodies',
    'polyclonal primary antibody': 'primary antibodies',
    'monoclonal primary antibody': 'primary antibodies',
    'other-host primary antibody': 'primary antibodies',
    # Recombinant proteins — species-tagged sub-labels (human / mouse / rat /
    # combined) bleed into each other in UMich eval because the species tag
    # is often absent in descriptions ("recombinant VEGF-C carrier free").
    'recombinant human protein': 'recombinant proteins',
    'recombinant mouse protein': 'recombinant proteins',
    'recombinant human/mouse/rat protein': 'recombinant proteins',
    'recombinant human/mouse protein': 'recombinant proteins',
    'recombinant human/murine/rat protein': 'recombinant proteins',
    'recombinant cas9 protein': 'recombinant proteins',
    # Expression plasmids — mammalian / bacterial / AAV all end up as
    # `synthetic *** expression plasmids` in training, but the host species
    # is often implicit in the vendor catalog rather than spelled out on
    # each SKU.  Collapse into one `expression plasmids` bucket.  Keeps
    # `plasmid vectors` (backbone-only SKUs) separate.
    'synthetic mammalian expression plasmids': 'expression plasmids',
    'synthetic bacterial expression plasmids': 'expression plasmids',
    'synthetic plasmids': 'expression plasmids',
    'aav plasmids': 'expression plasmids',
    # Non-viral expression plasmids — diagnostic on combined hold-out
    # showed 231/815 expression-plasmid FNs landed here.  `pet/pgex/pcdna`
    # vectors aren't reliably split as viral-vs-non-viral from descriptions.
    'non-viral expression plasmids': 'expression plasmids',

    # Synthetic DNA oligos — desalted vs purified is a purification-tag
    # distinction that almost never appears in descriptions.  Combined
    # hold-out: 903/982 "purified" FNs land in "desalted" (P=0.49, R=0.05
    # on the purified label).  Merging recovers ~900 errors.
    'synthetic dna oligonucleotide - purified': 'synthetic dna oligonucleotide - desalted',

    # PCR tubes vs tube strips — descriptions like "0.2ml pcr tb fcap rd"
    # don't reveal strip-vs-singleton.  266/359 FNs cross-flow.  Merge.
    'pcr tubes': 'pcr tube strips',

    # Radiolabeled vs unlabeled nucleotides — distinguishing feature is
    # only the `-32p` / `-33p` token.  ~300 FNs in the "radiolabeled"
    # bucket get misrouted (often to "sodium phosphate" via the
    # "deoxy*-phosphate sodium" pattern collision).  Collapse to plain
    # nucleotides; downstream code can still detect "32p"/"33p" if it
    # cares about the labeling distinction.
    'radiolabeled nucleotides': 'nucleotides',

    # "drug - other" is essentially indistinguishable from "small molecule
    # inhibitors" and "irrelevant chemicals - bioactive small molecules"
    # from procurement-line text alone — it gets P=0.33, R=0.37 in the
    # combined hold-out, the worst per-category score among support>=100
    # categories.  Items like "lovastatin", "indomethacin", "clobetasol"
    # are research-grade drugs used as lab reagents.  Collapse into
    # small molecule inhibitors (the dominant FP target).
    'drug - other': 'small molecule inhibitors',
    # Vials — sample / scintillation / autosampler / drosophila / screw cap
    # variants collapse into a single `vials` bucket.  Cryovials are kept
    # separate (distinct storage use case; usually labeled in descriptions).
    # Cap / insert / rack accessories also stay separate.
    'sample vials': 'vials',
    'scintillation vials': 'vials',
    'autosampler vials': 'vials',
    'drosophila vials': 'vials',
    'screw cap vials': 'vials',
}

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

# ------------------------------------------------------------------------------
# Coarse non-lab spending buckets.  Any item whose predicted category matches
# NONLAB_REGEX gets a `nonlab_bucket` label via assign_nonlab_bucket(); lab
# items get ''.  Rules are evaluated in order; first match wins, so list more
# specific patterns above general ones.
# ------------------------------------------------------------------------------
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

# Instrument-adjacent categories that don't start with "instrument".
_INSTRUMENTS_BARE = (
    "tissue embedding accessories",
    "pcr tube accessories",
    "spe accessories",
    "ief equilibration trays",
    "random mutagenesis systems",
)

# Tubing — its own bucket (nonlab - tubing + tubing - dialysis).
# Closures and seals — caps and closures - *, stoppers, test strips.
_CLOSURES_NONLAB = ("stoppers and closures", "test strips")

NONLAB_BUCKET_RULES = [
    # Chemicals / fees / electronics — single-prefix families.
    (re.compile(r'^irrelevant chemicals\b', re.IGNORECASE),  'chemicals'),
    (re.compile(r'^fees\b',                  re.IGNORECASE), 'fees'),
    (re.compile(r'^electronics\b',           re.IGNORECASE), 'electronics'),

    # Gases + a few chem strings caught by other NONLAB keywords ("caps" matches
    # "tris-caps transfer buffer").  Routed to chemicals explicitly.
    (re.compile(r'^nonlab\s*-\s*compressed gases\b', re.IGNORECASE), 'chemicals'),
    (re.compile(r'^argon gas\b',             re.IGNORECASE), 'chemicals'),
    (re.compile(r'^tris-caps transfer buffer\b', re.IGNORECASE), 'chemicals'),

    # Animals: live organisms vs. supplies.  Live rule must precede catch-all.
    (re.compile(r'^animal\s*-\s*(?:' + '|'.join(re.escape(x) for x in _ANIMALS_LIVE) + r')\b',
                re.IGNORECASE), 'animals_live'),
    (re.compile(r'^animal\b',                re.IGNORECASE), 'animal_supplies'),

    # Tubing + closures/caps/seals — folded into instruments_and_parts.
    (re.compile(r'^nonlab\s*-\s*tubing\b',   re.IGNORECASE), 'instruments_and_parts'),
    (re.compile(r'^tubing\b',                re.IGNORECASE), 'instruments_and_parts'),
    (re.compile(r'^caps and closures\b',     re.IGNORECASE), 'instruments_and_parts'),
    (re.compile(r'^nonlab\s*-\s*(?:' + '|'.join(re.escape(x) for x in _CLOSURES_NONLAB) + r')\b',
                re.IGNORECASE), 'instruments_and_parts'),

    # Software.
    (re.compile(r'^nonlab\s*-\s*software\b', re.IGNORECASE), 'software'),

    # Instruments and instrument parts.
    (re.compile(r'^instrument\b',            re.IGNORECASE), 'instruments_and_parts'),
    (re.compile(r'^sequencing\b',            re.IGNORECASE), 'instruments_and_parts'),
    (re.compile(r'^gas chromatography\b',    re.IGNORECASE), 'instruments_and_parts'),
    (re.compile(r'^hotplate\b',              re.IGNORECASE), 'instruments_and_parts'),
    (re.compile(r'^(?:' + '|'.join(re.escape(x) for x in _INSTRUMENTS_BARE) + r')\b',
                re.IGNORECASE), 'instruments_and_parts'),

    # nonlab - * subfamilies, most specific first.
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

    # Standalone `lab furniture` (no nonlab prefix).
    (re.compile(r'^lab furniture\b',         re.IGNORECASE), 'lab_furniture_and_hardware'),
]


def assign_nonlab_bucket(category):
    """Map a predicted category string to a coarse non-lab spending bucket.

    Returns '' for lab items (anything that doesn't match NONLAB_REGEX) and
    'other_misc' for non-lab items that don't match any bucket rule.  By
    design, only genuinely undefined categories fall through to other_misc:
    `nonlab - miscellaneous`, `nonlab - unclear`, `nonlab - unclassified`,
    `nonlab - bundle of products`, `bundle of products`, `nonlab - other`.
    """
    if not isinstance(category, str) or not category:
        return ''
    if not NONLAB_REGEX.search(category):
        return ''
    for pattern, bucket in NONLAB_BUCKET_RULES:
        if pattern.search(category):
            return bucket
    return 'other_misc'


def assign_nonlab_bucket_series(s):
    """Vectorized assign_nonlab_bucket for a pandas Series of categories."""
    import pandas as pd  # local import keeps config import-light
    return s.fillna('').astype(str).map(assign_nonlab_bucket)


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
    # NOTE: `cayman chemical` removed after FP audit (umich_supplier UMich
    # hold-out): Cayman is responsible for ~62 FPs labeled as
    # `irrelevant chemicals - bioactive small molecules` in the ground
    # truth.  Their catalog skews toward bulk research chemicals which
    # the taxonomy treats as non-lab.  The ML head + seed keywords still
    # catch genuine lab orders from Cayman.
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
    "origene",
    "genecopoeia",
    "viagen biotech",
    # Recombinant proteins / cytokines
    "peprotech",
    "boston biochem",
    # Synthetic peptides
    "bachem",
    "anaspec",
    "peptide 2.0",
    "peptide 2 0",
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
    # NOTE: `revvity health sciences` removed — catalog spans
    # radiolabeled compounds and bulk chemistry that the taxonomy
    # labels non-lab (~39 FPs on the umich_supplier hold-out).
    # Plasticware / labware specialists
    # NOTE: `usa scientific` removed — catalog includes instrument
    # accessories (racks, plate holders) labeled as `instrument part`
    # rather than lab consumables (~39 FPs).
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

# Supplier -> forced expert category overlay.  When a supplier's name
# contains the key as a substring (case-insensitive), the expert's
# category prediction is overridden to the value before the veto / market
# rule layers.  Market rules can still beat this if they fire (Step 4 of
# script 3), so a description-specific rule remains authoritative.
#
# Use only for vendors whose catalogs are nearly mono-category — these
# suppliers are essentially specialty foundries for one product class:
#   PEPROTECH / BOSTON BIOCHEM  -> recombinant proteins
#   AVANTI / NU-CHEK-PREP       -> purified lipids
#   DHARMACON                   -> synthetic sirna
#   ADDGENE / ORIGENE / GENECOPOEIA -> expression plasmids
#   BACHEM / ANASPEC / PEPTIDE 2.0  -> synthetic peptides
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

# Precompile per-category regex once so script 3 can do a single
# str.contains pass per category over the supplier column.
_supp_cat_patterns = {}
for _k, _cat in SUPPLIER_CATEGORY_FORCE.items():
    _supp_cat_patterns.setdefault(_cat, []).append(re.escape(_k.lower()))
SUPPLIER_CATEGORY_REGEX = {
    cat: re.compile('|'.join(pats), re.IGNORECASE)
    for cat, pats in _supp_cat_patterns.items()
}

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

    Inference-time twin of the regex stage in clean_foia_text/clean_foia_data.
    Mirrors the upstream pipeline so descriptions arriving at predict time
    (raw GovSpend, live inference, etc.) get cleaned consistently with the
    training-time `clean_desc`.

    Strips:
      - HTML entities and XML escape sequences (&amp;, &#153;, etc.)
      - Price / cost references ($300.00, (actual price $xx))
      - Quote / offer / PO / order / invoice numbered references
      - DNA/RNA nucleotide sequences (10+ consecutive base characters)
      - Gene-synthesis order metadata (configurationid, sequence:, etc.)
      - Catalog/part numbers (AB-1234, cat#12345)

    Notably does NOT strip:
      - Dimensions (12x75mm, 100ml) — these carry product-defining info and
        match what the upstream `size_unit_capture` rule preserves.
      - Pure numbers — upstream keeps short numerics; only 5+ digit pure
        numbers are stripped (as SKU fragments) at training time, and the
        same can happen at inference via the catalog-num rule above.
    """
    if not isinstance(text, str):
        return ""
    # Remove HTML entities (&amp; &#153; &lt; etc.)
    text = re.sub(r'&(?:[a-zA-Z]+|#\d+);', ' ', text)
    # Remove price references: "$300.00", "(actual price $xx)"
    text = re.sub(r'\(actual\s+price[^)]*\)', ' ', text, flags=re.IGNORECASE)
    text = re.sub(r'\$[\d,]+(?:\.\d+)?', ' ', text)
    # Numbered admin references — one rule per keyword (mirrors upstream).
    # The (?:...)+ group allows chained separators like `#:` or `no:` and
    # requires at least one explicit indicator keyword so we don't strip
    # prose like "quote follows".  Trailing id token must be ≥3 chars.
    text = re.sub(r'\bper\s+attached\s+quote\w*', ' ', text, flags=re.IGNORECASE)
    text = re.sub(r'\bquote\s*(?:(?:no\.?|number|[#:])\s*)+[\w\-/]{3,}\b', ' ', text, flags=re.IGNORECASE)
    text = re.sub(r'\boffer\s*(?:(?:no\.?|number|[#:])\s*)+[\w\-/]{3,}\b', ' ', text, flags=re.IGNORECASE)
    text = re.sub(r'\bp\.?\s*o\.?\s*(?:(?:no\.?|number|[#:])\s*)+[\w\-/]{3,}\b', ' ', text, flags=re.IGNORECASE)
    text = re.sub(r'\b(?:order|ord)\s*(?:(?:no\.?|number|[#:])\s*)+[\w\-/]{3,}\b', ' ', text, flags=re.IGNORECASE)
    text = re.sub(r'\binvoice\s*(?:(?:no\.?|number|[#:])\s*)+[\w\-/]{3,}\b', ' ', text, flags=re.IGNORECASE)
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


# ==============================================================================
# TREATED PRODUCT MARKET CLASSIFICATION - Thermo Fisher / Life Technologies
# Source of truth: ../../first_stage/select_categories/code/build.do
#   tier1 = serious-doubts finding (EU paras 41/69/98/105/250) or FTC
#           Dharmacon divestiture (23 cats)
#   tier2 = EU detailed-analysis / overlap mentioned (no doubts) or
#           overlap identified in section IV body text (157 cats)
#   tier3 = bundling / extension robustness — not antitrust-document-named
#           but co-purchased with Tier 1/2 (55 cats)
#   treated = tier1 | tier2 | tier3
# Re-sync with build.do whenever its tier assignments change.
# ==============================================================================
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

# ==============================================================================
# 7. Per-Source Training Sample Weights
# ==============================================================================
# Multiplicative weights on the LogisticRegression sample_weight parameter.
# Composes with class_weight='balanced' — sklearn multiplies them, so the
# lab/non-lab class balance is preserved regardless of these knobs.
#
# Keys can be:
#   - a `data_source` string (applies to every row of that source), or
#   - a (data_source, label) tuple (overrides for that specific combo).
# Tuple keys take priority over string keys.  Unlisted sources default to 1.0.
#
# Current row counts in the baseline prepared set (label=0 / label=1 / total):
#   ca_non_lab:      162,975 /      0 / 162,975
#   fisher_lab:        1,876 / 57,894 /  59,770
#   ut_dallas:        14,574 / 21,985 /  36,559
#   fisher_non_lab:    6,408 /    529 /   6,937
#
# Rationale for the defaults below:
#   - fisher_non_lab + ut_dallas are real procurement text (most similar to
#     the inference-time distribution), so upweight them.
#   - ca_non_lab is large but procurement-distant, so downweight.
#   - fisher_lab is left at 1.0 as the baseline.
SOURCE_WEIGHTS = {
    'ca_non_lab':     0.5,
    'fisher_non_lab': 3.0,
    'ut_dallas':      2.0,
    'umich':          2.0,
    'fisher_lab':     0.5,
    # fisher_chemical: ~37k Fisher chemicals, seed-filtered to drop
    # life-sci essentials.  Default 1.0; raise to push harder on
    # bulk-chemistry non-lab recall.
    'fisher_chemical': 1.5,
}


def get_sample_weights(data_sources, labels):
    """Build a sample_weight array aligned to (data_sources, labels).

    Looks up (source, label) tuple keys first, falls back to source-only
    keys, defaults to 1.0.  Returns a numpy float array.
    """
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
