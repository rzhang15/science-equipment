# rule_based_categorizer.py
"""
A simple, pattern-based categorizer that applies a set of hard-coded rules
from a YAML file to override or assign a market category.
This version supports keyword_groups, flexible keyword matching (handling spaces,
hyphens, and no-space variations), and any_of/all_of/none_of logic.
It also supports both whole-word and substring matching via asterisk syntax.
"""
import yaml
import re

class RuleBasedCategorizer:
    def __init__(self, rules_filepath):
        """
        Initializes the categorizer by loading and parsing the market rules YAML file.
        """
        print("ℹ️ Initializing RuleBasedCategorizer...")
        try:
            with open(rules_filepath, 'r') as f:
                raw_rules = yaml.safe_load(f)
            
            self.aliases = self._parse_aliases(raw_rules.get('keyword_groups', {}))
            self.rules = self._parse_rules(raw_rules.get('market_rules', []))
            
            print(f"  ✅ Loaded {len(self.rules)} market rules.")
        except FileNotFoundError:
            print(f"⚠️ Market rules file not found at: {rules_filepath}")
            self.rules = []
        except Exception as e:
            print(f"❌ Error parsing market rules file: {e}")
            self.rules = []

    def _parse_aliases(self, alias_config):
        """Converts the keyword_group config into a simple dictionary."""
        return {f"${key}": value for key, value in alias_config.items()}

    def _expand_keywords(self, keyword_list):
        """Expands a list of keywords, replacing any aliases with their values."""
        expanded = []
        for keyword in keyword_list:
            if keyword in self.aliases:
                expanded.extend(self.aliases[keyword])
            else:
                expanded.append(keyword)
        return expanded

    def _create_flexible_regex(self, keyword):
        """
        Converts a keyword string into a flexible regex, respecting substring syntax.
        "hf" -> regex for "\bhf\b" (whole word)
        "*hotstart*" -> regex for "hotstart" (substring)
        """
        use_word_boundaries = True
        if keyword.startswith('*') and keyword.endswith('*'):
            use_word_boundaries = False
            keyword = keyword.strip('*')

        parts = [re.escape(part) for part in keyword.split()]
        regex_str = r'[\s-]?'.join(parts)
        
        if use_word_boundaries:
            return re.compile(r'\b' + regex_str + r'\b', re.IGNORECASE)
        else:
            return re.compile(regex_str, re.IGNORECASE)

    def _parse_rules(self, rule_config):
        """Parses rules and converts keywords into flexible regex objects."""
        parsed_rules = []
        for rule in rule_config:
            parsed_rule = {'name': rule['name']}
            if 'all_of' in rule:
                keywords = self._expand_keywords(rule['all_of'])
                parsed_rule['all_of'] = [self._create_flexible_regex(kw) for kw in keywords]
            if 'any_of' in rule:
                keywords = self._expand_keywords(rule['any_of'])
                parsed_rule['any_of'] = [self._create_flexible_regex(kw) for kw in keywords]
            if 'none_of' in rule:
                keywords = self._expand_keywords(rule['none_of'])
                parsed_rule['none_of'] = [self._create_flexible_regex(kw) for kw in keywords]
            parsed_rules.append(parsed_rule)
        return parsed_rules

    def get_market_override(self, description):
        """
        Checks a product description against all compiled regex rules.
        """
        if not isinstance(description, str) or not self.rules:
            return None

        desc_lower = description.lower()
        
        for rule in self.rules:
            if 'none_of' in rule and any(regex.search(desc_lower) for regex in rule['none_of']):
                continue

            if 'all_of' in rule and not all(regex.search(desc_lower) for regex in rule['all_of']):
                continue

            if 'any_of' in rule and not any(regex.search(desc_lower) for regex in rule['any_of']):
                continue
            
            return rule['name']

        return None

