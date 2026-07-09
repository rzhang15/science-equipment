"""
K-sweep evidence for the K-NN imputation choice of K=3.

For each K in a sweep, evaluate the same K-NN recipe used in
2_similarity_wts.py (top-K + floor + sharpen + L1 normalize) against three
independent validation targets, holding everything else at production values
(sharpen=2.0, floor=0.05):

  (1) Holdout stress  (mirrors 5_holdout_stress.py)
        20-fold random 80/20 splits of the 208 FOIAs.  Predict held-out FOIA
        exposure from remaining FOIAs.  Report overall corr / MAE / slope /
        R2, plus corr in the Q1 (weakest max_sim) and Q5 (strongest max_sim)
        quintiles so the reader sees whether K matters more for hard cases.

  (2) Coauthor validation  (mirrors validate_coauthors.py)
        For every (FOIA PI, coauthor) pair with copubs count, predict the
        coauthor's imputed exposure using their TF-IDF vector, compare to the
        partner FOIA's true exposure.  Report corr overall and at
        copubs >= {5, 10, 20}, plus the twin-test metrics
        (median partner rank, %% top-5).

  (3) Cross-cluster validation  (mirrors cluster_sanity_check.py, K-NN arm)
        Build W on the full universe at this K, impute exposure for every
        universe author, aggregate to k=30 US clusters.  Report the
        cross-cluster correlation (universe-size-weighted) of mean_imputed vs
        mean_true FOIA-anchor exposure.

Same random seed for holdout folds across K values so the sweep is a fair
head-to-head.  Same coauthor pair set, same cluster labels.

The universe TF-IDF matrix is the memory-heavy piece.  We compute the
universe-FOIA cosine matrix once (dense, ~2.2 GB), then for each K just do
argpartition on that matrix -- no re-matmul.

Usage:
  python k_sweep.py --tag restricted --version hc --ks 1 2 3 5 10 20 \
                    --k-cluster 30 --skip-cluster    # if universe fit is too big

Outputs (all under ../../output):
  k_sweep_holdout_{version}{tag}.csv
  k_sweep_coauthor_{version}{tag}.csv
  k_sweep_cluster_{version}{tag}.csv
  figures/k_sweep_evidence_{version}{tag}.png
"""
import argparse
import os
import pickle
import numpy as np
import pandas as pd
import polars as pl
import scipy.sparse
import matplotlib.pyplot as plt
from sklearn.feature_extraction.text import CountVectorizer

OUT_DIR = "../../output"
FIG_DIR = f"{OUT_DIR}/figures"
EXPOSURE_DIR = "../../external/exposure_wts"
COAUTHOR_CSV = f"{OUT_DIR}/coauthor_text_stemmed.csv"
COAUTHORS_DTA = "../../external/coauthors/coauthors.dta"
EDGES = "/n/home02/cxu75/sci_eq/derived/openalex/cluster_fields/output/bert/author_paper_edges.parquet"
CLUSTER_DIR = "../../us_cluster_fields/output"


# --------------------------------------------------------------------------
# Core prediction primitive: mirrors 2_similarity_wts.process_batch exactly.
# --------------------------------------------------------------------------
def knn_predict_from_sim(sim, e_train, k, sharpen, floor):
    """Top-K, floor, sharpen^power, L1-normalize, weighted average.
    sim: (n_test, n_train) dense cosine.  Returns (pred, max_sim_row)."""
    n_test, n_train = sim.shape
    k = min(k, n_train)
    topk_idx = np.argpartition(-sim, k - 1, axis=1)[:, :k]
    rows = np.arange(n_test)[:, None]
    vals = sim[rows, topk_idx].copy()
    vals = np.where(vals >= floor, vals, 0.0)
    if sharpen != 1.0:
        vals = np.where(vals > 0, np.power(vals, sharpen), 0.0)
    row_sums = vals.sum(axis=1, keepdims=True)
    row_sums = np.where(row_sums > 0, row_sums, 1.0)
    w = vals / row_sums
    return (w * e_train[topk_idx]).sum(axis=1), sim.max(axis=1)


