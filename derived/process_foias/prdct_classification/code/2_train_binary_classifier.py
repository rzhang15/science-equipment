# 2_train_binary_classifier.py (Updated to include UT Dallas hold-out evaluation)
"""
Trains the ML model, builds the HybridClassifier, saves a hold-out set,
and then immediately evaluates the HybridClassifier's performance on both
the full blended hold-out set and the UT Dallas-specific portion of it.
"""
import pandas as pd
import joblib
import os
import argparse
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report

import config
from classifier import HybridClassifier, load_keywords_and_build_automaton, extract_market_keywords_and_build_automaton

def main(embedding_name: str):
    print(f"--- Training Hybrid Model with '{embedding_name}' Embeddings [Variant: {config.VARIANT}] ---")

    embedding_path = os.path.join(config.OUTPUT_DIR, f"embeddings_{embedding_name}.joblib")
    if not os.path.exists(embedding_path):
        print(f"Embeddings file not found: {embedding_path}. Run 1b_create_text_embeddings.py first.")
        return

    print("  - Loading data...")
    X = joblib.load(embedding_path)
    df_labels = pd.read_parquet(config.PREPARED_DATA_PATH)

    # Split the main DataFrame to preserve all columns for the hold-out set
    df_train, df_test = train_test_split(
        df_labels, test_size=0.2, random_state=42, stratify=df_labels['label']
    )

    # Save the 20% hold-out DataFrame for potential use in later scripts
    holdout_path = os.path.join(config.OUTPUT_DIR, "holdout_data_for_validation.parquet")
    df_test.to_parquet(holdout_path, index=False)
    print(f"Hold-out data for validation saved to: {holdout_path}")

    # Create the corresponding embedding and label arrays for training
    X_train = X[df_train.index]
    y_train = df_train['label']

    # Compute supplier priors from the training split so the HybridClassifier
    # can apply them as a post-hoc overlay at inference.  Only meaningful when
    # supplier data is available.
    supplier_priors = None
    if getattr(config, 'USE_SUPPLIER_PRIOR', False) and 'supplier' in df_train.columns:
        # Dedupe before running normalize_supplier — few hundred unique
        # suppliers across the whole training split.
        suppliers = df_train['supplier'].fillna('')
        tok_map = {s: config.normalize_supplier(s) for s in suppliers.unique()}
        tok_train = suppliers.map(tok_map)
        tmp = pd.DataFrame({'tok': tok_train, 'label': df_train['label'].values})
        tmp = tmp[tmp['tok'] != '']
        agg = tmp.groupby('tok')['label'].agg(['size', 'mean'])
        supplier_priors = {tok: (int(row['size']), float(row['mean']))
                           for tok, row in agg.iterrows()}
        print(f"  - Supplier priors: {len(supplier_priors)} suppliers computed "
              f"(training-split lab rates)")

    # 1. Train the ML model component
    print("  - Training the LogisticRegression component...")
    from sklearn.linear_model import LogisticRegression
    clf = LogisticRegression(
        C=1.0, class_weight='balanced', max_iter=1000,
        solver='liblinear', random_state=42, n_jobs=None,
    )
    clf.fit(X_train, y_train)
    print("  - ML component training complete.")

    # 2. Build the complete HybridClassifier
    print("\n  - Building the full HybridClassifier...")
    if embedding_name == 'tfidf':
        vectorizer_path = os.path.join(config.OUTPUT_DIR, "vectorizer_tfidf.joblib")
        vectorizer = joblib.load(vectorizer_path)
    elif embedding_name == 'bert':
        model_object_path = os.path.join(config.OUTPUT_DIR, "model_object_all-MiniLM-L6-v2.joblib")
        vectorizer = joblib.load(model_object_path)

    # Load supplier vectorizer if available
    supplier_vectorizer = None
    if config.USE_SUPPLIER:
        supp_vec_path = os.path.join(config.OUTPUT_DIR, "vectorizer_supplier_tfidf.joblib")
        if os.path.exists(supp_vec_path):
            supplier_vectorizer = joblib.load(supp_vec_path)
            print(f"  - Loaded supplier vectorizer from {supp_vec_path}")

    seed_automaton = load_keywords_and_build_automaton(config.SEED_KEYWORD_YAML)
    anti_seed_automaton = load_keywords_and_build_automaton(config.ANTI_SEED_KEYWORD_YAML)
    market_rule_automaton = extract_market_keywords_and_build_automaton(config.MARKET_RULES_YAML)

    # Load second-stage bulk-chemical filter if available.  Trained separately
    # by 2b_train_chemical_filter.py — absence is non-fatal.
    bulk_filter = None
    bulk_filter_vectorizer = None
    if getattr(config, 'USE_BULK_FILTER', False):
        bf_path = os.path.join(config.OUTPUT_DIR, "bulk_filter.joblib")
        bfv_path = os.path.join(config.OUTPUT_DIR, "bulk_filter_vectorizer.joblib")
        if os.path.exists(bf_path) and os.path.exists(bfv_path):
            bulk_filter = joblib.load(bf_path)
            bulk_filter_vectorizer = joblib.load(bfv_path)
            print(f"  - Loaded bulk-chemical filter from {bf_path}")
        else:
            print(f"  - No bulk filter found at {bf_path}; run 2b_train_chemical_filter.py to enable")

    hybrid_model = HybridClassifier(
        ml_model=clf,
        vectorizer=vectorizer,
        seed_automaton=seed_automaton,
        anti_seed_automaton=anti_seed_automaton,
        market_rule_automaton=market_rule_automaton,
        supplier_vectorizer=supplier_vectorizer,
        bulk_filter=bulk_filter,
        bulk_filter_vectorizer=bulk_filter_vectorizer,
        supplier_priors=supplier_priors,
    )

    model_path = os.path.join(config.OUTPUT_DIR, f"hybrid_classifier_{embedding_name}.joblib")
    joblib.dump(hybrid_model, model_path)
    print(f"HybridClassifier saved to: {model_path}")

    # --- 3. Evaluate the HYBRID MODEL on hold-out slices ---
    # Predict once on the full hold-out set, then slice by data_source for
    # each report.  The three evaluate_holdout calls previously ran predict
    # on overlapping subsets (UT Dallas, UMich, and their union).
    print("\n--- Predicting on full hold-out set ---")
    df_test = df_test.copy()
    holdout_descs = df_test[config.CLEAN_DESC_COL].fillna('')
    holdout_suppliers = (df_test['supplier']
                         if config.USE_SUPPLIER and 'supplier' in df_test.columns
                         else None)
    df_test['predicted_label'] = hybrid_model.predict(
        holdout_descs, suppliers=holdout_suppliers
    )

    def evaluate_holdout(df_slice, label, fp_suffix="", fn_suffix=""):
        """Report metrics + write FP/FN CSVs for a pre-predicted slice."""
        if df_slice.empty:
            print(f"  - No {label} items found in the hold-out set.")
            return

        print(f"\n--- Evaluating Hybrid Model on {label} Hold-Out ({len(df_slice)} items) ---")
        if 'predicted_label' not in df_slice.columns:
            descriptions = df_slice[config.CLEAN_DESC_COL].fillna('')
            suppliers = df_slice['supplier'] if config.USE_SUPPLIER and 'supplier' in df_slice.columns else None
            df_slice = df_slice.copy()
            df_slice['predicted_label'] = hybrid_model.predict(descriptions, suppliers=suppliers)

        y_true = df_slice['label']
        y_pred = df_slice['predicted_label']

        report = classification_report(y_true, y_pred, target_names=["Non-Lab (0)", "Lab (1)"])
        print(f"\nClassification Report ({label}):")
        print(report)

        df_fp = df_slice[(df_slice['label'] == 0) & (df_slice['predicted_label'] == 1)]
        fp_path = os.path.join(config.OUTPUT_DIR, f"false_positives{fp_suffix}.csv")
        df_fp.to_csv(fp_path, index=False)
        print(f"  - Saved {len(df_fp)} False Positives to: {fp_path}")

        df_fn = df_slice[(df_slice['label'] == 1) & (df_slice['predicted_label'] == 0)]
        fn_path = os.path.join(config.OUTPUT_DIR, f"false_negatives{fn_suffix}.csv")
        df_fn.to_csv(fn_path, index=False)
        print(f"  - Saved {len(df_fn)} False Negatives to: {fn_path}")

    # Always evaluate on UT Dallas hold-out
    evaluate_holdout(
        df_test[df_test['data_source'] == 'ut_dallas'],
        label="UT Dallas", fp_suffix="_utdallas", fn_suffix="_utdallas",
    )

    # UMich evaluation — source depends on variant:
    #   - umich_supplier: UMich is in training, so only the 20% hold-out slice
    #     is fair game (plus a combined UT Dallas + UMich hold-out report)
    #   - baseline:       UMich is not in training, so the entire UMich corpus
    #                     is out-of-sample and evaluated end-to-end
    if config.USE_UMICH:
        evaluate_holdout(
            df_test[df_test['data_source'] == 'umich'],
            label="UMich (hold-out)", fp_suffix="_umich", fn_suffix="_umich",
        )
        evaluate_holdout(
            df_test[df_test['data_source'].isin(['ut_dallas', 'umich'])],
            label="UT Dallas + UMich (combined)", fp_suffix="_combined", fn_suffix="_combined",
        )
    else:
        if os.path.exists(config.UMICH_EVAL_DATA_PATH):
            df_umich_eval = pd.read_parquet(config.UMICH_EVAL_DATA_PATH)
            evaluate_holdout(
                df_umich_eval,
                label="UMich (full out-of-sample)",
                fp_suffix="_umich", fn_suffix="_umich",
            )
        else:
            print(f"\n  - No UMich eval data at {config.UMICH_EVAL_DATA_PATH}; "
                  f"skipping UMich eval.  Re-run 1_build_training_dataset.py.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Train Hybrid Classifier and evaluate on hold-out data.")
    parser.add_argument("embedding_name", type=str, help="The name of the embedding set to use (e.g., 'tfidf', 'bert').")
    args = parser.parse_args()
    main(args.embedding_name)
