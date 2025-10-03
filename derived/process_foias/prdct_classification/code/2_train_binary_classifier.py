# 2_train_binary_classifier.py (REVISED)
"""
Trains the ML model component, builds the full HybridClassifier,
saves it, and evaluates its performance on the UT Dallas data.
"""
import pandas as pd
import joblib
import os
import argparse
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report

import config
# --- NEW: Import our HybridClassifier and its helper functions ---
from classifier import HybridClassifier, load_keywords_and_build_automaton

def main(embedding_name: str):
    print(f"--- Training Hybrid Model with '{embedding_name}' Embeddings ---")

    embedding_path = os.path.join(config.OUTPUT_DIR, f"embeddings_{embedding_name}.joblib")
    if not os.path.exists(embedding_path):
        print(f"❌ Embeddings file not found: {embedding_path}. Run 1b_create_text_embeddings.py first.")
        return

    print("  - Loading data...")
    X = joblib.load(embedding_path)
    df_labels = pd.read_parquet(config.PREPARED_DATA_PATH)
    y = df_labels['label']

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    # 1. Train the ML model component (the "student")
    print("  - Training the Logistic Regression component...")
    clf = LogisticRegression(solver='saga', n_jobs=-1, random_state=42, class_weight='balanced', max_iter=1000)
    clf.fit(X_train, y_train)
    print("  - ML component training complete.")

    # --- NEW: Build and save the complete HybridClassifier ---
    print("\n  - Building the full HybridClassifier...")
    
    # Load the vectorizer (either TF-IDF or the BERT model object)
    if embedding_name == 'tfidf':
        vectorizer_path = os.path.join(config.OUTPUT_DIR, "vectorizer_tfidf.joblib")
        vectorizer = joblib.load(vectorizer_path)
    elif embedding_name == 'bert':
        model_object_path = os.path.join(config.OUTPUT_DIR, "model_object_all-MiniLM-L6-v2.joblib")
        vectorizer = joblib.load(model_object_path) # The BERT model is our vectorizer
    
    # Load the keyword automata (the "gatekeepers")
    seed_automaton = load_keywords_and_build_automaton(config.SEED_KEYWORD_YAML)
    anti_seed_automaton = load_keywords_and_build_automaton(config.ANTI_SEED_KEYWORD_YAML)

    # Create an instance of our hybrid model
    hybrid_model = HybridClassifier(
        ml_model=clf,
        vectorizer=vectorizer,
        seed_automaton=seed_automaton,
        anti_seed_automaton=anti_seed_automaton
    )

    # Save the single, powerful hybrid model object
    model_path = os.path.join(config.OUTPUT_DIR, f"hybrid_classifier_{embedding_name}.joblib")
    joblib.dump(hybrid_model, model_path)
    print(f"✅ HybridClassifier saved to: {model_path}")

    # --- REVISED: The rest of the script now evaluates the HYBRID model ---
    
    # (Optional) You can still evaluate the ML component on the blended test set
    y_pred_proba = clf.predict_proba(X_test)[:, 1]
    y_pred = (y_pred_proba >= 0.5).astype(int)
    print("\n--- Evaluation of ML Component on Blended Test Set ---")
    print(classification_report(y_test, y_pred, target_names=["Non-Lab", "Lab"]))
    
    print("\n--- Starting Diagnostic Evaluation of HYBRID MODEL on UT Dallas Data ---")
    try:
        df_utdallas = pd.read_parquet(config.UT_DALLAS_MERGED_CLEAN_PATH)
        descriptions_utdallas = df_utdallas[config.CLEAN_DESC_COL].fillna('')
        
        # Define the "true" labels using the same category logic as before
        nonlab_pattern = '|'.join(config.NONLAB_CATEGORIES)
        is_true_nonlab = df_utdallas[config.UT_CAT_COL].str.contains(nonlab_pattern, case=False, na=False)
        y_true_utdallas = pd.Series(1, index=df_utdallas.index)
        y_true_utdallas[is_true_nonlab] = 0
        
        # Get predictions from the full hybrid model
        print("  - Generating predictions with the HybridClassifier...")
        y_pred_utdallas = hybrid_model.predict(descriptions_utdallas)

        print(f"\n--- Hybrid Model Performance on UT Dallas Data (Threshold: {config.PREDICTION_THRESHOLD}) ---")
        utdallas_report = classification_report(y_true_utdallas, y_pred_utdallas, target_names=["Non-Lab (0)", "Lab (1)"])
        print(utdallas_report)

        # Save the diagnostic report
        diag_report_path = os.path.join(config.OUTPUT_DIR, f"report_utdallas_hybrid_{embedding_name}.txt")
        with open(diag_report_path, 'w') as f:
            f.write("Hybrid Model Diagnostic Report on UT Dallas Data\n" + "="*50 + "\n" + utdallas_report)
        print(f"✅ UT Dallas hybrid diagnostic report saved to: {diag_report_path}")

        # Find and save misclassified items
        df_utdallas['true_label'] = y_true_utdallas
        df_utdallas['predicted_label'] = y_pred_utdallas
        df_false_negatives = df_utdallas[(df_utdallas['true_label'] == 1) & (df_utdallas['predicted_label'] == 0)]
        df_false_positives = df_utdallas[(df_utdallas['true_label'] == 0) & (df_utdallas['predicted_label'] == 1)]

        fn_output_path = os.path.join(config.OUTPUT_DIR, f"hybrid_errors_false_negatives_{embedding_name}.csv")
        df_false_negatives.to_csv(fn_output_path, index=False)
        print(f"  - ✅ Saved {len(df_false_negatives)} False Negatives to: {os.path.basename(fn_output_path)}")

        fp_output_path = os.path.join(config.OUTPUT_DIR, f"hybrid_errors_false_positives_{embedding_name}.csv")
        df_false_positives.to_csv(fp_output_path, index=False)
        print(f"  - ✅ Saved {len(df_false_positives)} False Positives to: {os.path.basename(fp_output_path)}")

    except Exception as e:
        print(f"❌ An error occurred during the UT Dallas diagnostic: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Train and evaluate the Hybrid Classifier.")
    parser.add_argument("embedding_name", type=str, help="The name of the embedding set to use (e.g., 'tfidf', 'bert').")
    args = parser.parse_args()
    main(args.embedding_name)