def _metrics(y_true, y_pred):
    y_true = np.asarray(y_true, dtype=np.float64)
    y_pred = np.asarray(y_pred, dtype=np.float64)
    m = np.isfinite(y_true) & np.isfinite(y_pred)
    yt, yp = y_true[m], y_pred[m]
    if len(yt) < 2 or yt.std() == 0 or yp.std() == 0:
        return {"n": int(len(yt)), "corr": np.nan, "mae": np.nan,
                "mse": np.nan, "r2": np.nan, "slope": np.nan}
    err = yt - yp
    ss_res = float(np.sum(err ** 2))
    ss_tot = float(np.sum((yt - yt.mean()) ** 2))
    return {
        "n": int(len(yt)),
        "corr": float(np.corrcoef(yt, yp)[0, 1]),
        "mae": float(np.mean(np.abs(err))),
        "mse": float(np.mean(err ** 2)),
        "r2": float(1 - ss_res / ss_tot) if ss_tot > 0 else np.nan,
        "slope": float(np.polyfit(yt, yp, 1)[0]),
    }


def _weighted_corr(x, y, w):
    x = np.asarray(x, dtype=np.float64); y = np.asarray(y, dtype=np.float64)
    w = np.asarray(w, dtype=np.float64)
    m = np.isfinite(x) & np.isfinite(y) & np.isfinite(w) & (w > 0)
    x, y, w = x[m], y[m], w[m]
    if len(x) < 2:
        return float("nan")
    mx = np.average(x, weights=w); my = np.average(y, weights=w)
    cov = np.average((x - mx) * (y - my), weights=w)
    vx  = np.average((x - mx) ** 2, weights=w)
    vy  = np.average((y - my) ** 2, weights=w)
    return float(cov / np.sqrt(vx * vy)) if vx > 0 and vy > 0 else float("nan")


# --------------------------------------------------------------------------
# (1) Holdout stress across K
# --------------------------------------------------------------------------
def sweep_holdout(X, e_foia, foia_ids, ks, folds, holdout_frac, sharpen, floor, seed):
    """K-fold random 80/20 stress test at each K.  Uses the SAME fold
    partition across K values so the comparison is not confounded by fold
    variance."""
    n = X.shape[0]
    n_test = int(round(holdout_frac * n))
    rng = np.random.default_rng(seed)
    fold_partitions = [rng.permutation(n) for _ in range(folds)]

    rows = []
    for f, perm in enumerate(fold_partitions):
        test_idx = np.sort(perm[:n_test])
        train_idx = np.sort(perm[n_test:])
        X_test = X[test_idx]; X_train = X[train_idx]
        sim = (X_test @ X_train.T).toarray().astype(np.float32)
        # Row-quintile assignment uses the row max_sim WITHIN THIS FOLD, and it
        # is K-independent (it's the max cosine to the train pool, not any
        # weighted quantity).  So quintile assignment is fixed across K.
        max_sim = sim.max(axis=1)

        for k in ks:
            pred, _ = knn_predict_from_sim(sim, e_foia[train_idx], k, sharpen, floor)
            for j, i in enumerate(test_idx):
                rows.append({
                    "k": k,
                    "fold": f,
                    "athr_id": foia_ids[i],
                    "max_sim_to_train": float(max_sim[j]),
                    "true": float(e_foia[i]),
                    "pred": float(pred[j]),
                })

    df = pd.DataFrame(rows)

    # Assign quintile using the pooled max_sim distribution WITHIN THE
    # k=ks[0] slice (identical to any other k since it's K-independent).
    ref = df[df["k"] == ks[0]]["max_sim_to_train"].to_numpy()
    q = np.quantile(ref, [0.2, 0.4, 0.6, 0.8])
    df["sim_bin"] = np.digitize(df["max_sim_to_train"].to_numpy(), q)

    out_rows = []
    for k in ks:
        sub = df[df["k"] == k]
        m_all = _metrics(sub["true"].to_numpy(), sub["pred"].to_numpy())
        out_rows.append({"k": k, "slice": "ALL", **m_all})
        for b in (0, 4):  # Q1 (weakest) and Q5 (strongest)
            g = sub[sub["sim_bin"] == b]
            m = _metrics(g["true"].to_numpy(), g["pred"].to_numpy())
            out_rows.append({"k": k, "slice": f"Q{b+1}", **m})
    return df, pd.DataFrame(out_rows)


