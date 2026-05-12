# classifier.py
import numpy as np
import pandas as pd
import yaml
import re
import ahocorasick
from scipy.sparse import hstack, csr_matrix
from sklearn.preprocessing import normalize

import config

# --- Engineered features ----------------------------------------------------
# Description-level numeric features appended to the TF-IDF + supplier matrix
# at both training (1b_create_text_embeddings.py) and inference time.  Kept
# thin so they don't dilute the TF-IDF signal; the LR learns their weights.

_VOLUME_UNIT_REGEX = re.compile(
    r'\b\d+(?:\.\d+)?\s*'
    r'(?:ml|ul|mg|kg|ug|ng|nm|um|nmol|umol|pmol|fmol|mol|liter|microliter)\b',
    re.IGNORECASE,
)


def compute_engineered_features(descriptions, weight=None):
    """Return a (n, 2) sparse CSR matrix of engineered features:
        col 0 — scaled token count: min(words, 50) / 50, in [0, 1]
        col 1 — has-volume-unit flag: 0 or 1 (matches tokens like
                '1.5ml', '100ul', '5nmol' — preserved by the new
                cleaning pipeline).

    Scaled by `weight` (defaults to config.FEATURE_WEIGHT).  Callers must
    use this same function at training and inference so the LR sees the
    same column meanings on both sides.
    """
    w = config.FEATURE_WEIGHT if weight is None else weight

    if isinstance(descriptions, pd.Series):
        texts = descriptions.fillna('').astype(str)
    else:
        texts = pd.Series([str(d) if isinstance(d, str) else '' for d in descriptions])

    tok_count = texts.str.split().str.len().fillna(0).clip(upper=50).astype(float) / 50.0
    has_vol = texts.str.contains(_VOLUME_UNIT_REGEX, regex=True, na=False).astype(float)

    arr = np.column_stack([tok_count.values, has_vol.values]) * w
    return csr_matrix(arr)


# --- Helper Functions ---
def _normalize_separator_pattern(token):
    """Build a regex fragment from `token` where any internal run of
    hyphen/whitespace becomes `[-\\s]+`, so a single seed line like
    `pipet-aid` also matches `pipet aid` (and vice versa).  Other
    characters are re.escape'd."""
    out = []
    i, n = 0, len(token)
    while i < n:
        ch = token[i]
        if ch == '-' or ch.isspace():
            out.append(r'[-\s]+')
            j = i + 1
            while j < n and (token[j] == '-' or token[j].isspace()):
                j += 1
            i = j
        else:
            out.append(re.escape(ch))
            i += 1
    return ''.join(out)


class SeedMatcher:
    """Two-mode matcher for seed YAML files:
      * `single_regex`  — word-bounded regex matching any one keyword
      * `group_regexes` — list of token-regex lists; a group fires when
                          EVERY token regex hits the description (any order)

    Duck-types like a compiled regex via `.search()` so `has_match()` works,
    and exposes `.batch_match()` so `batch_has_match()` can vectorize the
    co-occurrence check via pandas `str.contains`.
    """

    def __init__(self, single_regex, group_regexes):
        self.single_regex = single_regex
        self.group_regexes = group_regexes

    def search(self, text):
        if self.single_regex is not None and self.single_regex.search(text):
            return self
        for group in self.group_regexes:
            if all(r.search(text) for r in group):
                return self
        return None

    def batch_match(self, series):
        if self.single_regex is not None:
            mask = series.str.contains(self.single_regex, na=False)
        else:
            mask = pd.Series(False, index=series.index)
        for group in self.group_regexes:
            if not group:
                continue
            group_mask = pd.Series(True, index=series.index)
            for r in group:
                group_mask &= series.str.contains(r, na=False)
            mask |= group_mask
        return mask


def load_keywords_and_build_automaton(filepath):
    """Loads keywords (and optional all_of_groups) from a YAML file and
    returns a SeedMatcher.

    YAML schema:
        keywords:        list of single tokens / phrases (existing)
        all_of_groups:   optional list of token-lists; each group fires
                         when every token in the list appears anywhere in
                         the description (word-bounded, any order)

    Single-keyword matching is word-bounded with `(?<!\\w)…(?!\\w)`, an
    optional `(?:e?s)?` plural suffix, and treats internal hyphens and
    whitespace as equivalent (so `pipet-aid` covers `pipet aid` too).
    Long phrases are placed first in the alternation so they take
    precedence over shorter keyword prefixes.

    The legacy name is kept so call sites don't have to change;
    has_match() / batch_has_match() duck-type between SeedMatcher,
    plain compiled regex, and Aho-Corasick automaton.
    """
    try:
        with open(filepath, 'r') as f:
            data = yaml.safe_load(f) or {}
    except FileNotFoundError:
        print(f"Warning: Keyword file not found: {filepath}")
        return None

    raw_keywords = data.get('keywords') or []
    raw_groups = data.get('all_of_groups') or []

    clean = sorted({str(k).lower().strip() for k in raw_keywords if str(k).strip()},
                   key=len, reverse=True)
    if clean:
        token_patterns = [_normalize_separator_pattern(k) for k in clean]
        pattern = r'(?<!\w)(?:' + '|'.join(token_patterns) + r')(?:e?s)?(?!\w)'
        single_regex = re.compile(pattern, flags=re.IGNORECASE)
    else:
        single_regex = None

    group_regexes = []
    for g in raw_groups:
        tokens = [str(t).lower().strip() for t in (g or []) if str(t).strip()]
        if not tokens:
            continue
        compiled = []
        for t in tokens:
            tp = _normalize_separator_pattern(t)
            compiled.append(re.compile(r'(?<!\w)' + tp + r'(?:e?s)?(?!\w)',
                                       flags=re.IGNORECASE))
        group_regexes.append(compiled)

    if single_regex is None and not group_regexes:
        return None
    return SeedMatcher(single_regex, group_regexes)

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
    """Checks if a description matches the given matcher.  Accepts a
    SeedMatcher (seed / anti-seed), a compiled regex (legacy single-mode
    matchers), or an Aho-Corasick automaton (market rules, substring)."""
    if not isinstance(description, str) or automaton is None:
        return False
    text = description.lower()
    if hasattr(automaton, 'batch_match'):  # SeedMatcher
        return automaton.search(text) is not None
    if hasattr(automaton, 'search'):
        return automaton.search(text) is not None
    try:
        next(automaton.iter(text))
        return True
    except StopIteration:
        return False


def batch_has_match(descriptions, automaton):
    """Vectorized equivalent of `descriptions.apply(has_match, automaton=automaton)`.

    For SeedMatcher, dispatches to its own vectorized batch_match which
    folds together the single-keyword regex and any all_of token groups.
    For plain compiled regex, dispatches to pandas `Series.str.contains`.
    For Aho-Corasick automatons (market rules), falls back to a list
    comprehension over `.tolist()` — still avoids per-row pandas apply.

    Behavior matches has_match row-for-row: non-string values return False;
    the regex IGNORECASE flag is preserved; AC matching is lowercase.
    """
    idx = descriptions.index
    if automaton is None:
        return pd.Series(False, index=idx)
    if hasattr(automaton, 'batch_match'):  # SeedMatcher
        return automaton.batch_match(descriptions)
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

            # Append engineered description-level features (token count,
            # has-volume-unit).  Must mirror the same call in 1b.
            if getattr(config, 'USE_ENGINEERED_FEATURES', False):
                extra = compute_engineered_features(to_predict_ml['data'])
                vectors = hstack([vectors, extra])

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
