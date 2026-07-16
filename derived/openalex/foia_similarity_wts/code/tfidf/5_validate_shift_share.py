"""
Shift-share imputation validation exhibits (KNN k=3, hc + _cf).

Produces five referee-ready exhibits from the ONE object that matters:
S_hat = W @ S (universe x 46), imputed pre-period share matrix.

  E1  Leave-one-FOIA-out (LOFO) cross-validation of KNN
      For each of the 208 FOIAs, hold out, rebuild top-k on remaining 207,
      predict held-out shares. Report cell-level + PI-level-exposure metrics
      overall and by max_sim_to_train quintile. Scatter of predicted vs
      actual z = S @ g at the PI level.

  E2  Baseline comparison (same LOFO folds, different smoothers)
      Compare KNN(k=3) against: grand-mean, k=30-cluster-mean,
      KNN(k=1), KNN(k=5), KNN(k=10). Table of PI-level metrics.

  E3  Support diagnostics on the universe (under _cf filter)
      Histograms (as CSV) of max_sim and 3rd-neighbor sim. From the LOFO
      results, coverage-vs-accuracy curve: RMSE binned by max_sim.

  E4  Placebo (shuffled-share LOFO)
      Randomly permute FOIA rows of S so each FOIA gets another's shares.
      Re-run LOFO KNN, show PI-level exposure R2 collapses. Evidence that
      the neighbor structure carries the signal (not baseline levels).

  E5  Face-validity table (stratified by max_sim quintile)
      Under _cf, pick 2 universe PIs per quintile. For each: list its 3
      FOIA neighbors and each neighbor's top-5 TF-IDF terms. Reproducible
      via --seed.

Uses the production KNN recipe (top-k + floor + sharpen^p + L1-norm) so the
LOFO speaks to the same object 4_impute_shift_share.py produces.

Outputs (under ../../output/validation/):
  E1  lofo_pi_hc_cf_k3.csv                 per-FOIA (true_z, pred_z, max_sim,...)
      lofo_cell_hc_cf_k3.csv               per-market cell RMSE / n_nonzero
      lofo_summary_hc_cf_k3.txt            headline numbers
  E2  baselines_pi_hc_cf.csv               method x PI-metric table
  E3  support_hist_hc_cf.csv               max_sim + 3rd-sim histograms
      coverage_vs_rmse_hc_cf_k3.csv        LOFO RMSE by max_sim quintile
  E4  placebo_pi_hc_cf_k3.csv              PI-level metrics (shuffled)
      placebo_summary_hc_cf_k3.txt         headline
  E5  face_validity_hc_cf_k3.csv           universe PI + 3 neighbors + terms
"""
import argparse
import os
import pickle
import numpy as np
import pandas as pd
import scipy.sparse as sp

OUT_DIR = "../../output"
VAL_DIR = f"{OUT_DIR}/validation"

DEFAULT_BETAS_FILE = (
    "/n/holylabs/LABS/pakes_lab/Lab/sci_eq/analysis/first_stage/output/"
    "did_coefs_eb_price.dta"
)
DEFAULT_CLUSTER_K30 = (
    "../../../us_cluster_fields/output/author_static_clusters_30.csv"
)
CATEGORY_SHARE_FILE = "../../external/exposure_wts/athr_exposure_by_category_{version}.dta"
CATEGORY_RENAMES = {
    "acrylamide/bis solution": "acrylamide-bis solution",
    "dmem/f-12": "dmem-f-12",
}


# --------------------------------------------------------------------------- #
# Shared loaders                                                              #
# --------------------------------------------------------------------------- #

def load_shocks(path):
    df = pd.read_stata(path)
    df["category"] = df["category"].replace(CATEGORY_RENAMES)
    df = df.dropna(subset=["b"]).drop_duplicates(subset=["category"]).reset_index(drop=True)
    return df["category"].tolist(), df["b"].to_numpy(dtype=np.float64)


