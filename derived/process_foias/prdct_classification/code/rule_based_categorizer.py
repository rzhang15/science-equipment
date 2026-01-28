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

            # NEW: Auto-wildcard restriction enzymes to handle underscores
            if '$RESTRICTION_ENZYME' in self.aliases:
                self.aliases['$RESTRICTION_ENZYME'] = [
                    f"*{e}*" if not (e.startswith('*') and e.endswith('*')) else e 
                    for e in self.aliases['$RESTRICTION_ENZYME']
                ]
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

    def _get_regex(self, keyword, exact_match=False, ignore_case=True):
        # Cache key must include ignore_case to support the case_sensitive toggle
        cache_key = (keyword, exact_match, ignore_case)
        if cache_key in self._compiled_regexes:
            return self._compiled_regexes[cache_key]
        
        is_substring = keyword.startswith('*') and keyword.endswith('*')
        cleaned_keyword = keyword.strip('*')
        
        parts = [re.escape(part) for part in cleaned_keyword.split()]
        pattern_str = r'[\s-]?'.join(parts)
        
        if exact_match:
            final_pattern = r'^' + pattern_str + r'$'
        elif is_substring:
            # Substring mode: Matches inside strings like "F_SacI"
            final_pattern = pattern_str
        else:
            # Standard mode: Uses word boundaries
            final_pattern = r'(?<!\w)' + pattern_str + r'(?!\w)'
            
        flags = re.IGNORECASE if ignore_case else 0
        compiled_regex = re.compile(final_pattern, flags)
        self._compiled_regexes[cache_key] = compiled_regex
        return compiled_regex

    def get_market_override(self, clean_description, raw_description=None):
        if not isinstance(clean_description, str) or not self.override_rules:
            return None
        
        for rule in self.override_rules:
            # Toggle source text and case-sensitivity based on the rule flag
            case_sensitive = rule.get('case_sensitive', False)
            text_to_search = raw_description if (case_sensitive and raw_description) else clean_description
            ignore_case = not case_sensitive

            # 1. Check 'none_of' (Veto)
            if 'none_of' in rule:
                expanded_none_of = [kw for alias in rule['none_of'] for kw in self.aliases.get(alias, [alias])]
                if any(self._get_regex(kw, ignore_case=ignore_case).search(text_to_search) for kw in expanded_none_of):
                    continue

            # 2. All_of check (Requirement)
            if 'all_of' in rule:
                all_conditions_met = True
                for condition in rule['all_of']:
                    keywords = self.aliases.get(condition, [condition])
                    if not any(self._get_regex(kw, ignore_case=ignore_case).search(text_to_search) for kw in keywords):
                        all_conditions_met = False
                        break
                if not all_conditions_met:
                    continue
                # If all_of is the only condition and it's met, we can return
                if 'any_of' not in rule and 'exact_any_of' not in rule:
                    return rule['name']

            # 3. Any_of check (Match anywhere)
            if 'any_of' in rule:
                expanded = [kw for alias in rule['any_of'] for kw in self.aliases.get(alias, [alias])]
                if any(self._get_regex(kw, ignore_case=ignore_case).search(text_to_search) for kw in expanded):
                    return rule['name']

            # 4. Exact_any_of check (Must match full string)
            if 'exact_any_of' in rule:
                expanded_exact_any = [kw for alias in rule['exact_any_of'] for kw in self.aliases.get(alias, [alias])]
                if any(self._get_regex(kw, exact_match=True, ignore_case=ignore_case).search(text_to_search) for kw in expanded_exact_any):
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