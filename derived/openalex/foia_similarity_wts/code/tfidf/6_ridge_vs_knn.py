"""
Head-to-head K-fold holdout: Ridge regression vs top-K weighted-average K-NN,
on identical splits.

Each fold:
  1. Draw the same random train/test partition of the 208 FOIA anchors.
  2. K-NN prediction:  the production recipe from 5_holdout_stress.py
                       (top-K on cosine sim, floor, sharpen, L1-normalize,
                       weighted average of train exposure).
  3. Ridge prediction: RidgeCV over `--alphas` on the train fold to pick alpha
                       (efficient LOO GCV), then Ridge.predict on the test fold.
  4. Also record `max_sim_to_train` for stratifying error curves by
                       "how close is my nearest anchor" — same axis as 5_.

The point is a fair comparison: same folds, same seed, same target file. The
ridge alpha is picked on the training fold only (no leakage from test) and the
K-NN knobs are held at their production defaults.

Output:
  ../../output/ridge_vs_knn_pairs{tag}{out_tag}.csv     per (fold, FOIA) row
                                                        with pred_knn, pred_ridge
  ../../output/ridge_vs_knn_summary{tag}{out_tag}.csv   per method x sim_bin
  ../../output/ridge_vs_knn_overall{tag}{out_tag}.txt   headline comparison
"""
import argparse
import os
import numpy as np
import pandas as pd
import scipy.sparse
from sklearn.linear_model import Ridge, RidgeCV

OUT_DIR = "../../output"
DEFAULT_EXPOSURE_DTA = "../../external/exposure_wts/athr_exposure_hc.dta"
DEFAULT_ALPHAS = np.logspace(-3, 4, 30)


def _paths(tag: str, out_suffix: str = "") -> dict:
    if tag and not tag.startswith("_"):
        tag = "_" + tag
    if out_suffix and not out_suffix.startswith("_"):
        out_suffix = "_" + out_suffix
    return {
        "foia_matrix": f"{OUT_DIR}/tfidf_foia{tag}.npz",
        "foia_ids":    f"{OUT_DIR}/foia_ids_ordered{tag}.csv",
        "out_pairs":   f"{OUT_DIR}/ridge_vs_knn_pairs{tag}{out_suffix}.csv",
        "out_summary": f"{OUT_DIR}/ridge_vs_knn_summary{tag}{out_suffix}.csv",
        "out_overall": f"{OUT_DIR}/ridge_vs_knn_overall{tag}{out_suffix}.txt",
    }


def predict_knn(sim_test_train, E_train, k, sharpen, floor):
    """Top-K sharpened weighted average. Mirrors 5_holdout_stress.predict_holdout
    (which itself mirrors 2_similarity_wts.process_batch)."""
    n_test, n_train = sim_test_train.shape
    k = min(k, n_train)
    topk_idx = np.argpartition(-sim_test_train, k - 1, axis=1)[:, :k]
    rows = np.arange(n_test)[:, None]
    vals = sim_test_train[rows, topk_idx].copy()
    vals = np.where(vals >= floor, vals, 0.0)
    if sharpen != 1.0:
        vals = np.where(vals > 0, np.power(vals, sharpen), 0.0)
    row_sums = vals.sum(axis=1, keepdims=True)
    row_sums = np.where(row_sums > 0, row_sums, 1.0)
    w = vals / row_sums
    E_picked = E_train[topk_idx]
    return (w * E_picked).sum(axis=1)


def predict_ridge(X_train, y_train, X_test, alphas):
    """Pick alpha by GCV on train, predict on test. Returns pred, alpha_chosen."""
    m = RidgeCV(alphas=alphas, fit_intercept=True, scoring=None, cv=None)
    m.fit(X_train, y_train)
    alpha = float(m.alpha_)
    pred = Ridge(alpha=alpha, fit_intercept=True).fit(X_train, y_train).predict(X_test)
    return pred, alpha


