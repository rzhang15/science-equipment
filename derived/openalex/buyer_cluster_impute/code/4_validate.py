"""
Validate the BERT -> buyer-cluster -> exposure imputation path.

Two metrics, both fold-aware (no train/test leakage):

  (1) 5-fold CV cluster accuracy
      Can BERT predict the NMF top-1 cluster label?  Chance = 1 / K_eff.
      This is the same number 3_train_classifier.py prints, recomputed here
      so the full validation report is self-contained.

  (2) Leave-one-out exposure correlation, vs cosine baseline
      For each FOIA author i:
        - retrain the classifier on the other N-1 authors (BERT -> top1)
        - predict mixture p_i from BERT[i]
        - recompute per-cluster exposure means using NMF W weights on the
          held-in authors only:  mean_k = sum_{j!=i} W[j,k]*E[j] / sum_{j!=i} W[j,k]
        - E_imp[i] = p_i . mean
      Compare to the cosine baseline: top-K BERT-cosine neighbors of i
      (excluding i), exposure-weighted by similarity.

  Why this baseline: the cluster pivot is only worth keeping if it beats
  the simpler direct-cosine path. If cosine wins, the buyer-clusters add
  nothing for exposure prediction and we should skip the pivot.

Output: ../output/validate_report.txt
        ../output/figs/validate_loov.png
"""
import json
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import StratifiedKFold, cross_val_score
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline
from sklearn.metrics import r2_score
import config as cfg


COSINE_K = 20  # neighbor count for cosine baseline (per the best-K result in foia_similarity_wts/bert)


def build_pipeline(C: float = 0.3) -> Pipeline:
    return Pipeline([
        ("scale", StandardScaler(with_mean=True, with_std=True)),
        ("lr", LogisticRegression(max_iter=2000, C=C, solver="lbfgs",
                                  class_weight="balanced", random_state=cfg.RNG_SEED)),
    ])


def load_aligned():
    """Return BERT embeddings, NMF mixture W, top-1 labels, exposure, all aligned by athr_id."""
    emb = np.load(cfg.BERT_EMB)
    bert_ids = pd.read_csv(cfg.BERT_IDS, dtype={"athr_id": str})["athr_id"].tolist()

    auth = pd.read_csv(cfg.OUT / "buyer_authors.csv", dtype={"athr_id": str})
    W_all = np.load(cfg.OUT / "buyer_W.npy")            # (A, K) aligned to buyer_authors row order
    assert W_all.shape[0] == len(auth), "W rows must match buyer_authors rows"
    auth["nmf_row"] = np.arange(len(auth))              # remember NMF row before filtering

    exp = pd.read_stata(cfg.EXPOSURE_DTA)
    exp["athr_id"] = exp["athr_id"].astype(str)

    bert_pos = {a: i for i, a in enumerate(bert_ids)}
    auth["bert_idx"] = auth["athr_id"].map(bert_pos)
    auth = auth.merge(exp[["athr_id", "exposure"]], on="athr_id", how="left")

    keep = auth["bert_idx"].notna() & auth["exposure"].notna()
    sub = auth.loc[keep].reset_index(drop=True)

    X = emb[sub["bert_idx"].astype(int).values]
    W = W_all[sub["nmf_row"].astype(int).values]
    y = sub["top1_cluster"].astype(int).values
    E = sub["exposure"].astype(float).values
    print(f"aligned: {len(sub)} authors with BERT + exposure (of {len(auth)} cluster authors)")
    return X, W, y, E, sub["athr_id"].tolist()


def fivefold_cluster_accuracy(X: np.ndarray, y: np.ndarray) -> tuple[float, float, np.ndarray]:
    """5-fold CV accuracy on top-1 cluster labels. Drops classes with <5 examples (need 1 per fold)."""
    counts = np.bincount(y, minlength=cfg.K)
    keep_classes = np.where(counts >= 5)[0]
    mask = np.isin(y, keep_classes)
    Xk, yk = X[mask], y[mask]
    print(f"  cluster-acc: keeping {len(keep_classes)}/{cfg.K} clusters "
          f"(>=5 ex each) -> {mask.sum()}/{len(y)} authors")
    skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=cfg.RNG_SEED)
    scores = cross_val_score(build_pipeline(), Xk, yk, cv=skf, scoring="accuracy", n_jobs=-1)
    chance = 1.0 / len(keep_classes)
    return float(scores.mean()), chance, scores


def loov_cluster_imputation(X: np.ndarray, W: np.ndarray, y: np.ndarray, E: np.ndarray) -> np.ndarray:
    """For each author i, refit classifier on the rest, recompute per-cluster
    exposure means without i, predict mixture from BERT[i], impute exposure."""
    n = X.shape[0]
    E_pred = np.full(n, np.nan)

    # Restrict to classifier-trainable classes (>=3 ex globally, classifier requires per-fold presence)
    counts = np.bincount(y, minlength=cfg.K)
    train_classes = np.where(counts >= 3)[0]
    train_mask_global = np.isin(y, train_classes)

    cluster_weighted_E = (W * E[:, None]).sum(axis=0)   # (K,) numerator
    cluster_weighted_N = W.sum(axis=0)                  # (K,) denominator

    for i in range(n):
        train_idx = np.arange(n) != i
        # only train on authors whose label is in train_classes
        ti = train_idx & train_mask_global
        if not ti.any():
            continue
        clf = build_pipeline()
        clf.fit(X[ti], y[ti])
        # mixture for i: align classifier's classes_ back to K-vector
        proba_classes = clf.predict_proba(X[i:i+1])[0]
        p = np.zeros(cfg.K)
        for c_idx, c_lab in enumerate(clf.classes_):
            p[c_lab] = proba_classes[c_idx]

        # per-cluster exposure mean excluding i
        num_i = cluster_weighted_E - W[i] * E[i]
        den_i = cluster_weighted_N - W[i]
        mean_k = np.where(den_i > 1e-9, num_i / np.maximum(den_i, 1e-9), 0.0)

        E_pred[i] = float((p * mean_k).sum())
        if (i + 1) % 25 == 0:
            print(f"    loov cluster: {i+1}/{n}")
    return E_pred


