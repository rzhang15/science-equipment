"""
Grid sweep over LR hyperparameters and decision threshold to find a better
operating point for a chosen embedding (tfidf / minilm / specter2).

Reuses the existing embeddings on disk (no 1b refit) and the same stratified
hold-out split that 2_train_binary_classifier.py uses (random_state=42,
test_size=0.2).  Sweeps:
  - LogisticRegression C
  - LogisticRegression class_weight
  - decision threshold (corresponds to config.PREDICTION_THRESHOLD at
    inference time)

Writes the full results table to
output/<variant>/param_sweep_results_<model>.csv and prints the top
configurations by macro F1.

Usage:
    PIPELINE_VARIANT=umich_supplier python sweep_params.py tfidf
    PIPELINE_VARIANT=umich_supplier python sweep_params.py minilm

After picking a winner, update:
  - C and class_weight   -> 2_train_binary_classifier.py (the LR call)
  - threshold            -> config.PREDICTION_THRESHOLD
and rerun 2 / 3 / 5 to confirm the gain transfers through the hybrid model.

Caveat: this sweep evaluates the raw LR head, not the full HybridClassifier
(seed/anti-seed/supplier-prior overrides are not applied).  It identifies
the LR operating point most likely to be a good foundation; the hybrid
overrides will then further refine it.  See conversation transcript for
the script-2 vs sweep number divergence: rule-decided rows are unchanged
by LR tuning.
"""
import os
import argparse
import joblib
import pandas as pd
from itertools import product
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import precision_recall_fscore_support

import config


def main(embedding_name):
    print(f"--- LR Hyperparameter Sweep [Variant: {config.VARIANT}, model: {embedding_name}] ---\n")

    emb_path = os.path.join(config.OUTPUT_DIR, f"embeddings_{embedding_name}.joblib")
    if not os.path.exists(emb_path):
        raise SystemExit(
            f"Embeddings not found: {emb_path}\n"
            f"  Run: python 1b_create_text_embeddings.py {embedding_name}"
        )
    X = joblib.load(emb_path)
    if hasattr(X, 'tocsr'):
        X = X.tocsr()
    df = pd.read_parquet(config.PREPARED_DATA_PATH)
    print(f"  Embeddings: {X.shape[0]} rows x {X.shape[1]} features")

    df_train, df_test = train_test_split(
        df, test_size=0.2, random_state=42, stratify=df['label']
    )
    X_train = X[df_train.index]
    X_test  = X[df_test.index]
    y_train = df_train['label'].values
    y_test  = df_test['label'].values
    print(f"  Train: {X_train.shape[0]:>6}  Test: {X_test.shape[0]:>6}\n")

    # Grid — tune these if the first sweep suggests a different neighborhood
    Cs = [0.3, 1.0, 3.0, 10.0]
    class_weights = [
        ('balanced',     'balanced'),
        ('equal',        {0: 1.0, 1: 1.0}),
        ('precision_++', {0: 1.5, 1: 1.0}),  # punish FP harder
        ('recall_++',    {0: 1.0, 1: 1.5}),  # punish FN harder
    ]
    thresholds = [0.4, 0.5, 0.6, 0.7, 0.8]

    rows = []
    for C, (cw_name, cw) in product(Cs, class_weights):
        clf = LogisticRegression(
            C=C, class_weight=cw, max_iter=1000,
            solver='liblinear', random_state=42,
        )
        clf.fit(X_train, y_train)
        proba = clf.predict_proba(X_test)[:, 1]

        for thr in thresholds:
            y_pred = (proba >= thr).astype(int)
            p, r, f, _ = precision_recall_fscore_support(
                y_test, y_pred, labels=[0, 1], zero_division=0
            )
            row = {
                'C': C, 'class_weight': cw_name, 'threshold': thr,
                'P_nonlab': round(p[0], 4), 'R_nonlab': round(r[0], 4), 'F1_nonlab': round(f[0], 4),
                'P_lab':    round(p[1], 4), 'R_lab':    round(r[1], 4), 'F1_lab':    round(f[1], 4),
                'macro_F1': round((f[0] + f[1]) / 2, 4),
            }
            rows.append(row)

    df_results = pd.DataFrame(rows).sort_values('macro_F1', ascending=False).reset_index(drop=True)
    out_path = os.path.join(config.OUTPUT_DIR, f"param_sweep_results_{embedding_name}.csv")
    df_results.to_csv(out_path, index=False)
    print(f"Full results saved to: {out_path}\n")

    print("Top 15 by macro F1:")
    print(df_results.head(15).to_string(index=False))

    # Current production config for reference
    cur_thr = getattr(config, 'PREDICTION_THRESHOLD', 0.7)
    print(f"\nCurrent production: C=1.0, class_weight='balanced', threshold={cur_thr}")
    cur = df_results[
        (df_results['C'] == 1.0)
        & (df_results['class_weight'] == 'balanced')
        & (df_results['threshold'] == cur_thr)
    ]
    if len(cur):
        print(cur.to_string(index=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    choices = ['tfidf'] + list(config.BERT_MODELS.keys())
    parser.add_argument(
        "embedding_name", type=str, choices=choices,
        help=f"Which embedding to sweep against. One of: {choices}"
    )
    args = parser.parse_args()
    main(args.embedding_name)
