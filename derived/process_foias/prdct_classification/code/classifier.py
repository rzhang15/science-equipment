# classifier.py
import numpy as np
import pandas as pd
import yaml
import re
import ahocorasick
from scipy.sparse import hstack
from sklearn.preprocessing import normalize

import config

# --- Helper Functions ---
def load_keywords_and_build_automaton(filepath):
    """Loads keywords from a YAML file and compiles a word-bounded regex that
    matches each keyword as a whole word (optionally with an s/es plural
    suffix).  Using lookarounds `(?<!\\w)` / `(?!\\w)` instead of `\\b` so
    keywords with leading/trailing punctuation (e.g. "d(-)fructose") still
    match correctly.  Long phrases are placed first in the alternation so
    they take precedence over shorter keyword prefixes.

    Returns a compiled regex.  The legacy name is kept so call sites don't
    have to change; has_match() duck-types between regex and Aho-Corasick
    automaton (market rules still use the automaton).
    """
    try:
        with open(filepath, 'r') as f:
            keywords = yaml.safe_load(f).get('keywords', [])
        if not keywords:
            return None
        clean = sorted({str(k).lower().strip() for k in keywords if str(k).strip()},
                       key=len, reverse=True)
        escaped = [re.escape(k) for k in clean]
        pattern = r'(?<!\w)(?:' + '|'.join(escaped) + r')(?:e?s)?(?!\w)'
        return re.compile(pattern, flags=re.IGNORECASE)
    except FileNotFoundError:
        print(f"Warning: Keyword file not found: {filepath}")
        return None

def extract_market_keywords_and_build_automaton(rules_filepath, min_keyword_len=5):
    """
    Parses market_rules.yml to extract all keywords that define a lab item,
    then builds an Aho-Corasick automaton for fast matching.
    This mirrors the keyword extraction logic in 1_build_training_dataset.py.

    IMPORTANT: Wildcards (e.g., *iv*, *ph*) are stripped before building the
    automaton, which can produce very short fragments (2-3 chars) that cause
    massive false positives. The min_keyword_len filter prevents this.
    """
    keywords = set()
    skipped = []
    try:
        with open(rules_filepath, 'r') as f:
            rules = yaml.safe_load(f)

        aliases = {f"${k}": v for k, v in rules.get('keyword_groups', {}).items()}
        market_rules = rules.get('market_rules', [])

        for rule in market_rules:
            for key in ['all_of', 'any_of']:
                if key in rule:
                    for keyword in rule[key]:
                        if keyword in aliases:
                            expanded = aliases[keyword]
                            cleaned_expanded = [re.sub(r'[\*]', '', kw) for kw in expanded]
                            keywords.update(cleaned_expanded)
                        else:
                            cleaned_keyword = re.sub(r'[\*]', '', keyword)
                            keywords.add(cleaned_keyword)

        # Filter out short keywords that would cause false positives
        filtered = set()
        for kw in keywords:
            if len(kw.strip()) >= min_keyword_len:
                filtered.add(kw)
            else:
                skipped.append(kw)

        if skipped:
            print(f"  Market rule automaton: skipped {len(skipped)} keywords shorter than "
                  f"{min_keyword_len} chars: {sorted(skipped)[:20]}")

        if not filtered:
            return None
        A = ahocorasick.Automaton()
        for idx, keyword in enumerate(filtered):
            A.add_word(str(keyword).lower(), (idx, str(keyword).lower()))
        A.make_automaton()
        return A
    except Exception as e:
        print(f"Warning: Error building market rule automaton: {e}")
        return None

