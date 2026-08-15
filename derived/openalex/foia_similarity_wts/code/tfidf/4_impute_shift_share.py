"""
Shift-share imputation. Impute the PI x market share MATRIX, then multiply
imputed shares by observed market shocks. Shocks enter exactly (never
smoothed); only the shares are imputed. Supports three denominator versions
matching athr_exposure_{hc,all,treated_hc}.dta, and two smoothers (K-NN
weights W, or per-market Ridge on TF-IDF).

Math:
  s_ik    = (PI i's pre-period spend in market k) / (PI i's pre-period DENOM)
  S       sparse FOIA x K_treated
  S_hat   = smoothed universe x K_treated
              K-NN:  W @ S
              Ridge: fit Ridge(X_foia -> S[:,k]) per market k, predict on X_univ
  z_hat   = S_hat @ g      universe x 1 shift-share exposure
  S_sum   = rowsum(S_hat)  universe x 1 sum-of-shares control (mkt_spend_shr)

Denominators per --version:
  hc         : denom = sum of PI's spend on (Non-Lab==False & keep==1) categories
                (matches build.do's tot_hc_spend so exposure_ss scales like the
                observed athr_exposure_hc.dta.)
  all        : denom = sum of PI's spend on Non-Lab==False categories
                (all lab consumables — matches athr_exposure_all.dta.)
  treated_hc : denom = sum of PI's spend on the 46 treated HC categories only
                (matches athr_exposure_treated_hc.dta where mkt_spend_shr = 1
                by construction on the anchor side.)

Inputs:
  ../../external/exposure_wts/athr_category_spend.dta       PI x category x year
  --betas-path (default did_coefs_eb_price.dta)             per-market shocks g_k = b
  # for --method knn:
  ../../output/weight_matrix{tag}{k_sfx}.npz                universe x FOIA W
  # for --method ridge:
  ../../output/tfidf_foia{tag}.npz                          n_foia x V TF-IDF
  ../../output/tfidf_universe{tag}.npz                      n_univ x V TF-IDF
  ../../output/foia_ids_ordered{tag}.csv                    row order
  ../../output/universe_ids{tag}.parquet                    row order

Outputs (per --version, per --method):
  ../../output/final_imputed_shift_share_{version}{tag}{method_sfx}{filter_sfx}{k_sfx}.csv
       columns: athr_id, exposure_ss, sum_imputed_shares
  ../../output/imputed_shares_matrix_{version}{tag}{method_sfx}{filter_sfx}{k_sfx}.npz
       S_hat as CSR
  ../../output/imputed_shares_markets_{version}{tag}{method_sfx}{filter_sfx}{k_sfx}.csv
       per-market diagnostics: category, g, s_bar, rotemberg_wt, n_foia_pis
       (+ alpha, in_r2 for --method ridge)
  ../../output/shock_balance_{version}{tag}{method_sfx}{filter_sfx}{k_sfx}.csv
       BHJ shock-balance regression coefficients.

method_sfx = ""       for knn (backward-compat with existing K-NN outputs)
           = "_ridge" for ridge
eb_sfx     = ""       --eb-alpha 0 (default, no shrinkage)
           = "_eb{a}k"/"_ebmed" EB-shrink anchor share rows with prior
                      pseudo-spend a before imputation; also saves
                      foia_self_exposure{stem}.csv. --eb-prior cluster/peer
                      shrink toward local (field-specific) baskets instead of
                      the pool mean: "_ebc{a}k" / "_ebp{a}k".
filter_sfx = "_cf[N]" --cluster-filter on the full label file, N =
                      --min-foia-per-cluster when > 1
           + "_ls"    --ls-filter (life-science author mask; suffix via --ls-sfx,
                      e.g. "_ls100" for a K=100-based mask)
           + "_msNNN" --min-max-sim
k_sfx      = ""       --k 5 (default, untagged weight_matrix.npz)
           = "_k3"    --k 3 (reads weight_matrix_k3.npz; knn only)

The 2x2 of interest: bare (full universe), _cf (FOIA-anchored clusters),
_ls (life-science authors), _cf_ls (both).
"""
import argparse
import os
import numpy as np
import pandas as pd
import scipy.sparse as sp
from scipy.stats import norm
from sklearn.linear_model import Ridge, RidgeCV

OUT_DIR = "../../output"
CATEGORY_SPEND_FILE = "../../external/exposure_wts/athr_category_spend.dta"
# Per-version pre-computed share files from derived/exposure_msr/build.do.
# We read `spend / tot_shr_spend` directly from these instead of recomputing
# pi_total inline, so the shift-share denominator matches build.do exactly.
CATEGORY_SHARE_FILE = "../../external/exposure_wts/athr_exposure_by_category_{version}.dta"
OBSERVED_EXPOSURE_FILE = "../../external/exposure_wts/athr_exposure.dta"
DEFAULT_BETAS_FILE = (
    "/n/holylabs/LABS/pakes_lab/Lab/sci_eq/analysis/first_stage/output/"
    "did_coefs_eb_price.dta"
)
PRE_PERIOD_LAST_YEAR = 2013
VERSIONS = ["hc", "all", "treated_hc"]
DEFAULT_ALPHAS = np.logspace(-3, 4, 30)

