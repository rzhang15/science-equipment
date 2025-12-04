import re
import pandas as pd
import spacy
import nltk
import multiprocessing
from collections import OrderedDict
import warnings

# --- Import Central Configuration ---
try:
    import config
except ImportError:
    print("❌ Error: config.py not found. Please ensure it's in the same directory.")
    exit()
from nltk.corpus import stopwords

# --- Load NLTK Stopwords ---
STOP_EN = set(stopwords.words("english"))

# --- Load SpaCy Models ---
nlp_sm = None
nlp_chem = None
chem_ner_available = False

try:
    print("ℹ️ Loading SpaCy model (en_core_web_sm)...")
    nlp_sm = spacy.load(config.SPACY_MODEL_SM, disable=["parser", "ner"])
    nlp_sm.max_length = 4_000_000
    print("✅ SpaCy (en_core_web_sm) model loaded.")
except OSError:
    print(f"❌ SpaCy model '{config.SPACY_MODEL_SM}' not found.")
    print(f"   Please run: python -m spacy download {config.SPACY_MODEL_SM}")
    exit() # Exit if the core model is missing

try:
    print("ℹ️ Loading SciSpaCy model (en_ner_bc5cdr_md)...")
    nlp_chem = spacy.load(config.SPACY_MODEL_CHEM)
    chem_ner_available = True
    print("✅ SciSpaCy (en_ner_bc5cdr_md) model loaded.")
except OSError:
    warnings.warn(f"⚠️ SciSpaCy model '{config.SPACY_MODEL_CHEM}' not found. Chemical NER will be disabled.")
    warnings.warn(f"   Consider running: python -m spacy download {config.SPACY_MODEL_CHEM}")
except Exception as e: # Catch other potential errors during SciSpaCy loading
    warnings.warn(f"⚠️ Error loading SciSpaCy model '{config.SPACY_MODEL_CHEM}': {e}. Chemical NER will be disabled.")


# ==============================================================================
# Helper Functions
# ==============================================================================

def deduplicate_words(text: str) -> str:
    """Removes duplicate words while preserving order."""
    if not isinstance(text, str): return ""
    return " ".join(OrderedDict.fromkeys(text.split()))

LIGATURE_MAP = {"\uFB00":"ff", "\uFB01":"fi", "\uFB02":"fl", "\uFB03":"ffi", "\uFB04":"ffl", "\uFB05":"st", "\uFB06":"st"}
def de_ligature(text: str) -> str:
    """Replaces common ligatures."""
    if not isinstance(text, str): return ""
    return "".join(LIGATURE_MAP.get(ch, ch) for ch in text)

