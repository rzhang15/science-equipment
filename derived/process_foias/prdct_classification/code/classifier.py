# classifier.py (CORRECTED — priority: market_rules > anti_seed > seed > ML)
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

def extract_market_keywords_and_build_automaton(rules_filepath):
    """
    Parses market_rules.yml to extract all keywords that define a lab item,
    then builds an Aho-Corasick automaton for fast matching.
    This mirrors the keyword extraction logic in 1_build_training_dataset.py.
    """
    keywords = set()
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

        if not keywords:
            return None
        A = ahocorasick.Automaton()
        for idx, keyword in enumerate(keywords):
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

    def predict(self, descriptions):
        """
        Predicts labels for a list or Series of descriptions using the gatekeeper logic.
        Priority (matches training-time logic in 1_build_training_dataset.py):
          1. Market rule keyword match  -> label=1 (highest priority, overrides anti-seed)
          2. Anti-seed keyword match    -> label=0 (overrides seed)
          3. Seed keyword match         -> label=1
          4. No keyword match           -> ML model decides
        """
        if not isinstance(descriptions, (list, pd.Series)):
            descriptions = [descriptions]

        final_predictions = {}
        to_predict_ml = {'indices': [], 'data': []}

        for i, desc in enumerate(descriptions):
            is_market_rule = has_match(desc, self.market_rule_automaton)
            is_anti_seed = has_match(desc, self.anti_seed_automaton)
            is_seed = has_match(desc, self.seed_automaton)

            if is_market_rule:
                final_predictions[i] = 1  # Market rules override everything
            elif is_anti_seed:
                final_predictions[i] = 0  # Anti-seed overrides seed
            elif is_seed:
                final_predictions[i] = 1  # Seed keywords
            else:
                # No keyword match, queue it for the ML model
                to_predict_ml['indices'].append(i)
                to_predict_ml['data'].append(desc)

        # If any items were queued for the ML model, predict them
        if to_predict_ml['data']:
            if self.is_bert:
                vectors = self.vectorizer.encode(to_predict_ml['data'], show_progress_bar=False)
            else:
                vectors = self.vectorizer.transform(to_predict_ml['data'])

            ml_probas = self.ml_model.predict_proba(vectors)[:, 1]
            ml_preds = (ml_probas >= config.PREDICTION_THRESHOLD).astype(int)

            for i, pred in enumerate(ml_preds):
                original_index = to_predict_ml['indices'][i]
                final_predictions[original_index] = pred

        return np.array([final_predictions[i] for i in sorted(final_predictions)])
