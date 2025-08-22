# preprocess_utils.py
"""
Utility functions for chemical identification.
"""
import spacy
import warnings
import re
try:
    import config
except ImportError:
    print("❌ Error: config.py not found.")
    exit()

# --- Load SciSpaCy Model for NER ---
nlp_chem = None
chem_ner_available = False
try:
    print("ℹ️ Loading SciSpaCy model for chemical NER...")
    nlp_chem = spacy.load(config.SPACY_MODEL_CHEM)
    chem_ner_available = True
    print("✅ SciSpaCy model loaded.")
except OSError:
    warnings.warn(f"⚠️ SciSpaCy model '{config.SPACY_MODEL_CHEM}' not found. Chemical NER will be disabled.")
    warnings.warn(f"   To enable it, run: python -m spacy download {config.SPACY_MODEL_CHEM}")

def looks_chemical_regex(phrase: str) -> bool:
    """Checks if a phrase looks like a chemical using Regex rules."""
    if not isinstance(phrase, str): return False
    phrase_lower = phrase.lower()
    if hasattr(config, 'CAS_REGEX') and config.CAS_REGEX.search(phrase_lower):
        return True
    if any(phrase_lower.endswith(suf) for suf in config.CHEM_SUFFIX_LIST):
        return True
    if re.search(r"[a-z]\d|\d[a-z]", phrase_lower):
        return True
    return False

def looks_chemical(phrase: str) -> bool:
    """Master function for chemical detection."""
    if chem_ner_available and any(ent.label_ == "CHEMICAL" for ent in nlp_chem(phrase).ents):
        return True
    return looks_chemical_regex(phrase)