# ==============================================================================
# The Unified, Comprehensive Preprocessing Function
# ==============================================================================
def preprocess_series(series: pd.Series) -> pd.Series:
    if not isinstance(series, pd.Series): raise TypeError("Input must be a pandas Series.")
    if nlp_sm is None: raise RuntimeError("Core SpaCy model (nlp_sm) not loaded for preprocess_series.")
    print(f"ℹ️ Starting 'preprocess_series' (Targeted Fixes) for {len(series)} items...")
    txt = series.astype(str).str.lower().fillna("")
    txt = txt.apply(de_ligature)
    print("   - Applying synonym folding...")
    if hasattr(config, 'SYNONYMS') and config.SYNONYMS:
        for long_form, short_form in config.SYNONYMS.items():
            try:
                pattern = rf"\b{re.escape(long_form)}\b"
                txt = txt.str.replace(pattern, short_form, regex=True, case=False)
            except re.error as e:
                warnings.warn(f"⚠️ Synonym regex error for '{long_form}' -> '{short_form}': {e}")
    else:
        warnings.warn("⚠️ config.SYNONYMS not found or empty. Skipping synonym folding.")
    print("   - Protecting key terms...")
    placeholders = {}
    sorted_protected_words = sorted(list(config.PROTECTED_WORDS), key=len, reverse=True)
    for i, word in enumerate(sorted_protected_words):
        word_lower = word.lower()
        idx_str = ""
        temp_i = i
        if temp_i == 0:
            idx_str = "a"
        else:
            while temp_i >= 0:
                remainder = temp_i % 26
                idx_str = chr(97 + remainder) + idx_str
                temp_i = temp_i // 26 - 1
                if temp_i < 0 and idx_str: break
        placeholder = f"protectedmarker{idx_str}endmarker"
        placeholders[placeholder] = word_lower
        txt = txt.str.replace(rf"\b{re.escape(word_lower)}\b", placeholder, regex=True)
    print("   - Applying Regex rules...")
    regex_application_order = [
        "comma_space_to_space",
        "percent_ge_symbols",
        "simple_percent",
        "stray_math_symbols",
        "remove_hash_enclosed",
        "remove_hash_prefix",
        "remove_hash_suffix",
        "dr_name",
        "cas_full",
        "item_ref_full",
        "num_in_paren_unit_counts",
        "num_in_paren_quantities",
        "unitpack",
        "sets_pk",
        "dimensions",
        "mult",
        "trailing_slash_unit",
        "sku_multi_hyphen",
        "sku_num_hyphen_prefix_only",
        "sku_alpha_hyphen_num",
        "sku_letters_digits",
        "sku_num_num",
        "sku_very_long_num",
        "sku_with_nums",
        "nonalp",
        "trailh",
        "withslash",
        "clean_hyphens",
        "empty_parens",
        "multispc" # Always last
    ]

    for name in regex_application_order:
        if name not in config.REGEXES_NORMALIZE:
            continue
        rx, repl = config.REGEXES_NORMALIZE[name]
        try:
            if name == "unitpack": # Run unitpack multiple times
                for _ in range(3):
                    txt = txt.str.replace(rx, repl, regex=True)
            else:
                 txt = txt.str.replace(rx, repl, regex=True)
        except Exception as e:
            warnings.warn(f"⚠️ Warning: Regex '{name}' (Pattern: {rx.pattern if hasattr(rx, 'pattern') else rx}) failed: {e}")

    print("   - Restoring key terms...")
    for placeholder in sorted(placeholders.keys(), key=len, reverse=True):
        original_word = placeholders[placeholder]
        txt = txt.str.replace(placeholder, original_word, regex=False)

    print("   - Applying SpaCy lemmatization and filtering...")
    n_docs = len(txt)
    if n_docs == 0:
        return pd.Series([], dtype=str, index=series.index if series.index is not None else None)

    n_cores = multiprocessing.cpu_count() or 1
    n_proc = min(n_cores, max(1, n_docs // 10_000)) if n_docs > 10000 else 1
    print(f"   - Using {n_proc} processes.")

    docs = nlp_sm.pipe(txt.tolist(), n_process=n_proc, batch_size=5000)
    cleaned_texts = []
    for doc in docs:
        toks = []
        for t in doc:
            lemma = t.lemma_
            is_kept_char = lemma in config.KEEP_CHARS
            is_protected = lemma in config.PROTECTED_WORDS
            contains_digit = any(char.isdigit() for char in lemma)
            is_chem_fragment = lemma in config.CHEM_FRAGMENTS

            keep_token = False
            if is_protected:
                keep_token = True
            elif is_kept_char:
                keep_token = True
            elif is_chem_fragment:
                keep_token = True
            elif (lemma not in STOP_EN and
                  lemma not in config.UNIT_TOKENS and
                  lemma not in config.OTHER_STOPWORDS):
                if len(lemma) > 1:
                    keep_token = True
                elif contains_digit:
                    keep_token = True

            if keep_token:
                toks.append(lemma)
        sent = " ".join(toks)
        # 1. Normalize spaces and strip (BEFORE deduplication)
        sent = re.sub(r"\s+", " ", sent).strip()
        # 2. Deduplicate words (should happen on space-normalized string)
        sent = deduplicate_words(sent)
        # 3. Now apply specific rejoining and symbol compaction to the deduplicated string
        sent = re.sub(r"(\b[a-z0-9]+(?:-[a-z0-9]+)*)\s*\(\s*(0)\s*\)\s*(-)?", r"\1(\2)\3", sent, flags=re.I)
        sent = re.sub(r"(\b[a-z0-9]+)\s*\(\s*(\d+)\s*\)", r"\1(\2)", sent, flags=re.I)
        sent = re.sub(r"(\d)\s*,\s*(\d)", r"\1,\2", sent)
        sent = re.sub(r"([a-z0-9\(])\s*-\s*(\d\s*,\s*\d)", r"\1-\2", sent, flags=re.I)
        sent = re.sub(r"(\d(?:,\d)+)\s*-\s*([a-z0-9\)])", r"\1-\2", sent, flags=re.I)
        sent = re.sub(r"([a-z0-9\(])\s*-\s*([a-z0-9\)])", r"\1-\2", sent, flags=re.I)

        # General symbol compaction - This was the main culprit for merging space-separated identical terms
        # Apply this AFTER deduplication
        sent = re.sub(r"\s*([-/().])\s*", r"\1", sent)
        sent = re.sub(r"\s*,\s*", ",", sent)

        # 4. Careful Leading/Trailing Symbol Removal (from my previous suggestion)
        #    Applied to the single, deduplicated, and compacted string
        sent = re.sub(r"^\s*[\s.,#\*]+(?=[a-z0-9(])", "", sent, flags=re.I)
        sent = re.sub(r"(?<![a-z0-9)])[\s.,#\*]+\s*$", "", sent, flags=re.I)

        # 5. Final space normalization
        sent = re.sub(r"\s+", " ", sent).strip()
        # No need to deduplicate again here
        cleaned_texts.append(sent)

    final_cleaned_output = []

    _months_full_str = r"(?:january|february|march|april|may|june|july|august|september|october|november|december)"
    _months_abbr_str = r"(?:jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)"
    _months_pattern_str = rf"(?:{_months_full_str}|{_months_abbr_str})"
    _years_pattern_str = r"(?:200[0-9]|201[0-9]|202[0-5])"
    _day_pattern_str = r"\d{1,2}(?:st|nd|rd|th)?"

    date_removal_patterns = []
    if hasattr(config, '_MONTHS_PATTERN_STR') and hasattr(config, '_YEARS_PATTERN_STR') and hasattr(config, '_DAY_PATTERN_STR'):
        _cfg_months_pattern = config._MONTHS_PATTERN_STR
        _cfg_years_pattern = config._YEARS_PATTERN_STR
        _cfg_day_pattern = config._DAY_PATTERN_STR
        date_removal_patterns = [
            re.compile(r"\b\d{1,2}[-/]\d{1,2}[-/]\d{2,4}\b"),
            re.compile(rf"\b{_cfg_years_pattern}[-/]\d{{1,2}}[-/]\d{{1,2}}\b"),
            re.compile(rf"\b{_cfg_months_pattern}\s+{_cfg_day_pattern}(?:,)?\s+{_cfg_years_pattern}\b", re.I),
            re.compile(rf"\b{_cfg_day_pattern}\s+{_cfg_months_pattern}\s+{_cfg_years_pattern}\b", re.I),
            re.compile(rf"\b{_cfg_months_pattern}(?!\w)", re.I),
            re.compile(rf"\b{_cfg_years_pattern}(?![0-9a-z])", re.I),
        ]
    else: # Fallback if not defined in config (less ideal)
        warnings.warn("Date helper patterns not found in config.py; using local definitions for final pass. Define in config for consistency.")
        date_removal_patterns = [
            re.compile(r"\b\d{1,2}[-/]\d{1,2}[-/]\d{2,4}\b"),
            re.compile(rf"\b{_years_pattern_str}[-/]\d{{1,2}}[-/]\d{{1,2}}\b"),
            re.compile(rf"\b{_months_pattern_str}\s+{_day_pattern_str}(?:,)?\s+{_years_pattern_str}\b", re.I),
            re.compile(rf"\b{_day_pattern_str}\s+{_months_pattern_str}\s+{_years_pattern_str}\b", re.I),
            re.compile(rf"\b{_months_pattern_str}(?!\w)", re.I),
            re.compile(rf"\b{_years_pattern_str}(?![0-9a-z])", re.I),
        ]
    empty_parens_rx = re.compile(r"\(\s*\)")
    for sent_item in cleaned_texts:
        final_sent = sent_item
        for rx_date in date_removal_patterns:
            final_sent = rx_date.sub(" ", final_sent)
        final_sent = empty_parens_rx.sub(" ", final_sent)
        final_sent = re.sub(r"\s+", " ", final_sent).strip()
        if final_sent.endswith('.') or final_sent.endswith('-'):
            final_sent = final_sent[:-1].rstrip()
        if final_sent.startswith('-') or final_sent.startswith('.'):
            final_sent = final_sent[1:].rstrip()
        final_sent = re.sub(r"\s+", " ", final_sent).strip()
        final_cleaned_output.append(final_sent)

    # Update the print message and the variable being returned
    print("✅ 'preprocess_series' (with Final Pass Cleanup) complete.")
    return pd.Series(final_cleaned_output, index=series.index if series.index is not None else None)
# ==============================================================================
# Example Usage (when run directly) - User Provided + More
# ==============================================================================
if __name__ == "__main__":
    print("\n--- Testing preprocess_utils.py (Full Script with Expanded Tests) ---")

    test_data = pd.Series([
        "Item #123: 1 BOX (50ml) of FisherBrand PCR tubes, REF 456-ABC, 5% Off!",
        "100g BOC-GLY-OH powder, ACS grade",
        "DMEM High Glucose 500ML BOTTLE",
        "polymerase chain reaction kit", # Test synonym
        "Aspirin (CAS 50-78-2)",
        "CRYOGENIC LBL 1360 SETS/PK",
        "Tris(dibenzylideneacetone)dipalladium(0)97%",
        "NA-FMOC-NW-(2,2,4,6,7-PE 25G",
        "1,4-DIOXANE, ACS REAGENT, >=99.0%, 1,4-DIOXANE, ACS REAGENT, >=99.0%",
        "1605-0000 Microcentrifuge tubes- 0.5 ml.",
        "73404-RNeasy Plus Universal Mini Kit (50)",
        "molecular sieves for Dr. Meek",
        "MONO-2-ETHYLHEXYL (2-ETHYL 5ML",
        "PLATINUM(0)-1,3-DIVINYL-1,1,3,3-TETRAMET, PLATINUM(0)-1,3-DIVINYL-1,1,3,3-TETRAMET",
        "#6Q8030810920-000190#VWR PIPET PASTEUR 9IN CS1000",
        "glv examglove BLUE size L (pk/100)", # Test synonym and unit
        "assy kit for dna isolation", # Test synonym
        "tbe buffer solution 10x", # Test potential ambiguity (should be handled by synonyms)
        "rack for 1.5ml tbe (tubes)", # Test context for tbe if not in synonyms
        "RNeasy Mini Kit (Qiagen 74104) - 50 columns", # Test protected word with details
        "  leading and trailing spaces   ",
        "word1 word2 word2 word3 word1", # Test deduplication
        "water, hplc grade",
        "empty () parentheses test",
        "Tris base powder",
        "DCA 2000 KIT REAGENT 10TST/PK",
        "SYR FLT 26MM .2SFCA STRL 50/CS",
        "hcl1 hcl1 hcl2 hcl4 hcl3",
        "miRNeasy Mini Kit (50)",
        "HotStarTaq Master Mix Kit (1000 U)",
        "RNase-Free DNase Set (50)",
        "TRYPAN BLUE SOLUTION CELL CULTURE TESTED, TRYPAN BLUE SOLUTION CELL CULTURE TESTED",
        "XYLENES, ISOMERS PLUS ETHYLBENZENE, REA&, XYLENES, ISOMERS PLUS ETHYLBENZENE, REA&",
        "AMPICILLIN SOD CRYSTALLN 5GR",
        "PROLACT +6 HMF (15ML)",
        "19080001619-19080001619 - August 2019",
        "August 17, 5-515-52614",
        "R2126.1kb",
        "(-)-BLEBBISTATIN, (-)-BLEBBISTATIN",
        "41400045-Insulin-Transferrin-Selenium (ITS -G) (10",
        "KOD Hot Start DNA Polymerase 200 U, KOD Hot Start DNA Polymerase 200 U",
        "10X TAQ BUFFER KCL 4X1.25ML",
        "PHUSION HF DNA POLYM 100 UNITS",
        "100-106 (500mL)-Benchmark Fetal Bovine Serum",
        "ab4819-Anti-Erk1 (pT202/pY204) + Erk2 (pT185/pY187",
        "CC7682-3394-CytoOne(R) 100 x 20 mm TC dish",
        "9187-1208-Cryo-Tags(R), 1.5 x 0.75, assorted color",
        "#6Q8002690915-000020#GLOVE XMTN STERLING SM NTRL PK200"
    ])

    print("\n--- Testing 'preprocess_series' (Unified Heavy Duty) ---")
    print("Original:\n", test_data)

    # Ensure nlp_sm is loaded before calling preprocess_series
    if nlp_sm is None and hasattr(config, 'SPACY_MODEL_SM') and config.SPACY_MODEL_SM:
        print("Reloading nlp_sm for test block as it was None.")
        try:
            nlp_sm = spacy.load(config.SPACY_MODEL_SM, disable=["parser", "ner"])
            nlp_sm.max_length = 4_000_000
        except Exception as e:
            print(f"Failed to reload nlp_sm in test block: {e}")
            nlp_sm = None # Ensure it's None if reload fails


    if nlp_sm: # Only run if core spacy model is available
        cleaned_heavy = preprocess_series(test_data)
        print("Cleaned:\n", cleaned_heavy)
    else:
        print("Skipping preprocess_series test as nlp_sm is not available.")

    print("\n--- Test Complete ---")
