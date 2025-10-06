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
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report

import config
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

    # Split the main DataFrame to preserve all columns for the hold-out set
    df_train, df_test = train_test_split(
        df_labels, test_size=0.2, random_state=42, stratify=df_labels['label']
    )

    # Save the 20% hold-out DataFrame for potential use in later scripts
    holdout_path = os.path.join(config.OUTPUT_DIR, "holdout_data_for_validation.parquet")
    df_test.to_parquet(holdout_path, index=False)
    print(f"✅ Hold-out data for validation saved to: {holdout_path}")

    # Create the corresponding embedding and label arrays for training
    X_train = X[df_train.index]
    y_train = df_train['label']

    # 1. Train the ML model component
    print("  - Training the Logistic Regression component...")
    clf = LogisticRegression(solver='saga', n_jobs=-1, random_state=42, class_weight='balanced', max_iter=1000)
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
    
    seed_automaton = load_keywords_and_build_automaton(config.SEED_KEYWORD_YAML)
    anti_seed_automaton = load_keywords_and_build_automaton(config.ANTI_SEED_KEYWORD_YAML)

    hybrid_model = HybridClassifier(
        ml_model=clf,
        vectorizer=vectorizer,
        seed_automaton=seed_automaton,
        anti_seed_automaton=anti_seed_automaton
    )

    model_path = os.path.join(config.OUTPUT_DIR, f"hybrid_classifier_{embedding_name}.joblib")
    joblib.dump(hybrid_model, model_path)
    print(f"✅ HybridClassifier saved to: {model_path}")

    # --- 3. Evaluate the HYBRID MODEL on the UT Dallas portion of the hold-out set ---
    print("\n--- Evaluating Hybrid Model on UT Dallas Hold-Out Data (20%) ---")
    
    # Filter the test set to get only the UT Dallas items
    df_test_utdallas = df_test[df_test['data_source'] == 'ut_dallas'].copy()

    if not df_test_utdallas.empty:
        print(f"  - Found {len(df_test_utdallas)} UT Dallas items in the hold-out set.")
        descriptions_utdallas = df_test_utdallas[config.CLEAN_DESC_COL].fillna('')
        y_true_utdallas = df_test_utdallas['label']
        
        # Get predictions from the full hybrid model
        y_pred_utdallas = hybrid_model.predict(descriptions_utdallas)

        # Generate and print the report
        utdallas_report = classification_report(y_true_utdallas, y_pred_utdallas, target_names=["Non-Lab (0)", "Lab (1)"])
        print("\nClassification Report (UT Dallas Hold-Out):")
        print(utdallas_report)

        # --- ADDED CODE START ---
        print("\n  - Identifying and saving misclassifications...")
        
        # Add predictions to the dataframe to make filtering easy
        df_results = df_test_utdallas.copy()
        df_results['predicted_label'] = y_pred_utdallas

        # Isolate False Positives (True=0, Predicted=1)
        df_fp = df_results[(df_results['label'] == 0) & (df_results['predicted_label'] == 1)]
        fp_path = os.path.join(config.OUTPUT_DIR, "false_positives.csv")
        df_fp.to_csv(fp_path, index=False)
        print(f"    - Saved {len(df_fp)} False Positives to: {fp_path}")

        # Isolate False Negatives (True=1, Predicted=0)
        df_fn = df_results[(df_results['label'] == 1) & (df_results['predicted_label'] == 0)]
        fn_path = os.path.join(config.OUTPUT_DIR, "false_negatives.csv")
        df_fn.to_csv(fn_path, index=False)
        print(f"    - Saved {len(df_fn)} False Negatives to: {fn_path}")
        # --- ADDED CODE END ---

    else:
        print("  - No UT Dallas items were found in the hold-out set for this run.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Train Hybrid Classifier and evaluate on hold-out data.")
    parser.add_argument("embedding_name", type=str, help="The name of the embedding set to use (e.g., 'tfidf', 'bert').")
    args = parser.parse_args()
    main(args.embedding_name)