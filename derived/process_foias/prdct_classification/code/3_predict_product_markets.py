# 3_predict_product_markets.py (UPDATED with Similarity Score)
"""
Uses a flexibly chosen pipeline to predict product markets for various data sources.
Applies a gatekeeper, a chosen expert model, prediction veto rules, and final override rules.
Includes prediction source and final similarity score in the output.
"""
import pandas as pd
import glob
import os
import joblib
import argparse
from scipy import sparse
from sklearn.preprocessing import normalize
import numpy as np # Added for NaN

import config
from rule_based_categorizer import RuleBasedCategorizer
from categorize_items import TfidfItemCategorizer, EmbeddingItemCategorizer

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
        elif expert_choice == 'bert':
            expert_predictor = EmbeddingItemCategorizer("bert", "all-MiniLM-L6-v2")
            vectorizer_for_similarity = expert_predictor.encoder_model # The BERT model itself
            category_vectors_for_similarity = expert_predictor.category_vectors
            category_names_map = {name: i for i, name in enumerate(expert_predictor.category_names)}
        else:
            raise ValueError(f"Unsupported expert choice: {expert_choice}")

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

            dataframes_to_process.append(('govspend_panel.csv', df_gov))
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
            supplier_nonlab_mask = pd.Series(False, index=df_new.index)
            # Exact matches
            for exact_name in config.NONLAB_SUPPLIER_EXACT:
                supplier_nonlab_mask |= (supplier_lower == exact_name.lower().strip())
            # Keyword substring matches
            for kw in config.NONLAB_SUPPLIER_KEYWORDS:
                supplier_nonlab_mask |= supplier_lower.str.contains(kw.lower(), na=False)
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
            expert_predictions, expert_scores, step2_vectors = (
                expert_predictor.predict_batch(lab_descriptions)
            )
            step2_indices = lab_descriptions.index

            print("  - Step 3: Applying prediction veto rules...")
            validated_predictions = pd.Series(
                [rule_categorizer.validate_prediction(pred, desc) for pred, desc in zip(expert_predictions, lab_descriptions)],
                index=lab_descriptions.index
            )
            num_vetoed = validated_predictions.isna().sum()
            if num_vetoed > 0:
                print(f"  - WARNING:Vetoed {num_vetoed} expert predictions.")

            y_pred.update(validated_predictions)
            survived_veto = validated_predictions.notna()
            df_new.loc[validated_predictions.index[survived_veto], 'prediction_source'] = 'Expert Model'
            df_new.loc[expert_scores.index, 'similarity_score'] = expert_scores # Store initial score

        print("  - Step 4: Applying final market override rules...")
        has_raw_col = config.RAW_DESC_COL in df_new.columns
        clean_list = df_new[config.CLEAN_DESC_COL].astype(str).tolist()
        if has_raw_col:
            raw_list = df_new[config.RAW_DESC_COL].astype(str).tolist()
            pairs = list(zip(clean_list, raw_list))
        else:
            pairs = [(c, None) for c in clean_list]

        # FOIA product data is highly repetitive (same item ordered many
        # times).  Dedupe on (clean, raw) so the rule regex chain runs once
        # per unique pair instead of per row.
        unique_pairs = set(pairs)
        print(f"  - {len(unique_pairs)} unique description pairs among {len(pairs)} rows")
        pair_to_override = {
            p: rule_categorizer.get_market_override(p[0], p[1])
            for p in unique_pairs
        }
        overrides = pd.Series(
            [pair_to_override[p] for p in pairs], index=df_new.index
        )
        valid_overrides = overrides.dropna()
        y_pred.update(valid_overrides)
        print(f"  - Applied {len(valid_overrides)} market override rules.")
        if not valid_overrides.empty:
            df_new.loc[valid_overrides.index, 'prediction_source'] = 'Market Rules'

        y_pred.fillna("unclassified", inplace=True)
        cat_col = y_pred.astype(str).str.lower()
        
        # Consolidate Antibodies
        is_antibody = cat_col.str.contains("antibod", na=False)
        is_primary = cat_col.str.contains("primary", na=False)
        is_secondary = cat_col.str.contains("secondary", na=False)
        y_pred[is_antibody & is_primary] = "primary antibodies"
        y_pred[is_antibody & is_secondary] = "secondary antibodies"

        # Consolidate ELISA
        is_elisa = cat_col.str.contains("elisa", na=False)
        y_pred[is_elisa] = "elisa kits"

        # Consolidate Pipette Tips
        is_pipette_tip = cat_col.str.contains("pipette tip", na=False)
        y_pred[is_pipette_tip] = "pipette tips"

        # +++ Step 5: Calculate FINAL similarity scores +++
        print("  - Step 5: Calculating final similarity scores for lab predictions...")
        final_lab_mask = (y_pred != "Non-Lab") & (y_pred != "unclassified") & (y_pred != "Prediction Error") & (y_pred != "No Description")

        if final_lab_mask.any():
            lab_indices = final_lab_mask[final_lab_mask].index
            lab_final_preds = y_pred[lab_indices]
            lab_final_descs = clean_descriptions[lab_indices]

            # Reuse Step 2's cached vectors when all final-lab rows were in
            # the gatekeeper lab set.  Market overrides (Step 4) can promote
            # rows outside is_lab_mask to a category — encode those fresh.
            if step2_vectors is not None and lab_indices.isin(step2_indices).all():
                positions = step2_indices.get_indexer(lab_indices)
                lab_embeddings = step2_vectors[positions]
            else:
                if expert_choice == 'bert':
                    lab_embeddings = vectorizer_for_similarity.encode(
                        lab_final_descs.tolist(), show_progress_bar=True, batch_size=128
                    )
                else:
                    lab_embeddings = vectorizer_for_similarity.transform(lab_final_descs)

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


        # Assign final predictions
        df_new['predicted_market'] = y_pred
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
    parser.add_argument("--gatekeeper", type=str, required=True, choices=['tfidf', 'bert'])
    parser.add_argument(
        "--expert",
        type=str,
        required=True,
        choices=['tfidf', 'bert'],
    )
    args = parser.parse_args()
    main(gatekeeper_name=args.gatekeeper, expert_choice=args.expert, source_abbrev=args.source_abbrev)