# --------------------------------------------------------------------------
# (2) Coauthor validation across K -- K-NN arm only
# --------------------------------------------------------------------------
def _vectorize_in_foia_space(texts, vocab, idf_values):
    """Replicate 1_vectorize.py's TF-IDF transform on coauthor text using the
    saved production vocab + idf."""
    cv = CountVectorizer(vocabulary=vocab, tokenizer=str.split,
                         token_pattern=None, ngram_range=(1, 2),
                         dtype=np.float32)
    counts = cv.transform(texts).tocsr().astype(np.float32)
    if counts.nnz > 0:
        counts.data = np.log(counts.data) + 1.0
    tfidf = counts @ scipy.sparse.diags(idf_values.astype(np.float32))
    norms = np.sqrt(np.asarray(tfidf.multiply(tfidf).sum(axis=1)).ravel())
    inv = 1.0 / np.maximum(norms, 1e-12)
    return (scipy.sparse.diags(inv) @ tfidf).astype(np.float32).tocsr()


def _compute_copubs(pairs):
    foia_ids = pairs["athr_id"].unique().tolist()
    co_ids   = pairs["coauthor_id"].unique().tolist()
    foia_edges = (
        pl.scan_parquet(EDGES)
        .filter(pl.col("athr_id").is_in(foia_ids))
        .select(["athr_id", "id"])
        .rename({"athr_id": "foia_athr_id"})
    )
    co_edges = (
        pl.scan_parquet(EDGES)
        .filter(pl.col("athr_id").is_in(co_ids))
        .select(["athr_id", "id"])
        .rename({"athr_id": "coauthor_id"})
    )
    counts = (
        foia_edges.join(co_edges, on="id", how="inner")
        .group_by(["foia_athr_id", "coauthor_id"])
        .agg(pl.len().alias("copubs"))
        .collect(streaming=True)
        .to_pandas()
        .rename(columns={"foia_athr_id": "athr_id"})
    )
    return pairs.merge(counts, on=["athr_id", "coauthor_id"], how="left")[
        "copubs"].fillna(0).astype(int)


