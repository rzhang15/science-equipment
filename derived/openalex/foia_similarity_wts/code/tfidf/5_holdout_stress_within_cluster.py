"""
Holdout-FOIA stress test for within-cluster imputation.

Same as 5_holdout_stress.py but on the within-cluster approach:
  - Drop 20% of FOIAs (stratified by cluster)
  - Predict held-out FOIAs using remaining FOIAs *in the same cluster*
  - Record metrics per cluster

This validates that within-cluster imputation actually improves signal.

Usage:
  python 5_holdout_stress_within_cluster.py --tag restricted --folds 20

Output:
  output/holdout_stress_pairs_within_cluster_{tag}.csv
  output/holdout_stress_summary_within_cluster_{tag}.csv
  output/holdout_stress_overall_within_cluster_{tag}.txt
"""
import argparse
import os
import numpy as np
import pandas as pd
import scipy.sparse

OUT_DIR = "../../output"
EXPOSURE_DTA = "../../external/exposure_wts/athr_exposure.dta"


def predict_within_cluster(sim_test_in_cluster, E_train_in_cluster, k, sharpen, floor):
    """Top-K weighted-average prediction using only in-cluster FOIAs."""
    n_test = sim_test_in_cluster.shape[0]
    n_train = sim_test_in_cluster.shape[1]
    k = min(k, n_train)

    if k < 1 or n_train < 1:
        return np.zeros(n_test), np.zeros(n_test)

    # Top-K
    topk_idx = np.argpartition(-sim_test_in_cluster, k - 1, axis=1)[:, :k]
    rows = np.arange(n_test)[:, None]
    vals = sim_test_in_cluster[rows, topk_idx].copy()

    # Floor
    vals = np.where(vals >= floor, vals, 0.0)

    # Sharpen
    if sharpen != 1.0:
        vals = np.where(vals > 0, np.power(vals, sharpen), 0.0)

    # L1 normalize
    row_sums = vals.sum(axis=1, keepdims=True)
    row_sums = np.where(row_sums > 0, row_sums, 1.0)
    w = vals / row_sums

    E_picked = E_train_in_cluster[topk_idx]
    pred = (w * E_picked).sum(axis=1)
    max_sim = sim_test_in_cluster.max(axis=1)

    return pred, max_sim


