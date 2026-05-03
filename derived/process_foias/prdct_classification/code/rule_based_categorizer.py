# rule_based_categorizer.py (UPGRADED LOGIC V3)
"""
A pattern-based categorizer that applies three types of rules from a YAML file.
This version has corrected logic to handle nested conditions and a more robust
regex builder, now with support for exact-string matching.
"""
import warnings
import yaml
import re
import numpy as np
import pandas as pd

warnings.filterwarnings(
    "ignore",
    message="This pattern is interpreted as a regular expression, and has match groups",
    category=UserWarning,
)

class RuleBasedCategorizer:
    def __init__(self, rules_filepath):
        print("Initializing RuleBasedCategorizer with upgraded logic...")
        try:
            with open(rules_filepath, 'r') as f:
                raw_rules = yaml.safe_load(f)
            self.aliases = {f"${k}": v for k, v in raw_rules.get('keyword_groups', {}).items()}

            # Enzyme aliases used to be auto-wrapped in `*...*` here.  That
            # made a bare "BamHI" match inside unrelated tokens like
            # "F_BamHI_primer" or "BamHI site", misclassifying synthetic DNA
            # oligos (which routinely carry restriction-site names in their
            # descriptions) as restriction enzymes.  Keeping enzyme names
            # word-bounded is the correct default; list any punctuation
            # variants (e.g. `Nb.BsmI`, `BsaI-HFv2`) explicitly in the YAML.
            self.override_rules = raw_rules.get('market_rules', [])
            self.veto_rules = raw_rules.get('required_keywords', {})
            self.hierarchical_veto_rules = raw_rules.get('hierarchical_veto_rules', [])

            self._compiled_regexes = {}
            self._compiled_raw_regexes = {}

            # Flexible-separator enzyme regex (same one the gatekeeper uses)
            # — applied as an IMPLICIT tail rule in get_market_overrides_batch
            # so "Spe I", "Spe-I", "Spe1", "HindIII-HF" all resolve to
            # `restriction enzymes` even if the YAML's case-sensitive enzyme
            # rule misses the spacing variant.  Uses raw_series when
            # available (enzyme names are case-distinctive).
            try:
                from classifier import build_enzyme_regex
                self._enzyme_regex = build_enzyme_regex(rules_filepath)
            except Exception as e:
                print(f"  - NOTE: enzyme regex unavailable ({e}); "
                      f"implicit enzyme fallback disabled")
                self._enzyme_regex = None

            print(f"  - Loaded {len(self.override_rules)} market override rules.")
            print(f"  - Loaded {len(self.veto_rules)} exact-match veto rules.")
            print(f"  - Loaded {len(self.hierarchical_veto_rules)} hierarchical veto rules.")

            self._precompile_override_rules()

        except Exception as e:
            print(f"ERROR:Error parsing market rules file: {e}")
            self.override_rules, self.veto_rules, self.hierarchical_veto_rules = [], {}, []
            self._enzyme_regex = None
            self._rule_compiled = []
            self._tube_vial_cat_re = re.compile(r'(?:tube|vial)', re.IGNORECASE)
            self._tube_vial_accessory_re = re.compile(
                r'\b(?:rack|racks|plate|plates|plt|dish|dishes|dsh|'
                r'tray|trays|box|boxes|holder|holders)\b',
                re.IGNORECASE,
            )

    def _precompile_override_rules(self):
        """Precompile each override rule's combined regexes once so
        get_market_overrides_batch doesn't rebuild them on every call.
        Mirrors the clause logic of the per-row get_market_override exactly
        (none_of / regex_none_of / all_of / any_of / regex_any_of /
        exact_any_of), just with the regex construction lifted out of the
        hot loop.
        """
        self._rule_compiled = []
        for rule in self.override_rules:
            case_sensitive = rule.get('case_sensitive', False)
            ignore_case = not case_sensitive
            comp = {
                'name': rule['name'],
                'case_sensitive': case_sensitive,
                'none_of': None,
                'regex_none_of': None,
                'all_of': None,
                'any_of': None,
                'regex_any_of': None,
                'exact_any_of': None,
            }
            if 'none_of' in rule:
                comp['none_of'] = self._combine_keywords_regex(
                    self._expand_aliases(rule['none_of']),
                    ignore_case=ignore_case)
            if 'regex_none_of' in rule:
                comp['regex_none_of'] = self._combine_raw_regex(
                    rule['regex_none_of'], ignore_case=ignore_case)
            if 'all_of' in rule:
                conds = []
                for condition in rule['all_of']:
                    keywords = self.aliases.get(condition, [condition])
                    conds.append(self._combine_keywords_regex(
                        keywords, ignore_case=ignore_case))
                comp['all_of'] = conds  # entries may be None -> abort signal
            if 'any_of' in rule:
                comp['any_of'] = self._combine_keywords_regex(
                    self._expand_aliases(rule['any_of']),
                    ignore_case=ignore_case)
            if 'regex_any_of' in rule:
                comp['regex_any_of'] = self._combine_raw_regex(
                    rule['regex_any_of'], ignore_case=ignore_case)
            if 'exact_any_of' in rule:
                comp['exact_any_of'] = self._combine_keywords_regex(
                    self._expand_aliases(rule['exact_any_of']),
                    exact_match=True, ignore_case=ignore_case)
            self._rule_compiled.append(comp)

        # Tube/vial sibling guard regexes -- precompile once instead of on
        # every batch call.
        self._tube_vial_cat_re = re.compile(r'(?:tube|vial)', re.IGNORECASE)
        self._tube_vial_accessory_re = re.compile(
            r'\b(?:rack|racks|plate|plates|plt|dish|dishes|dsh|'
            r'tray|trays|box|boxes|holder|holders)\b',
            re.IGNORECASE,
        )

    def _build_pattern_string(self, keyword, exact_match=False):
        """Translate a wildcard/plain keyword into its raw regex pattern
        string (without flags / anchors).  Shared between the per-keyword
        `_get_regex` path and the batch keyword-combiner below.
        """
        # YAML auto-casts unquoted numeric entries (e.g. Cytiva SKUs like
        # `17104301`) to int/float.  Coerce here so the pattern builder
        # tolerates them without forcing every YAML author to remember to
        # quote numeric keywords.
        if not isinstance(keyword, str):
            keyword = str(keyword)
        is_substring = keyword.startswith('*') and keyword.endswith('*')
        cleaned_keyword = keyword.strip('*')

        segments = cleaned_keyword.split('*')
        segment_patterns = []
        for segment in segments:
            parts = [re.escape(part) for part in segment.split()]
            segment_patterns.append(r'[\s-]?'.join(parts))
        pattern_str = r'.*'.join(segment_patterns)

        if exact_match:
            return r'^' + pattern_str + r'$'
        if is_substring:
            return pattern_str
        return r'(?<!\w)' + pattern_str + r'(?!\w)'

    def _get_regex(self, keyword, exact_match=False, ignore_case=True):
        cache_key = (keyword, exact_match, ignore_case)
        if cache_key in self._compiled_regexes:
            return self._compiled_regexes[cache_key]
        flags = re.IGNORECASE if ignore_case else 0
        compiled_regex = re.compile(self._build_pattern_string(keyword, exact_match), flags)
        self._compiled_regexes[cache_key] = compiled_regex
        return compiled_regex

    def _combine_keywords_regex(self, keywords, exact_match=False, ignore_case=True):
        """Combine a list of wildcard/plain keywords into one alternation
        regex so a rule's entire clause can be evaluated with a single
        `Series.str.contains` call.  Returns None if the list is empty."""
        if not keywords:
            return None
        parts = ['(?:' + self._build_pattern_string(kw, exact_match) + ')'
                 for kw in keywords]
        flags = re.IGNORECASE if ignore_case else 0
        return re.compile('|'.join(parts), flags)

    def _combine_raw_regex(self, patterns, ignore_case=True):
        """Combine a list of raw regex patterns (regex_any_of / regex_none_of)
        into one alternation regex.  Returns None if the list is empty."""
        if not patterns:
            return None
        flags = re.IGNORECASE if ignore_case else 0
        return re.compile('|'.join(f'(?:{p})' for p in patterns), flags)

    def _get_raw_regex(self, pattern, ignore_case=True):
        """Compile & cache a raw-regex keyword (used by regex_any_of /
        regex_none_of).  Unlike _get_regex, the pattern string is treated as
        a real regex — no escaping, no wildcard translation, no automatic
        word boundaries.  Caller is responsible for anchors."""
        cache_key = (pattern, ignore_case)
        hit = self._compiled_raw_regexes.get(cache_key)
        if hit is not None:
            return hit
        flags = re.IGNORECASE if ignore_case else 0
        compiled = re.compile(pattern, flags)
        self._compiled_raw_regexes[cache_key] = compiled
        return compiled

    def get_market_override(self, clean_description, raw_description=None):
        if not isinstance(clean_description, str) or not self.override_rules:
            return None

        for rule in self.override_rules:
            # Toggle source text and case-sensitivity based on the rule flag
            case_sensitive = rule.get('case_sensitive', False)
            text_to_search = raw_description if (case_sensitive and raw_description) else clean_description
            ignore_case = not case_sensitive

            # 1. Check 'none_of' (Veto, fixed-string keywords)
            if 'none_of' in rule:
                expanded_none_of = [kw for alias in rule['none_of'] for kw in self.aliases.get(alias, [alias])]
                if any(self._get_regex(kw, ignore_case=ignore_case).search(text_to_search) for kw in expanded_none_of):
                    continue

            # 1b. Check 'regex_none_of' (Veto, raw regex)
            if 'regex_none_of' in rule:
                if any(self._get_raw_regex(p, ignore_case=ignore_case).search(text_to_search)
                       for p in rule['regex_none_of']):
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
                if 'any_of' not in rule and 'exact_any_of' not in rule and 'regex_any_of' not in rule:
                    return rule['name']

            # 3. Any_of check (Match anywhere)
            if 'any_of' in rule:
                expanded = [kw for alias in rule['any_of'] for kw in self.aliases.get(alias, [alias])]
                if any(self._get_regex(kw, ignore_case=ignore_case).search(text_to_search) for kw in expanded):
                    return rule['name']

            # 3b. Regex_any_of check (raw-regex match, unescaped).  Lets rules
            # express structural primer / oligo patterns (e.g. _F/_R token
            # suffixes) that bare substring matches can't capture without
            # massive false positives.
            if 'regex_any_of' in rule:
                if any(self._get_raw_regex(p, ignore_case=ignore_case).search(text_to_search)
                       for p in rule['regex_any_of']):
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
            # Veto if description is missing ALL required keywords
            if 'any_of' in rule_conditions:
                expanded_any_of = [kw for alias in rule_conditions['any_of'] for kw in self.aliases.get(alias, [alias])]
                if not any(self._get_regex(kw).search(description) for kw in expanded_any_of):
                    return None
            # Veto if description is missing ANY of the required keyword groups
            if 'all_of' in rule_conditions:
                for condition in rule_conditions['all_of']:
                    keywords = self.aliases.get(condition, [condition])
                    if not any(self._get_regex(kw).search(description) for kw in keywords):
                        return None
            # Veto if description contains ANY excluded keyword
            if 'none_of' in rule_conditions:
                expanded_none_of = [kw for alias in rule_conditions['none_of'] for kw in self.aliases.get(alias, [alias])]
                if any(self._get_regex(kw).search(description) for kw in expanded_none_of):
                    return None

        return prediction

    # ------------------------------------------------------------------
    # Batch / vectorized paths.  Replace per-row Python loops with a few
    # pandas `str.contains` calls per rule -- each rule's keyword clause is
    # combined into a single alternation regex and evaluated against the
    # whole Series at once.  First-match-wins semantics are preserved by
    # marking rows unassigned after each rule fires.
    # ------------------------------------------------------------------

    def _expand_aliases(self, clause):
        """Return a flat list of keywords after expanding alias references
        ($NAME -> keyword_groups[NAME])."""
        return [kw for alias in clause for kw in self.aliases.get(alias, [alias])]

    def get_market_overrides_batch(self, clean_series, raw_series=None):
        """Vectorized equivalent of iterating `get_market_override` over a
        Series.  Returns a pd.Series of override names (or None) aligned
        with clean_series.index.  Preserves first-match-wins semantics and
        all clause logic of the per-row path.

        Perf notes:
        - Per-rule regexes are precompiled at init (`_rule_compiled`) so
          the hot loop does one `str.contains` per clause, no `re.compile`.
        - The still-unassigned set is a numpy bool mask (`still_open`) with
          O(1) updates, instead of a pandas Index rebuilt with .difference
          after every match (that was O(N) * 786 rules).
        - Each rule evaluates only on the still-unassigned slice; early
          rules claim most rows so later rules run on a much shorter array.
        - Tube/vial sibling guard is vectorized (single str.contains pass
          over assigned category names, no per-row apply(lambda)).
        """
        n = len(clean_series)
        out_index = clean_series.index
        if not self._rule_compiled or n == 0:
            return pd.Series([None] * n, index=out_index, dtype='object')

        # Underlying string arrays -- we do pandas str.contains on freshly
        # sliced views of these, but track the unassigned set with a numpy
        # bool mask so we don't pay Index.difference on every rule.
        clean_arr = clean_series.astype(str).to_numpy()
        raw_arr = (raw_series.astype(str).to_numpy()
                   if raw_series is not None else None)

        overrides_np = np.full(n, None, dtype=object)
        still_open = np.ones(n, dtype=bool)

        for comp in self._rule_compiled:
            if not still_open.any():
                break

            src_arr = (raw_arr if (comp['case_sensitive'] and raw_arr is not None)
                       else clean_arr)

            sub_pos = np.flatnonzero(still_open)
            sub_text = pd.Series(src_arr[sub_pos])

            survivors = np.ones(len(sub_pos), dtype=bool)

            # none_of / regex_none_of exclusions
            rgx = comp['none_of']
            if rgx is not None:
                survivors &= ~sub_text.str.contains(rgx, na=False).to_numpy()
                if not survivors.any():
                    continue
            rgx = comp['regex_none_of']
            if rgx is not None:
                survivors &= ~sub_text.str.contains(rgx, na=False).to_numpy()
                if not survivors.any():
                    continue

            # all_of: each condition must match >=1 keyword.  A None entry
            # means the condition resolved to an empty keyword list at init
            # time -- preserve original abort-on-None semantics.
            if comp['all_of'] is not None:
                aborted = False
                for rgx in comp['all_of']:
                    if rgx is None:
                        aborted = True
                        break
                    survivors &= sub_text.str.contains(rgx, na=False).to_numpy()
                    if not survivors.any():
                        aborted = True
                        break
                if aborted:
                    continue

            # any_of / regex_any_of / exact_any_of -- union, at least one
            # required for the rule to fire.
            any_rgx = comp['any_of']
            rxany_rgx = comp['regex_any_of']
            exact_rgx = comp['exact_any_of']
            has_any_clause = (any_rgx is not None
                              or rxany_rgx is not None
                              or exact_rgx is not None)
            if has_any_clause:
                any_mask = np.zeros(len(sub_pos), dtype=bool)
                if any_rgx is not None:
                    any_mask |= sub_text.str.contains(any_rgx, na=False).to_numpy()
                if rxany_rgx is not None:
                    any_mask |= sub_text.str.contains(rxany_rgx, na=False).to_numpy()
                if exact_rgx is not None:
                    any_mask |= sub_text.str.contains(exact_rgx, na=False).to_numpy()
                survivors &= any_mask
            elif comp['all_of'] is None:
                # No positive clause -- rule cannot fire.
                continue

            if not survivors.any():
                continue

            matched_pos = sub_pos[survivors]
            overrides_np[matched_pos] = comp['name']
            still_open[matched_pos] = False

        # --- Implicit enzyme-regex fallback --------------------------------
        # The YAML `restriction enzymes` rules are case-sensitive, word-
        # bounded substring matches.  They miss spaced / hyphenated / Arabic-
        # numeral variants ("Spe I", "Spe-I", "Spe1").  Run the shared
        # flexible-separator regex on any rows still unassigned after the
        # YAML pass.  Matches the raw description when available (case-
        # distinctive); clean array is used otherwise.
        if self._enzyme_regex is not None and still_open.any():
            src_arr = raw_arr if raw_arr is not None else clean_arr
            sub_pos = np.flatnonzero(still_open)
            tail = pd.Series(src_arr[sub_pos])
            enzyme_hits = tail.str.contains(self._enzyme_regex, na=False).to_numpy()
            if enzyme_hits.any():
                overrides_np[sub_pos[enzyme_hits]] = 'restriction enzymes'

        # --- Tube / vial sibling guard (fully vectorized) ------------------
        # Applies to any rule that emitted a tube- or vial-named category.
        # If the description also contains rack / plate / dish / tray / box /
        # holder (likely a sibling accessory), clear the override so the row
        # falls through to the expert model.  Replaces the old
        # assigned.apply(lambda v: ...) with a single str.contains pass.
        assigned_mask = pd.notna(overrides_np)
        if assigned_mask.any():
            assigned_pos = np.flatnonzero(assigned_mask)
            assigned_names = pd.Series(overrides_np[assigned_pos])
            tv_mask = (assigned_names.str.contains(self._tube_vial_cat_re, na=False) &
                       ~assigned_names.str.startswith('animal')).to_numpy()
            if tv_mask.any():
                tv_pos = assigned_pos[tv_mask]
                tv_texts = pd.Series(clean_arr[tv_pos])
                has_accessory = tv_texts.str.contains(
                    self._tube_vial_accessory_re, na=False).to_numpy()
                if has_accessory.any():
                    overrides_np[tv_pos[has_accessory]] = None

        return pd.Series(overrides_np, index=out_index, dtype='object')

    def validate_predictions_batch(self, predictions, descriptions):
        """Vectorized equivalent of iterating `validate_prediction` over a
        Series.  Returns an object Series aligned with predictions.index;
        vetoed entries are None, others pass through unchanged.
        """
        predictions = pd.Series(predictions).copy()
        descriptions = pd.Series(descriptions).astype(str)
        if len(predictions) != len(descriptions):
            raise ValueError("predictions and descriptions length mismatch")

        result = predictions.astype(object).copy()

        preds_lower = predictions.fillna('').astype(str).str.lower()
        descs_lower = descriptions.str.lower()
        # Align descs_lower to predictions.index so .loc lookups work.
        descs_lower.index = predictions.index

        # Track rows that matched a hierarchical prefix so they skip the
        # flat-veto pass (mirrors the early `return` in the per-row path).
        hierarchical_hit = pd.Series(False, index=predictions.index)

        for rule in self.hierarchical_veto_rules:
            prefix = rule.get('prefix', '').lower()
            abbreviations = rule.get('abbreviations', {})
            mask = preds_lower.str.startswith(prefix) & ~hierarchical_hit
            if not mask.any():
                continue
            # Per-row substring check: cannot be vectorized with str.contains
            # because the needle varies per row.
            for idx in mask[mask].index:
                specific = preds_lower.loc[idx][len(prefix):]
                d = descs_lower.loc[idx]
                kept = bool(specific) and (specific in d)
                if not kept and specific in abbreviations:
                    for abbrev in abbreviations[specific]:
                        if abbrev and abbrev.lower() in d:
                            kept = True
                            break
                if not kept:
                    result.loc[idx] = None
            hierarchical_hit |= mask

        for pred_name, rule_conditions in self.veto_rules.items():
            mask = (preds_lower == pred_name) & ~hierarchical_hit
            if not mask.any():
                continue
            sub_descs = descriptions.loc[mask]
            keep = pd.Series(True, index=sub_descs.index)

            if 'any_of' in rule_conditions:
                rgx = self._combine_keywords_regex(
                    self._expand_aliases(rule_conditions['any_of']))
                keep &= sub_descs.str.contains(rgx, na=False) if rgx is not None else False
            if 'all_of' in rule_conditions:
                for condition in rule_conditions['all_of']:
                    keywords = self.aliases.get(condition, [condition])
                    rgx = self._combine_keywords_regex(keywords)
                    if rgx is None:
                        keep &= False
                        break
                    keep &= sub_descs.str.contains(rgx, na=False)
            if 'none_of' in rule_conditions:
                rgx = self._combine_keywords_regex(
                    self._expand_aliases(rule_conditions['none_of']))
                if rgx is not None:
                    keep &= ~sub_descs.str.contains(rgx, na=False)

            vetoed_idx = keep[~keep].index
            if len(vetoed_idx):
                result.loc[vetoed_idx] = None

        return result