# 3_predict_product_markets.py (UPDATED with Similarity Score)
"""
Uses a flexibly chosen pipeline to predict product markets for various data sources.
Applies a gatekeeper, a chosen expert model, prediction veto rules, and final override rules.
Includes prediction source and final similarity score in the output.
"""
import pandas as pd
import glob
import os
import re
import joblib
import argparse
import multiprocessing as mp
from scipy import sparse
from sklearn.preprocessing import normalize
import numpy as np # Added for NaN

import config
from rule_based_categorizer import RuleBasedCategorizer
from categorize_items import TfidfItemCategorizer, EmbeddingItemCategorizer


# ---------------------------------------------------------------------------
# Multiprocessing helpers for step 4 (market override rules).
#
# The rule evaluation is embarrassingly parallel by row, and the single-core
# cost (~1us/rule/row x 793 rules) dominates runtime on the 11M-obs job.
# Workers each hold their own RuleBasedCategorizer so the 793 precompiled
# rule regexes exist once per process.
# ---------------------------------------------------------------------------
_WORKER_CATEGORIZER = None


def _init_override_worker(rules_path):
    """Pool initializer: build the per-worker categorizer ONCE so every
    task in the chunk doesn't reload the YAML + recompile regexes."""
    global _WORKER_CATEGORIZER
    _WORKER_CATEGORIZER = RuleBasedCategorizer(rules_path)


def _apply_overrides_chunk(args):
    clean_chunk, raw_chunk = args
    return _WORKER_CATEGORIZER.get_market_overrides_batch(
        clean_chunk, raw_chunk
    )


def _default_override_workers():
    """Honor MARKET_RULES_WORKERS first, then the Slurm allocation, then
    the process's CPU affinity (respects cgroups).  Falls back to a capped
    os.cpu_count() only when none of the above are available."""
    for var in ('MARKET_RULES_WORKERS', 'SLURM_CPUS_PER_TASK'):
        v = os.environ.get(var)
        if v:
            try:
                return max(1, int(v))
            except ValueError:
                pass
    try:
        return max(1, len(os.sched_getaffinity(0)))
    except (AttributeError, OSError):
        return min(os.cpu_count() or 1, 16)

