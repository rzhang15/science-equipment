"""
Grid sweep over per-source sample weights, holding LR hyperparameters fixed
at the current production values (C=10, class_weight='balanced',
threshold=config.PREDICTION_THRESHOLD).  Each config is a dict of
SOURCE_WEIGHTS-style entries (str or (str, int) keys -> float).

Reuses cached embeddings on disk (no 1b refit) and the same stratified
hold-out split as 2_train_binary_classifier.py (random_state=42,
test_size=0.2).

Reports overall macro F1 plus a precision/recall breakdown per data_source
slice so you can see *which* slice each weighting moves.

Usage:
    python sweep_source_weights.py tfidf
    PIPELINE_VARIANT=umich_supplier python sweep_source_weights.py tfidf

Caveat: same as sweep_params.py — this evaluates the raw LR head, not the
full HybridClassifier.  Seed/anti-seed/supplier-prior overrides aren't
applied here, so the absolute numbers will differ from script 2.  But
relative deltas between weight configs transfer through.
"""
import os
import argparse
import joblib
import pandas as pd
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import precision_recall_fscore_support

import config


# ---- Weight grid -------------------------------------------------------------
# Each entry: (name, {source_or_(source,label): weight}).  Anything unlisted
# defaults to 1.0 inside get_sample_weights.
WEIGHT_CONFIGS = [
    ('all_1',
        {}),  # everything at 1.0 — control
    ('starter',
        {'ca_non_lab': 0.5, 'fisher_non_lab': 3.0, 'ut_dallas': 2.0,
         'umich': 2.0, 'fisher_lab': 1.0}),
    ('ca_down_only',
        {'ca_non_lab': 0.5}),
    ('ca_minimal',
        {'ca_non_lab': 0.05, 'fisher_non_lab': 3.0, 'ut_dallas': 2.0,
         'umich': 2.0, 'fisher_lab': 1.0}),
    ('procurement_heavy',
        {'ca_non_lab': 0.25, 'fisher_non_lab': 5.0, 'ut_dallas': 3.0,
         'umich': 3.0, 'fisher_lab': 1.0}),
    ('procurement_extreme',
        {'ca_non_lab': 0.1, 'fisher_non_lab': 5.0, 'ut_dallas': 5.0,
         'umich': 5.0, 'fisher_lab': 1.0}),
    ('equalize_lab_classes',
        # Same as starter but additionally equalize fisher_lab vs ut_dallas
        # at label=1 (57894/21985 ~= 2.63).
        {'ca_non_lab': 0.5, 'fisher_non_lab': 3.0, 'ut_dallas': 2.0,
         'umich': 2.0, 'fisher_lab': 1.0, ('ut_dallas', 1): 2.63,
         ('umich', 1): 2.63}),
    ('fisher_lab_down',
        # Starter but downweight fisher_lab so it doesn't dominate label=1.
        {'ca_non_lab': 0.5, 'fisher_non_lab': 3.0, 'ut_dallas': 2.0,
         'umich': 2.0, 'fisher_lab': 0.5}),
]


def sample_weights_from_dict(weight_dict, data_sources, labels):
    """Same logic as config.get_sample_weights but takes the dict directly
    (lets us iterate without mutating config.SOURCE_WEIGHTS)."""
    src = pd.Series(data_sources).astype(str).reset_index(drop=True)
    lab = pd.Series(labels).astype(int).reset_index(drop=True)
    src_only = {k: float(v) for k, v in weight_dict.items() if isinstance(k, str)}
    weights = src.map(src_only).fillna(1.0).to_numpy(dtype=float)
    for key, w in weight_dict.items():
        if isinstance(key, tuple) and len(key) == 2:
            s, l = key
            mask = (src.values == s) & (lab.values == int(l))
            weights[mask] = float(w)
    return weights