def build_share_matrix(share_path, foia_ids, market_index):
    df = pd.read_stata(share_path)
    df["athr_id"] = df["athr_id"].astype(str)
    df["category"] = df["category"].astype(str).replace(CATEGORY_RENAMES)
    df = df.dropna(subset=["spend", "tot_shr_spend"])
    df = df[(df["spend"] > 0) & (df["tot_shr_spend"] > 0)]
    df["share"] = df["spend"].astype(float) / df["tot_shr_spend"].astype(float)
    df = df[df["category"].isin(market_index)]
    df = df[df["athr_id"].isin(set(foia_ids))]
    foia_pos = {aid: i for i, aid in enumerate(foia_ids)}
    market_pos = {c: i for i, c in enumerate(market_index)}
    rows = df["athr_id"].map(foia_pos).to_numpy()
    cols = df["category"].map(market_pos).to_numpy()
    data = df["share"].to_numpy(dtype=np.float64)
    S = sp.csr_matrix((data, (rows, cols)),
                      shape=(len(foia_ids), len(market_index)))
    return S


def apply_cf_filter(df_univ, W, cluster_path, foia_ids, min_n=1):
    """Cluster-filter the universe: drop universe authors whose k=30 cluster
    has fewer than min_n FOIA anchors. Matches 4_impute_shift_share.py's
    apply_filters logic. Returns (keep_mask, cl_df)."""
    cl = pd.read_csv(cluster_path)
    cl["athr_id"] = cl["athr_id"].astype(str)
    if "cluster_label" not in cl.columns:
        raise SystemExit(f"{cluster_path} needs [athr_id, cluster_label]")

    df_foia = pd.DataFrame({"athr_id": foia_ids})
    foia_in_cl = df_foia.merge(cl, on="athr_id", how="inner")
    foia_counts = foia_in_cl.groupby("cluster_label").size()
    kept = set(foia_counts[foia_counts >= min_n].index)

    m = df_univ.merge(cl, on="athr_id", how="left")
    mask = m["cluster_label"].notna() & m["cluster_label"].isin(kept)
    return mask.to_numpy(), cl


# --------------------------------------------------------------------------- #
# KNN prediction (mirrors 2_similarity_wts.process_batch exactly)             #
# --------------------------------------------------------------------------- #

def knn_predict(sim, S_train, k, sharpen, floor):
    """sim: (n_test, n_train) cosine. S_train: (n_train, M) shares.
    Returns (S_pred, max_sim_to_train, sim_at_k). Applies floor -> sharpen ->
    L1-norm exactly like production."""
    n_test, n_train = sim.shape
    k = min(k, n_train)
    topk = np.argpartition(-sim, k - 1, axis=1)[:, :k]
    r = np.arange(n_test)[:, None]
    vals = sim[r, topk].copy()
    max_sim = sim.max(axis=1)
    sim_at_k = vals.min(axis=1)          # k-th neighbor sim (worst kept)
    vals = np.where(vals >= floor, vals, 0.0)
    if sharpen != 1.0:
        vals = np.where(vals > 0, np.power(vals, sharpen), 0.0)
    rs = vals.sum(axis=1, keepdims=True)
    rs = np.where(rs > 0, rs, 1.0)
    w = vals / rs
    S_pred = np.zeros((n_test, S_train.shape[1]), dtype=np.float64)
    S_train_dense = S_train.toarray() if sp.issparse(S_train) else np.asarray(S_train)
    for i in range(n_test):
        S_pred[i] = w[i] @ S_train_dense[topk[i]]
    return S_pred, max_sim, sim_at_k


# --------------------------------------------------------------------------- #
# LOFO driver                                                                 #
# --------------------------------------------------------------------------- #

def lofo_folds(n, n_folds, rng):
    """Yield (test_idx, train_idx). If n_folds >= n: leave-one-out.
    Else: K-fold shuffled."""
    perm = rng.permutation(n)
    if n_folds >= n:
        for i in range(n):
            test = np.array([perm[i]])
            train = np.concatenate([perm[:i], perm[i+1:]])
            yield np.sort(test), np.sort(train)
    else:
        for f in range(n_folds):
            lo = f * n // n_folds
            hi = (f + 1) * n // n_folds
            test = np.sort(perm[lo:hi])
            train = np.sort(np.concatenate([perm[:lo], perm[hi:]]))
            yield test, train


