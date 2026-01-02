# classifier.py (CORRECTED)
import numpy as np
import pandas as pd
import yaml
import ahocorasick
import config

# --- Helper Functions (no changes here) ---
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
        print(f"â ïž Keyword file not found: {filepath}")
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
    def __init__(self, ml_model, vectorizer, seed_automaton, anti_seed_automaton):
        self.ml_model = ml_model
        self.vectorizer = vectorizer
        self.seed_automaton = seed_automaton
        self.anti_seed_automaton = anti_seed_automaton
        self.is_bert = hasattr(vectorizer, 'encode')

    def predict(self, descriptions):
        """
        Predicts labels for a list or Series of descriptions using the gatekeeper logic.
        (CORRECTED to prioritize seed keywords)
        """
        if not isinstance(descriptions, (list, pd.Series)):
            descriptions = [descriptions]
        
        final_predictions = {}
        to_predict_ml = {'indices': [], 'data': []}

        for i, desc in enumerate(descriptions):
            # *** LOGIC CHANGE IS HERE ***
            # The logic is now sequential, with seed keywords having the final say.
            is_anti_seed = has_match(desc, self.anti_seed_automaton)
            is_seed = has_match(desc, self.seed_automaton)

            if is_seed:
                final_predictions[i] = 1  
            elif is_anti_seed:
                final_predictions[i] = 0  
            else:
                # No keyword match, queue it for the ML model
                to_predict_ml['indices'].append(i)
                to_predict_ml['data'].append(desc)

        # If any items were queued for the ML model, predict them (no changes here)
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