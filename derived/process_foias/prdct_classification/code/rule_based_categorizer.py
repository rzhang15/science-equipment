# rule_based_categorizer.py (UPGRADED LOGIC V3)
"""
A pattern-based categorizer that applies three types of rules from a YAML file.
This version has corrected logic to handle nested conditions and a more robust
regex builder, now with support for exact-string matching.
"""
import yaml
import re

class RuleBasedCategorizer:
    def __init__(self, rules_filepath):
        print("ℹ️ Initializing RuleBasedCategorizer with upgraded logic...")
        try:
            with open(rules_filepath, 'r') as f:
                raw_rules = yaml.safe_load(f)
            
            self.aliases = {f"${k}": v for k, v in raw_rules.get('keyword_groups', {}).items()}
            self.override_rules = raw_rules.get('market_rules', [])
            self.veto_rules = raw_rules.get('required_keywords', {})
            self.hierarchical_veto_rules = raw_rules.get('hierarchical_veto_rules', [])
            
            self._compiled_regexes = {}

            print(f"  - Loaded {len(self.override_rules)} market override rules.")
            print(f"  - Loaded {len(self.veto_rules)} exact-match veto rules.")
            print(f"  - Loaded {len(self.hierarchical_veto_rules)} hierarchical veto rules.")

        except Exception as e:
            print(f"❌ Error parsing market rules file: {e}")
            self.override_rules, self.veto_rules, self.hierarchical_veto_rules = [], {}, []

    # MODIFIED: This function now accepts an 'exact_match' flag
    def _get_regex(self, keyword, exact_match=False):
        """Creates and caches regex objects with improved word boundary logic."""
        # Use a tuple as the key to cache both normal and exact-match regexes
        cache_key = (keyword, exact_match)
        if cache_key in self._compiled_regexes:
            return self._compiled_regexes[cache_key]
        
        is_substring = keyword.startswith('*') and keyword.endswith('*')
        cleaned_keyword = keyword.strip('*')
        
        parts = [re.escape(part) for part in cleaned_keyword.split()]
        pattern_str = r'[\s-]?'.join(parts)
        
        if exact_match:
            # New: Anchor the pattern to the start (^) and end ($) of the string
            final_pattern = r'^' + pattern_str + r'$'
        elif is_substring:
            final_pattern = pattern_str
        else:
            final_pattern = r'(?<!\w)' + pattern_str + r'(?!\w)'
            
        compiled_regex = re.compile(final_pattern, re.IGNORECASE)
        self._compiled_regexes[cache_key] = compiled_regex
        return compiled_regex

    # MODIFIED: This function now checks for the new 'exact_any_of' condition
    def get_market_override(self, description):
        if not isinstance(description, str) or not self.override_rules:
            return None
        
        for rule in self.override_rules:
            # Check 'none_of' first to quickly reject a rule
            if 'none_of' in rule:
                expanded_none_of = [kw for alias in rule['none_of'] for kw in self.aliases.get(alias, [alias])]
                if any(self._get_regex(kw).search(description) for kw in expanded_none_of):
                    continue

            # --- Condition Checks ---
            # Set a flag to ensure at least one positive condition was met
            condition_found = False

            # All_of must be true if it exists
            if 'all_of' in rule:
                condition_found = True
                all_conditions_met = True
                for condition in rule['all_of']:
                    if condition in self.aliases:
                        if not any(self._get_regex(kw).search(description) for kw in self.aliases[condition]):
                            all_conditions_met = False
                            break
                    else:
                        if not self._get_regex(condition).search(description):
                            all_conditions_met = False
                            break
                if not all_conditions_met:
                    continue

            # Any_of must be true if it exists
            if 'any_of' in rule:
                condition_found = True
                expanded_any_of = [kw for alias in rule['any_of'] for kw in self.aliases.get(alias, [alias])]
                if not any(self._get_regex(kw).search(description) for kw in expanded_any_of):
                    continue
            
            # New: Exact_any_of must be true if it exists
            if 'exact_any_of' in rule:
                condition_found = True
                expanded_exact_any = [kw for alias in rule['exact_any_of'] for kw in self.aliases.get(alias, [alias])]
                if not any(self._get_regex(kw, exact_match=True).search(description) for kw in expanded_exact_any):
                    continue

            # If any positive condition was found and not vetoed, return the rule name
            if condition_found:
                 return rule['name']

        return None

    def validate_prediction(self, prediction, description):
        # This function remains unchanged
        if not prediction or not isinstance(prediction, str):
            return prediction
            
        pred_lower = prediction.lower()

        for rule in self.hierarchical_veto_rules:
            prefix = rule.get('prefix', '').lower()
            if pred_lower.startswith(prefix):
                specific_item = pred_lower.removeprefix(prefix)
                
                if specific_item in description.lower():
                    return prediction
                
                abbreviations = rule.get('abbreviations', {})
                if specific_item in abbreviations:
                    for abbrev in abbreviations[specific_item]:
                        if abbrev.lower() in description.lower():
                            return prediction
                
                return None

        if pred_lower in self.veto_rules:
            rule_conditions = self.veto_rules[pred_lower]
            if 'any_of' in rule_conditions:
                expanded_any_of = [kw for alias in rule_conditions['any_of'] for kw in self.aliases.get(alias, [alias])]
                if not any(self._get_regex(kw).search(description) for kw in expanded_any_of):
                    return None

        return prediction