def run_lofo(X_foia, S, g, k, sharpen, floor, n_folds, rng,
             method="knn", clusters=None):
    """Run LOFO for one smoother. Returns per-FOIA DataFrame with
    (fold, foia_row, true_z, pred_z, max_sim, sim_at_k, cell_l1)."""
    n = X_foia.shape[0]
    M = S.shape[1]
    S_dense = S.toarray()
    true_z = np.asarray(S @ g).ravel()
    Xn = X_foia.astype(np.float32)     # rows already L2-normalized by 1_vectorize

    rows = []
    for test_idx, train_idx in lofo_folds(n, n_folds, rng):
        X_test = Xn[test_idx]
        X_train = Xn[train_idx]
        S_train = sp.csr_matrix(S_dense[train_idx])
        sim = (X_test @ X_train.T).toarray().astype(np.float32)

        if method == "knn":
            S_pred, max_sim, sim_at_k = knn_predict(sim, S_train, k, sharpen, floor)
        elif method == "grand_mean":
            mean_row = S_dense[train_idx].mean(axis=0)
            S_pred = np.tile(mean_row, (len(test_idx), 1))
            max_sim = sim.max(axis=1)
            sim_at_k = np.zeros(len(test_idx))
        elif method == "cluster_mean":
            if clusters is None:
                raise ValueError("cluster_mean needs clusters= array")
            cl_train = clusters[train_idx]
            cl_test = clusters[test_idx]
            grand = S_dense[train_idx].mean(axis=0)
            unique = np.unique(cl_train[cl_train != -1])
            cl_means = {c: S_dense[train_idx][cl_train == c].mean(axis=0)
                        for c in unique}
            S_pred = np.vstack([
                cl_means.get(c, grand) if c != -1 else grand
                for c in cl_test
            ])
            max_sim = sim.max(axis=1)
            sim_at_k = np.zeros(len(test_idx))
        else:
            raise ValueError(f"unknown method {method}")

        pred_z = S_pred @ g
        cell_l1 = np.abs(S_pred - S_dense[test_idx]).sum(axis=1)
        for j, i in enumerate(test_idx):
            rows.append({
                "foia_row": int(i),
                "true_z": float(true_z[i]),
                "pred_z": float(pred_z[j]),
                "max_sim": float(max_sim[j]),
                "sim_at_k": float(sim_at_k[j]),
                "cell_l1": float(cell_l1[j]),
            })
    return pd.DataFrame(rows)


def pi_metrics(df):
    y, p = df["true_z"].to_numpy(), df["pred_z"].to_numpy()
    m = np.isfinite(y) & np.isfinite(p)
    y, p = y[m], p[m]
    if len(y) < 2:
        return {"n": len(y), "corr": np.nan, "rmse": np.nan,
                "slope": np.nan, "r2": np.nan}
    err = y - p
    ss_res = float((err ** 2).sum())
    ss_tot = float(((y - y.mean()) ** 2).sum())
    slope = float(np.polyfit(y, p, 1)[0])
    return {
        "n": int(len(y)),
        "corr": float(np.corrcoef(y, p)[0, 1]),
        "rmse": float(np.sqrt((err ** 2).mean())),
        "slope": slope,
        "r2": float(1 - ss_res / ss_tot) if ss_tot > 0 else np.nan,
    }