def main(embedding_name):
    print(f"--- SOURCE_WEIGHTS sweep [Variant: {config.VARIANT}, model: {embedding_name}] ---\n")

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
    X_test = X[df_test.index]
    y_train = df_train['label'].values
    y_test = df_test['label'].values
    src_train = df_train['data_source'].astype(str).values
    src_test = df_test['data_source'].astype(str).values
    print(f"  Train: {X_train.shape[0]:>6}  Test: {X_test.shape[0]:>6}")

    threshold = getattr(config, 'PREDICTION_THRESHOLD', 0.5)
    print(f"  Fixed LR: C=10.0, class_weight='balanced', threshold={threshold}\n")

    overall_rows = []
    slice_rows = []
    train_sources = sorted(set(src_train))

    for name, wdict in WEIGHT_CONFIGS:
        sw = sample_weights_from_dict(wdict, src_train, y_train)
        clf = LogisticRegression(
            C=10.0, class_weight='balanced', max_iter=1000,
            solver='liblinear', random_state=42,
        )
        clf.fit(X_train, y_train, sample_weight=sw)
        proba = clf.predict_proba(X_test)[:, 1]
        y_pred = (proba >= threshold).astype(int)

        # Overall metrics (pooled across all sources).
        p, r, f, _ = precision_recall_fscore_support(
            y_test, y_pred, labels=[0, 1], zero_division=0
        )
        overall_rows.append({
            'config': name,
            'P_nonlab': round(p[0], 4), 'R_nonlab': round(r[0], 4), 'F1_nonlab': round(f[0], 4),
            'P_lab':    round(p[1], 4), 'R_lab':    round(r[1], 4), 'F1_lab':    round(f[1], 4),
            'macro_F1': round((f[0] + f[1]) / 2, 4),
            'n_test':   len(y_test),
        })

        # Per-source slice metrics (only sources actually present in test).
        for s in train_sources:
            mask = src_test == s
            n = int(mask.sum())
            if n == 0:
                continue
            yt = y_test[mask]
            yp = y_pred[mask]
            # Skip slices that don't contain both labels — sklearn would warn.
            labels_present = sorted(set(yt))
            p_s, r_s, f_s, _ = precision_recall_fscore_support(
                yt, yp, labels=[0, 1], zero_division=0
            )
            slice_rows.append({
                'config': name,
                'data_source': s,
                'n_test': n,
                'n_nonlab': int((yt == 0).sum()),
                'n_lab':    int((yt == 1).sum()),
                'P_nonlab': round(p_s[0], 4), 'R_nonlab': round(r_s[0], 4),
                'P_lab':    round(p_s[1], 4), 'R_lab':    round(r_s[1], 4),
                'macro_F1': round((f_s[0] + f_s[1]) / 2, 4),
            })

    df_overall = pd.DataFrame(overall_rows).sort_values('macro_F1', ascending=False)
    df_slice = pd.DataFrame(slice_rows)

    overall_out = os.path.join(config.OUTPUT_DIR, f"source_weight_sweep_{embedding_name}.csv")
    slice_out = os.path.join(config.OUTPUT_DIR, f"source_weight_sweep_{embedding_name}_by_source.csv")
    df_overall.to_csv(overall_out, index=False)
    df_slice.to_csv(slice_out, index=False)
    print(f"Overall results: {overall_out}")
    print(f"Per-source slice results: {slice_out}\n")

    print("=== Overall (sorted by macro F1) ===")
    print(df_overall.to_string(index=False))
    print()
    print("=== Per-source slice (precision/recall by data_source) ===")
    if not df_slice.empty:
        # Show a compact pivot: rows = config x source, columns = key metrics.
        for s in train_sources:
            sub = df_slice[df_slice['data_source'] == s]
            if sub.empty:
                continue
            print(f"\n  -- {s} (n_test={sub.iloc[0]['n_test']}, "
                  f"nonlab={sub.iloc[0]['n_nonlab']}, lab={sub.iloc[0]['n_lab']}) --")
            cols = ['config', 'P_nonlab', 'R_nonlab', 'P_lab', 'R_lab', 'macro_F1']
            print(sub[cols].to_string(index=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    choices = ['tfidf'] + list(config.BERT_MODELS.keys())
    parser.add_argument(
        "embedding_name", type=str, choices=choices, nargs='?', default='tfidf',
        help=f"Which embedding to sweep against (default: tfidf). One of: {choices}"
    )
    args = parser.parse_args()
    main(args.embedding_name)