CATEGORY_RENAMES = {
    "acrylamide/bis solution": "acrylamide-bis solution",
    "dmem/f-12": "dmem-f-12",
}


def load_shocks(betas_path):
    df = pd.read_stata(betas_path)
    if "category" not in df.columns or "b" not in df.columns:
        raise SystemExit(
            f"{betas_path} must have columns [category, b]: got {list(df.columns)}"
        )
    df["category"] = df["category"].replace(CATEGORY_RENAMES)
    df = df.dropna(subset=["b"]).drop_duplicates(subset=["category"])
    df = df.reset_index(drop=True)
    return df["category"].tolist(), df["b"].to_numpy(dtype=np.float64)


def build_share_matrix(share_path, foia_ids, market_index, version):
    """Build FOIA x K_treated share matrix S using the pre-computed denominator.

    Reads athr_exposure_by_category_{version}.dta (produced by build.do in
    derived/exposure_msr) which already has (spend, tot_shr_spend) per
    (PI, category), so we can take shr = spend / tot_shr_spend directly. This
    guarantees the shift-share denominator exactly matches the one used to
    construct athr_exposure_{version}.dta's scalar mkt_spend_shr — the K-NN
    aggregation S_sum will then match the scalar mkt_spend_shr column
    (up to floating point).
    """
    df = pd.read_stata(share_path)
    df["athr_id"] = df["athr_id"].astype(str)
    df["category"] = df["category"].astype(str).replace(CATEGORY_RENAMES)
    df = df.dropna(subset=["spend", "tot_shr_spend"])
    df = df[(df["spend"] > 0) & (df["tot_shr_spend"] > 0)]
    df["share"] = df["spend"].astype(float) / df["tot_shr_spend"].astype(float)

    # Denominator spend per anchor (constant within athr_id), captured before
    # the treated-market restriction; 0 for anchors with no visible spend.
    denom = df.drop_duplicates("athr_id").set_index("athr_id")["tot_shr_spend"]
    T = denom.reindex(foia_ids).fillna(0.0).to_numpy(dtype=np.float64)

    # Restrict to the 46 treated categories (columns of S).
    df = df[df["category"].isin(market_index)]

    foia_id_set = set(foia_ids)
    df = df[df["athr_id"].isin(foia_id_set)]

    foia_pos = {aid: i for i, aid in enumerate(foia_ids)}
    market_pos = {c: i for i, c in enumerate(market_index)}
    rows = df["athr_id"].map(foia_pos).to_numpy()
    cols_idx = df["category"].map(market_pos).to_numpy()
    data = df["share"].to_numpy(dtype=np.float64)

    S = sp.csr_matrix(
        (data, (rows, cols_idx)),
        shape=(len(foia_ids), len(market_index)),
    )

    coverage = pd.Series(
        np.asarray((S != 0).sum(axis=0)).ravel(),
        index=market_index,
        name="n_foia_pis",
    )
    return S, coverage, T


def compute_pi_characteristics(spend_path, foia_ids):
    df = pd.read_stata(
        spend_path,
        columns=["athr_id", "category", "year", "spend", "lab_spend"],
    )
    df = df[df["year"] <= PRE_PERIOD_LAST_YEAR]
    df = df.dropna(subset=["spend"])
    df["lab_spend"] = df["lab_spend"].fillna(0)
    df = df[df["athr_id"].isin(set(foia_ids))]

    grp = df.groupby("athr_id")
    pi = pd.DataFrame({
        "total_spend": grp["spend"].sum(),
        "lab_spend_total": grp["lab_spend"].sum(),
        "n_cats": grp["category"].nunique(),
    }).reset_index()
    pi["log_total_spend"] = np.log(pi["total_spend"].clip(lower=1))
    pi["log_lab_spend"] = np.log(pi["lab_spend_total"].clip(lower=1))
    pi["lab_share"] = pi["lab_spend_total"] / pi["total_spend"].clip(lower=1)

    pi = pi.set_index("athr_id").reindex(foia_ids).reset_index()
    return pi