def build_enzyme_regex(rules_filepath, min_keyword_len=4):
    """Builds a CASE-SENSITIVE word-bounded regex for restriction enzymes.

    Procurement descriptions spell enzymes several ways:
      - CamelCase catalog form:   "SpeI", "HindIII", "EcoRI"
      - ALL-CAPS procurement:     "SPEI", "HINDIII", "ECORI"
      - Spaced:                   "Spe I",  "Hind III", "Eco RI"
      - Hyphenated:               "Spe-I",  "Hind-III"
      - Arabic numeral suffix:    "Spe1" / "Spe-1" / "Hind3"
      - With -HF / -HFv2 suffix:  "SpeI-HF", "HindIII-HFv2"
    English collisions ('saline', 'pacific', 'bearing') only appear in
    lowercase, so the CamelCase / ALL-CAPS case sensitivity avoids them.

    The returned regex matches each enzyme as
        <prefix>[\\s\\-]?<suffix>(-HF(?:v\\d+)?)?
    where <suffix> accepts both the Roman numeral (I / II / III / IV / V)
    and the Arabic-digit equivalent (1 / 2 / 3 / 4 / 5).  The separator
    between prefix and suffix is optional (allows "SpeI", "Spe I", "Spe-I").
    """
    try:
        with open(rules_filepath, 'r') as f:
            rules = yaml.safe_load(f)
        enzymes = rules.get('keyword_groups', {}).get('RESTRICTION_ENZYME', [])
        roman_to_arabic = {'I': '1', 'II': '2', 'III': '3', 'IV': '4', 'V': '5'}
        # (prefix, roman_suffix, hf_tail) — case-distinct entries stored as
        # tuples of raw strings; we emit both CamelCase and ALL-CAPS forms.
        parsed = []
        for name in enzymes:
            name = str(name).strip()
            if len(name) < min_keyword_len:
                continue
            # Strip optional -HF / -HFv2 tail; keep it on the pattern so we
            # still match it but allow variants without it.
            m = re.match(r'^((?:Nb\.|Nt\.)?.+?)(III|IV|II|I|V)(-HF(?:v\d+)?)?$', name)
            if not m:
                # Name doesn't end in a Roman numeral — fall back to the
                # literal form (e.g., rare names like "Acc65I" where the
                # digit is inline); still match it exactly.
                parsed.append((name, '', ''))
                continue
            prefix, suffix, hf = m.group(1), m.group(2), m.group(3) or ''
            parsed.append((prefix, suffix, hf))
        patterns = set()
        for prefix, suffix, hf in parsed:
            if not suffix:  # literal-form fallback
                patterns.add(re.escape(prefix))
                patterns.add(re.escape(prefix.upper()))
                continue
            arabic = roman_to_arabic.get(suffix, '')
            suffix_alt = f'(?:{suffix}|{arabic})' if arabic else suffix
            hf_opt = r'(?:\-HF(?:v\d+)?)?'  # always optional to be lenient
            sep = r'[\s\-]?'
            for case_prefix in (prefix, prefix.upper()):
                patterns.add(re.escape(case_prefix) + sep + suffix_alt + hf_opt)
        if not patterns:
            return None
        # Longer patterns first so e.g. HindIII wins over HindII when both
        # could match a prefix.
        sorted_patterns = sorted(patterns, key=len, reverse=True)
        pattern = r'(?<!\w)(?:' + '|'.join(sorted_patterns) + r')(?!\w)'
        return re.compile(pattern)  # NO re.IGNORECASE — case matters
    except FileNotFoundError:
        return None


def has_match(description, automaton):
    """Checks if a description matches the given matcher.  Accepts either a
    compiled regex (seed / anti-seed, word-bounded) or an Aho-Corasick
    automaton (market rules, substring)."""
    if not isinstance(description, str) or automaton is None:
        return False
    text = description.lower()
    if hasattr(automaton, 'search'):
        return automaton.search(text) is not None
    try:
        next(automaton.iter(text))
        return True
    except StopIteration:
        return False


def batch_has_match(descriptions, automaton):
    """Vectorized equivalent of `descriptions.apply(has_match, automaton=automaton)`.

    For compiled-regex matchers (seed / anti-seed), dispatches to pandas
    `Series.str.contains`, which runs the match loop in C.  For Aho-Corasick
    automatons (market rules), falls back to a list comprehension over
    `.tolist()` — still avoids per-row pandas apply overhead.

    Behavior matches has_match row-for-row: non-string values return False;
    the regex IGNORECASE flag is preserved; AC matching is lowercase.
    """
    idx = descriptions.index
    if automaton is None:
        return pd.Series(False, index=idx)
    if hasattr(automaton, 'search'):
        # Compiled regex already has re.IGNORECASE; na=False matches the
        # non-string guard in has_match.
        return descriptions.str.contains(automaton, na=False)

    def _match(d):
        if not isinstance(d, str):
            return False
        try:
            next(automaton.iter(d.lower()))
            return True
        except StopIteration:
            return False
    return pd.Series([_match(d) for d in descriptions], index=idx)


def _is_trivial_desc(desc):
    """Deprecated: was flipping UMich primer/antibody IDs (e.g. rad51exon3for,
    gbaa1858mut2, p38, ab68672) to non-lab, wiping out 1500+ real lab items.
    Kept for reference; no longer wired into predict()."""
    if not isinstance(desc, str):
        return True
    for tok in desc.split():
        if tok.isalpha() and len(tok) >= 3:
            return False
    return True