def cell_metrics(lofo_df, S, X_foia, foia_ids, market_index, g,
                 k, sharpen, floor, n_folds, rng):
    """Recompute LOFO holding cell-level residuals per market. Cheap: just
    aggregate S_pred - S over the same folds. Returns per-market DataFrame."""
    n = X_foia.shape[0]
    M = S.shape[1]
    S_dense = S.toarray()
    resid_sq = np.zeros(M)
    n_test_per = np.zeros(M, dtype=np.int64)
    nz_per = (S_dense > 0).sum(axis=0)
    Xn = X_foia.astype(np.float32)
    for test_idx, train_idx in lofo_folds(n, n_folds, rng):
        X_test = Xn[test_idx]
        X_train = Xn[train_idx]
        S_train = sp.csr_matrix(S_dense[train_idx])
        sim = (X_test @ X_train.T).toarray().astype(np.float32)
        S_pred, _, _ = knn_predict(sim, S_train, k, sharpen, floor)
        resid_sq += ((S_pred - S_dense[test_idx]) ** 2).sum(axis=0)
        n_test_per += len(test_idx)
    rmse = np.sqrt(resid_sq / np.maximum(n_test_per, 1))
    return pd.DataFrame({
        "category": market_index,
        "rmse": rmse,
        "n_foia_nonzero": nz_per,
        "s_bar": S_dense.mean(axis=0),
        "g": g,
    })


# --------------------------------------------------------------------------- #
# E3 support diagnostics                                                      #
# --------------------------------------------------------------------------- #

def support_hist(diag_df, keep_mask, k, bins=25):
    """Return DataFrame with max_sim + sim_at_k histograms on the _cf universe."""
    d = diag_df.loc[keep_mask].copy()
    # max_sim already computed. Third-neighbor sim would need the raw sim
    # matrix. We approximate with mean_topk_sim if k matches — but honest
    # option: use max_sim only for E3 histogram (the LOFO sim_at_k covers
    # k-th neighbor behavior).
    max_edges = np.linspace(0, max(d["max_sim"].max(), 0.5), bins + 1)
    max_h, _ = np.histogram(d["max_sim"], bins=max_edges)
    mean_edges = np.linspace(0, max(d["mean_topk_sim"].max(), 0.5), bins + 1)
    mean_h, _ = np.histogram(d["mean_topk_sim"], bins=mean_edges)
    return pd.DataFrame({
        "bin_lo": max_edges[:-1],
        "bin_hi": max_edges[1:],
        "max_sim_count": max_h,
        "mean_topk_sim_bin_lo": mean_edges[:-1],
        "mean_topk_sim_bin_hi": mean_edges[1:],
        "mean_topk_sim_count": mean_h,
    })


def coverage_vs_rmse(lofo_df, n_bins=5):
    """LOFO cell-l1 error binned by max_sim quintile."""
    q = np.quantile(lofo_df["max_sim"], np.linspace(0, 1, n_bins + 1))
    lofo_df = lofo_df.copy()
    lofo_df["sim_bin"] = np.digitize(lofo_df["max_sim"], q[1:-1])
    rows = []
    for b in range(n_bins):
        sub = lofo_df[lofo_df["sim_bin"] == b]
        if len(sub) == 0:
            continue
        rows.append({
            "quintile": b + 1,
            "max_sim_lo": float(q[b]),
            "max_sim_hi": float(q[b + 1]),
            "n": int(len(sub)),
            "cell_l1_mean": float(sub["cell_l1"].mean()),
            "pi_rmse": float(np.sqrt(((sub["true_z"] - sub["pred_z"]) ** 2).mean())),
            "pi_corr": float(np.corrcoef(sub["true_z"], sub["pred_z"])[0, 1])
                       if len(sub) >= 2 else np.nan,
        })
    return pd.DataFrame(rows)


# --------------------------------------------------------------------------- #
# E5 face-validity                                                            #
# --------------------------------------------------------------------------- #