def sweep_coauthor(X_foia, foia_ids, e_foia, tag, ks, sharpen, floor,
                   copub_thresholds):
    """For each K, run the K-NN coauthor validation.  The sim matrix is
    computed ONCE (coauthors × FOIAs) then top-K is taken per K."""
    tag_s = tag if tag.startswith("_") or not tag else "_" + tag
    feat_names_path = f"{OUT_DIR}/feature_names{tag_s}.pkl"
    feat_diag_path  = f"{OUT_DIR}/feature_diagnostics{tag_s}.parquet"

    with open(feat_names_path, "rb") as f:
        feature_names = list(pickle.load(f))
    diag = pd.read_parquet(feat_diag_path)
    assert list(diag["feature"]) == feature_names, "feature ordering mismatch"
    idf_values = diag["idf"].to_numpy().astype(np.float32)

    df_co = pd.read_csv(COAUTHOR_CSV)
    df_co["processed_text"] = df_co["processed_text"].fillna("").astype(str)
    df_co["athr_id"] = df_co["athr_id"].astype(str)
    X_co = _vectorize_in_foia_space(df_co["processed_text"].tolist(),
                                    feature_names, idf_values).astype(np.float64)

    # Coauthor -> FOIA cosine similarity (dense, one-shot).
    sim = (X_co @ X_foia.T.astype(np.float64)).toarray().astype(np.float64)

    df_map = pd.read_stata(COAUTHORS_DTA)
    df_map["athr_id"] = df_map["athr_id"].astype(str)
    df_map["coauthor_id"] = df_map["coauthor_id"].astype(str)
    foia_idx_by_id = {a: i for i, a in enumerate(foia_ids)}
    co_idx_by_id   = {a: i for i, a in enumerate(df_co["athr_id"].tolist())}
    df = df_map[df_map["coauthor_id"].isin(co_idx_by_id) &
                df_map["athr_id"].isin(foia_idx_by_id)].copy()
    df["foia_pos"] = df["athr_id"].map(foia_idx_by_id)
    df["co_pos"]   = df["coauthor_id"].map(co_idx_by_id)
    df["e_foia_true"] = e_foia[df["foia_pos"].values]

    # Twin-test rank (K-independent).
    ranks = (-sim).argsort(axis=1).argsort(axis=1)
    df["partner_rank"] = ranks[df["co_pos"].values, df["foia_pos"].values]

    df["copubs"] = _compute_copubs(df[["athr_id", "coauthor_id"]].copy())

    rows = []
    pairs_all = []
    for k in ks:
        pred, _ = knn_predict_from_sim(sim, e_foia, k, sharpen, floor)
        preds_pair = pred[df["co_pos"].values]
        d = df.copy()
        d["k"] = k
        d["pred_knn"] = preds_pair
        pairs_all.append(d[["k", "athr_id", "coauthor_id", "e_foia_true",
                            "pred_knn", "partner_rank", "copubs"]])
        # Overall + copub cuts.
        for lo in [0] + copub_thresholds:
            sub = d if lo == 0 else d[d["copubs"] >= lo]
            m = _metrics(sub["e_foia_true"].to_numpy(),
                         sub["pred_knn"].to_numpy())
            rows.append({
                "k": k,
                "copub_cut": ">=" + str(lo) if lo > 0 else "ALL",
                "median_rank": float(sub["partner_rank"].median()) if len(sub) else np.nan,
                "pct_top5":    float((sub["partner_rank"] < 5).mean()) if len(sub) else np.nan,
                **m,
            })
    return pd.concat(pairs_all, ignore_index=True), pd.DataFrame(rows)


