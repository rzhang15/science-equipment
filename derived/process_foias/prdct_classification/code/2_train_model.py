# 2_train_model.py (UPDATED to use the final threshold from config)
"""
Trains and saves the binary classification model (Lab vs. Non-Lab).
Evaluates the model using the final threshold set in config.py.
"""
import pandas as pd
import joblib
from sklearn.model_selection import train_test_split
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.metrics import classification_report, confusion_matrix, roc_auc_score, matthews_corrcoef

import config

def main():
    print("--- Starting Step 2: Training Lab/Not-Lab Model ---")

    try:
        df = pd.read_parquet(config.PREPARED_DATA_PATH)
    except FileNotFoundError:
        print(f"❌ Prepared data not found at {config.PREPARED_DATA_PATH}. Run 1_prepare_data.py first.")
        return

    X = df['prepared_description'].fillna('')
    y = df['label']

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    pipeline = Pipeline([
        ("vec", TfidfVectorizer(ngram_range=(1, 3), min_df=3)),
        ("clf", LogisticRegression(solver='liblinear', random_state=42, class_weight='balanced'))
    ])

    print("ℹ️ Training the Logistic Regression model...")
    pipeline.fit(X_train, y_train)
    print("✅ Model training complete.")

    # --- Get Probabilities ---
    y_pred_proba = pipeline.predict_proba(X_test)[:, 1] # Probabilities for the 'Lab' class

    # --- UPDATED: Evaluate using only the final threshold from config.py ---
    final_threshold = config.PREDICTION_THRESHOLD
    print(f"\n--- Model Evaluation (Using Final Threshold: {final_threshold}) ---")

    # Apply the final threshold to the probabilities
    y_pred_final = (y_pred_proba >= final_threshold).astype(int)

    print("\nClassification Report:")
    print(classification_report(y_test, y_pred_final, target_names=["Non-Lab", "Lab"]))

    print("\n--- Additional Performance Metrics ---")
    cm = confusion_matrix(y_test, y_pred_final)
    tn, fp, fn, tp = cm.ravel()
    print("Confusion Matrix:")
    print(f"  - True Negatives: {tn}")
    print(f"  - False Positives: {fp}")
    print(f"  - False Negatives: {fn}")
    print(f"  - True Positives:    {tp}")

    auc_score = roc_auc_score(y_test, y_pred_proba)
    print(f"\nROC AUC Score: {auc_score:.4f}")

    mcc = matthews_corrcoef(y_test, y_pred_final)
    print(f"\nMatthews Correlation Coefficient (MCC): {mcc:.4f}")

    joblib.dump(pipeline, config.LAB_MODEL_PATH)
    print(f"\n✅ Lab/Not-Lab classification model saved to: {config.LAB_MODEL_PATH}")

    print("--- Step 2: Model Training Complete ---")

if __name__ == "__main__":
    main()