def face_validity_table(X_univ, X_foia, W, universe_ids, foia_ids,
                        feature_names, keep_mask, k, per_quintile, rng):
    """Stratify _cf universe by max_sim quintile, sample per_quintile per bin.
    For each sampled universe PI: list its top-k FOIA neighbors from W, and
    top-5 TF-IDF terms per neighbor.
    """
    keep_idx = np.where(keep_mask)[0]
    W_kept = W[keep_idx]
    max_sim = np.asarray(W_kept.max(axis=1).todense()).ravel()

    q = np.quantile(max_sim, np.linspace(0, 1, 6))
    rows = []
    for b in range(5):
        lo, hi = q[b], q[b + 1]
        pool = np.where((max_sim >= lo) & (max_sim <= hi))[0]
        if len(pool) == 0:
            continue
        picks = rng.choice(pool, size=min(per_quintile, len(pool)), replace=False)
        for local_idx in picks:
            univ_idx = keep_idx[local_idx]
            row = W[univ_idx]
            # get k largest by weight
            dense = row.toarray().ravel()
            if dense.sum() == 0:
                continue
            top = np.argsort(-dense)[:k]
            top = top[dense[top] > 0]
            neighbor_ids = [foia_ids[j] for j in top]
            neighbor_wts = [float(dense[j]) for j in top]

            # Top TF-IDF terms per neighbor
            neighbor_terms = []
            for j in top:
                r = X_foia[j].toarray().ravel()
                top_t = np.argsort(-r)[:5]
                terms = [feature_names[t] for t in top_t if r[t] > 0]
                neighbor_terms.append(",".join(terms))

            rows.append({
                "quintile": b + 1,
                "max_sim_lo": float(lo),
                "max_sim_hi": float(hi),
                "univ_athr_id": universe_ids[univ_idx],
                "univ_max_sim": float(max_sim[local_idx]),
                "neighbors": ";".join(neighbor_ids),
                "neighbor_wts": ";".join(f"{w:.3f}" for w in neighbor_wts),
                "neighbor_top_terms": " || ".join(neighbor_terms),
            })
    return pd.DataFrame(rows)