# --------------------------------------------------------------------------
# (3) Cross-cluster validation across K -- builds W on universe per K
# --------------------------------------------------------------------------
def sweep_cluster(X_univ, X_foia, universe_ids, foia_ids, e_foia,
                  ks, sharpen, floor, k_cluster, tag, version):
    """For each K, build the top-K weight vector on the full universe
    (imputed exposure per author, no need to store W), then aggregate to
    the k_cluster US clusters and report cross-cluster corr against
    mean FOIA-anchor exposure."""
    cluster_csv = f"{CLUSTER_DIR}/author_static_clusters_{k_cluster}.csv"
    if not os.path.exists(cluster_csv):
        raise SystemExit(f"missing cluster labels: {cluster_csv}")
    df_clusters = pd.read_csv(cluster_csv,
                              dtype={"athr_id": str, "cluster_label": int})
    foia_labels = pd.DataFrame({"athr_id": foia_ids, "e_true": e_foia}).merge(
        df_clusters, on="athr_id", how="left")
    univ_labels = universe_ids.merge(df_clusters, on="athr_id", how="left")
    print(f"  cluster labels: FOIA no-cluster="
          f"{int(foia_labels['cluster_label'].isna().sum())}/{len(foia_labels)}  "
          f"univ no-cluster={int(univ_labels['cluster_label'].isna().sum()):,}"
          f"/{len(univ_labels):,}")

    # Precompute universe × FOIA cosine ONCE (heavy).
    print(f"  computing universe -> FOIA cosine (once, "
          f"{X_univ.shape[0]:,} x {X_foia.shape[0]})...")
    X_foia_T = X_foia.T.toarray().astype(np.float32)   # tiny
    n_univ = X_univ.shape[0]
    n_foia = X_foia.shape[0]
    # Batch to avoid a single 2.2 GB allocation peak on top of X_univ.
    BATCH = 50_000
    sim_top = None       # will hold the top-max(ks) per row: (n_univ, k_max)
    sim_top_idx = None
    k_max = max(ks)
    sim_top = np.zeros((n_univ, k_max), dtype=np.float32)
    sim_top_idx = np.zeros((n_univ, k_max), dtype=np.int32)
    for s in range(0, n_univ, BATCH):
        e = min(s + BATCH, n_univ)
        batch_sim = X_univ[s:e].dot(X_foia_T)          # (b, n_foia) dense
        # Argpartition to top k_max, then only keep those K columns.
        b = batch_sim.shape[0]
        if k_max < n_foia:
            topk_idx = np.argpartition(-batch_sim, k_max - 1, axis=1)[:, :k_max]
        else:
            topk_idx = np.tile(np.arange(n_foia), (b, 1))
        rows_local = np.repeat(np.arange(b), k_max)
        topk_vals = batch_sim[rows_local, topk_idx.ravel()].reshape(b, k_max)
        sim_top[s:e] = topk_vals.astype(np.float32)
        sim_top_idx[s:e] = topk_idx.astype(np.int32)
        del batch_sim, topk_vals, topk_idx
    print(f"  done, sim_top: {sim_top.nbytes/1e6:.0f} MB")

    # Precompute per-cluster FOIA mean exposure.
    foia_ok = foia_labels.dropna(subset=["cluster_label"]).copy()
    foia_mean = foia_ok.groupby("cluster_label")["e_true"].mean()
    foia_n = foia_ok.groupby("cluster_label").size()

    rows = []
    for k in ks:
        # For this K, take the top-k columns of sim_top (subset of top-k_max).
        # We need the top-k of the RANKED top-k_max, so partition again on the
        # k_max-size row.
        if k < k_max:
            rank_idx = np.argpartition(-sim_top, k - 1, axis=1)[:, :k]
            rows_local = np.arange(n_univ)[:, None]
            vals = sim_top[rows_local, rank_idx]
            idx  = sim_top_idx[rows_local, rank_idx]
        else:
            vals = sim_top
            idx  = sim_top_idx
        vals = np.where(vals >= floor, vals, 0.0)
        if sharpen != 1.0:
            vals = np.where(vals > 0, np.power(vals, sharpen), 0.0)
        row_sums = vals.sum(axis=1, keepdims=True)
        row_sums = np.where(row_sums > 0, row_sums, 1.0)
        w = vals / row_sums
        imputed_univ = (w * e_foia[idx]).sum(axis=1)

        d = univ_labels.copy()
        d["imputed"] = imputed_univ
        d_ok = d.dropna(subset=["cluster_label"])
        univ_mean = d_ok.groupby("cluster_label")["imputed"].mean()
        univ_n = d_ok.groupby("cluster_label").size()

        merged = pd.DataFrame({
            "mean_foia": foia_mean, "mean_imp": univ_mean,
            "n_foia": foia_n, "n_univ": univ_n,
        }).reset_index().dropna(subset=["mean_foia", "mean_imp"])
        merged = merged[merged["n_foia"] >= 1]
        if len(merged) >= 2:
            corr_unw = float(merged[["mean_foia", "mean_imp"]].corr().iloc[0, 1])
            corr_w   = _weighted_corr(merged["mean_foia"], merged["mean_imp"],
                                      merged["n_univ"])
            slope    = float(np.polyfit(merged["mean_foia"], merged["mean_imp"], 1)[0])
        else:
            corr_unw = corr_w = slope = float("nan")
        rows.append({
            "k": k, "n_clusters": int(len(merged)),
            "corr_unweighted": corr_unw, "corr_weighted": corr_w,
            "slope": slope,
        })
    return pd.DataFrame(rows)


