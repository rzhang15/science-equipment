# 2b_train_chemical_filter.py
"""
Trains a second-stage "bulk chemical / instrument part" filter.

Target problem: the primary classifier misclassifies bulk commodity chemicals
(e.g. "acetonitrile-d6", "puriss toluene") and instrument parts as lab.  These
categories account for ~79% of primary-model false positives on the UT Dallas
hold-out.  A general-purpose classifier trained on all 250k items is dominated
by easy signals (DNA oligos, gloves) and under-trained on the fine chemistry
distinction between "lab reagent" and "bulk chemical".

This filter is trained on a focused subset:
    positive class (flip to non-lab) = irrelevant chemicals + instrument parts
    negative class (keep as lab)     = all label=1 rows (real lab items)

At inference time it runs only on items the primary model labels as lab, and
flips to non-lab when its confidence exceeds BULK_FILTER_THRESHOLD.
"""
import os
import joblib
import pandas as pd
import lightgbm as lgb
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report

import config


BULK_CATEGORY_PREFIXES = ("irrelevant chemicals", "instrument part")


def build_filter_labels(df):
    """Label rows for the second-stage filter.

    Returns a DataFrame restricted to rows usable for training, with a new
    `filter_label` column where 1 = bulk/instrument (flip target) and
    0 = genuine lab item.
    """
    cat = df['category'].fillna('').str.lower()
    is_bulk = cat.str.startswith(BULK_CATEGORY_PREFIXES)
    is_lab = df['label'] == 1

    keep = is_bulk | is_lab
    out = df[keep].copy()
    out['filter_label'] = is_bulk[keep].astype(int).values
    return out


def main():
    print(f"--- Training Bulk-Chemical Filter [Variant: {config.VARIANT}] ---")

    df = pd.read_parquet(config.PREPARED_DATA_PATH)
    print(f"  - Loaded {len(df):,} prepared rows")

    df_f = build_filter_labels(df)
    n_pos = int(df_f['filter_label'].sum())
    n_neg = len(df_f) - n_pos
    print(f"  - Filter training set: {len(df_f):,} rows "
          f"({n_pos:,} bulk/instrument, {n_neg:,} lab)")

    descriptions = df_f[config.CLEAN_DESC_COL].fillna('').map(config.clean_for_model)
    y = df_f['filter_label'].values

    X_train_txt, X_test_txt, y_train, y_test = train_test_split(
        descriptions, y, test_size=0.2, random_state=42, stratify=y
    )

    print("  - Fitting TF-IDF vectorizer (word 1-2 grams, min_df=3)...")
    vectorizer = TfidfVectorizer(
        ngram_range=(1, 2),
        min_df=3,
        max_df=0.95,
        sublinear_tf=True,
        stop_words='english',
    )
    X_train = vectorizer.fit_transform(X_train_txt)
    X_test = vectorizer.transform(X_test_txt)
    print(f"    vocab size: {len(vectorizer.vocabulary_):,}")

    print("  - Training LightGBM filter...")
    clf = lgb.LGBMClassifier(
        n_estimators=400,
        learning_rate=0.05,
        num_leaves=63,
        min_child_samples=20,
        feature_fraction=0.8,
        bagging_fraction=0.8,
        bagging_freq=5,
        class_weight='balanced',
        random_state=42,
        n_jobs=-1,
        verbose=-1,
    )
    clf.fit(X_train, y_train)

    print("\n--- Filter evaluation on held-out slice ---")
    y_pred_default = clf.predict(X_test)
    print("At default threshold (0.5):")
    print(classification_report(
        y_test, y_pred_default,
        target_names=["lab (keep)", "bulk/instrument (flip)"]
    ))

    probs = clf.predict_proba(X_test)[:, 1]
    thresh = config.BULK_FILTER_THRESHOLD
    y_pred_thr = (probs >= thresh).astype(int)
    print(f"At BULK_FILTER_THRESHOLD ({thresh}):")
    print(classification_report(
        y_test, y_pred_thr,
        target_names=["lab (keep)", "bulk/instrument (flip)"]
    ))

    model_path = os.path.join(config.OUTPUT_DIR, "bulk_filter.joblib")
    vec_path = os.path.join(config.OUTPUT_DIR, "bulk_filter_vectorizer.joblib")
    joblib.dump(clf, model_path)
    joblib.dump(vectorizer, vec_path)
    print(f"\nSaved filter model to: {model_path}")
    print(f"Saved filter vectorizer to: {vec_path}")


if __name__ == "__main__":
    main()