# --------------------------------------------------------------------------- #
# Main                                                                        #
# --------------------------------------------------------------------------- #

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="",
                    help="Empty (default) matches production: analysis.do reads "
                         "final_imputed_shift_share_hc_cf.csv, which is built "
                         "from the baseline artifacts (weight_matrix.npz etc., "
                         "no _restricted suffix). Pass 'restricted' only to "
                         "validate the restricted variant.")
    ap.add_argument("--version", default="hc", choices=["hc", "all", "treated_hc"])
    ap.add_argument("--min-foia-per-cluster", type=int, default=1,
                    help="_cf threshold (1 => _cf, matches analysis.do default).")
    ap.add_argument("--cluster-file", default=DEFAULT_CLUSTER_K30,
                    help="k=30 US-cluster labels (per user memory).")
    ap.add_argument("--betas-path", default=DEFAULT_BETAS_FILE)
    ap.add_argument("--k", type=int, default=3, help="Top-K neighbors (production=3).")
    ap.add_argument("--sharpen", type=float, default=2.0)
    ap.add_argument("--floor", type=float, default=0.05)
    ap.add_argument("--n-folds", type=int, default=208,
                    help=">= n_foia => true leave-one-out. Default: LOO.")
    ap.add_argument("--seed", type=int, default=8975)
    ap.add_argument("--face-per-quintile", type=int, default=2)
    ap.add_argument("--baselines", nargs="+",
                    default=["grand_mean", "cluster_mean", "knn1", "knn5", "knn10"],
                    choices=["grand_mean", "cluster_mean", "knn1", "knn3",
                             "knn5", "knn10"])
    ap.add_argument("--skip", nargs="+", default=[],
                    choices=["e1", "e2", "e3", "e4", "e5"],
                    help="Exhibits to skip.")
    args = ap.parse_args()

    os.makedirs(VAL_DIR, exist_ok=True)
    tag = args.tag
    if tag and not tag.startswith("_"):
        tag = "_" + tag
    sfx = "_cf" if args.min_foia_per_cluster <= 1 else f"_cf{args.min_foia_per_cluster}"
    stem = f"{args.version}{sfx}_k{args.k}"

    # ---- Load pipeline artifacts ----
    print(f"[load] tag={args.tag}  version={args.version}  filter={sfx}  k={args.k}")
    X_foia = sp.load_npz(f"{OUT_DIR}/tfidf_foia{tag}.npz").tocsr().astype(np.float32)
    X_univ = sp.load_npz(f"{OUT_DIR}/tfidf_universe{tag}.npz").tocsr().astype(np.float32)
    foia_ids = pd.read_csv(f"{OUT_DIR}/foia_ids_ordered{tag}.csv",
                           dtype={"athr_id": str})["athr_id"].tolist()
    df_univ = pd.read_parquet(f"{OUT_DIR}/universe_ids{tag}.parquet")
    df_univ["athr_id"] = df_univ["athr_id"].astype(str)
    universe_ids = df_univ["athr_id"].tolist()
    with open(f"{OUT_DIR}/feature_names{tag}.pkl", "rb") as f:
        feature_names = pickle.load(f)
    W = sp.load_npz(f"{OUT_DIR}/weight_matrix{tag}.npz")
    diag = pd.read_parquet(f"{OUT_DIR}/match_diagnostics{tag}.parquet")
    print(f"  X_foia={X_foia.shape}  X_univ={X_univ.shape}  |vocab|={len(feature_names)}")

    market_index, g = load_shocks(args.betas_path)
    S = build_share_matrix(
        CATEGORY_SHARE_FILE.format(version=args.version),
        foia_ids, market_index,
    )
    print(f"  S={S.shape}  nnz={S.nnz:,}   #shocks={len(g)}")

    # _cf filter
    if not os.path.exists(args.cluster_file):
        raise SystemExit(f"missing cluster file: {args.cluster_file}")
    keep_mask, cl_df = apply_cf_filter(
        df_univ, W, args.cluster_file, foia_ids, args.min_foia_per_cluster,
    )
    print(f"  _cf universe: kept {keep_mask.sum():,}/{len(keep_mask):,}"
          f" ({100*keep_mask.mean():.1f}%)")

    # FOIA cluster labels (for E2 cluster-mean baseline)
    foia_clusters = (
        pd.DataFrame({"athr_id": foia_ids})
        .merge(cl_df, on="athr_id", how="left")["cluster_label"]
        .fillna(-1).astype(int).to_numpy()
    )

    rng = np.random.default_rng(args.seed)

    # ------ E1: LOFO ------
    if "e1" not in args.skip:
        print("\n[E1] LOFO cross-validation of KNN(k=3)")
        lofo = run_lofo(X_foia, S, g, args.k, args.sharpen, args.floor,
                        args.n_folds, np.random.default_rng(args.seed))
        lofo.to_csv(f"{VAL_DIR}/lofo_pi_{stem}.csv", index=False)
        m = pi_metrics(lofo)
        print(f"  PI-level: n={m['n']}  corr={m['corr']:.3f}  "
              f"rmse={m['rmse']:.4f}  slope={m['slope']:.3f}  r2={m['r2']:.3f}")

        cell = cell_metrics(lofo, S, X_foia, foia_ids, market_index, g,
                            args.k, args.sharpen, args.floor,
                            args.n_folds, np.random.default_rng(args.seed))
        cell.to_csv(f"{VAL_DIR}/lofo_cell_{stem}.csv", index=False)
        with open(f"{VAL_DIR}/lofo_summary_{stem}.txt", "w") as f:
            f.write(f"LOFO KNN(k={args.k})  version={args.version}{sfx}\n")
            f.write(f"  PI-level: n={m['n']}  corr={m['corr']:.4f}  "
                    f"rmse={m['rmse']:.5f}  slope={m['slope']:.4f}  "
                    f"r2={m['r2']:.4f}\n")
            f.write(f"  cell-level mean L1 residual across markets: "
                    f"{lofo['cell_l1'].mean():.5f}\n")
            f.write(f"  n folds run: {args.n_folds}   seed={args.seed}\n")
        print(f"  Saved {VAL_DIR}/lofo_pi_{stem}.csv")
        print(f"  Saved {VAL_DIR}/lofo_cell_{stem}.csv")
        print(f"  Saved {VAL_DIR}/lofo_summary_{stem}.txt")

    # ------ E2: baselines ------
    if "e2" not in args.skip:
        print("\n[E2] Baseline comparison on the same LOFO folds")
        rows = []
        methods = []
        for name in args.baselines + ["knn3"] if "knn3" not in args.baselines else args.baselines:
            methods.append(name)
        methods = list(dict.fromkeys(methods))     # dedupe, preserve order
        for m_name in methods:
            if m_name.startswith("knn"):
                kk = int(m_name[3:])
                df_m = run_lofo(X_foia, S, g, kk, args.sharpen, args.floor,
                                args.n_folds, np.random.default_rng(args.seed))
            elif m_name == "grand_mean":
                df_m = run_lofo(X_foia, S, g, args.k, args.sharpen, args.floor,
                                args.n_folds, np.random.default_rng(args.seed),
                                method="grand_mean")
            elif m_name == "cluster_mean":
                df_m = run_lofo(X_foia, S, g, args.k, args.sharpen, args.floor,
                                args.n_folds, np.random.default_rng(args.seed),
                                method="cluster_mean", clusters=foia_clusters)
            else:
                continue
            met = pi_metrics(df_m)
            met["method"] = m_name
            rows.append(met)
            print(f"  {m_name:<14s}  corr={met['corr']:.3f}  "
                  f"rmse={met['rmse']:.4f}  slope={met['slope']:.3f}  r2={met['r2']:.3f}")
        pd.DataFrame(rows)[["method", "n", "corr", "rmse", "slope", "r2"]]\
            .to_csv(f"{VAL_DIR}/baselines_pi_{args.version}{sfx}.csv", index=False)
        print(f"  Saved {VAL_DIR}/baselines_pi_{args.version}{sfx}.csv")

    # ------ E3: support diagnostics ------
    if "e3" not in args.skip:
        print("\n[E3] Support diagnostics under _cf")
        hist = support_hist(diag, keep_mask, args.k)
        hist.to_csv(f"{VAL_DIR}/support_hist_{args.version}{sfx}.csv", index=False)
        print(f"  Saved {VAL_DIR}/support_hist_{args.version}{sfx}.csv")
        if "e1" not in args.skip:
            cov = coverage_vs_rmse(lofo)
            cov.to_csv(f"{VAL_DIR}/coverage_vs_rmse_{stem}.csv", index=False)
            print(f"  Saved {VAL_DIR}/coverage_vs_rmse_{stem}.csv")
            print(cov.to_string(index=False))

    # ------ E4: placebo (shuffled shares) ------
    if "e4" not in args.skip:
        print("\n[E4] Placebo: shuffle FOIA rows of S, re-run LOFO KNN")
        perm = rng.permutation(X_foia.shape[0])
        S_perm = sp.csr_matrix(S.toarray()[perm])
        placebo = run_lofo(X_foia, S_perm, g, args.k, args.sharpen, args.floor,
                           args.n_folds, np.random.default_rng(args.seed))
        placebo.to_csv(f"{VAL_DIR}/placebo_pi_{stem}.csv", index=False)
        pm = pi_metrics(placebo)
        with open(f"{VAL_DIR}/placebo_summary_{stem}.txt", "w") as f:
            f.write(f"PLACEBO (shuffled S rows) KNN(k={args.k})  version={args.version}{sfx}\n")
            f.write(f"  corr={pm['corr']:.4f}  rmse={pm['rmse']:.5f}  "
                    f"slope={pm['slope']:.4f}  r2={pm['r2']:.4f}\n")
            f.write("Compare to Exhibit 1: PI-level correlation should collapse.\n")
        print(f"  placebo corr={pm['corr']:.3f}  r2={pm['r2']:.3f}")
        print(f"  Saved {VAL_DIR}/placebo_pi_{stem}.csv")

    # ------ E5: face validity ------
    if "e5" not in args.skip:
        print("\n[E5] Face-validity table (stratified by max_sim quintile)")
        face_rng = np.random.default_rng(args.seed + 1)
        face = face_validity_table(X_univ, X_foia, W, universe_ids, foia_ids,
                                   feature_names, keep_mask, args.k,
                                   args.face_per_quintile, face_rng)
        face.to_csv(f"{VAL_DIR}/face_validity_{stem}.csv", index=False)
        print(f"  Saved {VAL_DIR}/face_validity_{stem}.csv  ({len(face)} rows)")

    print("\nDone.")


if __name__ == "__main__":
    main()
