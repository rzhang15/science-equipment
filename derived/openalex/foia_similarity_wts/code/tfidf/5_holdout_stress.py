"""
K-fold holdout-FOIA stress test.

Simulates "what if my anchor set were smaller than 207?" by repeatedly:
  - dropping a random `--holdout-frac` of FOIAs (test)
  - predicting the held-out FOIAs' exposure from the remaining (train) FOIAs
    using the SAME recipe as production (top-K, sharpen, floor, L1-norm)
  - recording (athr_id, fold, max_sim_to_train, true, pred)

This is a stronger generalization test than the LOO sweep because each test
FOIA only has ~165 anchors (not 206) to match against, mimicking the universe
author's situation when their nearest FOIAs are sparse. Reporting metrics
stratified by max_sim_to_train tells you the prediction error curve as a
function of "how close is my nearest anchor".

Note: this re-uses the production-fitted FOIA matrix (so vocab + FOIA-aware
pruning are held fixed). Refitting step 1 per fold is possible but would
change essentially nothing — the universe contribution to vocab fit
dominates 207 FOIA docs; the only fold-dependent piece is FOIA-aware
pruning, which drops features below foia_min_df=2 after holding 20% out.
A separate full-pipeline-refit script can be added if a referee asks.

Output:
  ../../output/holdout_stress_pairs{tag}.csv     per (fold, FOIA) row
  ../../output/holdout_stress_summary{tag}.csv   per max_sim_to_train bin
  ../../output/holdout_stress_overall{tag}.txt   one-line headline numbers
"""
import argparse
import os
import numpy as np
import pandas as pd
import scipy.sparse

OUT_DIR = "../../output"
EXPOSURE_DTA = "../../external/exposure_wts/athr_exposure.dta"


def _paths(tag: str) -> dict:
    if tag and not tag.startswith("_"):
        tag = "_" + tag
    return {
        "foia_matrix": f"{OUT_DIR}/tfidf_foia{tag}.npz",
        "foia_ids":    f"{OUT_DIR}/foia_ids_ordered{tag}.csv",
        "out_pairs":   f"{OUT_DIR}/holdout_stress_pairs{tag}.csv",
        "out_summary": f"{OUT_DIR}/holdout_stress_summary{tag}.csv",
        "out_overall": f"{OUT_DIR}/holdout_stress_overall{tag}.txt",
    }