# --- The Main Hybrid Classifier Class ---
class HybridClassifier:
    def __init__(self, ml_model, vectorizer, seed_automaton, anti_seed_automaton,
                 market_rule_automaton=None, supplier_vectorizer=None,
                 bulk_filter=None, bulk_filter_vectorizer=None,
                 supplier_priors=None, enzyme_regex=None):
        self.ml_model = ml_model
        self.vectorizer = vectorizer
        self.seed_automaton = seed_automaton
        self.anti_seed_automaton = anti_seed_automaton
        self.market_rule_automaton = market_rule_automaton
        self.enzyme_regex = enzyme_regex
        self.supplier_vectorizer = supplier_vectorizer
        self.bulk_filter = bulk_filter
        self.bulk_filter_vectorizer = bulk_filter_vectorizer
        # supplier_priors: dict {normalized_supplier_token: (count, lab_rate)}
        # from training data; used to override lab predictions on suppliers
        # that are overwhelmingly non-lab (Office Max, Fine Science Tools, ...).
        self.supplier_priors = supplier_priors or {}
        self.is_bert = hasattr(vectorizer, 'encode')

        # Build automaton for strong lab signals that bypass the ML override
        self.strong_lab_automaton = None
        if hasattr(config, 'STRONG_LAB_SIGNALS') and config.STRONG_LAB_SIGNALS:
            A = ahocorasick.Automaton()
            for idx, kw in enumerate(config.STRONG_LAB_SIGNALS):
                A.add_word(kw.lower(), (idx, kw.lower()))
            A.make_automaton()
            self.strong_lab_automaton = A

        # Compile primer / oligo regex (structural name pattern, bypasses ML
        # because bare primer names carry no text signal for the model).
        self.primer_regex = None
        if getattr(config, 'USE_PRIMER_RULE', False) and getattr(config, 'PRIMER_REGEX', ''):
            self.primer_regex = re.compile(config.PRIMER_REGEX, re.IGNORECASE)

    def predict(self, descriptions, suppliers=None):
        """
        Predicts labels for a list or Series of descriptions.

        Priority:
          1. Anti-seed match            -> label=0 (always non-lab)
          2. Seed match                 -> label=1 (always lab)
          3. Lab-supplier allowlist     -> label=1 (supplier name in
                                           config.LAB_SUPPLIER_KEYWORDS;
                                           requires suppliers to be passed in)
          4. Market-rule match          -> label=1 (gated by config.USE_MARKET_RULE_GATE,
                                           default off: market rules use wildcard
                                           fragments that produce massive FPs at
                                           inference when not balanced by the
                                           training-time category downgrade)
          5. Primer regex match         -> label=1 (gated by config.USE_PRIMER_RULE)
          6. No keyword match           -> ML model at PREDICTION_THRESHOLD

        Optional post-hoc filters (bulk-chemical, supplier-prior) are gated by
        config flags.  When active they skip items in strong_lab_indices
        (seed / primer matches) so those forced-lab items cannot be flipped back.
        """
        if not isinstance(descriptions, (list, pd.Series)):
            descriptions = [descriptions]

        suppliers_list = None
        if suppliers is not None:
            if isinstance(suppliers, pd.Series):
                suppliers_list = suppliers.tolist()
            else:
                suppliers_list = list(suppliers)

        final_predictions = {}
        strong_lab_indices = set()
        anti_seed_indices = set()
        to_predict_ml = {'indices': [], 'data': []}

        use_market_gate = getattr(config, 'USE_MARKET_RULE_GATE', False)
        lab_supplier_regex = getattr(config, 'LAB_SUPPLIER_REGEX', None)
        primer_regex = getattr(self, 'primer_regex', None)

        # Vectorize the rule pre-pass: clean once, run each matcher over the
        # whole series, then resolve priorities from boolean masks.  Replaces
        # a per-row loop that made 3–4 regex/AC calls (each re-lowercasing
        # the string) — the big hold-out cost.
        n = len(descriptions)
        desc_series = pd.Series(
            list(descriptions) if not isinstance(descriptions, pd.Series) else descriptions.values
        )
        cleaned_series = desc_series.map(
            lambda d: config.clean_for_model(d) if isinstance(d, str) else ''
        )
        cleaned_list = cleaned_series.tolist()

        anti_mask = batch_has_match(cleaned_series, self.anti_seed_automaton).to_numpy()
        seed_mask = batch_has_match(cleaned_series, self.seed_automaton).to_numpy()
        if use_market_gate:
            market_mask = batch_has_match(cleaned_series, self.market_rule_automaton).to_numpy()
        else:
            market_mask = np.zeros(n, dtype=bool)

        # Case-sensitive restriction enzyme match: runs on the RAW description
        # (not clean_for_model output) because clean_for_model strips patterns
        # like 'ALWI-500' as catalog numbers — which is exactly the shape real
        # enzyme orders take.  Case-sensitive matching on CamelCase + ALL-CAPS
        # forms keeps 'saline' / 'pacific' / 'bearing' (lowercase prose) dark.
        enzyme_regex = getattr(self, 'enzyme_regex', None)
        if enzyme_regex is not None:
            raw_series = pd.Series(
                [str(d) if isinstance(d, str) else '' for d in (
                    descriptions if isinstance(descriptions, (list, pd.Series)) else [descriptions]
                )]
            )
            enzyme_mask = raw_series.str.contains(enzyme_regex, na=False).to_numpy()
        else:
            enzyme_mask = np.zeros(n, dtype=bool)

        lab_supp_mask = np.zeros(n, dtype=bool)
        if lab_supplier_regex is not None and suppliers_list is not None:
            supp_series = pd.Series(['' if s is None else str(s) for s in suppliers_list])
            lab_supp_mask = supp_series.str.contains(lab_supplier_regex, na=False).to_numpy()

        if primer_regex is not None:
            primer_mask = cleaned_series.str.contains(primer_regex, na=False).to_numpy()
        else:
            primer_mask = np.zeros(n, dtype=bool)

        strong_lab_mask = (seed_mask | market_mask | enzyme_mask | lab_supp_mask | primer_mask) & ~anti_mask
        ml_mask = ~anti_mask & ~strong_lab_mask

        cleaned_descs = dict(enumerate(cleaned_list))
        for i in np.flatnonzero(anti_mask).tolist():
            final_predictions[i] = 0
            anti_seed_indices.add(i)
        for i in np.flatnonzero(strong_lab_mask).tolist():
            final_predictions[i] = 1
            strong_lab_indices.add(i)
        ml_indices = np.flatnonzero(ml_mask).tolist()
        to_predict_ml['indices'] = ml_indices
        to_predict_ml['data'] = [cleaned_list[i] for i in ml_indices]

        if to_predict_ml['data']:
            if self.is_bert:
                desc_vectors = self.vectorizer.encode(to_predict_ml['data'], show_progress_bar=False)
            else:
                desc_vectors = self.vectorizer.transform(to_predict_ml['data'])

            if self.supplier_vectorizer is not None and suppliers_list is not None:
                supp_tokens = [config.normalize_supplier(str(suppliers_list[i]))
                               for i in to_predict_ml['indices']]
                supp_vectors = self.supplier_vectorizer.transform(supp_tokens)
                desc_norm = normalize(desc_vectors, norm='l2')
                supp_norm = normalize(supp_vectors, norm='l2')
                vectors = hstack([desc_norm * config.DESC_WEIGHT,
                                  supp_norm * config.SUPPLIER_WEIGHT])
            else:
                vectors = desc_vectors

            ml_probas = self.ml_model.predict_proba(vectors)[:, 1]
            for j, idx in enumerate(to_predict_ml['indices']):
                final_predictions[idx] = int(ml_probas[j] >= config.PREDICTION_THRESHOLD)

        # Second-stage bulk-chemical / instrument-part filter.  Runs only on
        # items currently predicted as lab and without a strong lab signal —
        # strong-lab items (antibody, pcr master mix, ...) are never in the
        # bulk-chemical class, so skipping them avoids wasted inference and
        # guards against a spurious filter flip.
        use_bulk = (getattr(config, 'USE_BULK_FILTER', False)
                    and self.bulk_filter is not None
                    and self.bulk_filter_vectorizer is not None)
        if use_bulk:
            candidates = [i for i, p in final_predictions.items()
                          if p == 1 and i not in strong_lab_indices]
            if candidates:
                cand_texts = [cleaned_descs[i] for i in candidates]
                X_cand = self.bulk_filter_vectorizer.transform(cand_texts)
                probs = self.bulk_filter.predict_proba(X_cand)[:, 1]
                thr = config.BULK_FILTER_THRESHOLD
                for i, prob in zip(candidates, probs):
                    if prob >= thr:
                        final_predictions[i] = 0

        # Post-hoc supplier-prior overlay.  Flip predictions when the
        # supplier's training-split lab rate is extreme and its count meets
        # the minimum.  Anti-seed and strong-lab items are preserved.
        use_prior = (getattr(config, 'USE_SUPPLIER_PRIOR', False)
                     and self.supplier_priors
                     and suppliers_list is not None)
        if use_prior:
            min_count = getattr(config, 'SUPPLIER_PRIOR_MIN_COUNT', 20)
            low_thr = getattr(config, 'SUPPLIER_PRIOR_LAB_THRESHOLD', 0.1)
            high_thr = getattr(config, 'SUPPLIER_PRIOR_LAB_HIGH_THRESHOLD', 0.9)
            for i in range(len(descriptions)):
                if i in anti_seed_indices or i in strong_lab_indices:
                    continue
                tok = config.normalize_supplier(str(suppliers_list[i]))
                prior = self.supplier_priors.get(tok)
                if prior is None:
                    continue
                cnt, rate = prior
                if cnt < min_count:
                    continue
                if final_predictions[i] == 1 and rate <= low_thr:
                    final_predictions[i] = 0
                elif final_predictions[i] == 0 and rate >= high_thr:
                    final_predictions[i] = 1

        return np.array([final_predictions[i] for i in sorted(final_predictions)])
