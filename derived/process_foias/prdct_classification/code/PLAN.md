# Pipeline Fix Plan

## User Decisions
- **Matching method**: Aho-Corasick everywhere (change training to match inference)
- **Override scope**: Allow overrides to resurrect gatekeeper-rejected items (current behavior is intended)
- **Data leakage**: DEFER (rare categories could be lost in early split; leakage only affects hold-out metrics, not real-world inference)

---

## Step 1: Fix YAML bugs in `market_rules.yml`

Quick, high-impact fixes to silently broken rules:

- **Typo `all_Zall_of:`** → change to `all_of:` (crosslinking reagents / edc rule, ~line 1305)
- **Typo `non_of:`** → change to `none_of:` AND make it a list (tris base rule, ~line 1345)
- **Bare string `all_of: "antibody"`** → change to `all_of: ["antibody"]` (~line 399, polyclonal primary antibody rule)
- **Bare string `all_of: "peptides"`** → change to `all_of: ["peptides"]` (~line 568, synthetic peptides rule)
- **"polyclonal secondary antibody" rule** (~line 396): currently only checks `["secondary", "antibody"]` — add `"polyclonal"` or a polyclonal-specific keyword to `any_of`, OR rename the market to just "secondary antibody" if that's more accurate

---

## Step 2: Fix matching method mismatch in `1_build_training_dataset.py`

**Problem**: Training uses regex `\b...\b` word-boundary matching. Inference uses Aho-Corasick substring matching. Items get different labels at train vs inference time.

**Changes to `1_build_training_dataset.py`**:
- Remove functions `load_keywords_and_build_regex()` and `has_exact_word_match()`
- Import from `classifier.py`: `load_keywords_and_build_automaton`, `extract_market_keywords_and_build_automaton`, `has_match`
- Replace seed keyword labeling (lines ~133-138): build automaton with `load_keywords_and_build_automaton`, apply with `has_match`
- Replace market rule keyword labeling (lines ~141-152): build automaton with `extract_market_keywords_and_build_automaton`, apply with `has_match`
- Replace anti-seed keyword labeling (lines ~155-160): build automaton with `load_keywords_and_build_automaton`, apply with `has_match`
- All three use the same Aho-Corasick matching that `classifier.py` uses at inference time

---

## Step 3: Fix prediction source tracking in `3_predict_product_markets.py`

**Problem**: Line 150 sets `prediction_source = 'Expert Model'` for ALL items the expert touched, including vetoed ones. Vetoed items end up with `predicted_market="Non-Lab"` but `prediction_source="Expert Model"` — misleading.

**Fix**:
- After computing `validated_predictions`, only set prediction_source for items that survived veto (where `validated_predictions.notna()`)
- Items that were vetoed keep their original `prediction_source = 'Non-Lab'`

---

## Step 4: Fix validation alignment in `5_validate_utdallas.py`

**Problem**: Predictions and ground truth are aligned by row position. If anything upstream reorders rows, validation is silently wrong.

**Fix**:
- Use a key-based merge on the UT Dallas merge keys (`supplier_id`, `sku`, `product_desc`, `supplier`) instead of positional alignment
- Load both the classified CSV and the ground-truth parquet, merge on keys, then compare

---

## Step 5: Parameterize vectorizer `min_df` in `config.py`

**Problem**: `1_build_training_dataset.py` uses `min_df=7` (from config) and `1b_create_text_embeddings.py` uses `min_df=5` (hardcoded). Confusing.

**Fix**:
- Add `GATEKEEPER_VECTORIZER_MIN_DF = 5` to `config.py`
- Update `1b_create_text_embeddings.py` to use `config.GATEKEEPER_VECTORIZER_MIN_DF`
- Rename existing `VECTORIZER_MIN_DF` to `CATEGORY_VECTORIZER_MIN_DF` for clarity

---

## Step 6: Add deduplication logging in `1_build_training_dataset.py`

**Problem**: `drop_duplicates(keep='first')` silently resolves label conflicts in favor of UT Dallas (first in concatenation order).

**Fix**:
- Before deduplication, identify duplicated descriptions with conflicting labels across sources
- Log the count and a sample of conflicts
- Keep `keep='first'` behavior (UT Dallas priority is reasonable since it has ground-truth categories)

---

## Step 7: Clean up `initial_seed.yml`

Remove duplicate keywords:
- "tip bulk" (lines 14 and 43)
- "accutase" (lines 114 and 248)
- "percoll" (lines 142 and 156)
- "digitonin" (lines 416 and 480)

---

## Files Modified (summary)

| File | Steps | Nature of Change |
|------|-------|-----------------|
| `market_rules.yml` | 1 | Fix typos and bare-string bugs |
| `1_build_training_dataset.py` | 2, 6 | Replace regex with Aho-Corasick; add dedup logging |
| `3_predict_product_markets.py` | 3 | Fix prediction_source for vetoed items |
| `5_validate_utdallas.py` | 4 | Key-based merge instead of positional alignment |
| `config.py` | 5 | Rename/add vectorizer min_df constants |
| `1b_create_text_embeddings.py` | 5 | Use config constant for min_df |
| `initial_seed.yml` | 7 | Remove duplicate keywords |

## Re-run Order After Fixes
After all changes: re-run steps 1 → 1b → 1c → 2 → 3 → 5 (full pipeline rebuild)
