"""
FOIA leave-one-out validation across multiple k and stratified by how
isolated each FOIA is in topic space.

Why: the existing tfidf/loov.py and bert/loov.py sweep k but report only
correlation, and they aggregate across all FOIAs. Authors who are the
only one of their type in the FOIA pool will always predict badly --
that's a property of kNN imputation, not a model failure. To pick a
defensible k, we need MSE separately on FOIAs that have ≥1 close
neighbor vs those that don't.

What this does:
  1. Loads FOIA embeddings (TF-IDF sparse or BERT dense).
  2. Computes FOIA x FOIA cosine sim, mask diagonal.
  3. For each FOIA, isolation = max cosine sim to any other FOIA. High
     = well-represented in the pool; low = isolated.
  4. For each k in --k-grid, leave-one-out predict every FOIA's exposure
     as a top-k weighted average (optionally sharpened, mirroring the
     production tfidf/2_similarity_wts.py params) of the other FOIAs.
  5. Report MSE / MAE / corr / R^2 overall and by isolation bucket.
  6. Plot MSE-vs-k by isolation bucket -> the k that minimizes MSE on
     well-represented FOIAs is your defensible choice.

Outputs:
  ../output/figures/loov_k_sweep_{method}.png
  ../output/loov_k_sweep_{method}.csv         (per-k overall metrics)
  ../output/loov_k_sweep_by_iso_{method}.csv  (per-(k, iso-bin) metrics)
"""
import argparse
import os
import numpy as np
import pandas as pd
import scipy.sparse
import matplotlib.pyplot as plt

OUT_DIR = "../output"
FIG_DIR = f"{OUT_DIR}/figures"
EXPOSURE_DTA = "../external/exposure_wts/athr_exposure.dta"


def load_foia_sim(method: str, model_tag: str) -> tuple[np.ndarray, list[str]]:
    """Return (sim, foia_ids) where sim is dense (n_foia, n_foia) cosine,
    diagonal masked to -inf."""
    if method == "tfidf":
        X = scipy.sparse.load_npz(f"{OUT_DIR}/tfidf_foia.npz").tocsr().astype(np.float32)
        # Already L2-normalized by tfidf/1_vectorize.py
        sim = (X @ X.T).toarray().astype(np.float32)
        foia_ids = pd.read_csv(f"{OUT_DIR}/foia_ids_ordered.csv")["athr_id"].astype(str).tolist()
    else:
        emb_path = f"{OUT_DIR}/bert_foia_{model_tag}.npy"
        ids_path = f"{OUT_DIR}/bert_foia_ids_{model_tag}.csv"
        X = np.load(emb_path).astype(np.float32)
        norms = np.linalg.norm(X, axis=1, keepdims=True); norms[norms == 0] = 1
        X = X / norms
        sim = (X @ X.T).astype(np.float32)
        foia_ids = pd.read_csv(ids_path)["athr_id"].astype(str).tolist()
    np.fill_diagonal(sim, -np.inf)
    return sim, foia_ids


def predict_loov(sim: np.ndarray, E: np.ndarray, k: int,
                 sharpen: float, floor: float) -> np.ndarray:
    """Top-k weighted average prediction for every row, with the diagonal
    already masked to -inf so the row's own exposure is never used."""
    n = sim.shape[0]
    k = min(k, n - 1)
    # top-k per row (largest values, ignoring -inf diagonal automatically)
    part = np.argpartition(-sim, kth=k - 1, axis=1)[:, :k]
    rows = np.arange(n)[:, None]
    vals = sim[rows, part].copy()
    vals = np.where(vals >= floor, vals, 0.0)
    if sharpen != 1.0:
        vals = np.where(vals > 0, np.power(vals, sharpen), 0.0)
    row_sums = vals.sum(axis=1, keepdims=True)
    row_sums = np.where(row_sums > 0, row_sums, 1.0)
    w = vals / row_sums
    # E[part]: pull each row's selected k neighbors' exposures
    E_picked = E[part]    # (n, k)
    return (w * E_picked).sum(axis=1)


