# 2b_train_expert_classifier.py
"""
Trains and evaluates a parametric, multi-class classifier (Logistic Regression)
to serve as the "expert" model for predicting specific lab product markets.
This script now includes a proper train-test split for realistic evaluation.
"""
import pandas as pd
import joblib
import os
import time
import warnings
import threading
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report
from sklearn.exceptions import ConvergenceWarning
from sklearn.model_selection import train_test_split

import config

def main():
    print("--- Starting Step 2b: Training and Evaluating Expert Classifier ---")

    # 1. Load data and embeddings
    print("  - Loading data and embeddings...")
    try:
        all_embeddings = joblib.load(os.path.join(config.OUTPUT_DIR, "embeddings_tfidf.joblib"))
        df_prepared = pd.read_parquet(config.PREPARED_DATA_PATH)
    except FileNotFoundError as e:
        print(f"❌ A required file was not found: {e}. Run steps 1 and 1b first.")
        return

    # 2. Filter for the full UT Dallas lab dataset
    lab_mask = (df_prepared['label'] == 1) & (df_prepared['data_source'] == 'ut_dallas')
    df_full_lab_data = df_prepared[lab_mask].dropna(subset=[config.UT_CAT_COL])
    
    full_indices = df_full_lab_data.index
    X = all_embeddings[full_indices]
    y = df_full_lab_data[config.UT_CAT_COL]

    # 3. NEW: Filter out categories with only one member to allow for stratification
    print("\n  - Pre-filtering data to ensure all categories can be split for testing...")
    category_counts = y.value_counts()
    valid_categories = category_counts[category_counts >= 2].index
    
    filter_mask = y.isin(valid_categories)
    # FIX: Convert the pandas Series mask to a numpy array for SciPy compatibility
    X_filtered = X[filter_mask.values]
    y_filtered = y[filter_mask]
    
    print(f"  - Removed {len(category_counts) - len(valid_categories)} singleton categories.")
    print(f"  - Proceeding with {X_filtered.shape[0]} items in {len(valid_categories)} categories.")


    # 4. Split data into training and a hold-out test set for proper evaluation
    print("\n  - Splitting data into 80% training and 20% hold-out test sets...")
    X_train, X_test, y_train, y_test = train_test_split(
        X_filtered, y_filtered, test_size=0.2, random_state=42, stratify=y_filtered
    )
    print(f"  - Training on {X_train.shape[0]} samples, testing on {X_test.shape[0]} samples.")
    
    # 5. Train the full multi-class Logistic Regression model on the TRAINING data
    print("\n  - Starting multi-classifier training...")
    start_time = time.time()

    expert_clf = LogisticRegression(
        solver='saga',
        multi_class='ovr',
        n_jobs=-1,
        random_state=42,
        class_weight='balanced',
        max_iter=3000,
        verbose=0
    )

    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter("always")
        expert_clf.fit(X_train, y_train)
        
        # Check for convergence issues after training
        converged = not any(isinstance(warn.message, ConvergenceWarning) for warn in w)

    end_time = time.time()
    print(f"\n  - ✅ Multi-classifier training finished in {end_time - start_time:.2f} seconds.")

    if converged:
        print("  - ✅ All classifiers converged successfully.")
    else:
        print("  - ⚠️ ConvergenceWarning: At least one classifier did not converge. Consider increasing max_iter.")

    # 6. Save the trained expert model
    model_path = os.path.join(config.OUTPUT_DIR, "expert_classifier_tfidf.joblib")
    joblib.dump(expert_clf, model_path)
    print(f"  - Expert model saved to: {model_path}")

    # 7. Evaluate the model on the HOLD-OUT TEST DATA
    print("\n--- Performance on Hold-Out Test Data ---")
    y_pred = expert_clf.predict(X_test)
    report = classification_report(y_test, y_pred, zero_division=0)
    print(report)

if __name__ == "__main__":
    main()

