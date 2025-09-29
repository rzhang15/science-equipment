# 2_train_model.py (Modified for modular embeddings)
"""
Trains and evaluates a classifier using pre-computed embeddings.
This script can be run for any set of vectors (TF-IDF, Word2Vec, BERT, etc.).
"""
import pandas as pd
import joblib
import os
import argparse
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report
import matplotlib.pyplot as plt
import seaborn as sns

import config

def main(embedding_name: str):
    """
    Trains a model using a specified set of embeddings.

    Args:
        embedding_name (str): The name of the embedding set (e.g., 'scibert', 'gte').
    """
    print(f"--- Training Model with '{embedding_name}' Embeddings ---")

    # 1. Construct the path to the specified embeddings file
    embedding_path = os.path.join(config.OUTPUT_DIR, f"embeddings_{embedding_name}.joblib")
    if not os.path.exists(embedding_path):
        print(f"❌ Embeddings file not found: {embedding_path}. Run 1b_generate_embeddings.py first.")
        return

    # 2. Load the pre-computed vectors and the corresponding labels
    print("  - Loading data...")
    X = joblib.load(embedding_path)
    df_labels = pd.read_parquet(config.PREPARED_DATA_PATH)
    y = df_labels['label']

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    # 3. Use a simple classifier; the heavy lifting was done in the embedding step
    clf = LogisticRegression(solver='saga', n_jobs=-1, random_state=42, class_weight='balanced', max_iter=1000)

    print("  - Training the Logistic Regression model...")
    clf.fit(X_train, y_train)
    print("  - Model training complete.")
    print("  - Saving the trained model...")
    # This path should match the LAB_MODEL_PATH in your config.py
    model_path = os.path.join(config.OUTPUT_DIR, f"lab_binary_classifier_{embedding_name}.joblib")
    joblib.dump(clf, model_path)
    print(f"✅ Model saved to: {model_path}")
    # 4. Evaluate the model and print the report
    y_pred_proba = clf.predict_proba(X_test)[:, 1]
    custom_threshold = 0.8 
    y_pred = (y_pred_proba >= custom_threshold).astype(int)

    print(f"\n--- Evaluation with Custom Threshold: {custom_threshold} ---")
    report = classification_report(y_test, y_pred, target_names=["Non-Lab", "Lab"])
    print("\nClassification Report:")
    print(report)

    # 5. Save the report to a uniquely named file for comparison
    report_path = os.path.join(config.OUTPUT_DIR, f"report_{embedding_name}.txt")
    with open(report_path, 'w') as f:
        f.write(f"Performance Report for '{embedding_name}' embeddings\n")
        f.write("="*50 + "\n")
        f.write(report)
    print(f"✅ Classification report saved to: {report_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Train a classifier on pre-computed embeddings.")
    parser.add_argument(
        "embedding_name",
        type=str,
        help="The name of the embedding set to use (e.g., 'tfidf', 'word2vec', 'scibert', 'gte')."
    )
    args = parser.parse_args()
    main(args.embedding_name)
