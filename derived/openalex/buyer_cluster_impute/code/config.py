"""Shared paths and parameters for the buyer-cluster imputation pipeline."""
from pathlib import Path

# --- paths (relative to code/) ---
EXT = Path("../external")
OUT = Path("../output")
FIG = OUT / "figs"

SPEND_DTA    = EXT / "spend"     / "athr_category_spend.dta"
EXPOSURE_DTA = EXT / "spend"     / "athr_exposure.dta"
BERT_EMB     = EXT / "foia_bert" / "bert_foia_pritamdeka_S-Scibert-snli-multinli-stsb_unstemmed.npy"
BERT_IDS     = EXT / "foia_bert" / "bert_foia_ids_pritamdeka_S-Scibert-snli-multinli-stsb_unstemmed.csv"

# --- modeling params ---
K            = 15           # number of buyer types (NMF components)
NMF_INIT     = "nndsvda"    # deterministic init; small smoothing for zero-heavy data
NMF_MAX_ITER = 1000
RNG_SEED     = 42

# Min authors to include a category (drop ultra-rare cats so NMF doesn't fit noise)
MIN_AUTHORS_PER_CAT = 3
