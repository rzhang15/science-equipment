# rule_based_categorizer.py (UPGRADED LOGIC V3)
"""
A pattern-based categorizer that applies three types of rules from a YAML file.
This version has corrected logic to handle nested conditions and a more robust
regex builder, now with support for exact-string matching.
"""
import yaml
import re
import pandas as pd

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

        except Exception as e:
            print(f"ERROR:Error parsing market rules file: {e}")
            self.override_rules, self.veto_rules, self.hierarchical_veto_rules = [], {}, []
            self._enzyme_regex = None

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

        Key perf trick: each rule only evaluates against rows that haven't
        been assigned a category yet.  Early rules (shipping / freight,
        high-priority oligo patterns) claim most rows; later rules run on a
        much shrunken Series, which is what makes the batch beat the per-row
        loop despite evaluating whole-Series regex calls.
        """
        if not self.override_rules:
            return pd.Series([None] * len(clean_series),
                             index=clean_series.index, dtype='object')

        clean_series = clean_series.astype(str)
        if raw_series is not None:
            raw_series = raw_series.astype(str)

        overrides = pd.Series([None] * len(clean_series),
                              index=clean_series.index, dtype='object')
        # Track unassigned rows as an Index for O(k) shrinking each rule.
        unassigned_idx = clean_series.index

        for rule in self.override_rules:
            if len(unassigned_idx) == 0:
                break

            case_sensitive = rule.get('case_sensitive', False)
            src = (raw_series if (case_sensitive and raw_series is not None)
                   else clean_series)
            ignore_case = not case_sensitive

            # Run all str.contains calls against ONLY the still-unassigned
            # slice -- this is what makes the batch version scale.
            text = src.loc[unassigned_idx]
            survivors = pd.Series(True, index=unassigned_idx)

            # none_of exclusions
            if 'none_of' in rule:
                rgx = self._combine_keywords_regex(
                    self._expand_aliases(rule['none_of']), ignore_case=ignore_case)
                if rgx is not None:
                    survivors &= ~text.str.contains(rgx, na=False)
                    if not survivors.any():
                        continue
            if 'regex_none_of' in rule:
                rgx = self._combine_raw_regex(rule['regex_none_of'], ignore_case=ignore_case)
                if rgx is not None:
                    survivors &= ~text.str.contains(rgx, na=False)
                    if not survivors.any():
                        continue

            # all_of: each condition must have >=1 matching keyword
            if 'all_of' in rule:
                aborted = False
                for condition in rule['all_of']:
                    keywords = self.aliases.get(condition, [condition])
                    rgx = self._combine_keywords_regex(keywords, ignore_case=ignore_case)
                    if rgx is None:
                        aborted = True
                        break
                    survivors &= text.str.contains(rgx, na=False)
                    if not survivors.any():
                        aborted = True
                        break
                if aborted or not survivors.any():
                    continue

            # any_of / regex_any_of / exact_any_of -- union, at least one
            # required for the rule to fire.
            has_any_clause = any(k in rule for k in ('any_of', 'regex_any_of', 'exact_any_of'))
            if has_any_clause:
                any_mask = pd.Series(False, index=unassigned_idx)
                if 'any_of' in rule:
                    rgx = self._combine_keywords_regex(
                        self._expand_aliases(rule['any_of']), ignore_case=ignore_case)
                    if rgx is not None:
                        any_mask |= text.str.contains(rgx, na=False)
                if 'regex_any_of' in rule:
                    rgx = self._combine_raw_regex(rule['regex_any_of'], ignore_case=ignore_case)
                    if rgx is not None:
                        any_mask |= text.str.contains(rgx, na=False)
                if 'exact_any_of' in rule:
                    rgx = self._combine_keywords_regex(
                        self._expand_aliases(rule['exact_any_of']),
                        exact_match=True, ignore_case=ignore_case)
                    if rgx is not None:
                        any_mask |= text.str.contains(rgx, na=False)
                survivors &= any_mask
            elif 'all_of' not in rule:
                # No positive clause -- rule cannot fire.
                continue

            if not survivors.any():
                continue

            matched_idx = survivors[survivors].index
            overrides.loc[matched_idx] = rule['name']
            unassigned_idx = unassigned_idx.difference(matched_idx)

        # --- Implicit enzyme-regex fallback --------------------------------
        # The YAML `restriction enzymes` rules are case-sensitive, word-
        # bounded substring matches.  They miss spaced / hyphenated / Arabic-
        # numeral variants ("Spe I", "Spe-I", "Spe1").  Run the shared
        # flexible-separator regex on any rows still unassigned after the
        # YAML pass.  Matches the raw description when available (case-
        # distinctive); clean_series is used otherwise.
        if self._enzyme_regex is not None and len(unassigned_idx) > 0:
            src = raw_series if raw_series is not None else clean_series
            tail = src.loc[unassigned_idx]
            enzyme_hits = tail.str.contains(self._enzyme_regex, na=False)
            if enzyme_hits.any():
                hit_idx = enzyme_hits[enzyme_hits].index
                overrides.loc[hit_idx] = 'restriction enzymes'

        # --- Tube / vial sibling guard -------------------------------------
        # Applies to ANY rule that emitted a tube- or vial-named category.
        # If the description also contains rack / plate / dish / tray / box /
        # holder (likely a sibling accessory), clear the override so the
        # row falls through to the expert model (which can disambiguate
        # between e.g. `microcentrifuge tubes` and `microtube racks`).
        # Cheaper than adding none_of guards to 40+ individual tube rules,
        # and automatically extends to future tube/vial rules.
        tube_vial_cat_re = re.compile(r'(?:tube|vial)', re.IGNORECASE)
        accessory_re = re.compile(
            r'\b(?:rack|racks|plate|plates|plt|dish|dishes|dsh|'
            r'tray|trays|box|boxes|holder|holders)\b',
            re.IGNORECASE,
        )
        # Build mask of assigned rows with a tube/vial category name
        assigned = overrides.dropna()
        if len(assigned) > 0:
            tv_mask = assigned.apply(
                lambda v: bool(tube_vial_cat_re.search(str(v)))
            )
            tv_idx = tv_mask[tv_mask].index
            if len(tv_idx) > 0:
                texts = clean_series.loc[tv_idx]
                has_accessory = texts.str.contains(accessory_re, na=False)
                clear_idx = has_accessory[has_accessory].index
                if len(clear_idx) > 0:
                    overrides.loc[clear_idx] = None

        return overrides

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