def metrics(y_true, y_pred):
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
                    help="FOIA matrix tag (default: 'restricted' matches "
                         "production exposure file).")
    ap.add_argument("--exposure-dta", default=DEFAULT_EXPOSURE_DTA,
                    help="Path to FOIA exposure .dta with columns "
                         "(athr_id, exposure).")
    ap.add_argument("--out-tag", default="",
                    help="Suffix for output filenames so multiple denominators "
                         "coexist. E.g. --out-tag hc.")
    ap.add_argument("--folds", type=int, default=20)
    ap.add_argument("--holdout-frac", type=float, default=0.20)
    ap.add_argument("--k", type=int, default=5,
                    help="Top-K for the K-NN arm, matches 2_similarity_wts.py.")
    ap.add_argument("--sharpen", type=float, default=2.0)
    ap.add_argument("--floor", type=float, default=0.05)
    ap.add_argument("--alphas", nargs="+", type=float, default=None,
                    help="Ridge alpha grid. Default: logspace(-3, 4, 30).")
    ap.add_argument("--seed", type=int, default=8975,
                    help="Match 5_holdout_stress.py default so the K-NN column "
                         "here reproduces the standalone K-NN summary exactly.")
    args = ap.parse_args()

    paths = _paths(args.tag, args.out_tag)
    for p in (paths["foia_matrix"], paths["foia_ids"], args.exposure_dta):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")

    alphas = np.asarray(args.alphas) if args.alphas else DEFAULT_ALPHAS

    print(f"Head-to-head: K-NN (K={args.k} sharpen={args.sharpen} floor={args.floor})  "
          f"vs  Ridge (GCV alpha in [{alphas.min():.3g}, {alphas.max():.3g}], n={len(alphas)})")
    print(f"folds={args.folds}  holdout_frac={args.holdout_frac}  "
          f"tag={args.tag!r}  exposure={args.exposure_dta!r}  seed={args.seed}")

    X = scipy.sparse.load_npz(paths["foia_matrix"]).tocsr().astype(np.float64)
    foia_ids = pd.read_csv(paths["foia_ids"])["athr_id"].astype(str).tolist()
    n = X.shape[0]
    print(f"FOIA pool: {n}   vocab: {X.shape[1]:,}")

    df_exp = pd.read_stata(args.exposure_dta)[["athr_id", "exposure"]]
    df_exp["athr_id"] = df_exp["athr_id"].astype(str)
    E = (pd.Series(df_exp.set_index("athr_id")["exposure"])
         .reindex(foia_ids).fillna(0).values.astype(np.float64))
    print(f"Exposure: mean={E.mean():.4f}  sd={E.std():.4f}  "
          f"range=[{E.min():.4f}, {E.max():.4f}]   nonzero={(E != 0).sum()}/{n}")

    rng = np.random.default_rng(args.seed)
    n_test = int(round(args.holdout_frac * n))
    rows = []

    for f in range(args.folds):
        perm = rng.permutation(n)
        test_idx = np.sort(perm[:n_test])
        train_idx = np.sort(perm[n_test:])
        X_test = X[test_idx]
        X_train = X[train_idx]

        # cosine sim (rows already L2-normalized by 1_vectorize)
        sim = (X_test @ X_train.T).toarray().astype(np.float64)
        max_sim = sim.max(axis=1)

        pred_knn = predict_knn(sim, E[train_idx], args.k, args.sharpen, args.floor)
        pred_ridge, alpha_f = predict_ridge(X_train, E[train_idx], X_test, alphas)

        for j, i in enumerate(test_idx):
            rows.append({
                "fold": f,
                "athr_id": foia_ids[i],
                "n_train": int(len(train_idx)),
                "max_sim_to_train": float(max_sim[j]),
                "true_exposure": float(E[i]),
                "pred_knn": float(pred_knn[j]),
                "pred_ridge": float(pred_ridge[j]),
                "ridge_alpha": alpha_f,
            })

        m_k = metrics(E[test_idx], pred_knn)
        m_r = metrics(E[test_idx], pred_ridge)
        print(f"  fold {f:2d}: alpha={alpha_f:8.4g}  "
              f"KNN MSE={m_k['mse']:.5f} corr={m_k['corr']:+.3f}   "
              f"Ridge MSE={m_r['mse']:.5f} corr={m_r['corr']:+.3f}")

    df = pd.DataFrame(rows)
    df.to_csv(paths["out_pairs"], index=False)
    print(f"\nSaved per-(fold,FOIA) rows: {paths['out_pairs']}")

    # ----- aggregate by max_sim_to_train quintile, side by side -----
    q = np.quantile(df["max_sim_to_train"].values, [0.2, 0.4, 0.6, 0.8])
    df["sim_bin"] = np.digitize(df["max_sim_to_train"].values, q)
    bin_names = {0: "Q1 (most isolated)", 1: "Q2", 2: "Q3", 3: "Q4",
                 4: "Q5 (best matched)"}

    rows_summary = []
    for b in sorted(df["sim_bin"].unique()):
        sub = df[df["sim_bin"] == b]
        for method, col in (("knn", "pred_knn"), ("ridge", "pred_ridge")):
            m = metrics(sub["true_exposure"].values, sub[col].values)
            rows_summary.append({
                "method": method,
                "sim_bin": int(b),
                "label": bin_names[b],
                "max_sim_lo": float(sub["max_sim_to_train"].min()),
                "max_sim_hi": float(sub["max_sim_to_train"].max()),
                **m,
            })
    for method, col in (("knn", "pred_knn"), ("ridge", "pred_ridge")):
        overall = metrics(df["true_exposure"].values, df[col].values)
        rows_summary.append({
            "method": method,
            "sim_bin": -1,
            "label": "ALL",
            "max_sim_lo": float(df["max_sim_to_train"].min()),
            "max_sim_hi": float(df["max_sim_to_train"].max()),
            **overall,
        })

    df_summary = pd.DataFrame(rows_summary)
    df_summary.to_csv(paths["out_summary"], index=False)
    print(f"Saved per-bin summary: {paths['out_summary']}")

    print("\n--- Metrics by max_sim_to_train quintile, KNN vs Ridge ---")
    cols = ["method", "label", "n", "max_sim_lo", "max_sim_hi",
            "mse", "mae", "corr", "slope", "r2"]
    print(df_summary[cols].to_string(index=False))

    # ----- one-line headline -----
    knn_all   = df_summary[(df_summary["method"] == "knn")   & (df_summary["sim_bin"] == -1)].iloc[0]
    ridge_all = df_summary[(df_summary["method"] == "ridge") & (df_summary["sim_bin"] == -1)].iloc[0]
    knn_q1   = df_summary[(df_summary["method"] == "knn")   & (df_summary["sim_bin"] == 0)].iloc[0]
    ridge_q1 = df_summary[(df_summary["method"] == "ridge") & (df_summary["sim_bin"] == 0)].iloc[0]
    knn_q5   = df_summary[(df_summary["method"] == "knn")   & (df_summary["sim_bin"] == 4)].iloc[0]
    ridge_q5 = df_summary[(df_summary["method"] == "ridge") & (df_summary["sim_bin"] == 4)].iloc[0]

    line = (
        f"ridge_vs_knn  tag={args.tag}  exposure={args.exposure_dta}  "
        f"folds={args.folds}  holdout_frac={args.holdout_frac}  "
        f"K={args.k}  sharpen={args.sharpen}  floor={args.floor}\n"
        f"  n_predictions={len(df)}   ridge_alpha median={df['ridge_alpha'].median():.4g}\n"
        f"  OVERALL:              KNN  MSE={knn_all['mse']:.5f} corr={knn_all['corr']:+.3f} r2={knn_all['r2']:+.3f}\n"
        f"                        RIDGE MSE={ridge_all['mse']:.5f} corr={ridge_all['corr']:+.3f} r2={ridge_all['r2']:+.3f}\n"
        f"  Q1 (most isolated):   KNN  MSE={knn_q1['mse']:.5f} corr={knn_q1['corr']:+.3f} r2={knn_q1['r2']:+.3f}\n"
        f"                        RIDGE MSE={ridge_q1['mse']:.5f} corr={ridge_q1['corr']:+.3f} r2={ridge_q1['r2']:+.3f}\n"
        f"  Q5 (best matched):    KNN  MSE={knn_q5['mse']:.5f} corr={knn_q5['corr']:+.3f} r2={knn_q5['r2']:+.3f}\n"
        f"                        RIDGE MSE={ridge_q5['mse']:.5f} corr={ridge_q5['corr']:+.3f} r2={ridge_q5['r2']:+.3f}\n"
    )
    with open(paths["out_overall"], "w") as f:
        f.write(line)
    print(f"\n{line}")
    print(f"Saved overall headline: {paths['out_overall']}")


if __name__ == "__main__":
    main()
