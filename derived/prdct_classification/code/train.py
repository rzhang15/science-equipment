#!/usr/bin/env python3

import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report

def main():
    """
    Trains a text classification model to categorize supplier-product items
    and then uses the model to predict categories for new data.
    """

    # 1. Load the UT Dallas labeled data
    df_utd = pd.read_csv("ut_dallas_labeled_data.csv")
    # Columns assumed to be: ['supplier', 'product_description', 'sku', 'category']

    # 2. Create a combined text feature (ignoring SKU for now)
    df_utd['text_combined'] = df_utd['supplier'].astype(str) + ' ' + df_utd['product_description'].astype(str)

    # 3. Define features (X) and labels (y)
    X = df_utd['text_combined']
    y = df_utd['category']

    # 4. Split into training and test sets
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    # 5. Vectorize text data using TF-IDF
    tfidf = TfidfVectorizer(
        stop_words='english',   # remove common stopwords
        max_features=5000      # limit vocabulary size for demo
    )
    X_train_tfidf = tfidf.fit_transform(X_train)
    X_test_tfidf  = tfidf.transform(X_test)

    # 6. Train a Logistic Regression classifier
    clf = LogisticRegression(max_iter=1000, random_state=42)
    clf.fit(X_train_tfidf, y_train)

    # 7. Evaluate the model on the test set
    y_pred = clf.predict(X_test_tfidf)
    print("=== Classification Report (Test Set) ===")
    print(classification_report(y_test, y_pred))

    # ---------------------------------------------------------
    # 8. Use the trained model for new data (other universities)
    # ---------------------------------------------------------

    # Load the new unlabeled data
    df_other_uni = pd.read_csv("other_univ_data.csv")
    # Columns assumed to be: ['supplier', 'product_description']

    # Combine supplier + description
    df_other_uni['text_combined'] = df_other_uni['supplier'].astype(str) + ' ' + df_other_uni['product_description'].astype(str)

    # Vectorize using the SAME TF-IDF (do not fit again!)
    df_other_uni_tfidf = tfidf.transform(df_other_uni['text_combined'])

    # Predict using the trained classifier
    df_other_uni['predicted_category'] = clf.predict(df_other_uni_tfidf)

    # Print out some predictions (optional)
    print("\n=== Sample Predictions on Other University Data ===")
    print(df_other_uni[['supplier', 'product_description', 'predicted_category']].head(10))

    # Optionally, save the predictions to a CSV
    df_other_uni.to_csv("other_univ_data_with_predictions.csv", index=False)
    print("\nPredictions saved to 'other_univ_data_with_predictions.csv'.")

if __name__ == "__main__":
    main()