def shock_balance(S, g, pi_chars, char_cols, market_index):
    s_bar_col = np.asarray(S.sum(axis=0)).ravel()
    if s_bar_col.sum() == 0:
        print("  WARN: S has zero mass; skip shock balance.")
        return None

    print("\n--- Shock balance (Borusyak-Hull-Jaravel) ---")
    print("  Regression: g_k = a + b * X_bar_k + e,  weights = Sum_i s_ik")
    print("  H0: shocks are quasi-randomly assigned wrt pre-period X => b approx 0")
    print()
    print(f"  {'characteristic':<22s}  {'beta':>10s}  {'se':>10s}  {'t':>7s}  {'p':>6s}")

    rows = []
    for col in char_cols:
        X = pi_chars[col].to_numpy(dtype=np.float64)
        mask = np.isfinite(X)
        if mask.sum() == 0:
            print(f"  {col:<22s}  (all NaN, skipped)")
            continue
        X = np.where(mask, X, X[mask].mean())

        X_bar_num = np.asarray(S.T @ X).ravel()
        X_bar = np.where(s_bar_col > 0, X_bar_num / np.maximum(s_bar_col, 1e-12), 0.0)

        w = s_bar_col
        wsum = w.sum()
        Xb_mean = (w * X_bar).sum() / wsum
        g_mean = (w * g).sum() / wsum
        Xc = X_bar - Xb_mean
        gc = g - g_mean
        num = (w * Xc * gc).sum()
        den = (w * Xc * Xc).sum()
        if den <= 0:
            print(f"  {col:<22s}  (no variation in X_bar, skipped)")
            continue
        beta = num / den
        resid = gc - beta * Xc
        K_eff = int((w > 0).sum())
        sigma2 = (w * resid ** 2).sum() / max(K_eff - 2, 1)
        se = np.sqrt(sigma2 / den)
        t = beta / se if se > 0 else np.nan
        p = 2 * (1 - norm.cdf(abs(t))) if np.isfinite(t) else np.nan
        rows.append((col, beta, se, t, p, K_eff))
        print(f"  {col:<22s}  {beta:+10.4f}  {se:10.4f}  {t:+7.2f}  {p:6.3f}")

    return pd.DataFrame(
        rows,
        columns=["characteristic", "beta", "se", "t", "p_value", "n_markets"],
    )


def report_W_health(W):
    row_sums = np.asarray(W.sum(axis=1)).ravel()
    nz = row_sums > 0
    print(f"  W rows with any weight: {nz.sum():,}/{W.shape[0]:,}")
    if nz.sum() == 0:
        return
    rs = row_sums[nz]
    print(
        f"  W row-sum stats (nonzero rows): "
        f"mean={rs.mean():.4f}  p5={np.percentile(rs,5):.4f}  "
        f"p95={np.percentile(rs,95):.4f}"
    )
    if not np.allclose(rs, 1.0, atol=1e-3):
        print(
            "  WARN: W is not L1-normalized. S_hat entries will be similarity-"
            "weighted SUMS, not averages."
        )


def eb_shrink_shares(S, T, alpha, prior=None):
    """Dirichlet-style shrinkage of each anchor's share row toward a prior
    basket:
        s~_ik = (T_i * s_ik + alpha * prior_ik) / (T_i + alpha)
    T_i is the anchor's denominator spend, so own-data weight T_i/(T_i+alpha)
    grows with how much of the anchor's purchasing we actually observe.
    prior is an n x K matrix of per-anchor prior baskets; None = the spend-
    weighted pool mean for every anchor. Rows with T_i = 0 (no visible
    denominator spend) are left all-zero rather than assigned the prior.
    Returns (S_tilde csr, sbar, own_wt)."""
    Sd = np.asarray(S.todense(), dtype=np.float64)
    obs = T > 0
    sbar = (T[obs] @ Sd[obs]) / T[obs].sum()
    if prior is None:
        prior = np.tile(sbar, (len(T), 1))
    own_wt = np.zeros_like(T)
    own_wt[obs] = T[obs] / (T[obs] + alpha)
    St = Sd.copy()
    St[obs] = own_wt[obs, None] * Sd[obs] + (1.0 - own_wt[obs, None]) * prior[obs]
    return sp.csr_matrix(St), sbar, own_wt


def build_local_priors(S, T, args, foia_ids, tag, alpha):
    """Per-anchor prior baskets for --eb-prior cluster/peer. Both are leave-
    one-out and spend-weighted, so well-measured anchors define their
    neighborhood's prior and no anchor is its own prior.

    cluster: LOO spend-weighted mean basket of same-cluster anchors, itself
             blended toward the global mean with weight T_cluster/(T_cluster
             + alpha) so single-anchor / thin clusters fall back gracefully.
    peer   : LOO mean basket over all other anchors, weighted by
             (TF-IDF cosine to the anchor) x (denominator spend)."""
    Sd = np.asarray(S.todense(), dtype=np.float64)
    n = len(T)
    tw = T[:, None] * Sd
    gbar = tw.sum(axis=0) / T.sum()
    prior = np.zeros_like(Sd)
    if args.eb_prior == "peer":
        X = sp.load_npz(f"{OUT_DIR}/tfidf_foia{tag}.npz").tocsr().astype(np.float64)
        if X.shape[0] != n:
            raise SystemExit(f"tfidf_foia{tag}.npz rows {X.shape[0]} != n_foia {n}")
        A = np.asarray((X @ X.T).todense())
        np.fill_diagonal(A, 0.0)
        num = A @ tw
        den = A @ T
        ok = den > 0
        prior[ok] = num[ok] / den[ok, None]
        prior[~ok] = gbar
    else:
        cf = args.eb_cluster_file or args.cluster_filter
        if not cf or not os.path.exists(cf):
            raise SystemExit("--eb-prior cluster needs --eb-cluster-file (or --cluster-filter)")
        cl = pd.read_csv(cf, dtype={"athr_id": str})
        labels = cl.set_index("athr_id")["cluster_label"].reindex(foia_ids).to_numpy()
        idx = np.arange(n)
        for i in range(n):
            same = (labels == labels[i]) & (idx != i) if pd.notna(labels[i]) else np.zeros(n, bool)
            Tc = T[same].sum()
            cbar = (T[same] @ Sd[same]) / Tc if Tc > 0 else gbar
            w = Tc / (Tc + alpha)
            prior[i] = w * cbar + (1.0 - w) * gbar
    return prior


