# classifier.py
import numpy as np
import pandas as pd
import yaml
import re
import ahocorasick
import config

# --- Helper Functions ---
def load_keywords_and_build_automaton(filepath):
    """Loads keywords from a YAML file and builds an Aho-Corasick automaton."""
    try:
        with open(filepath, 'r') as f:
            keywords = yaml.safe_load(f).get('keywords', [])
            if not keywords: return None
            A = ahocorasick.Automaton()
            for idx, keyword in enumerate(keywords):
                A.add_word(str(keyword).lower(), (idx, str(keyword).lower()))
            A.make_automaton()
            return A
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

def has_match(description, automaton):
    """Checks if a description contains any keyword from the given automaton."""
    if not isinstance(description, str) or automaton is None:
        return False
    try:
        next(automaton.iter(description.lower()))
        return True
    except StopIteration:
        return False

# --- The Main Hybrid Classifier Class ---
class HybridClassifier:
    def __init__(self, ml_model, vectorizer, seed_automaton, anti_seed_automaton,
                 market_rule_automaton=None):
        self.ml_model = ml_model
        self.vectorizer = vectorizer
        self.seed_automaton = seed_automaton
        self.anti_seed_automaton = anti_seed_automaton
        self.market_rule_automaton = market_rule_automaton
        self.is_bert = hasattr(vectorizer, 'encode')

        # Build automaton for strong lab signals that bypass the ML override
        self.strong_lab_automaton = None
        if hasattr(config, 'STRONG_LAB_SIGNALS') and config.STRONG_LAB_SIGNALS:
            A = ahocorasick.Automaton()
            for idx, kw in enumerate(config.STRONG_LAB_SIGNALS):
                A.add_word(kw.lower(), (idx, kw.lower()))
            A.make_automaton()
            self.strong_lab_automaton = A

    def predict(self, descriptions):
        """
        Predicts labels for a list or Series of descriptions using the gatekeeper logic.

        Priority:
          1. Anti-seed keyword match         -> label=0 (always non-lab)
          2. Market rule / seed keyword match -> label=1, UNLESS the ML model is
             confidently non-lab (probability < KEYWORD_OVERRIDE_THRESHOLD)
             AND the description does NOT contain a strong lab signal.
             Strong lab signals (e.g. "antibody") always force lab when a
             keyword also matches.
          3. No keyword match                -> ML model decides at PREDICTION_THRESHOLD
        """
        if not isinstance(descriptions, (list, pd.Series)):
            descriptions = [descriptions]

        final_predictions = {}
        to_predict_ml = {'indices': [], 'data': []}
        keyword_check = {'indices': [], 'data': [], 'keyword_label': [],
                         'has_strong_signal': []}

        for i, desc in enumerate(descriptions):
            is_anti_seed = has_match(desc, self.anti_seed_automaton)
            is_market_rule = has_match(desc, self.market_rule_automaton)
            is_seed = has_match(desc, self.seed_automaton)

            if is_anti_seed:
                final_predictions[i] = 0  # Anti-seed always wins
            elif is_market_rule or is_seed:
                strong = has_match(desc, self.strong_lab_automaton)
                keyword_check['indices'].append(i)
                keyword_check['data'].append(desc)
                keyword_check['keyword_label'].append(1)
                keyword_check['has_strong_signal'].append(strong)
            else:
                to_predict_ml['indices'].append(i)
                to_predict_ml['data'].append(desc)

        # Combine all items that need ML scoring
        all_ml_data = keyword_check['data'] + to_predict_ml['data']
        all_ml_indices = keyword_check['indices'] + to_predict_ml['indices']

        if all_ml_data:
            if self.is_bert:
                vectors = self.vectorizer.encode(all_ml_data, show_progress_bar=False)
            else:
                vectors = self.vectorizer.transform(all_ml_data)

            ml_probas = self.ml_model.predict_proba(vectors)[:, 1]

            # Process keyword-matched items: trust ML if it's confidently non-lab,
            # UNLESS a strong lab signal is present (then always trust keyword)
            n_kw = len(keyword_check['data'])
            override_threshold = config.KEYWORD_OVERRIDE_THRESHOLD
            for j in range(n_kw):
                original_index = keyword_check['indices'][j]
                prob = ml_probas[j]
                if keyword_check['has_strong_signal'][j]:
                    # Strong lab signal present — always trust keyword match
                    final_predictions[original_index] = 1
                elif prob < override_threshold:
                    # ML is confidently non-lab — override the keyword match
                    final_predictions[original_index] = 0
                else:
                    # ML agrees or is uncertain — trust the keyword match
                    final_predictions[original_index] = 1

            # Process non-keyword items: standard ML threshold
            for j in range(n_kw, len(all_ml_data)):
                original_index = all_ml_indices[j]
                prob = ml_probas[j]
                final_predictions[original_index] = int(prob >= config.PREDICTION_THRESHOLD)

        return np.array([final_predictions[i] for i in sorted(final_predictions)])