def metrics(y_true, y_pred):
    """Compute regression metrics."""
    mask = np.isfinite(y_true) & np.isfinite(y_pred)
    y_true, y_pred = y_true[mask], y_pred[mask]
    err = y_true - y_pred
    ss_res = float(np.sum(err ** 2))
    ss_tot = float(np.sum((y_true - y_true.mean()) ** 2))
    if len(y_true) < 2:
        return {"n": int(len(y_true)), "mse": np.nan, "mae": np.nan,
                "corr": np.nan, "r2": np.nan, "slope": np.nan}
    return {
        "n": int(len(y_true)),
        "mse": float(np.mean(err ** 2)),
        "mae": float(np.mean(np.abs(err))),
        "corr": float(np.corrcoef(y_true, y_pred)[0, 1]),
        "r2": float(1 - ss_res / ss_tot) if ss_tot > 0 else np.nan,
        "slope": float(np.polyfit(y_true, y_pred, 1)[0]),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="restricted",
                    help="Tag for within-cluster outputs (default 'restricted').")
    ap.add_argument("--folds", type=int, default=20)
    ap.add_argument("--holdout-frac", type=float, default=0.20)
    ap.add_argument("--k", type=int, default=5)
    ap.add_argument("--sharpen", type=float, default=2.0)
    ap.add_argument("--floor", type=float, default=0.05)
    ap.add_argument("--seed", type=int, default=8975)
    args = ap.parse_args()

    tag = args.tag
    if tag and not tag.startswith("_"):
        tag = "_" + tag

    # Paths
    foia_clusters_path = f"{OUT_DIR}/foia_clusters_K15{tag}.csv"
    tfidf_foia_path = f"{OUT_DIR}/tfidf_foia{tag}.npz"
    foia_ids_path = f"{OUT_DIR}/foia_ids_ordered{tag}.csv"

    out_pairs = f"{OUT_DIR}/holdout_stress_pairs_within_cluster{tag}.csv"
    out_summary = f"{OUT_DIR}/holdout_stress_summary_within_cluster{tag}.csv"
    out_overall = f"{OUT_DIR}/holdout_stress_overall_within_cluster{tag}.txt"

    # Check inputs
    for p in (foia_clusters_path, tfidf_foia_path, foia_ids_path, EXPOSURE_DTA):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")

    print(f"Recipe: K={args.k}  sharpen={args.sharpen}  floor={args.floor}  "
          f"holdout_frac={args.holdout_frac}  folds={args.folds}  within-cluster")

    # Load data
    print("Loading data...")
    foia_clusters = pd.read_csv(foia_clusters_path)
    X = scipy.sparse.load_npz(tfidf_foia_path).tocsr().astype(np.float32)
    foia_ids = pd.read_csv(foia_ids_path)["athr_id"].astype(str).tolist()
    df_exp = pd.read_stata(EXPOSURE_DTA)[["athr_id", "exposure"]]
    df_exp["athr_id"] = df_exp["athr_id"].astype(str)
    E = pd.Series(df_exp.set_index("athr_id")["exposure"]).reindex(foia_ids).fillna(0).values.astype(np.float32)

    print(f"  FOIAs: {len(foia_ids)}, clusters: {foia_clusters['cluster'].max() + 1}")
    print(f"  Exposure: mean={E.mean():.4f}  sd={E.std():.4f}")

    # Build per-cluster FOIA lists
    cluster_to_indices = {}
    for c in foia_clusters['cluster'].unique():
        cluster_to_indices[c] = np.where(foia_clusters['cluster'] == c)[0]

    rng = np.random.default_rng(args.seed)
    rows = []

    # Per-fold holdout within cluster
    for f in range(args.folds):
        print(f"Fold {f+1}/{args.folds}...")

        # Collect predictions across all clusters
        for cluster_id in sorted(cluster_to_indices.keys()):
            cluster_indices = cluster_to_indices[cluster_id]
            n_cluster = len(cluster_indices)

            if n_cluster < 2:
                continue  # Can't holdout from single-FOIA cluster

            # Holdout within this cluster
            n_test = max(1, int(round(args.holdout_frac * n_cluster)))
            perm = rng.permutation(n_cluster)
            test_local_idx = np.sort(perm[:n_test])
            train_local_idx = np.sort(perm[n_test:])

            test_idx = cluster_indices[test_local_idx]
            train_idx = cluster_indices[train_local_idx]

            X_test = X[test_idx]
            X_train = X[train_idx]

            # Cosine sim (rows already L2-normalized)
            sim = (X_test @ X_train.T).toarray().astype(np.float32)
            pred, max_sim = predict_within_cluster(sim, E[train_idx], args.k, args.sharpen, args.floor)

            # Record
            for j, i in enumerate(test_idx):
                rows.append({
                    "fold": f,
                    "cluster": cluster_id,
                    "athr_id": foia_ids[i],
                    "n_train": int(len(train_idx)),
                    "max_sim_to_train": float(max_sim[j]),
                    "true_exposure": float(E[i]),
                    "pred_exposure": float(pred[j]),
                })

    df = pd.DataFrame(rows)
    df.to_csv(out_pairs, index=False)
    print(f"Saved per-(fold,FOIA): {out_pairs}")

    # Aggregate by cluster
    rows_summary = []
    for cluster_id in sorted(cluster_to_indices.keys()):
        sub = df[df['cluster'] == cluster_id]
        if len(sub) > 0:
            m = metrics(sub["true_exposure"].values, sub["pred_exposure"].values)
            rows_summary.append({
                "cluster": int(cluster_id),
                "n_foias_in_cluster": int(len(cluster_to_indices[cluster_id])),
                **m
            })

    overall = metrics(df["true_exposure"].values, df["pred_exposure"].values)
    rows_summary.append({
        "cluster": -1,
        "n_foias_in_cluster": -1,
        **overall
    })

    df_summary = pd.DataFrame(rows_summary)
    df_summary.to_csv(out_summary, index=False)
    print(f"Saved per-cluster summary: {out_summary}")

    print("\n--- Metrics by cluster ---")
    cols = ["cluster", "n_foias_in_cluster", "n", "mse", "mae", "corr", "slope", "r2"]
    print(df_summary[cols].to_string(index=False))

    # Overall headline
    line = (
        f"holdout_stress_within_cluster  tag={args.tag}  folds={args.folds}\n"
        f"  K={args.k}  sharpen={args.sharpen}  floor={args.floor}\n"
        f"  n_predictions={len(df)}\n"
        f"  OVERALL:  MSE={overall['mse']:.5f}  MAE={overall['mae']:.5f}  "
        f"corr={overall['corr']:.3f}  slope={overall['slope']:.3f}  "
        f"r2={overall['r2']:.3f}\n"
    )
    with open(out_overall, "w") as f:
        f.write(line)
    print(f"\n{line}")
    print(f"Saved overall: {out_overall}")


if __name__ == "__main__":
    main()