# --------------------------------------------------------------------------
# Plotting
# --------------------------------------------------------------------------
def plot_evidence(df_h, df_c, df_x, out_png, ks, version, tag, k_star=3):
    """Build the 4-panel k-sweep evidence figure."""
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))

    # (0,0) Holdout: corr overall / Q1 / Q5 vs K, slope on twin.
    ax = axes[0, 0]
    for slc, style, lbl in [
        ("ALL", "o-", "overall"),
        ("Q1",  "s--", "Q1 (weakest max_sim)"),
        ("Q5",  "^-",  "Q5 (strongest max_sim)"),
    ]:
        sub = df_h[df_h["slice"] == slc].sort_values("k")
        ax.plot(sub["k"], sub["corr"], style, label=f"corr {lbl}")
    ax.axvline(k_star, color="k", ls=":", lw=1, alpha=0.6, label=f"K={k_star}")
    ax.set_xscale("log")
    ax.set_xticks(ks); ax.set_xticklabels(ks)
    ax.set_xlabel("K")
    ax.set_ylabel("corr(pred, true)")
    ax.set_title("Holdout stress — corr vs K\n(20 folds, 80/20 splits, sharpen=2, floor=0.05)")
    ax.legend(fontsize=8)
    ax.grid(alpha=0.3)

    # (0,1) Coauthor: corr at multiple copub thresholds.
    ax = axes[0, 1]
    cuts = sorted({c for c in df_c["copub_cut"].unique() if c != "ALL"},
                  key=lambda x: int(x.replace(">=", "")))
    for cut, style in zip(["ALL"] + cuts, ["o-", "s--", "^-", "v:", "D-."]):
        sub = df_c[df_c["copub_cut"] == cut].sort_values("k")
        ax.plot(sub["k"], sub["corr"], style, label=f"copubs {cut}")
    ax.axvline(k_star, color="k", ls=":", lw=1, alpha=0.6, label=f"K={k_star}")
    ax.set_xscale("log")
    ax.set_xticks(ks); ax.set_xticklabels(ks)
    ax.set_xlabel("K")
    ax.set_ylabel("corr(pred_knn, partner_true)")
    ax.set_title("Coauthor validation — corr vs K\n(K-NN arm)")
    ax.legend(fontsize=8)
    ax.grid(alpha=0.3)

    # (1,0) Cross-cluster: weighted r vs K.
    ax = axes[1, 0]
    df_x_s = df_x.sort_values("k")
    ax.plot(df_x_s["k"], df_x_s["corr_weighted"], "o-", label="weighted r (by n_univ)")
    ax.plot(df_x_s["k"], df_x_s["corr_unweighted"], "s--", label="unweighted r")
    ax.axvline(k_star, color="k", ls=":", lw=1, alpha=0.6, label=f"K={k_star}")
    ax.set_xscale("log")
    ax.set_xticks(ks); ax.set_xticklabels(ks)
    ax.set_xlabel("K")
    ax.set_ylabel("cross-cluster r")
    ax.set_title("Cross-cluster validation — r vs K\n(mean imputed univ vs mean FOIA anchors, k=30 US clusters)")
    ax.legend(fontsize=8)
    ax.grid(alpha=0.3)

    # (1,1) MAE overall (holdout) + slope (cross-cluster) as a "cost of shrinkage" view.
    ax = axes[1, 1]
    h_all = df_h[df_h["slice"] == "ALL"].sort_values("k")
    ax.plot(h_all["k"], h_all["mae"], "o-", color="C0", label="Holdout MAE")
    ax2 = ax.twinx()
    ax2.plot(df_x_s["k"], df_x_s["slope"], "s--", color="C3", label="Cluster slope")
    ax2.axhline(1.0, color="k", ls=":", lw=0.6, alpha=0.4)
    ax.axvline(k_star, color="k", ls=":", lw=1, alpha=0.6)
    ax.set_xscale("log")
    ax.set_xticks(ks); ax.set_xticklabels(ks)
    ax.set_xlabel("K")
    ax.set_ylabel("Holdout MAE (blue)", color="C0")
    ax2.set_ylabel("Cross-cluster slope (red)", color="C3")
    ax.set_title("Shrinkage cost — MAE (down) and level slope (toward 1)")
    ax.grid(alpha=0.3)

    fig.suptitle(
        f"K-NN neighbor-count evidence   version={version}   tag={tag}\n"
        f"Same recipe as production (sharpen=2, floor=0.05); only K varies",
        fontsize=13, fontweight="bold",
    )
    fig.tight_layout()
    fig.savefig(out_png, dpi=150)
    print(f"Saved figure: {out_png}")