def loov_cosine_baseline(X: np.ndarray, E: np.ndarray, k: int) -> np.ndarray:
    """Top-K cosine-neighbor exposure mean (leave-one-out)."""
    # L2-normalize for cosine
    Xn = X / np.linalg.norm(X, axis=1, keepdims=True).clip(min=1e-9)
    sim = Xn @ Xn.T
    np.fill_diagonal(sim, -np.inf)
    n = X.shape[0]
    E_pred = np.zeros(n)
    for i in range(n):
        row = sim[i].copy()
        top = np.argpartition(row, -k)[-k:]
        w = np.clip(row[top], 0.0, None)
        s = w.sum()
        E_pred[i] = float((w @ E[top]) / s) if s > 0 else 0.0
    return E_pred


def main():
    cfg.FIG.mkdir(parents=True, exist_ok=True)

    X, W, y, E, ids = load_aligned()

    print("\n--- (1) 5-fold CV cluster accuracy ---")
    cv_mean, chance, cv_scores = fivefold_cluster_accuracy(X, y)
    print(f"  mean acc = {cv_mean:.3f}   chance = {chance:.3f}   "
          f"folds = [{', '.join(f'{s:.3f}' for s in cv_scores)}]")

    print("\n--- (2) LOOV exposure (cluster path) ---")
    E_cluster = loov_cluster_imputation(X, W, y, E)
    valid = ~np.isnan(E_cluster)
    r_clu = float(np.corrcoef(E_cluster[valid], E[valid])[0, 1])
    r2_clu = float(r2_score(E[valid], E_cluster[valid]))
    print(f"  N={valid.sum()}   r={r_clu:.4f}   R2={r2_clu:.4f}")

    print(f"\n--- (3) LOOV exposure (cosine baseline, K={COSINE_K}) ---")
    E_cos = loov_cosine_baseline(X, E, k=COSINE_K)
    r_cos = float(np.corrcoef(E_cos, E)[0, 1])
    r2_cos = float(r2_score(E, E_cos))
    print(f"  N={len(E)}   r={r_cos:.4f}   R2={r2_cos:.4f}")

    # ----- report -----
    rep_path = cfg.OUT / "validate_report.txt"
    with open(rep_path, "w") as f:
        f.write("BUYER-CLUSTER VALIDATION REPORT\n")
        f.write("================================\n\n")
        f.write(f"N FOIA authors (BERT + exposure): {len(E)}\n")
        f.write(f"K (NMF components):                {cfg.K}\n\n")
        f.write("(1) 5-fold CV cluster accuracy\n")
        f.write(f"    mean   = {cv_mean:.4f}\n")
        f.write(f"    chance = {chance:.4f}\n")
        f.write(f"    folds  = [{', '.join(f'{s:.3f}' for s in cv_scores)}]\n\n")
        f.write("(2) LOOV exposure correlation (cluster path)\n")
        f.write(f"    N={int(valid.sum())}   r={r_clu:.4f}   R2={r2_clu:.4f}\n\n")
        f.write(f"(3) LOOV exposure correlation (cosine baseline, K={COSINE_K})\n")
        f.write(f"    N={len(E)}   r={r_cos:.4f}   R2={r2_cos:.4f}\n\n")
        f.write("Verdict\n")
        verdict = ("cluster path beats cosine" if r_clu > r_cos
                   else "cosine baseline beats cluster path")
        f.write(f"    Delta r (cluster - cosine) = {r_clu - r_cos:+.4f}   -> {verdict}\n")
    print(f"\nWrote {rep_path}")

    # ----- json for machine readers -----
    with open(cfg.OUT / "validate_metrics.json", "w") as f:
        json.dump({"n": int(len(E)), "K": cfg.K,
                   "cv_cluster_accuracy_mean": cv_mean, "cv_chance": chance,
                   "cv_fold_scores": [float(s) for s in cv_scores],
                   "loov_cluster_r": r_clu, "loov_cluster_r2": r2_clu,
                   "loov_cosine_r": r_cos, "loov_cosine_r2": r2_cos,
                   "cosine_k": COSINE_K}, f, indent=2)

    # ----- plot -----
    fig, axes = plt.subplots(1, 2, figsize=(12, 5), sharey=True)
    for ax, pred, title, r in [(axes[0], E_cluster[valid], "Cluster path", r_clu),
                                (axes[1], E_cos, f"Cosine baseline (K={COSINE_K})", r_cos)]:
        actual = E[valid] if "Cluster" in title else E
        ax.scatter(pred, actual, alpha=0.5, s=20)
        lo, hi = float(min(pred.min(), actual.min())), float(max(pred.max(), actual.max()))
        ax.plot([lo, hi], [lo, hi], "r--", alpha=0.5)
        ax.set_xlabel("imputed exposure"); ax.set_title(f"{title}\nr={r:.3f}")
        ax.grid(True, linestyle="--", alpha=0.4)
    axes[0].set_ylabel("actual exposure")
    fig.suptitle(f"LOOV exposure imputation  (N={len(E)})")
    fig.tight_layout()
    fig.savefig(cfg.FIG / "validate_loov.png", dpi=120)
    plt.close(fig)
    print(f"Wrote {cfg.FIG}/validate_loov.png")


if __name__ == "__main__":
    main()