def impute_knn(S, W):
    """K-NN: S_hat = W @ S. Returns CSR."""
    return (W @ S).tocsr()


def impute_ridge(S, X_foia, X_univ, alphas, clip_nonneg=True, verbose=True):
    """Per-market ridge. For each column k of S:
        RidgeCV on (X_foia, S[:,k]) -> alpha_k
        Ridge fit -> beta_k, intercept_k
        pred_k = X_univ @ beta_k + intercept_k
    Returns (S_hat as CSR, per-market diagnostics as DataFrame)."""
    K = S.shape[1]
    n_univ = X_univ.shape[0]
    S_hat = np.zeros((n_univ, K), dtype=np.float64)
    diag_rows = []
    S_dense = S.toarray() if sp.issparse(S) else np.asarray(S)
    for k in range(K):
        y = S_dense[:, k].astype(np.float64)
        n_nz = int((y > 0).sum())
        if y.std() == 0.0 or n_nz == 0:
            S_hat[:, k] = float(y.mean())
            diag_rows.append({"col": k, "alpha": np.nan, "in_r2": 0.0,
                              "n_nonzero": n_nz})
            if verbose:
                print(f"    market {k+1}/{K}: zero variance, using mean={y.mean():.4g}",
                      flush=True)
            continue
        cv = RidgeCV(alphas=alphas, fit_intercept=True, scoring=None, cv=None)
        cv.fit(X_foia, y)
        alpha = float(cv.alpha_)
        model = Ridge(alpha=alpha, fit_intercept=True).fit(X_foia, y)
        pred = X_univ.dot(model.coef_.astype(np.float64)) + float(model.intercept_)
        if clip_nonneg:
            np.maximum(pred, 0.0, out=pred)
        S_hat[:, k] = pred
        in_r2 = float(model.score(X_foia, y))
        diag_rows.append({"col": k, "alpha": alpha, "in_r2": in_r2,
                          "n_nonzero": n_nz})
        if verbose and (k + 1) % 10 == 0:
            print(f"    market {k+1}/{K}  alpha={alpha:.3g}  in_R2={in_r2:.3f}  "
                  f"n_nz={n_nz}", flush=True)
    return sp.csr_matrix(S_hat), pd.DataFrame(diag_rows)