# --------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="restricted",
                    help="TF-IDF tag (matches --tag from 1_vectorize.py). "
                         "Default 'restricted' = production.")
    ap.add_argument("--version", default="hc",
                    choices=["hc", "all", "treated_hc"],
                    help="Exposure denominator to validate against.")
    ap.add_argument("--ks", type=int, nargs="+", default=[1, 2, 3, 5, 10, 20],
                    help="K values to sweep.  Default 1 2 3 5 10 20.")
    ap.add_argument("--sharpen", type=float, default=2.0,
                    help="Held fixed at 2.0 (production) across the sweep.")
    ap.add_argument("--floor", type=float, default=0.05,
                    help="Held fixed at 0.05 (production).")
    ap.add_argument("--folds", type=int, default=20,
                    help="Holdout folds.  Same partition across K.")
    ap.add_argument("--holdout-frac", type=float, default=0.20)
    ap.add_argument("--seed", type=int, default=8975)
    ap.add_argument("--k-cluster", type=int, default=30,
                    help="US cluster K for cross-cluster validation (project default 30).")
    ap.add_argument("--copub-thresholds", type=int, nargs="+",
                    default=[5, 10, 20],
                    help="copubs cuts to break out in the coauthor sweep.")
    ap.add_argument("--skip-holdout", action="store_true")
    ap.add_argument("--skip-coauthor", action="store_true")
    ap.add_argument("--skip-cluster", action="store_true",
                    help="Skip the cross-cluster sweep (loads the 1.9 GB universe "
                         "TF-IDF and builds W per K, ~2-3 GB peak).")
    args = ap.parse_args()

    tag_s = args.tag if not args.tag or args.tag.startswith("_") else "_" + args.tag
    foia_matrix_path = f"{OUT_DIR}/tfidf_foia{tag_s}.npz"
    foia_ids_path    = f"{OUT_DIR}/foia_ids_ordered{tag_s}.csv"
    univ_matrix_path = f"{OUT_DIR}/tfidf_universe{tag_s}.npz"
    univ_ids_path    = f"{OUT_DIR}/universe_ids{tag_s}.parquet"
    exposure_dta     = f"{EXPOSURE_DIR}/athr_exposure_{args.version}.dta"

    for p in (foia_matrix_path, foia_ids_path, exposure_dta):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")
    os.makedirs(FIG_DIR, exist_ok=True)

    print(f"Config: ks={args.ks}  sharpen={args.sharpen}  floor={args.floor}  "
          f"folds={args.folds}  holdout_frac={args.holdout_frac}  "
          f"version={args.version}  tag={args.tag}")

    # Shared inputs.
    print("Loading FOIA matrix + exposures...")
    X_foia = scipy.sparse.load_npz(foia_matrix_path).tocsr().astype(np.float32)
    foia_ids = pd.read_csv(foia_ids_path, dtype={"athr_id": str})["athr_id"].tolist()
    df_exp = pd.read_stata(exposure_dta)[["athr_id", "exposure"]]
    df_exp["athr_id"] = df_exp["athr_id"].astype(str)
    e_foia = (pd.Series(df_exp.set_index("athr_id")["exposure"])
              .reindex(foia_ids).fillna(0).values.astype(np.float32))
    print(f"  FOIA: {X_foia.shape}   exposure mean={e_foia.mean():.4f} sd={e_foia.std():.4f}")

    out_stem = f"{args.version}{tag_s}"

    # (1) Holdout
    if not args.skip_holdout:
        print("\n=== (1) Holdout stress sweep ===")
        _, df_h = sweep_holdout(X_foia, e_foia, foia_ids,
                                args.ks, args.folds, args.holdout_frac,
                                args.sharpen, args.floor, args.seed)
        df_h.to_csv(f"{OUT_DIR}/k_sweep_holdout_{out_stem}.csv", index=False)
        print(df_h.to_string(index=False))
        print(f"Saved: {OUT_DIR}/k_sweep_holdout_{out_stem}.csv")
    else:
        df_h = pd.read_csv(f"{OUT_DIR}/k_sweep_holdout_{out_stem}.csv")

    # (2) Coauthor
    if not args.skip_coauthor:
        print("\n=== (2) Coauthor validation sweep ===")
        _, df_c = sweep_coauthor(X_foia, foia_ids, e_foia, args.tag,
                                 args.ks, args.sharpen, args.floor,
                                 args.copub_thresholds)
        df_c.to_csv(f"{OUT_DIR}/k_sweep_coauthor_{out_stem}.csv", index=False)
        print(df_c.to_string(index=False))
        print(f"Saved: {OUT_DIR}/k_sweep_coauthor_{out_stem}.csv")
    else:
        df_c = pd.read_csv(f"{OUT_DIR}/k_sweep_coauthor_{out_stem}.csv")

    # (3) Cluster
    if not args.skip_cluster:
        print("\n=== (3) Cross-cluster sweep (loads full universe TF-IDF) ===")
        if not os.path.exists(univ_matrix_path) or not os.path.exists(univ_ids_path):
            raise SystemExit(
                f"missing universe artifacts (need {univ_matrix_path} and "
                f"{univ_ids_path}).  Pass --skip-cluster to skip this sweep."
            )
        X_univ = scipy.sparse.load_npz(univ_matrix_path).tocsr().astype(np.float32)
        universe_ids = pd.read_parquet(univ_ids_path)
        universe_ids["athr_id"] = universe_ids["athr_id"].astype(str)
        print(f"  Universe: {X_univ.shape}")
        df_x = sweep_cluster(X_univ, X_foia, universe_ids, foia_ids, e_foia,
                             args.ks, args.sharpen, args.floor,
                             args.k_cluster, args.tag, args.version)
        df_x.to_csv(f"{OUT_DIR}/k_sweep_cluster_{out_stem}.csv", index=False)
        print(df_x.to_string(index=False))
        print(f"Saved: {OUT_DIR}/k_sweep_cluster_{out_stem}.csv")
        del X_univ
    else:
        p = f"{OUT_DIR}/k_sweep_cluster_{out_stem}.csv"
        df_x = pd.read_csv(p) if os.path.exists(p) else pd.DataFrame(
            {"k": args.ks, "corr_weighted": np.nan, "corr_unweighted": np.nan,
             "slope": np.nan, "n_clusters": 0})

    out_png = f"{FIG_DIR}/k_sweep_evidence_{out_stem}.png"
    plot_evidence(df_h, df_c, df_x, out_png, args.ks, args.version, args.tag)

    print("\nDone.")


if __name__ == "__main__":
    main()