def metrics(y_true: np.ndarray, y_pred: np.ndarray) -> dict:
    err = y_true - y_pred
    ss_res = np.sum(err ** 2)
    ss_tot = np.sum((y_true - y_true.mean()) ** 2)
    return {
        "mse": float(np.mean(err ** 2)),
        "mae": float(np.mean(np.abs(err))),
        "corr": float(np.corrcoef(y_true, y_pred)[0, 1]) if len(y_true) > 1 else np.nan,
        "r2": float(1 - ss_res / ss_tot) if ss_tot > 0 else np.nan,
        "slope": float(np.polyfit(y_true, y_pred, 1)[0]) if len(y_true) > 1 else np.nan,
        "n": int(len(y_true)),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--method", choices=["bert", "tfidf"], default="tfidf")
    ap.add_argument("--model-tag",
                    default="pritamdeka_S-Scibert-snli-multinli-stsb_unstemmed",
                    help="BERT-only: tag used in bert_foia_{tag}.npy filename.")
    ap.add_argument("--k-grid", default="1,3,5,10,15,20,30,50,100",
                    help="Comma-sep k values to sweep.")
    ap.add_argument("--sharpen", type=float, default=1.0,
                    help="Raise cosine sims to this power before normalizing "
                         "(production tfidf uses 2.0).")
    ap.add_argument("--floor", type=float, default=0.0,
                    help="Drop neighbors with cosine sim below this (production "
                         "tfidf uses 0.05).")
    ap.add_argument("--iso-quantiles", default="0.2,0.5,0.8",
                    help="Quantile cutpoints on isolation (=max sim to others). "
                         "Lowest bucket = most isolated FOIAs.")
    args = ap.parse_args()

    os.makedirs(FIG_DIR, exist_ok=True)
    k_grid = [int(k) for k in args.k_grid.split(",")]

    print(f"Method: {args.method}")
    sim, foia_ids = load_foia_sim(args.method, args.model_tag)
    n_foia = sim.shape[0]
    print(f"  FOIA pool: {n_foia}")

    # FOIA exposure aligned to the matrix order (some FOIAs may be missing
    # from athr_exposure.dta -> fillna 0 like production does).
    df_exp = pd.read_stata(EXPOSURE_DTA)[["athr_id", "exposure"]]
    df_exp["athr_id"] = df_exp["athr_id"].astype(str)
    E = pd.Series(df_exp.set_index("athr_id")["exposure"]).reindex(foia_ids).fillna(0).values
    print(f"  exposure: mean={E.mean():.4f}  std={E.std():.4f}  "
          f"range=[{E.min():.4f}, {E.max():.4f}]")

    # isolation metric: each FOIA's max cosine to any other FOIA (so the
    # diagonal-masked sim's row max is the right thing).
    sim_for_iso = np.where(np.isneginf(sim), -1, sim)
    isolation = sim_for_iso.max(axis=1)
    iso_q = [float(q) for q in args.iso_quantiles.split(",")]
    iso_cuts = np.quantile(isolation, iso_q)
    iso_labels = [f"q{int(q*100)}" for q in iso_q] + [f"q{int(iso_q[-1]*100)}+"]
    iso_bin = np.digitize(isolation, iso_cuts)
    bin_names = ["most isolated"] + \
                [f"mid {iso_labels[i]}" for i in range(1, len(iso_labels) - 1)] + \
                ["best connected"]
    print(f"  isolation distribution: min={isolation.min():.3f}  "
          f"median={np.median(isolation):.3f}  max={isolation.max():.3f}")
    for b, name in enumerate(bin_names):
        n_b = (iso_bin == b).sum()
        if n_b:
            print(f"    bin {b} ({name}): n={n_b}  "
                  f"max-sim range=[{isolation[iso_bin == b].min():.3f}, "
                  f"{isolation[iso_bin == b].max():.3f}]")

    # ----- sweep k -----
    overall_rows = []
    bybin_rows = []
    preds_by_k = {}
    for k in k_grid:
        y_pred = predict_loov(sim, E, k, args.sharpen, args.floor)
        preds_by_k[k] = y_pred
        m = metrics(E, y_pred)
        m_overall = {"k": k, **m}
        overall_rows.append(m_overall)
        print(f"k={k:3d}   MSE={m['mse']:.5f}   MAE={m['mae']:.5f}   "
              f"corr={m['corr']:.3f}   slope={m['slope']:.3f}   R2={m['r2']:.3f}")
        for b, name in enumerate(bin_names):
            mask = iso_bin == b
            if mask.sum() < 3:
                continue
            mb = metrics(E[mask], y_pred[mask])
            bybin_rows.append({"k": k, "iso_bin": b, "iso_label": name, **mb})

    df_overall = pd.DataFrame(overall_rows)
    df_bybin = pd.DataFrame(bybin_rows)

    # Pick optimal k separately for each isolation bucket, by MSE.
    print("\nOptimal k (lowest MSE) per isolation bucket:")
    for b, name in enumerate(bin_names):
        sub = df_bybin[df_bybin["iso_bin"] == b]
        if len(sub) == 0:
            continue
        best = sub.loc[sub["mse"].idxmin()]
        print(f"  {name:18s} (n={int(best['n'])}):  best k={int(best['k']):3d}  "
              f"MSE={best['mse']:.5f}  corr={best['corr']:.3f}  slope={best['slope']:.3f}")
    best_overall = df_overall.loc[df_overall["mse"].idxmin()]
    print(f"  {'ALL':18s} (n={int(best_overall['n'])}):  best k={int(best_overall['k']):3d}  "
          f"MSE={best_overall['mse']:.5f}  corr={best_overall['corr']:.3f}  "
          f"slope={best_overall['slope']:.3f}")

    # ----- figure -----
    fig, axes = plt.subplots(2, 2, figsize=(13, 10))

    # (0,0) MSE vs k by isolation bucket + overall
    ax = axes[0, 0]
    for b, name in enumerate(bin_names):
        sub = df_bybin[df_bybin["iso_bin"] == b]
        if len(sub) == 0:
            continue
        ax.plot(sub["k"], sub["mse"], "o-", label=f"{name} (n={int(sub['n'].iloc[0])})")
    ax.plot(df_overall["k"], df_overall["mse"], "k--", lw=2, label=f"ALL (n={n_foia})")
    ax.set_xscale("log")
    ax.set_xlabel("k")
    ax.set_ylabel("LOOV MSE")
    ax.set_title("MSE vs k by FOIA isolation")
    ax.legend(fontsize=8)
    ax.grid(alpha=0.3)

    # (0,1) correlation vs k
    ax = axes[0, 1]
    for b, name in enumerate(bin_names):
        sub = df_bybin[df_bybin["iso_bin"] == b]
        if len(sub) == 0:
            continue
        ax.plot(sub["k"], sub["corr"], "o-", label=name)
    ax.plot(df_overall["k"], df_overall["corr"], "k--", lw=2, label="ALL")
    ax.set_xscale("log")
    ax.set_xlabel("k")
    ax.set_ylabel("LOOV correlation")
    ax.set_title("Correlation vs k")
    ax.legend(fontsize=8)
    ax.grid(alpha=0.3)

    # (1,0) slope vs k -- shows shrinkage
    ax = axes[1, 0]
    for b, name in enumerate(bin_names):
        sub = df_bybin[df_bybin["iso_bin"] == b]
        if len(sub) == 0:
            continue
        ax.plot(sub["k"], sub["slope"], "o-", label=name)
    ax.plot(df_overall["k"], df_overall["slope"], "k--", lw=2, label="ALL")
    ax.axhline(1.0, color="r", ls=":", lw=0.8, alpha=0.5)
    ax.set_xscale("log")
    ax.set_xlabel("k")
    ax.set_ylabel("OLS slope (pred ~ true)")
    ax.set_title("Slope vs k  (=1 means no shrinkage)")
    ax.legend(fontsize=8)
    ax.grid(alpha=0.3)

    # (1,1) per-FOIA scatter at the overall-best k
    ax = axes[1, 1]
    best_k = int(best_overall["k"])
    y_pred = preds_by_k[best_k]
    for b, name in enumerate(bin_names):
        mask = iso_bin == b
        if mask.sum() == 0:
            continue
        ax.scatter(E[mask], y_pred[mask], alpha=0.7, s=20, label=name)
    lo, hi = min(E.min(), y_pred.min()), max(E.max(), y_pred.max())
    ax.plot([lo, hi], [lo, hi], "k--", lw=1, alpha=0.6)
    ax.set_xlabel("FOIA true exposure")
    ax.set_ylabel(f"LOOV predicted (k={best_k})")
    ax.set_title(f"Per-FOIA scatter at best overall k={best_k}")
    ax.legend(fontsize=8)
    ax.grid(alpha=0.3)

    fig.suptitle(
        f"LOOV k-sweep stratified by FOIA isolation  ({args.method.upper()})  "
        f"sharpen={args.sharpen}  floor={args.floor}",
        fontsize=13, fontweight="bold",
    )
    fig.tight_layout()
    out_png = f"{FIG_DIR}/loov_k_sweep_{args.method}.png"
    fig.savefig(out_png, dpi=150)
    print(f"\nSaved {out_png}")

    out_overall = f"{OUT_DIR}/loov_k_sweep_{args.method}.csv"
    df_overall.to_csv(out_overall, index=False)
    out_bybin = f"{OUT_DIR}/loov_k_sweep_by_iso_{args.method}.csv"
    df_bybin.to_csv(out_bybin, index=False)
    print(f"Saved {out_overall}")
    print(f"Saved {out_bybin}")


if __name__ == "__main__":
    main()