def predict_holdout(sim_test_train, E_train, k, sharpen, floor):
    """Top-K weighted-average prediction. sim is (n_test, n_train), already
    L2-cosine. Mirrors 2_similarity_wts.process_batch exactly so this test
    speaks to the production recipe."""
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
    return (w * E_picked).sum(axis=1), sim_test_train.max(axis=1)


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
    ap.add_argument("--folds", type=int, default=20)
    ap.add_argument("--holdout-frac", type=float, default=0.20)
    ap.add_argument("--k", type=int, default=5,
                    help="Top-K, matches 2_similarity_wts.py default.")
    ap.add_argument("--sharpen", type=float, default=2.0)
    ap.add_argument("--floor", type=float, default=0.05)
    ap.add_argument("--seed", type=int, default=8975)
    args = ap.parse_args()

    paths = _paths(args.tag)
    for p in (paths["foia_matrix"], paths["foia_ids"], EXPOSURE_DTA):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")

    print(f"Recipe: K={args.k}  sharpen={args.sharpen}  floor={args.floor}  "
          f"holdout_frac={args.holdout_frac}  folds={args.folds}  tag={args.tag!r}")

    X = scipy.sparse.load_npz(paths["foia_matrix"]).tocsr().astype(np.float32)
    foia_ids = pd.read_csv(paths["foia_ids"])["athr_id"].astype(str).tolist()
    n = X.shape[0]
    print(f"FOIA pool: {n}   vocab: {X.shape[1]:,}")

    df_exp = pd.read_stata(EXPOSURE_DTA)[["athr_id", "exposure"]]
    df_exp["athr_id"] = df_exp["athr_id"].astype(str)
    E = pd.Series(df_exp.set_index("athr_id")["exposure"]).reindex(foia_ids).fillna(0).values.astype(np.float32)
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
        sim = (X_test @ X_train.T).toarray().astype(np.float32)
        pred, max_sim = predict_holdout(sim, E[train_idx], args.k, args.sharpen, args.floor)

        for j, i in enumerate(test_idx):
            rows.append({
                "fold": f,
                "athr_id": foia_ids[i],
                "n_train": int(len(train_idx)),
                "max_sim_to_train": float(max_sim[j]),
                "true_exposure": float(E[i]),
                "pred_exposure": float(pred[j]),
            })

        m = metrics(E[test_idx], pred)
        print(f"  fold {f:2d}: n_test={len(test_idx)}  MSE={m['mse']:.5f}  "
              f"corr={m['corr']:.3f}  slope={m['slope']:.3f}")

    df = pd.DataFrame(rows)
    df.to_csv(paths["out_pairs"], index=False)
    print(f"Saved per-(fold,FOIA) rows: {paths['out_pairs']}")

    # ----- aggregate by max_sim_to_train bin -----
    # Use quintiles of max_sim_to_train. The lowest quintile = FOIAs whose
    # nearest train anchor is far away — these are the analog of universe
    # authors with weak imputations.
    q = np.quantile(df["max_sim_to_train"].values, [0.2, 0.4, 0.6, 0.8])
    df["sim_bin"] = np.digitize(df["max_sim_to_train"].values, q)
    bin_names = {0: "Q1 (most isolated)", 1: "Q2", 2: "Q3", 3: "Q4",
                 4: "Q5 (best matched)"}

    rows_summary = []
    for b in sorted(df["sim_bin"].unique()):
        sub = df[df["sim_bin"] == b]
        m = metrics(sub["true_exposure"].values, sub["pred_exposure"].values)
        rows_summary.append({
            "sim_bin": int(b),
            "label": bin_names[b],
            "max_sim_lo": float(sub["max_sim_to_train"].min()),
            "max_sim_hi": float(sub["max_sim_to_train"].max()),
            **m,
        })
    overall = metrics(df["true_exposure"].values, df["pred_exposure"].values)
    rows_summary.append({"sim_bin": -1, "label": "ALL",
                         "max_sim_lo": float(df["max_sim_to_train"].min()),
                         "max_sim_hi": float(df["max_sim_to_train"].max()),
                         **overall})

    df_summary = pd.DataFrame(rows_summary)
    df_summary.to_csv(paths["out_summary"], index=False)
    print(f"Saved per-bin summary: {paths['out_summary']}")

    print("\n--- Metrics by max_sim_to_train quintile ---")
    cols = ["label", "n", "max_sim_lo", "max_sim_hi", "mse", "mae",
            "corr", "slope", "r2"]
    print(df_summary[cols].to_string(index=False))

    # ----- one-line headline -----
    n_unique_foia = df["athr_id"].nunique()
    n_obs = len(df)
    line = (
        f"holdout_stress  tag={args.tag}  folds={args.folds}  "
        f"holdout_frac={args.holdout_frac}  K={args.k}  sharpen={args.sharpen}\n"
        f"  n_unique_FOIAs_tested={n_unique_foia}/{n}   n_predictions={n_obs}\n"
        f"  OVERALL:  MSE={overall['mse']:.5f}  MAE={overall['mae']:.5f}  "
        f"corr={overall['corr']:.3f}  slope={overall['slope']:.3f}  "
        f"r2={overall['r2']:.3f}\n"
        f"  Q1 (most isolated):  MSE={rows_summary[0]['mse']:.5f}  "
        f"corr={rows_summary[0]['corr']:.3f}  slope={rows_summary[0]['slope']:.3f}\n"
        f"  Q5 (best matched):   MSE={rows_summary[-2]['mse']:.5f}  "
        f"corr={rows_summary[-2]['corr']:.3f}  slope={rows_summary[-2]['slope']:.3f}\n"
    )
    with open(paths["out_overall"], "w") as f:
        f.write(line)
    print(f"\n{line}")
    print(f"Saved overall headline: {paths['out_overall']}")


if __name__ == "__main__":
    main()