def apply_filters(df_univ, S_hat, args, df_foia, diag_file):
    """Apply --min-max-sim, --cluster-filter and --ls-filter.
    Returns filtered (df_univ, S_hat)."""
    if args.min_max_sim > 0:
        if not os.path.exists(diag_file):
            raise SystemExit(f"--min-max-sim needs {diag_file}")
        diag = pd.read_parquet(diag_file)[["athr_id", "max_sim"]]
        n_before = len(df_univ)
        df_univ = df_univ.merge(diag, on="athr_id", how="left")
        keep_mask = df_univ["max_sim"] >= args.min_max_sim
        keep_idx_mask = keep_mask.to_numpy()
        df_univ = df_univ.loc[keep_mask].drop(columns=["max_sim"])
        S_hat = S_hat[keep_idx_mask]
        print(f"  max_sim filter (>= {args.min_max_sim}): "
              f"kept {len(df_univ):,}/{n_before:,}")

    if args.cluster_filter:
        if not os.path.exists(args.cluster_filter):
            raise SystemExit(f"--cluster-filter not found: {args.cluster_filter}")
        cl = pd.read_csv(args.cluster_filter)
        if "cluster_label" not in cl.columns or "athr_id" not in cl.columns:
            raise SystemExit(
                f"--cluster-filter needs [athr_id, cluster_label]: got {list(cl.columns)}"
            )
        min_n = max(1, args.min_foia_per_cluster)
        foia_in_cl = df_foia.merge(cl, on="athr_id", how="inner")
        foia_counts = foia_in_cl.groupby("cluster_label").size()
        foia_clusters = set(foia_counts[foia_counts >= min_n].index)
        n_before = len(df_univ)
        df_univ = df_univ.merge(cl, on="athr_id", how="left")
        keep_mask = (
            df_univ["cluster_label"].notna()
            & df_univ["cluster_label"].isin(foia_clusters)
        )
        keep_idx_mask = keep_mask.to_numpy()
        df_univ = df_univ.loc[keep_mask].drop(columns=["cluster_label"])
        S_hat = S_hat[keep_idx_mask]
        print(f"  cluster filter ({args.cluster_filter}, min-foia-per-cluster={min_n}): "
              f"kept {len(df_univ):,}/{n_before:,}")

    if args.ls_filter:
        if not os.path.exists(args.ls_filter):
            raise SystemExit(f"--ls-filter not found: {args.ls_filter}")
        ls = pd.read_csv(args.ls_filter, dtype={"athr_id": str})
        if "athr_id" not in ls.columns:
            raise SystemExit(
                f"--ls-filter needs an athr_id column: got {list(ls.columns)}"
            )
        n_before = len(df_univ)
        keep_mask = df_univ["athr_id"].isin(set(ls["athr_id"]))
        keep_idx_mask = keep_mask.to_numpy()
        df_univ = df_univ.loc[keep_mask]
        S_hat = S_hat[keep_idx_mask]
        print(f"  ls filter ({args.ls_filter}): "
              f"kept {len(df_univ):,}/{n_before:,}")

    return df_univ, S_hat


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="",
                    help="Suffix matching --tag in 1_vectorize / 2_similarity_wts. "
                         "Empty = baseline artifacts.")
    ap.add_argument("--versions", nargs="+", default=VERSIONS, choices=VERSIONS,
                    help="Which exposure-denominator versions to impute (loops).")
    ap.add_argument("--method", choices=["knn", "ridge"], default="knn",
                    help="Smoother for S -> S_hat. 'knn' uses the W matrix from "
                         "2_similarity_wts.py (backward-compat with the previous "
                         "4_ default). 'ridge' fits a Ridge per market on TF-IDF, "
                         "using the same X_foia/X_univ artifacts as "
                         "3_impute_exposure_ridge.py.")
    ap.add_argument("--betas-path", default=DEFAULT_BETAS_FILE,
                    help="Stata file with columns [category, b] giving per-market shocks.")
    ap.add_argument("--alphas", nargs="+", type=float, default=None,
                    help="Ridge alpha grid (only used if --method ridge). "
                         "Default logspace(-3, 4, 30).")
    ap.add_argument("--cluster-filter", default="",
                    help="author_static_clusters_{K}.csv (full labels) from "
                         "us_cluster_fields. After imputation, drop universe "
                         "authors whose cluster has fewer FOIA PIs than "
                         "--min-foia-per-cluster. Adds '_cf' to output names. "
                         "Combine with --ls-filter for '_cf_ls'.")
    ap.add_argument("--min-foia-per-cluster", type=int, default=1,
                    help="Minimum FOIA count required for a cluster to be kept "
                         "under --cluster-filter. 1 -> '_cf', 2 -> '_cf2', "
                         "5 -> '_cf5'. Matches 3_impute_exposure.py.")
    ap.add_argument("--ls-filter", default="",
                    help="author_static_clusters_{K}_ls.csv from "
                         "us_cluster_fields. After imputation, drop universe "
                         "authors not on this life-science author list. Adds "
                         "--ls-sfx to output names.")
    ap.add_argument("--ls-sfx", default="_ls",
                    help="Output suffix used when --ls-filter is set. Use e.g. "
                         "'_ls100' for a mask built on the K=100 clustering so "
                         "it coexists with the K=30 '_ls' outputs.")
    ap.add_argument("--k", type=int, default=5,
                    help="Which K-NN weight matrix to load (knn only): 5 = the "
                         "untagged weight_matrix.npz (default), any other k "
                         "reads weight_matrix_k{k}.npz (built by "
                         "2_similarity_wts.py --k {k} --out-tag k{k}) and "
                         "appends '_k{k}' to output names.")
    ap.add_argument("--min-max-sim", type=float, default=0.0,
                    help="Drop universe authors whose max cosine to any FOIA PI is "
                         "below this threshold. Default 0.0 = keep all.")
    ap.add_argument("--eb-alpha", default="0",
                    help="Empirical-Bayes shrinkage of anchor share rows toward "
                         "the spend-weighted pool-mean basket before imputation: "
                         "s_ik <- (T_i*s_ik + a*sbar_k)/(T_i + a), where T_i is "
                         "the anchor's denominator spend. Give a in dollars, or "
                         "'median' = median T_i among observed anchors, computed "
                         "per version. 0 = off. Appends '_eb{a}k'/'_ebmed' to "
                         "output names and saves foia_self_exposure{stem}.csv.")
    ap.add_argument("--eb-prior", choices=["global", "cluster", "peer"], default="global",
                    help="Prior basket for --eb-alpha shrinkage. global: spend-"
                         "weighted pool mean ('_eb'). cluster: leave-one-out "
                         "spend-weighted mean of same-cluster anchors, blended "
                         "toward the global mean by cluster spend ('_ebc'; needs "
                         "--eb-cluster-file or --cluster-filter). peer: leave-one-"
                         "out TF-IDF-similarity x spend weighted mean over all "
                         "other anchors ('_ebp'). Local priors preserve cross-"
                         "field basket differences; only within-neighborhood "
                         "idiosyncrasy is shrunk.")
    ap.add_argument("--eb-cluster-file", default="",
                    help="athr_id,cluster_label csv defining --eb-prior cluster "
                         "neighborhoods; defaults to --cluster-filter when set.")
    args = ap.parse_args()

    tag = args.tag
    if tag and not tag.startswith("_"):
        tag = "_" + tag

    method_sfx = "" if args.method == "knn" else "_ridge"
    filter_sfx = ""
    if args.cluster_filter:
        filter_sfx += "_cf" if args.min_foia_per_cluster <= 1 else f"_cf{args.min_foia_per_cluster}"
    if args.ls_filter:
        filter_sfx += args.ls_sfx if args.ls_sfx.startswith("_") else "_" + args.ls_sfx
    if args.min_max_sim > 0:
        filter_sfx += f"_ms{int(round(args.min_max_sim * 100)):03d}"
    k_sfx = "" if (args.k == 5 or args.method != "knn") else f"_k{args.k}"
    eb_alpha = None
    eb_sfx = ""
    if args.eb_alpha != "0":
        prior_tag = {"global": "", "cluster": "c", "peer": "p"}[args.eb_prior]
        if args.eb_alpha == "median":
            eb_sfx = f"_eb{prior_tag}med"
        else:
            eb_alpha = float(args.eb_alpha)
            if eb_alpha <= 0:
                raise SystemExit(f"--eb-alpha must be positive or 'median': {args.eb_alpha}")
            eb_sfx = f"_eb{prior_tag}{eb_alpha / 1000:g}k"

    # ---- Load ids and shocks (shared across versions) ----
    universe_ids_file = f"{OUT_DIR}/universe_ids{tag}.parquet"
    foia_ids_file = f"{OUT_DIR}/foia_ids_ordered{tag}.csv"
    diag_file = f"{OUT_DIR}/match_diagnostics{tag}.parquet"
    for p in (universe_ids_file, foia_ids_file):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")
    if not os.path.exists(CATEGORY_SPEND_FILE):
        raise SystemExit(f"missing: {CATEGORY_SPEND_FILE}")
    for v in args.versions:
        p = CATEGORY_SHARE_FILE.format(version=v)
        if not os.path.exists(p):
            raise SystemExit(f"missing per-version share file: {p}")
    if not os.path.exists(args.betas_path):
        raise SystemExit(f"missing: {args.betas_path}")

    print("Loading universe + FOIA id orders ...")
    df_univ_master = pd.read_parquet(universe_ids_file)
    df_univ_master["athr_id"] = df_univ_master["athr_id"].astype(str)
    df_foia = pd.read_csv(foia_ids_file, dtype={"athr_id": str})
    foia_ids = df_foia["athr_id"].astype(str).tolist()

    print(f"Loading shocks from {args.betas_path} ...")
    market_index, g = load_shocks(args.betas_path)
    print(f"  markets with shocks: {len(market_index)}")
    print(f"  g_k stats: mean={g.mean():.4f}  sd={g.std():.4f}  "
          f"min={g.min():.4f}  max={g.max():.4f}")

    # ---- Load the smoother once (W for knn, TF-IDF for ridge) ----
    W = None
    X_foia = None
    X_univ = None
    if args.method == "knn":
        weights_file = f"{OUT_DIR}/weight_matrix{tag}{k_sfx}.npz"
        if not os.path.exists(weights_file):
            raise SystemExit(f"missing: {weights_file}")
        print(f"Loading W (tag={args.tag!r}, k={args.k}) ...")
        W = sp.load_npz(weights_file)
        print(f"  W shape: {W.shape}  nnz: {W.nnz:,}")
        report_W_health(W)
        if W.shape != (len(df_univ_master), len(foia_ids)):
            raise SystemExit(
                f"W shape {W.shape} != (n_univ={len(df_univ_master)}, n_foia={len(foia_ids)})"
            )
    else:
        foia_matrix_file = f"{OUT_DIR}/tfidf_foia{tag}.npz"
        univ_matrix_file = f"{OUT_DIR}/tfidf_universe{tag}.npz"
        for p in (foia_matrix_file, univ_matrix_file):
            if not os.path.exists(p):
                raise SystemExit(f"missing: {p}")
        print(f"Loading TF-IDF matrices (tag={args.tag!r}) ...")
        X_foia = sp.load_npz(foia_matrix_file).tocsr().astype(np.float64)
        X_univ = sp.load_npz(univ_matrix_file).tocsr()
        print(f"  X_foia={X_foia.shape}  X_univ={X_univ.shape}  dtype={X_univ.dtype}")
        if X_foia.shape[0] != len(foia_ids):
            raise SystemExit(f"X_foia rows {X_foia.shape[0]} != n_foia {len(foia_ids)}")
        if X_univ.shape[0] != len(df_univ_master):
            raise SystemExit(f"X_univ rows {X_univ.shape[0]} != n_univ {len(df_univ_master)}")

    alphas = np.asarray(args.alphas) if args.alphas else DEFAULT_ALPHAS

    # ---- PI characteristics (shared) ----
    print("Computing FOIA pre-period characteristics ...")
    pi_chars = compute_pi_characteristics(CATEGORY_SPEND_FILE, foia_ids)

    # ---- Per-version loop ----
    version_summary_rows = []
    for version in args.versions:
        print(f"\n{'='*78}")
        print(f"version={version}   method={args.method}   tag={args.tag!r}")
        print(f"{'='*78}")

        share_path = CATEGORY_SHARE_FILE.format(version=version)
        print(f"Building FOIA share matrix S from {share_path} (version={version}) ...")
        S, coverage, T = build_share_matrix(
            share_path, foia_ids, market_index, version,
        )
        print(f"  S shape: {S.shape}  nnz: {S.nnz:,}  "
              f"density: {S.nnz / max(S.shape[0]*S.shape[1], 1):.4f}")
        print(f"  FOIA PIs with >=1 treated-market share: "
              f"{(np.asarray(S.sum(axis=1)).ravel() > 0).sum():,} / {S.shape[0]:,}")
        cov = coverage.to_numpy()
        print(f"  per-market coverage: min={cov.min()}  "
              f"p5={int(np.percentile(cov,5))}  p50={int(np.percentile(cov,50))}  "
              f"p95={int(np.percentile(cov,95))}  max={cov.max()}")

        eb_df = None
        if eb_sfx:
            obs = T > 0
            alpha_v = eb_alpha if eb_alpha is not None else float(np.median(T[obs]))
            self_raw = np.asarray(S @ g).ravel()
            prior = None
            if args.eb_prior != "global":
                prior = build_local_priors(S, T, args, foia_ids, tag, alpha_v)
            S, sbar, own_wt = eb_shrink_shares(S, T, alpha_v, prior=prior)
            self_eb = np.asarray(S @ g).ravel()
            print(f"\n  --- EB shrinkage (alpha=${alpha_v:,.0f}, prior={args.eb_prior}) ---")
            print(f"  rows shrunk: {obs.sum()}/{len(T)}  (T=0 rows left at zero)")
            print(f"  self-exposure sd across anchors: raw={self_raw[obs].std():.4f}"
                  f"  shrunk={self_eb[obs].std():.4f}"
                  f"  (retained {self_eb[obs].std() / max(self_raw[obs].std(), 1e-12):.0%})")
            q = np.percentile(own_wt[obs], [25, 50, 75])
            print(f"  own-data weight T/(T+alpha): p25={q[0]:.2f}  "
                  f"p50={q[1]:.2f}  p75={q[2]:.2f}")
            movers = np.argsort(np.abs(self_eb - self_raw))[::-1][:5]
            print("  largest self-exposure changes:")
            for i in movers:
                print(f"    {foia_ids[i]}: {self_raw[i]:+.4f} -> {self_eb[i]:+.4f}"
                      f"  (T=${T[i]:,.0f}, own_wt={own_wt[i]:.2f})")
            eb_df = pd.DataFrame({
                "athr_id": foia_ids,
                "T_denom_spend": T,
                "own_wt": own_wt,
                "self_exposure_raw": self_raw,
                "self_exposure_eb": self_eb,
                "sum_shares_eb": np.asarray(S.sum(axis=1)).ravel(),
            })

        print(f"Imputing shares  (method={args.method})  ...")
        if args.method == "knn":
            S_hat = impute_knn(S, W)
            ridge_diag = None
        else:
            S_hat, ridge_diag = impute_ridge(S, X_foia, X_univ, alphas)

        print("Aggregating: z_hat = S_hat @ g,  S_sum = rowsum(S_hat) ...")
        z_hat = np.asarray(S_hat @ g).ravel()
        S_sum = np.asarray(S_hat.sum(axis=1)).ravel()

        s_bar = np.asarray(S_hat.mean(axis=0)).ravel()
        ss = (s_bar ** 2).sum()
        eff_n_norm = (s_bar.sum() ** 2) / ss if ss > 0 else 0.0
        print(f"  effective number of shocks (BHJ-style): {eff_n_norm:.2f}")

        # Exposure comparison against observed anchor-level exposure
        self_z = np.asarray(S @ g).ravel()
        foia_mask = self_z != 0
        print("\n  --- Exposure level comparison ---")
        print(f"  Self-imputed FOIA exposure (S @ g):")
        print(f"    n nonzero PIs: {foia_mask.sum()}/{len(self_z)}")
        if foia_mask.any():
            print(f"    mean={self_z[foia_mask].mean():+.5f}  "
                  f"sd={self_z[foia_mask].std():.5f}  "
                  f"med={np.median(self_z[foia_mask]):+.5f}")
        print(f"  Universe imputed exposure (S_hat @ g):")
        z_nz = z_hat != 0
        print(f"    n nonzero authors: {z_nz.sum():,}/{len(z_hat):,}")
        if z_nz.any():
            print(f"    mean={z_hat[z_nz].mean():+.5f}  "
                  f"sd={z_hat[z_nz].std():.5f}  "
                  f"med={np.median(z_hat[z_nz]):+.5f}")

        # Shock balance test (S only, so version-invariant results reflect topical
        # confounds; still useful per-version for the record)
        balance_df = shock_balance(
            S, g, pi_chars,
            char_cols=["log_total_spend", "log_lab_spend", "n_cats", "lab_share"],
            market_index=market_index,
        )

        # Rotemberg weights
        rot_num = s_bar * g
        rot_den = rot_num.sum()
        rot_wt = rot_num / rot_den if rot_den != 0 else np.zeros_like(rot_num)
        top = np.argsort(np.abs(rot_wt))[::-1][:10]
        print("  top-10 |Rotemberg weight| markets:")
        for j in top:
            print(f"    {market_index[j]:<40s}  alpha_k={rot_wt[j]:+.3f}  "
                  f"s_bar={s_bar[j]:.4f}  g={g[j]:+.4f}")

        # Apply optional filters (per-version — cluster filter usually chosen globally)
        df_univ = df_univ_master.copy()
        df_univ["exposure_ss"] = z_hat
        df_univ["sum_imputed_shares"] = S_sum
        df_univ, S_hat = apply_filters(df_univ, S_hat, args, df_foia, diag_file)

        # ---- Save outputs (version-specific filenames) ----
        stem = f"_{version}{tag}{method_sfx}{eb_sfx}{filter_sfx}{k_sfx}"
        out_csv = f"{OUT_DIR}/final_imputed_shift_share{stem}.csv"
        out_npz = f"{OUT_DIR}/imputed_shares_matrix{stem}.npz"
        out_markets = f"{OUT_DIR}/imputed_shares_markets{stem}.csv"

        df_univ[["athr_id", "exposure_ss", "sum_imputed_shares"]].to_csv(out_csv, index=False)
        sp.save_npz(out_npz, S_hat)

        markets_df = pd.DataFrame({
            "market_idx": np.arange(len(market_index)),
            "category": market_index,
            "g": g,
            "s_bar": s_bar,
            "rotemberg_wt": rot_wt,
            "n_foia_pis": coverage.to_numpy(),
        })
        if ridge_diag is not None:
            markets_df = markets_df.merge(
                ridge_diag.rename(columns={"col": "market_idx"}),
                on="market_idx", how="left",
            )
        markets_df.to_csv(out_markets, index=False)

        if balance_df is not None:
            out_balance = f"{OUT_DIR}/shock_balance{stem}.csv"
            balance_df.to_csv(out_balance, index=False)
            print(f"  Saved {out_balance}")

        if eb_df is not None:
            out_self = f"{OUT_DIR}/foia_self_exposure{stem}.csv"
            eb_df.to_csv(out_self, index=False)
            print(f"  Saved {out_self}  (shrunk anchor-level self exposure)")

        print(f"  Saved {out_csv}")
        print(f"  Saved {out_npz}  (universe x K_treated imputed share matrix)")
        print(f"  Saved {out_markets}")

        version_summary_rows.append({
            "version": version,
            "method":  args.method,
            "n_foia_with_shares":     int((np.asarray(S.sum(axis=1)).ravel() > 0).sum()),
            "z_hat_mean_universe":    float(z_hat.mean()),
            "z_hat_sd_universe":      float(z_hat.std()),
            "S_sum_mean_universe":    float(S_sum.mean()),
            "S_sum_sd_universe":      float(S_sum.std()),
            "eff_n_shocks":           float(eff_n_norm),
        })

    print("\n" + "=" * 78)
    print("Per-version shift-share imputation summary")
    print("=" * 78)
    df_summary = pd.DataFrame(version_summary_rows)
    with pd.option_context("display.width", 220,
                           "display.max_columns", None,
                           "display.float_format", "{:.4f}".format):
        print(df_summary.to_string(index=False))
    summary_out = f"{OUT_DIR}/shift_share_summary{tag}{method_sfx}{eb_sfx}{filter_sfx}{k_sfx}.csv"
    df_summary.to_csv(summary_out, index=False)
    print(f"\nSaved {summary_out}")
    print("Done!")


if __name__ == "__main__":
    main()