def main(gatekeeper_name: str, expert_choice: str, source_abbrev: str = None):
    print(f"--- Starting Prediction Pipeline [Variant: {config.VARIANT}] ---")
    print(f"  - Gatekeeper Model:    {gatekeeper_name}")
    print(f"  - Expert Model Choice:   {expert_choice}")
    print(f"  - Data Source:         {source_abbrev or 'All Universities/GovSpend'}")

    # 1. Load all models and categorizers
    print("\nLoading necessary models and categorizers...")
    try:
        gatekeeper_model = joblib.load(os.path.join(config.OUTPUT_DIR, f"hybrid_classifier_{gatekeeper_name}.joblib"))

        # --- Load the appropriate expert predictor and tools for similarity ---
        if expert_choice == 'tfidf':
            expert_predictor = TfidfItemCategorizer()
            vectorizer_for_similarity = expert_predictor.vectorizer
            # Keep sparse — fancy-indexing this into dense blows up memory
            # (N_items x N_tfidf_features). sparse indexing, normalize, and the
            # multiply+sum path below all handle sparse natively.
            category_vectors_for_similarity = expert_predictor.category_vectors.tocsr()
            category_names_map = {name: i for i, name in enumerate(expert_predictor.category_names)}
        elif expert_choice in config.BERT_MODELS:
            expert_predictor = EmbeddingItemCategorizer(expert_choice, config.BERT_MODELS[expert_choice])
            vectorizer_for_similarity = expert_predictor.encoder_model
            category_vectors_for_similarity = expert_predictor.category_vectors
            category_names_map = {name: i for i, name in enumerate(expert_predictor.category_names)}
        else:
            raise ValueError(
                f"Unsupported expert choice: {expert_choice}. "
                f"Expected 'tfidf' or one of: {list(config.BERT_MODELS)}"
            )

        rule_categorizer = RuleBasedCategorizer(config.MARKET_RULES_YAML)

    except Exception as e:
        print(f"ERROR:A required model or file was not found: {e}. Please run previous scripts.")
        return

    # 2. Find and load input files
    dataframes_to_process = []
    source_lower = source_abbrev.lower() if source_abbrev else ''
    if 'utdallas' in source_lower:
        print(f"\nUT Dallas specified. Loading the pre-cleaned and merged file from script 0.")
        try:
            df_utd = pd.read_parquet(config.UT_DALLAS_MERGED_CLEAN_PATH)
            dataframes_to_process.append(('utdallas_merged_clean.parquet', df_utd))
        except FileNotFoundError:
            print(f"ERROR:Pre-merged UT Dallas file not found. Run 0_clean_category_file.py first.")
            return
    elif 'umich' in source_lower:
        print(f"\nUMich specified. Loading the pre-cleaned and merged file from script 0.")
        try:
            df_um = pd.read_parquet(config.UMICH_MERGED_CLEAN_PATH)
            dataframes_to_process.append(('umich_merged_clean.parquet', df_um))
        except FileNotFoundError:
            print(f"ERROR: Pre-merged UMich file not found. Run 0_clean_category_file.py first.")
            return
    elif 'govspend' in source_lower:
        print(f"\nGovSpend specified. Loading the GovSpend panel data.")
        try:
            df_gov = pd.read_csv(config.GOVSPEND_PANEL_CSV, low_memory=False)

            # Expect pre-cleaned data with clean_desc already present
            # (run clean_foia_data.py on govspend_panel.csv first)
            if config.CLEAN_DESC_COL in df_gov.columns:
                print(f"  - Found pre-cleaned '{config.CLEAN_DESC_COL}' column.")
            else:
                # Fallback: copy raw description if clean_desc is missing
                source_col_name = 'prdct_description' if 'prdct_description' in df_gov.columns else 'product_desc'
                if source_col_name not in df_gov.columns:
                    print(f"ERROR: Could not find description column in GovSpend file.")
                    return
                print(f"  - WARNING: '{config.CLEAN_DESC_COL}' not found. "
                      f"Using raw '{source_col_name}' -- run clean_foia_data.py first for best results.")
                df_gov[config.CLEAN_DESC_COL] = df_gov[source_col_name]

            # Ensure raw description column exists for market override rules
            if config.RAW_DESC_COL not in df_gov.columns:
                for candidate in ['prdct_description', 'product_desc']:
                    if candidate in df_gov.columns:
                        df_gov[config.RAW_DESC_COL] = df_gov[candidate]
                        break

            # GovSpend uses 'suppliername'; training/inference code expects 'supplier'.
            if 'supplier' not in df_gov.columns and 'suppliername' in df_gov.columns:
                df_gov['supplier'] = df_gov['suppliername']

            dataframes_to_process.append((os.path.basename(config.GOVSPEND_PANEL_CSV), df_gov))
        except FileNotFoundError:
            print(f"ERROR:GovSpend file not found at: {config.GOVSPEND_PANEL_CSV}")
            return
    else:
        # Load other university files
        search_pattern = os.path.join(config.FOIA_INPUT_DIR, f"{source_abbrev}*_standardized_clean.csv" if source_abbrev else "*_standardized_clean.csv")
        input_files = glob.glob(search_pattern)
        if not input_files:
            print(f"ERROR:No files found for pattern: {search_pattern}")
            return
        print(f"\nFound {len(input_files)} file(s) to process.")
        for file_path in input_files:
            try:
                df = pd.read_csv(file_path, low_memory=False)
                # --- Ensure the description column exists ---
                if config.CLEAN_DESC_COL not in df.columns:
                     # Attempt to find common alternatives if standard isn't present
                     alt_desc_cols = ['cleaned_description', 'Item Description']
                     found_col = None
                     for col in alt_desc_cols:
                          if col in df.columns:
                              print(f"  - INFO: Using alternative description column '{col}' for {os.path.basename(file_path)}")
                              df.rename(columns={col: config.CLEAN_DESC_COL}, inplace=True)
                              found_col = True
                              break
                     if not found_col:
                          print(f"  - WARNING:Skipping file: Missing required column '{config.CLEAN_DESC_COL}' in {os.path.basename(file_path)}")
                          continue # Skip this file
                # --- End Ensure Column ---
                dataframes_to_process.append((os.path.basename(file_path), df))
            except Exception as e:
                print(f"  - WARNING:Error loading file {os.path.basename(file_path)}: {e}")


    # 3. Process each loaded dataframe
    for filename, df_new in dataframes_to_process:
        print(f"\n--- Processing file: {filename} ---")
        # Ensure description column exists after potential rename
        if config.CLEAN_DESC_COL not in df_new.columns:
            print(f"  - WARNING:Skipping file: Still missing required column '{config.CLEAN_DESC_COL}' after checks.")
            continue
            
        clean_descriptions = df_new[config.CLEAN_DESC_COL].astype(str).fillna("")
        suppliers = df_new['supplier'] if config.USE_SUPPLIER and 'supplier' in df_new.columns else None

        # --- Pipeline Logic ---
        df_new['prediction_source'] = 'Non-Lab'
        df_new['similarity_score'] = np.nan
        y_pred = pd.Series("Non-Lab", index=df_new.index)

        print("  - Step 1: Running gatekeeper...")
        is_lab_mask = (gatekeeper_model.predict(clean_descriptions, suppliers=suppliers) == 1)
        print(f"  - Gatekeeper identified {is_lab_mask.sum()} potential lab items.")

        # --- Step 1.5: Supplier-based Non-Lab filter ---
        if 'supplier' in df_new.columns:
            supplier_lower = df_new['supplier'].astype(str).str.lower().str.strip()
            # Exact matches -- single isin instead of a loop of == comparisons.
            exact_set = {n.lower().strip() for n in config.NONLAB_SUPPLIER_EXACT}
            if exact_set:
                supplier_nonlab_mask = supplier_lower.isin(exact_set)
            else:
                supplier_nonlab_mask = pd.Series(False, index=df_new.index)
            # Keyword substring matches -- fold every keyword into a single
            # alternation regex and do ONE str.contains pass.  Pandas treats
            # the pattern as regex by default, so we preserve the original
            # (un-escaped) interpretation.
            if config.NONLAB_SUPPLIER_KEYWORDS:
                kw_re = re.compile(
                    '|'.join(f'(?:{kw.lower()})'
                             for kw in config.NONLAB_SUPPLIER_KEYWORDS)
                )
                supplier_nonlab_mask |= supplier_lower.str.contains(kw_re, na=False)
            # Force matched items to Non-Lab (remove from lab mask)
            supplier_override_count = (is_lab_mask & supplier_nonlab_mask).sum()
            if supplier_override_count > 0:
                is_lab_mask = is_lab_mask & ~supplier_nonlab_mask
                df_new.loc[supplier_nonlab_mask, 'prediction_source'] = 'Supplier Non-Lab'
                print(f"  - Supplier filter: {supplier_override_count} items forced to Non-Lab ({supplier_nonlab_mask.sum()} total supplier Non-Lab).")

        step2_vectors = None
        step2_indices = None
        if is_lab_mask.any():
            # Expert model uses clean descriptions (no supplier token) for
            # content-based category matching
            lab_descriptions = clean_descriptions[is_lab_mask]

            print(f"  - Step 2: Predicting markets with '{expert_choice}' expert (batched)...")
            # One transform/encode + one cosine matmul for all lab rows.
            # item_vectors are cached for Step 5 to avoid re-encoding.
            lab_suppliers = (suppliers.loc[lab_descriptions.index]
                             if suppliers is not None else None)
            expert_predictions, expert_scores, step2_vectors = (
                expert_predictor.predict_batch(lab_descriptions, suppliers=lab_suppliers)
            )
            step2_indices = lab_descriptions.index

            # Step 2.5: Supplier-based category force.  Mono-category vendors
            # (Peprotech / Avanti / Addgene / Bachem / ...) get their expert
            # prediction overridden to the canonical category for that vendor.
            # Runs before veto + market rules so a description-specific rule
            # in Step 4 still wins.  Only fires when the supplier name matches
            # and the category exists in the expert's known categories
            # (otherwise the override is silently skipped to avoid debug
            # warnings in Step 5).
            supp_cat_regex = getattr(config, 'SUPPLIER_CATEGORY_REGEX', None)
            if supp_cat_regex and lab_suppliers is not None:
                lab_supp_lower = lab_suppliers.astype(str).str.lower()
                total_forced = 0
                for cat, regex in supp_cat_regex.items():
                    if cat not in category_names_map:
                        continue
                    mask = lab_supp_lower.str.contains(regex, na=False)
                    if mask.any():
                        expert_predictions.loc[mask] = cat
                        total_forced += int(mask.sum())
                if total_forced:
                    print(f"  - Step 2.5: Supplier-category force overrode {total_forced} expert predictions.")

            print("  - Step 3: Applying prediction veto rules...")
            validated_predictions = rule_categorizer.validate_predictions_batch(
                expert_predictions, lab_descriptions
            )
            validated_predictions.index = lab_descriptions.index
            num_vetoed = validated_predictions.isna().sum()
            if num_vetoed > 0:
                print(f"  - WARNING:Vetoed {num_vetoed} expert predictions.")

            y_pred.update(validated_predictions)
            survived_veto = validated_predictions.notna()
            df_new.loc[validated_predictions.index[survived_veto], 'prediction_source'] = 'Expert Model'
            df_new.loc[expert_scores.index, 'similarity_score'] = expert_scores # Store initial score

        print("  - Step 4: Applying final market override rules...")
        has_raw_col = config.RAW_DESC_COL in df_new.columns
        clean_series_full = df_new[config.CLEAN_DESC_COL].astype(str)
        raw_series_full = df_new[config.RAW_DESC_COL].astype(str) if has_raw_col else None

        # FOIA product data is highly repetitive (same item ordered many
        # times).  Dedupe (clean, raw) pairs so the batch runs on uniques
        # only; then broadcast results back to every row.  Uses factorize on
        # a concatenated string key (C-level hashing) + numpy fancy-index to
        # broadcast — avoids Python tuple construction / hashing for the
        # 300k-row path.
        if has_raw_col:
            pair_key = clean_series_full.str.cat(raw_series_full, sep='\x1f')
        else:
            pair_key = clean_series_full
        codes, _ = pd.factorize(pair_key.to_numpy())
        # factorize assigns codes in first-appearance order, so the k-th
        # unique row is the first row with codes == k.
        n_unique = int(codes.max()) + 1 if len(codes) else 0
        first_pos = np.unique(codes, return_index=True)[1]
        print(f"  - {n_unique} unique description pairs among {len(pair_key)} rows")
        unique_clean = clean_series_full.iloc[first_pos].reset_index(drop=True)
        unique_raw = (raw_series_full.iloc[first_pos].reset_index(drop=True)
                      if has_raw_col else None)

        # Run market rules in parallel across worker processes.  The rule
        # evaluation is CPU-bound (793 rules x N rows of re.search calls)
        # and embarrassingly parallel by row, so we shard unique_clean /
        # unique_raw into chunks and fan out.  Single-process path kicks in
        # for small inputs where pool startup would dominate.
        n_workers = _default_override_workers()
        PARALLEL_MIN = 20_000
        if n_unique >= PARALLEL_MIN and n_workers > 1:
            # Aim for ~4 chunks per worker so a slow chunk doesn't idle the
            # rest of the pool.  Chunk via iloc slices, which inherit the
            # parent's RangeIndex (so pd.concat stacks them contiguously).
            target_chunks = n_workers * 4
            chunk_size = max(1, (n_unique + target_chunks - 1) // target_chunks)
            chunks = []
            for start in range(0, n_unique, chunk_size):
                end = min(start + chunk_size, n_unique)
                chunks.append((
                    unique_clean.iloc[start:end],
                    unique_raw.iloc[start:end] if unique_raw is not None else None,
                ))
            print(f"  - Applying market rules in parallel: "
                  f"{n_workers} workers x {len(chunks)} chunks "
                  f"(~{chunk_size} rows/chunk).")
            # fork start method (Linux default) skips re-import of this
            # module in the children; initializer still builds a fresh
            # categorizer per worker so we don't depend on parent state.
            ctx = mp.get_context('fork')
            with ctx.Pool(
                n_workers,
                initializer=_init_override_worker,
                initargs=(config.MARKET_RULES_YAML,),
            ) as pool:
                results = pool.map(_apply_overrides_chunk, chunks)
            # ignore_index=True gives us a clean 0..n_unique-1 RangeIndex
            # matching the input order (pool.map preserves input order).
            unique_overrides = pd.concat(results, ignore_index=True)
        else:
            unique_overrides = rule_categorizer.get_market_overrides_batch(
                unique_clean, unique_raw)

        # Remap rule outputs to the collapsed taxonomy the expert was trained
        # on.  market_rules.yml is deliberately kept granular (e.g. "extended
        # length pipette tips", "glass beakers", "rabbit-host anti-mouse
        # polyclonal primary antibody") so rollups are reversible later --
        # script 3 collapses at inference so the expert's category vectors
        # can be matched.
        #
        # Two kinds of rollup, both mirroring script 0:
        #   (a) explicit 1:1 renames from config.CATEGORY_CONSOLIDATION
        #   (b) keyword-based buckets: any "pipette tip*" -> "pipette tips";
        #       antibody + primary + polyclonal/monoclonal split + "secondary"
        #       -> the three antibody buckets.
        cons_map = getattr(config, 'CATEGORY_CONSOLIDATION', None)
        if cons_map:
            unique_overrides = unique_overrides.replace(cons_map)

        # Mirror script 0's keyword-based rollups on rule outputs so rule
        # categories like "extended length pipette tips" or "rabbit-host
        # anti-mouse polyclonal primary antibody" don't fall off the expert
        # model's category list (which only knows the collapsed names).
        _lower = unique_overrides.str.lower()
        unique_overrides.loc[
            _lower.str.contains("pipette tip", na=False)] = "pipette tips"
        unique_overrides.loc[
            _lower.str.contains("elisa", na=False)] = "elisa kits"
        _lower = unique_overrides.str.lower()  # recompute after elisa rollup
        _is_ab = _lower.str.contains("antibod", na=False)
        _is_prim = _lower.str.contains("primary", na=False)
        _is_sec = _lower.str.contains("secondary", na=False)
        _is_poly = _lower.str.contains("polyclonal", na=False)
        _is_mono = _lower.str.contains("monoclonal", na=False)
        unique_overrides.loc[_is_ab & _is_prim & _is_poly] = "polyclonal primary antibodies"
        unique_overrides.loc[_is_ab & _is_prim & _is_mono] = "monoclonal primary antibodies"
        unique_overrides.loc[_is_ab & _is_sec] = "secondary antibodies"

        # Broadcast unique -> every row via numpy fancy-index on codes.
        overrides = pd.Series(
            unique_overrides.to_numpy()[codes],
            index=df_new.index,
        )
        valid_overrides = overrides.dropna()
        y_pred.update(valid_overrides)
        print(f"  - Applied {len(valid_overrides)} market override rules.")
        if not valid_overrides.empty:
            df_new.loc[valid_overrides.index, 'prediction_source'] = 'Market Rules'

        y_pred.fillna("unclassified", inplace=True)

        # Deliberately no post-override re-consolidation here.  Previously
        # this step flattened every antibody to "primary antibodies"/
        # "secondary antibodies" and every elisa to "elisa kits", which
        # overwrote the expert's fine-grained labels (e.g. polyclonal /
        # monoclonal primary antibodies, pre-coated sandwich colorimetric
        # elisa kits) and zeroed their precision/recall at eval.  Any
        # taxonomy roll-up belongs in script 0's CATEGORY_CONSOLIDATION so
        # the expert learns the collapsed labels in the first place.

        # Detect items where the rule layer assigned a NON-LAB market
        # category (e.g. "animal - drosophila supplies",
        # "irrelevant chemicals - solvents", "instrument part - buffer dams").
        # The rule patterns are deliberately kept in market_rules.yml so the
        # granular category is preserved for downstream non-lab analysis —
        # but for the binary lab/non-lab decision we trust the rule over the
        # gatekeeper here.  Mark them so step 5 skips the lab-similarity
        # lookup (which would just warn about missing categories — the
        # expert is built on lab categories only).  Uses the same regex
        # that scripts 0/1 use to define non-lab.
        nonlab_from_rules_mask = y_pred.astype(str).str.contains(
            config.NONLAB_REGEX, na=False
        )
        if nonlab_from_rules_mask.any():
            n_nl = int(nonlab_from_rules_mask.sum())
            print(f"  - {n_nl} items have a non-lab market category from rules; "
                  f"keeping granular label, flagging as non-lab for binary eval.")
            df_new.loc[nonlab_from_rules_mask, 'is_nonlab_market'] = True

        # +++ Step 5: Calculate FINAL similarity scores +++
        print("  - Step 5: Calculating final similarity scores for lab predictions...")
        final_lab_mask = (
            (y_pred != "Non-Lab")
            & (y_pred != "unclassified")
            & (y_pred != "Prediction Error")
            & (y_pred != "No Description")
            & ~nonlab_from_rules_mask  # skip rule-assigned non-lab categories
        )

        if final_lab_mask.any():
            lab_indices = final_lab_mask[final_lab_mask].index
            lab_final_preds = y_pred[lab_indices]
            lab_final_descs = clean_descriptions[lab_indices]

            # Reuse Step 2's cached vectors when all final-lab rows were in
            # the gatekeeper lab set.  Market overrides (Step 4) can promote
            # rows outside is_lab_mask to a category — encode those fresh.
            lab_final_suppliers = (suppliers.loc[lab_indices]
                                   if suppliers is not None else None)
            if step2_vectors is not None and lab_indices.isin(step2_indices).all():
                positions = step2_indices.get_indexer(lab_indices)
                lab_embeddings = step2_vectors[positions]
            else:
                if expert_choice in config.BERT_MODELS:
                    lab_embeddings = expert_predictor._encode_with_supplier(
                        lab_final_descs.tolist(), lab_final_suppliers
                    )
                else:
                    lab_embeddings = vectorizer_for_similarity.transform(
                        lab_final_descs, suppliers=lab_final_suppliers
                    )

            # Vectorized row-wise cosine: gather each row's assigned category
            # vector in one fancy-index, L2-normalize both sides, dot per row.
            cat_idx_arr = np.array(
                [category_names_map.get(c, -1) for c in lab_final_preds]
            )
            valid_pos = np.where(cat_idx_arr >= 0)[0]
            missing_pos = np.where(cat_idx_arr < 0)[0]
            if len(missing_pos):
                for c in sorted(set(lab_final_preds.iloc[missing_pos].tolist())):
                    print(f"  -  DEBUG: Category mismatch. Rule category '{c}' not found in expert model's category list.")

            final_scores = np.full(len(lab_indices), np.nan)
            if len(valid_pos):
                v_lab_n = normalize(lab_embeddings[valid_pos], axis=1)
                cat_vecs_n = normalize(category_vectors_for_similarity, axis=1)
                cat_idx_valid = cat_idx_arr[valid_pos]

                # Group by assigned category and compute per-group. Avoids a
                # fancy-index over category rows that blows up either memory
                # (dense) or scipy's int32 nnz counter (sparse) when the
                # number of selected rows is large.
                scores = np.empty(len(valid_pos))
                for ci in np.unique(cat_idx_valid):
                    mask = cat_idx_valid == ci
                    v_cat_row = cat_vecs_n[ci]
                    v_lab_rows = v_lab_n[mask]
                    if sparse.issparse(v_lab_rows):
                        s = np.asarray(v_lab_rows.multiply(v_cat_row).sum(axis=1)).ravel()
                    else:
                        s = v_lab_rows @ np.asarray(v_cat_row).ravel()
                    scores[mask] = s
                final_scores[valid_pos] = scores

            df_new.loc[lab_indices, 'similarity_score'] = final_scores

            # Release big intermediates before to_csv so peak memory isn't
            # (item vectors + full output frame) during write.
            del lab_embeddings

        if step2_vectors is not None:
            del step2_vectors
            step2_vectors = None

        # Assign final predictions
        df_new['predicted_market'] = y_pred
        df_new['nonlab_bucket'] = config.assign_nonlab_bucket_series(df_new['predicted_market'])
        # --- End of Pipeline ---

        # Step G: Save the results
        output_filename = f"{os.path.splitext(filename)[0]}_classified_with_{expert_choice}.csv"
        output_path = os.path.join(config.OUTPUT_DIR, output_filename)
        df_new.to_csv(output_path, index=False)
        print(f"Prediction file saved to: {output_path}")

    print("\n--- All files processed. ---")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run product market predictions on new data.")
    parser.add_argument("source_abbrev", type=str, nargs='?', default=None, help="Abbreviation of data source (e.g., 'utdallas', 'govspend', university prefix). If empty, processes all non-UTDallas, non-GovSpend files.")
    _model_choices = ['tfidf'] + list(config.BERT_MODELS.keys())
    parser.add_argument("model", type=str, nargs='?', default=None, choices=_model_choices,
                        help="Shortcut: use this model for BOTH gatekeeper and expert. Overridden per-role by --gatekeeper / --expert.")
    parser.add_argument("--gatekeeper", type=str, default=None, choices=_model_choices)
    parser.add_argument("--expert", type=str, default=None, choices=_model_choices)
    args = parser.parse_args()

    gatekeeper = args.gatekeeper or args.model
    expert = args.expert or args.model
    if gatekeeper is None or expert is None:
        parser.error("Must specify the model positionally (e.g. 'tfidf') or via --gatekeeper and --expert.")
    main(gatekeeper_name=gatekeeper, expert_choice=expert, source_abbrev=args.source_abbrev)