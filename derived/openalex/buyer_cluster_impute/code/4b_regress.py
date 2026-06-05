"""
Direct BERT -> exposure regression baselines, for comparison against
4_validate.py's cosine-neighbor and cluster-pivot LOOV numbers.

Three models, all evaluated leave-one-out on the same 203 FOIA authors:
  (A) Ridge on BERT only
  (B) kNN-regression on BERT (cosine distance, k=20)  -- sklearn analogue of
      the cosine baseline in 4_validate.py, included as a sanity check
  (C) Ridge on [BERT || cluster_mixture]              -- does the cluster
      probability vector carry marginal info beyond BERT?

Ridge alpha is picked by inner 5-fold CV on the training set within each LOO
fold (no leakage of i into its own alpha selection).

Output: ../output/validate_regress_report.txt
        appends rows to ../output/validate_metrics.json under "regression"
        ../output/figs/validate_regress.png
"""
import json
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from sklearn.linear_model import RidgeCV
from sklearn.neighbors import KNeighborsRegressor
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline
from sklearn.metrics import r2_score
import config as cfg

# reuse the data loader from 4_validate.py so alignment matches exactly
from importlib import import_module
v = import_module("4_validate")


ALPHAS = [0.1, 1.0, 10.0, 100.0, 1000.0]
KNN_K = 20  # match the cosine-baseline K in 4_validate.py


def build_ridge() -> Pipeline:
    return Pipeline([
        ("scale", StandardScaler(with_mean=True, with_std=True)),
        ("ridge", RidgeCV(alphas=ALPHAS, cv=5)),
    ])


def build_knn() -> Pipeline:
    return Pipeline([
        ("scale", StandardScaler(with_mean=True, with_std=True)),
        # cosine-similarity neighbors: use 'cosine' metric explicitly
        ("knn", KNeighborsRegressor(n_neighbors=KNN_K, metric="cosine", weights="distance")),
    ])


def loov_predict(X: np.ndarray, E: np.ndarray, build_fn) -> np.ndarray:
    n = X.shape[0]
    E_pred = np.zeros(n)
    for i in range(n):
        idx = np.arange(n) != i
        m = build_fn()
        m.fit(X[idx], E[idx])
        E_pred[i] = float(m.predict(X[i:i+1])[0])
        if (i + 1) % 25 == 0:
            print(f"    loov: {i+1}/{n}")
    return E_pred


def evaluate(name: str, E_pred: np.ndarray, E: np.ndarray) -> tuple[float, float]:
    r = float(np.corrcoef(E_pred, E)[0, 1])
    r2 = float(r2_score(E, E_pred))
    print(f"  {name:>32}   r={r:+.4f}   R2={r2:+.4f}")
    return r, r2


def main():
    cfg.FIG.mkdir(parents=True, exist_ok=True)

    X, W, y, E, ids = v.load_aligned()
    print(f"N={len(E)}  dim(BERT)={X.shape[1]}  K(mixture)={W.shape[1]}")

    # ---- (A) Ridge on BERT ----
    print("\n--- (A) Ridge on BERT only ---")
    E_a = loov_predict(X, E, build_ridge)
    r_a, r2_a = evaluate("Ridge(BERT)", E_a, E)

    # ---- (B) kNN regression on BERT ----
    print(f"\n--- (B) kNN on BERT (cosine, K={KNN_K}) ---")
    E_b = loov_predict(X, E, build_knn)
    r_b, r2_b = evaluate(f"kNN(BERT,K={KNN_K})", E_b, E)

    # ---- (C) Ridge on [BERT || cluster mixture] ----
    print("\n--- (C) Ridge on [BERT || cluster mixture] ---")
    XW = np.hstack([X, W.astype(X.dtype)])
    E_c = loov_predict(XW, E, build_ridge)
    r_c, r2_c = evaluate("Ridge(BERT+mixture)", E_c, E)

    # ---- report ----
    rep_path = cfg.OUT / "validate_regress_report.txt"
    with open(rep_path, "w") as f:
        f.write("DIRECT-REGRESSION VALIDATION REPORT\n")
        f.write("====================================\n\n")
        f.write(f"N FOIA authors: {len(E)}   dim(BERT)={X.shape[1]}   K(mixture)={W.shape[1]}\n")
        f.write(f"Ridge alphas: {ALPHAS}   kNN K: {KNN_K}\n\n")
        f.write(f"(A) Ridge(BERT)           r={r_a:+.4f}   R2={r2_a:+.4f}\n")
        f.write(f"(B) kNN(BERT, K={KNN_K})        r={r_b:+.4f}   R2={r2_b:+.4f}\n")
        f.write(f"(C) Ridge(BERT+mixture)   r={r_c:+.4f}   R2={r2_c:+.4f}\n\n")
        f.write("vs 4_validate.py numbers (same N=203 authors):\n")
        try:
            prev = json.load(open(cfg.OUT / "validate_metrics.json"))
            f.write(f"    cosine baseline (K={prev.get('cosine_k')}): r={prev.get('loov_cosine_r'):+.4f}\n")
            f.write(f"    cluster pivot:                    r={prev.get('loov_cluster_r'):+.4f}\n")
        except Exception as e:
            f.write(f"    (could not load validate_metrics.json: {e})\n")
    print(f"\nWrote {rep_path}")

    # ---- merge metrics into validate_metrics.json ----
    try:
        metrics = json.load(open(cfg.OUT / "validate_metrics.json"))
    except FileNotFoundError:
        metrics = {}
    metrics["regression"] = {
        "ridge_bert":          {"r": r_a, "r2": r2_a, "alphas": ALPHAS},
        "knn_bert":            {"r": r_b, "r2": r2_b, "k": KNN_K},
        "ridge_bert_mixture":  {"r": r_c, "r2": r2_c, "alphas": ALPHAS},
    }
    with open(cfg.OUT / "validate_metrics.json", "w") as f:
        json.dump(metrics, f, indent=2)

    # ---- plot ----
    fig, axes = plt.subplots(1, 3, figsize=(15, 5), sharey=True)
    for ax, pred, title, r in [
        (axes[0], E_a, "Ridge(BERT)", r_a),
        (axes[1], E_b, f"kNN(BERT, K={KNN_K})", r_b),
        (axes[2], E_c, "Ridge(BERT+mixture)", r_c),
    ]:
        ax.scatter(pred, E, alpha=0.5, s=20)
        lo, hi = float(min(pred.min(), E.min())), float(max(pred.max(), E.max()))
        ax.plot([lo, hi], [lo, hi], "r--", alpha=0.5)
        ax.set_xlabel("imputed exposure"); ax.set_title(f"{title}\nr={r:+.3f}")
        ax.grid(True, linestyle="--", alpha=0.4)
    axes[0].set_ylabel("actual exposure")
    fig.suptitle(f"LOOV exposure imputation -- direct regression  (N={len(E)})")
    fig.tight_layout()
    fig.savefig(cfg.FIG / "validate_regress.png", dpi=120)
    plt.close(fig)
    print(f"Wrote {cfg.FIG}/validate_regress.png")


if __name__ == "__main__":
    main()
