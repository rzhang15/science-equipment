"""
KNN shift-share imputation with optional row-sum-preserving EB denoising.

Core object:
    s_ik = PI i's pre-period share in treated market k

EB denoises the composition of s_i across treated markets while preserving:

    sum_k s_ik^EB = sum_k s_ik^raw

for every FOIA PI.

After EB:
    S_hat = W @ S
    exposure_ss = S_hat @ g
    sum_imputed_shares = rowsum(S_hat)

There is no separate imputation of total treated-market share.

EB priors
---------
peer:
    Shrink toward the similarity-weighted basket of the top K most similar
    OTHER FOIA PIs.

cluster:
    Shrink toward the equal-weighted basket of the OTHER FOIA PIs in the same
    cluster.

There is NO global prior.

If a PI has no usable peer/cluster prior, its row is left unchanged.

Recommended:
    --eb-own-weight 0.90
    --eb-prior peer
    --eb-peer-k 5

Filters / suffixes retained:
    --cluster-filter + --min-foia-per-cluster
        -> _cf, _cf2, _cf5

    --ls-filter + --ls-sfx
        -> _ls, _lsa, ...

    --min-max-sim .25
        -> _ms025

    --k 3
        -> _k3
"""

import argparse
import os

import numpy as np
import pandas as pd
import scipy.sparse as sp
from scipy.stats import norm


OUT_DIR = "../../output"
CATEGORY_SPEND_FILE = "../../external/exposure_wts/athr_category_spend.dta"
CATEGORY_SHARE_FILE = "../../external/exposure_wts/athr_exposure_by_category_{version}.dta"

DEFAULT_BETAS_FILE = (
    "/n/holylabs/LABS/pakes_lab/Lab/sci_eq/analysis/"
    "first_stage/output/did_coefs_eb_price.dta"
)

VERSIONS = ["hc", "all", "treated_hc"]
PRE_PERIOD_LAST_YEAR = 2013

CATEGORY_RENAMES = {
    "acrylamide/bis solution": "acrylamide-bis solution",
    "dmem/f-12": "dmem-f-12",
}


# =============================================================================
# Loading
# =============================================================================

def load_shocks(path):
    df = pd.read_stata(path)

    if not {"category", "b_eb"}.issubset(df.columns):
        raise SystemExit(f"{path} needs [category, b_eb]; got {list(df.columns)}")

    df["category"] = df["category"].astype(str).replace(CATEGORY_RENAMES)
    df = df.dropna(subset=["b_eb"]).drop_duplicates("category").reset_index(drop=True)

    return df["category"].tolist(), df["b_eb"].to_numpy(float)


def build_share_matrix(path, foia_ids, markets):
    df = pd.read_stata(path)

    df["athr_id"] = df["athr_id"].astype(str)
    df["category"] = df["category"].astype(str).replace(CATEGORY_RENAMES)

    df = df.dropna(subset=["spend", "tot_shr_spend"])
    df = df[(df["spend"] > 0) & (df["tot_shr_spend"] > 0)].copy()
    df["share"] = df["spend"].astype(float) / df["tot_shr_spend"].astype(float)

    df = df[
        df["category"].isin(markets)
        & df["athr_id"].isin(set(foia_ids))
    ].copy()

    ipos = {aid: i for i, aid in enumerate(foia_ids)}
    kpos = {cat: k for k, cat in enumerate(markets)}

    S = sp.csr_matrix(
        (
            df["share"].to_numpy(float),
            (
                df["athr_id"].map(ipos).to_numpy(),
                df["category"].map(kpos).to_numpy(),
            ),
        ),
        shape=(len(foia_ids), len(markets)),
    )

    coverage = np.asarray((S != 0).sum(axis=0)).ravel()
    return S, coverage


# =============================================================================
# PI characteristics / BHJ balance
# =============================================================================

def compute_pi_characteristics(path, foia_ids):
    df = pd.read_stata(
        path,
        columns=["athr_id", "category", "year", "spend", "lab_spend"],
    )

    df["athr_id"] = df["athr_id"].astype(str)
    df = df[(df["year"] <= PRE_PERIOD_LAST_YEAR) & df["spend"].notna()].copy()
    df["lab_spend"] = df["lab_spend"].fillna(0)
    df = df[df["athr_id"].isin(set(foia_ids))]

    grp = df.groupby("athr_id")

    out = pd.DataFrame({
        "total_spend": grp["spend"].sum(),
        "lab_spend_total": grp["lab_spend"].sum(),
        "n_cats": grp["category"].nunique(),
    })

    out["log_total_spend"] = np.log(out["total_spend"].clip(lower=1))
    out["log_lab_spend"] = np.log(out["lab_spend_total"].clip(lower=1))
    out["lab_share"] = out["lab_spend_total"] / out["total_spend"].clip(lower=1)

    return out.reindex(foia_ids).reset_index()


def shock_balance(S, g, chars):
    w = np.asarray(S.sum(axis=0)).ravel()

    if w.sum() == 0:
        print("  WARN: S has zero mass; skipping shock balance.")
        return None

    rows = []

    print("\n--- Shock balance ---")
    print(f"  {'characteristic':<22s} {'beta':>10s} {'se':>10s} {'t':>7s} {'p':>7s}")

    for col in ["log_total_spend", "log_lab_spend", "n_cats", "lab_share"]:
        X = chars[col].to_numpy(float)
        finite = np.isfinite(X)

        if finite.sum() == 0:
            continue

        X = np.where(finite, X, X[finite].mean())
        Xbar = np.asarray(S.T @ X).ravel() / np.maximum(w, 1e-12)

        xm = np.average(Xbar, weights=w)
        gm = np.average(g, weights=w)

        xc = Xbar - xm
        gc = g - gm

        den = np.sum(w * xc ** 2)
        if den <= 0:
            continue

        beta = np.sum(w * xc * gc) / den
        resid = gc - beta * xc

        K = int((w > 0).sum())
        sigma2 = np.sum(w * resid ** 2) / max(K - 2, 1)
        se = np.sqrt(sigma2 / den)

        t = beta / se if se > 0 else np.nan
        p = 2 * (1 - norm.cdf(abs(t))) if np.isfinite(t) else np.nan

        rows.append((col, beta, se, t, p, K))
        print(f"  {col:<22s} {beta:+10.4f} {se:10.4f} {t:+7.2f} {p:7.3f}")

    return pd.DataFrame(
        rows,
        columns=["characteristic", "beta", "se", "t", "p_value", "n_markets"],
    )


# =============================================================================
# EB
# =============================================================================

def normalize_rows(S):
    """
    Normalize each positive row only as an internal device for denoising its
    composition. Original row sums are returned and restored exactly.
    """
    X = S.toarray().astype(float)
    row_sum = X.sum(axis=1)

    P = np.zeros_like(X)
    good = row_sum > 0
    P[good] = X[good] / row_sum[good, None]

    return P, row_sum


def build_peer_prior(P, X_foia, foia_ids, peer_k, min_sim=0.0):
    """
    For each FOIA PI, use the top K most similar OTHER FOIA PIs.

    Prior:
        mu_i = sum_j sim_ij * P_j / sum_j sim_ij

    No global fallback. If no usable peers exist, prior_available=False.
    """
    if peer_k < 1:
        raise SystemExit("--eb-peer-k must be >= 1.")

    A = (X_foia @ X_foia.T).tocsr()
    A.setdiag(0)
    A.eliminate_zeros()

    n = len(foia_ids)
    prior = np.zeros_like(P)
    available = np.zeros(n, dtype=bool)
    diag = []

    row_has_mass = P.sum(axis=1) > 0

    for i in range(n):
        lo, hi = A.indptr[i], A.indptr[i + 1]
        js = A.indices[lo:hi]
        sims = A.data[lo:hi].astype(float)

        keep = (sims > min_sim) & row_has_mass[js]
        js = js[keep]
        sims = sims[keep]

        if len(js):
            order = np.argsort(sims)[::-1][:peer_k]
            js = js[order]
            sims = sims[order]

        if len(js) and sims.sum() > 0:
            prior[i] = sims @ P[js] / sims.sum()
            available[i] = True

            eff_n = sims.sum() ** 2 / np.square(sims).sum()
            mean_sim = sims.mean()
            min_used_sim = sims.min()
            max_used_sim = sims.max()
        else:
            eff_n = 0.0
            mean_sim = np.nan
            min_used_sim = np.nan
            max_used_sim = np.nan

        diag.append({
            "athr_id": foia_ids[i],
            "n_prior_peers": len(js),
            "prior_eff_n": eff_n,
            "mean_peer_sim": mean_sim,
            "min_peer_sim": min_used_sim,
            "max_peer_sim": max_used_sim,
            "prior_available": available[i],
        })

    return prior, available, pd.DataFrame(diag)


def build_cluster_prior(P, foia_ids, cluster_file):
    """
    Equal-weight leave-one-out cluster prior.

    No global fallback. If PI i has no other FOIA PI with positive treated
    shares in its cluster, prior_available=False and i will not be shrunk.
    """
    if not cluster_file or not os.path.exists(cluster_file):
        raise SystemExit("--eb-prior cluster requires --eb-cluster-file.")

    cl = pd.read_csv(cluster_file, dtype={"athr_id": str})

    if not {"athr_id", "cluster_label"}.issubset(cl.columns):
        raise SystemExit(
            f"{cluster_file} needs [athr_id, cluster_label]; got {list(cl.columns)}"
        )

    labels = (
        cl.drop_duplicates("athr_id")
        .set_index("athr_id")["cluster_label"]
        .reindex(foia_ids)
        .to_numpy()
    )

    n = len(foia_ids)
    idx = np.arange(n)

    prior = np.zeros_like(P)
    available = np.zeros(n, dtype=bool)
    row_has_mass = P.sum(axis=1) > 0

    diag = []

    for i in range(n):
        same = (
            pd.notna(labels[i])
            & (labels == labels[i])
            & (idx != i)
            & row_has_mass
        )

        n_other = int(same.sum())

        if n_other:
            prior[i] = P[same].mean(axis=0)
            available[i] = True

        diag.append({
            "athr_id": foia_ids[i],
            "cluster_label": labels[i],
            "n_prior_peers": n_other,
            "prior_eff_n": float(n_other),
            "prior_available": available[i],
        })

    return prior, available, pd.DataFrame(diag)


def eb_shrink_shares(S, prior, prior_available, own_weight):
    """
    Row-sum-preserving EB:

        P_i^EB = lambda P_i + (1-lambda) prior_i
        S_i^EB = rowsum(S_i) * P_i^EB

    where lambda = --eb-own-weight.

    If no prior is available for PI i, leave its row unchanged.
    Zero rows always remain zero.
    """
    if not 0 < own_weight <= 1:
        raise SystemExit("--eb-own-weight must be in (0,1].")

    P, raw_sum = normalize_rows(S)
    positive = raw_sum > 0

    prior = np.asarray(prior, float).copy()

    # Normalize priors defensively.
    prior_sum = prior.sum(axis=1)
    good_prior = prior_available & (prior_sum > 0)
    prior[good_prior] /= prior_sum[good_prior, None]

    shrink = positive & good_prior

    P_eb = P.copy()
    P_eb[shrink] = (
        own_weight * P[shrink]
        + (1 - own_weight) * prior[shrink]
    )

    S_eb = raw_sum[:, None] * P_eb
    S_eb[~positive] = 0

    # Hard invariant.
    err = np.max(np.abs(S_eb.sum(axis=1) - raw_sum))

    if err > 1e-10:
        raise RuntimeError(f"EB changed row sums; max error={err:.3e}")

    return sp.csr_matrix(S_eb), shrink


def eb_diagnostics(S_raw, S_eb, g):
    z0 = np.asarray(S_raw @ g).ravel()
    z1 = np.asarray(S_eb @ g).ravel()

    good = np.asarray(S_raw.sum(axis=1)).ravel() > 0
    z0, z1 = z0[good], z1[good]

    if len(z0) < 2:
        return {
            "raw_sd": np.nan,
            "eb_sd": np.nan,
            "sd_retained": np.nan,
            "slope": np.nan,
            "corr": np.nan,
        }

    sd0 = z0.std()
    sd1 = z1.std()

    slope = (
        np.cov(z0, z1, ddof=0)[0, 1] / np.var(z0)
        if np.var(z0) > 0
        else np.nan
    )

    corr = (
        np.corrcoef(z0, z1)[0, 1]
        if sd0 > 0 and sd1 > 0
        else np.nan
    )

    return {
        "raw_sd": sd0,
        "eb_sd": sd1,
        "sd_retained": sd1 / sd0 if sd0 > 0 else np.nan,
        "slope": slope,
        "corr": corr,
    }


# =============================================================================
# KNN diagnostics
# =============================================================================

def report_W_health(W):
    rs = np.asarray(W.sum(axis=1)).ravel()
    good = rs > 0

    print(f"W rows with weight: {good.sum():,}/{len(rs):,}")

    if good.any():
        print(
            f"W row sums: mean={rs[good].mean():.4f}, "
            f"p5={np.percentile(rs[good], 5):.4f}, "
            f"p95={np.percentile(rs[good], 95):.4f}"
        )

        if not np.allclose(rs[good], 1, atol=1e-3):
            print("WARN: W rows are not L1-normalized.")


def knn_loo_influence(W, S, g, foia_ids):
    """
    Leave-one-FOIA-anchor-out diagnostic only.
    """
    Wc = W.tocsc()

    anchor_z = np.asarray(S @ g).ravel()
    row_sum = np.asarray(W.sum(axis=1)).ravel()
    numerator = np.asarray(W @ anchor_z).ravel()

    baseline = np.zeros(len(row_sum))
    good = row_sum > 0
    baseline[good] = numerator[good] / row_sum[good]

    rows = []

    for i, aid in enumerate(foia_ids):
        lo, hi = Wc.indptr[i], Wc.indptr[i + 1]
        jj = Wc.indices[lo:hi]
        wij = Wc.data[lo:hi]

        denom = row_sum[jj] - wij
        valid = denom > 1e-12

        if valid.any():
            loo = (
                numerator[jj[valid]] - wij[valid] * anchor_z[i]
            ) / denom[valid]

            delta = loo - baseline[jj[valid]]

            rmse = np.sqrt(np.mean(delta ** 2))
            mean_abs = np.mean(np.abs(delta))
            max_abs = np.max(np.abs(delta))
        else:
            rmse = mean_abs = max_abs = np.nan

        rows.append({
            "athr_id": aid,
            "n_universe_affected": len(jj),
            "weight_mass": wij.sum(),
            "loo_rmse": rmse,
            "loo_mean_abs": mean_abs,
            "loo_max_abs": max_abs,
        })

    return pd.DataFrame(rows)


# =============================================================================
# Universe filters
# =============================================================================

def apply_filters(df_univ, S_hat, args, df_foia):
    """
    Post-imputation filters.

    Suffixes:
        _cf / _cf2 / _cf5
        _ls / _lsa / ...
        _msNNN
    """

    if args.min_max_sim > 0:
        diag_file = f"{OUT_DIR}/match_diagnostics.parquet"

        if not os.path.exists(diag_file):
            raise SystemExit(f"--min-max-sim needs {diag_file}")

        diag = pd.read_parquet(diag_file)[["athr_id", "max_sim"]]
        diag["athr_id"] = diag["athr_id"].astype(str)

        n0 = len(df_univ)

        df_univ = df_univ.merge(diag, on="athr_id", how="left")
        keep = df_univ["max_sim"] >= args.min_max_sim

        S_hat = S_hat[keep.to_numpy()]
        df_univ = df_univ.loc[keep].drop(columns=["max_sim"]).copy()

        print(
            f"max_sim >= {args.min_max_sim}: "
            f"{len(df_univ):,}/{n0:,}"
        )

    if args.cluster_filter:
        if not os.path.exists(args.cluster_filter):
            raise SystemExit(f"--cluster-filter not found: {args.cluster_filter}")

        cl = pd.read_csv(args.cluster_filter, dtype={"athr_id": str})

        if not {"athr_id", "cluster_label"}.issubset(cl.columns):
            raise SystemExit(
                "--cluster-filter needs [athr_id, cluster_label]; "
                f"got {list(cl.columns)}"
            )

        min_n = max(1, args.min_foia_per_cluster)

        foia_in_cl = df_foia.merge(cl, on="athr_id", how="inner")
        counts = foia_in_cl.groupby("cluster_label").size()
        keep_clusters = set(counts[counts >= min_n].index)

        n0 = len(df_univ)

        df_univ = df_univ.merge(
            cl[["athr_id", "cluster_label"]],
            on="athr_id",
            how="left",
        )

        keep = (
            df_univ["cluster_label"].notna()
            & df_univ["cluster_label"].isin(keep_clusters)
        )

        S_hat = S_hat[keep.to_numpy()]
        df_univ = df_univ.loc[keep].drop(columns=["cluster_label"]).copy()

        print(
            f"cluster filter min FOIA={min_n}: "
            f"{len(df_univ):,}/{n0:,}"
        )

    if args.ls_filter:
        if not os.path.exists(args.ls_filter):
            raise SystemExit(f"--ls-filter not found: {args.ls_filter}")

        ls = pd.read_csv(args.ls_filter, dtype={"athr_id": str})

        if "athr_id" not in ls.columns:
            raise SystemExit("--ls-filter needs an athr_id column.")

        n0 = len(df_univ)

        keep = df_univ["athr_id"].isin(set(ls["athr_id"]))

        S_hat = S_hat[keep.to_numpy()]
        df_univ = df_univ.loc[keep].copy()

        print(f"LS filter: {len(df_univ):,}/{n0:,}")

    return df_univ, S_hat


# =============================================================================
# Suffixes
# =============================================================================

def build_suffixes(args):
    k_sfx = "" if args.k == 5 else f"_k{args.k}"

    filter_sfx = ""

    if args.cluster_filter:
        filter_sfx += (
            "_cf"
            if args.min_foia_per_cluster <= 1
            else f"_cf{args.min_foia_per_cluster}"
        )

    if args.ls_filter:
        filter_sfx += (
            args.ls_sfx
            if args.ls_sfx.startswith("_")
            else "_" + args.ls_sfx
        )

    if args.min_max_sim > 0:
        filter_sfx += f"_ms{int(round(args.min_max_sim * 100)):03d}"

    eb_sfx = ""

    if args.eb_own_weight < 1:
        prior_tag = "p" if args.eb_prior == "peer" else "c"
        own_pct = int(round(args.eb_own_weight * 100))

        eb_sfx = f"_eb{prior_tag}{own_pct}"

        if args.eb_prior == "peer":
            eb_sfx += f"k{args.eb_peer_k}"

    return eb_sfx, filter_sfx, k_sfx


# =============================================================================
# Main
# =============================================================================

def main():
    ap = argparse.ArgumentParser()

    # Core
    ap.add_argument("--versions", nargs="+", choices=VERSIONS, default=VERSIONS)
    ap.add_argument("--betas-path", default=DEFAULT_BETAS_FILE)

    ap.add_argument(
        "--k",
        type=int,
        default=5,
        help=(
            "KNN size used for universe imputation. "
            "5 -> weight_matrix.npz; "
            "3 -> weight_matrix_k3.npz and suffix _k3."
        ),
    )

    # -------------------------------------------------------------------------
    # EB
    # -------------------------------------------------------------------------

    ap.add_argument(
        "--eb-own-weight",
        type=float,
        default=0.9,
        help=(
            "Weight each FOIA PI keeps on its own observed treated-market "
            "composition. 1=EB off. Default .90; try .95, .85."
        ),
    )

    ap.add_argument(
        "--eb-prior",
        choices=["peer", "cluster"],
        default="peer",
        help=(
            "peer: top-K TF-IDF-similar FOIA PIs. "
            "cluster: other FOIA PIs in same cluster. "
            "No global prior."
        ),
    )

    ap.add_argument(
        "--eb-peer-k",
        type=int,
        default=5,
        help="Number of nearest FOIA peers used for peer EB prior.",
    )

    ap.add_argument(
        "--eb-min-peer-sim",
        type=float,
        default=0.0,
        help=(
            "Optional minimum TF-IDF similarity for peer prior. "
            "Default 0 keeps the top K positive-similarity peers."
        ),
    )

    ap.add_argument(
        "--eb-cluster-file",
        default="",
        help=(
            "athr_id,cluster_label CSV used only for "
            "--eb-prior cluster."
        ),
    )

    # -------------------------------------------------------------------------
    # Existing post-imputation filters
    # -------------------------------------------------------------------------

    ap.add_argument(
        "--cluster-filter",
        default="",
        help=(
            "Post-imputation universe cluster filter. "
            "This is separate from --eb-cluster-file."
        ),
    )

    ap.add_argument(
        "--min-foia-per-cluster",
        type=int,
        default=1,
        help="1 -> _cf, 2 -> _cf2, 5 -> _cf5.",
    )

    ap.add_argument(
        "--ls-filter",
        default="",
        help="Post-imputation life-science author mask.",
    )

    ap.add_argument(
        "--ls-sfx",
        default="_ls",
        help="Filename suffix for LS mask, e.g. _ls or _lsa.",
    )

    ap.add_argument(
        "--min-max-sim",
        type=float,
        default=0.0,
        help="Drop universe authors below this max FOIA similarity.",
    )

    # Diagnostics
    ap.add_argument(
        "--loo-influence",
        action="store_true",
        help="Save leave-one-FOIA-anchor influence before and after EB.",
    )

    args = ap.parse_args()

    if not 0 < args.eb_own_weight <= 1:
        raise SystemExit("--eb-own-weight must be in (0,1].")

    if args.eb_peer_k < 1:
        raise SystemExit("--eb-peer-k must be >= 1.")

    # -------------------------------------------------------------------------
    # IDs / shocks
    # -------------------------------------------------------------------------

    universe_file = f"{OUT_DIR}/universe_ids.parquet"
    foia_file = f"{OUT_DIR}/foia_ids_ordered.csv"

    for path in [universe_file, foia_file]:
        if not os.path.exists(path):
            raise SystemExit(f"missing: {path}")

    df_univ_master = pd.read_parquet(universe_file)
    df_univ_master["athr_id"] = df_univ_master["athr_id"].astype(str)

    df_foia = pd.read_csv(foia_file, dtype={"athr_id": str})
    foia_ids = df_foia["athr_id"].tolist()

    markets, g = load_shocks(args.betas_path)

    print(f"Universe: {len(df_univ_master):,}")
    print(f"FOIA anchors: {len(foia_ids):,}")
    print(f"Treated markets: {len(markets)}")

    # -------------------------------------------------------------------------
    # KNN matrix
    # -------------------------------------------------------------------------

    k_sfx = "" if args.k == 5 else f"_k{args.k}"
    weights_file = f"{OUT_DIR}/weight_matrix{k_sfx}.npz"

    if not os.path.exists(weights_file):
        raise SystemExit(f"missing: {weights_file}")

    W = sp.load_npz(weights_file).tocsr()

    if W.shape != (len(df_univ_master), len(foia_ids)):
        raise SystemExit(
            f"W shape {W.shape} != "
            f"({len(df_univ_master)}, {len(foia_ids)})"
        )

    report_W_health(W)

    # -------------------------------------------------------------------------
    # FOIA TF-IDF only needed for peer EB
    # -------------------------------------------------------------------------

    X_foia = None

    if args.eb_own_weight < 1 and args.eb_prior == "peer":
        tfidf_file = f"{OUT_DIR}/tfidf_foia.npz"

        if not os.path.exists(tfidf_file):
            raise SystemExit(f"peer EB needs {tfidf_file}")

        X_foia = sp.load_npz(tfidf_file).tocsr().astype(float)

        if X_foia.shape[0] != len(foia_ids):
            raise SystemExit(
                f"X_foia rows {X_foia.shape[0]} != n_foia {len(foia_ids)}"
            )

    chars = compute_pi_characteristics(
        CATEGORY_SPEND_FILE,
        foia_ids,
    )

    eb_sfx, filter_sfx, k_sfx = build_suffixes(args)
    summaries = []

    # =========================================================================
    # Version loop
    # =========================================================================

    for version in args.versions:
        print("\n" + "=" * 78)
        print(f"version={version}")
        print("=" * 78)

        share_file = CATEGORY_SHARE_FILE.format(version=version)

        if not os.path.exists(share_file):
            raise SystemExit(f"missing: {share_file}")

        S_raw, coverage = build_share_matrix(
            share_file,
            foia_ids,
            markets,
        )

        raw_sum = np.asarray(S_raw.sum(axis=1)).ravel()
        positive = raw_sum > 0

        print(
            f"FOIA PIs with treated shares: "
            f"{positive.sum()}/{len(positive)}"
        )

        if positive.any():
            print(
                f"FOIA row sums: "
                f"mean={raw_sum[positive].mean():.4f}, "
                f"sd={raw_sum[positive].std():.4f}"
            )

        S = S_raw.copy()
        prior_diag = None
        shrink_mask = np.zeros(len(foia_ids), dtype=bool)

        # ---------------------------------------------------------------------
        # EB
        # ---------------------------------------------------------------------

        if args.eb_own_weight < 1:
            P, _ = normalize_rows(S_raw)

            if args.eb_prior == "peer":
                prior, available, prior_diag = build_peer_prior(
                    P,
                    X_foia,
                    foia_ids,
                    peer_k=args.eb_peer_k,
                    min_sim=args.eb_min_peer_sim,
                )

            else:
                cluster_file = args.eb_cluster_file

                if not cluster_file:
                    # Convenience: use the same cluster file as the
                    # post-imputation filter if supplied.
                    cluster_file = args.cluster_filter

                prior, available, prior_diag = build_cluster_prior(
                    P,
                    foia_ids,
                    cluster_file,
                )

            S, shrink_mask = eb_shrink_shares(
                S_raw,
                prior,
                available,
                args.eb_own_weight,
            )

            d = eb_diagnostics(S_raw, S, g)

            print("\n--- EB ---")
            print(f"prior: {args.eb_prior}")
            print(f"own weight: {args.eb_own_weight:.2f}")
            print(
                f"anchors actually shrunk: "
                f"{shrink_mask.sum()}/{positive.sum()}"
            )

            if args.eb_prior == "peer":
                print(f"peer K: {args.eb_peer_k}")

            print(
                f"FOIA exposure SD: "
                f"{d['raw_sd']:.5f} -> {d['eb_sd']:.5f} "
                f"({d['sd_retained']:.1%} retained)"
            )

            print(f"EB/raw slope: {d['slope']:.3f}")
            print(f"EB/raw correlation: {d['corr']:.3f}")

            eb_sum = np.asarray(S.sum(axis=1)).ravel()

            print(
                "max FOIA row-sum change: "
                f"{np.max(np.abs(eb_sum - raw_sum)):.3e}"
            )

        # ---------------------------------------------------------------------
        # LOO
        # ---------------------------------------------------------------------

        loo = None

        if args.loo_influence:
            loo_raw = knn_loo_influence(
                W,
                S_raw,
                g,
                foia_ids,
            )

            loo_eb = knn_loo_influence(
                W,
                S,
                g,
                foia_ids,
            )

            loo = loo_raw.merge(
                loo_eb,
                on="athr_id",
                suffixes=("_raw", "_eb"),
            )

            print("\nTop 5 raw-influence FOIA anchors:")

            for _, r in loo.nlargest(5, "loo_rmse_raw").iterrows():
                print(
                    f"  {r['athr_id']}: "
                    f"{r['loo_rmse_raw']:.5f} -> "
                    f"{r['loo_rmse_eb']:.5f}"
                )

        # ---------------------------------------------------------------------
        # Universe imputation
        # ---------------------------------------------------------------------

        S_hat = (W @ S).tocsr()

        z_hat = np.asarray(S_hat @ g).ravel()
        sum_imputed_shares = np.asarray(S_hat.sum(axis=1)).ravel()

        s_bar = np.asarray(S_hat.mean(axis=0)).ravel()

        rot_num = s_bar * g
        rot_den = rot_num.sum()

        rot_wt = (
            rot_num / rot_den
            if rot_den != 0
            else np.zeros_like(rot_num)
        )

        ss = np.square(s_bar).sum()
        eff_n = s_bar.sum() ** 2 / ss if ss > 0 else 0.0

        print(
            f"\nUniverse exposure: "
            f"mean={z_hat.mean():+.5f}, "
            f"sd={z_hat.std():.5f}"
        )

        print(
            f"Mean sum imputed shares: "
            f"{sum_imputed_shares.mean():.5f}"
        )

        # ---------------------------------------------------------------------
        # Universe filtering
        # ---------------------------------------------------------------------

        df_univ = df_univ_master.copy()
        df_univ["exposure_ss"] = z_hat
        df_univ["sum_imputed_shares"] = sum_imputed_shares

        df_univ, S_hat_filtered = apply_filters(
            df_univ,
            S_hat,
            args,
            df_foia,
        )

        # ---------------------------------------------------------------------
        # Outputs
        # ---------------------------------------------------------------------

        stem = f"_{version}{eb_sfx}{filter_sfx}{k_sfx}"

        out_csv = f"{OUT_DIR}/final_imputed_shift_share{stem}.csv"
        out_npz = f"{OUT_DIR}/imputed_shares_matrix{stem}.npz"
        out_markets = f"{OUT_DIR}/imputed_shares_markets{stem}.csv"

        df_univ[
            ["athr_id", "exposure_ss", "sum_imputed_shares"]
        ].to_csv(out_csv, index=False)

        sp.save_npz(out_npz, S_hat_filtered)

        markets_df = pd.DataFrame({
            "market_idx": np.arange(len(markets)),
            "category": markets,
            "g": g,
            "s_bar": s_bar,
            "rotemberg_wt": rot_wt,
            "n_foia_pis": coverage,
        })

        markets_df.to_csv(out_markets, index=False)

        # ---------------------------------------------------------------------
        # FOIA diagnostics
        # ---------------------------------------------------------------------

        foia_diag = pd.DataFrame({
            "athr_id": foia_ids,
            "sum_shares_raw": raw_sum,
            "sum_shares_eb": np.asarray(S.sum(axis=1)).ravel(),
            "exposure_raw": np.asarray(S_raw @ g).ravel(),
            "exposure_eb": np.asarray(S @ g).ravel(),
            "eb_shrunk": shrink_mask,
        })

        if prior_diag is not None:
            foia_diag = foia_diag.merge(
                prior_diag,
                on="athr_id",
                how="left",
            )

        foia_diag.to_csv(
            f"{OUT_DIR}/foia_eb_diagnostics{stem}.csv",
            index=False,
        )

        if loo is not None:
            loo.to_csv(
                f"{OUT_DIR}/foia_loo_influence{stem}.csv",
                index=False,
            )

        balance = shock_balance(S, g, chars)

        if balance is not None:
            balance.to_csv(
                f"{OUT_DIR}/shock_balance{stem}.csv",
                index=False,
            )

        # ---------------------------------------------------------------------
        # Summary
        # ---------------------------------------------------------------------

        self_raw = np.asarray(S_raw @ g).ravel()
        self_eb = np.asarray(S @ g).ravel()

        summaries.append({
            "version": version,
            "eb_prior": args.eb_prior if args.eb_own_weight < 1 else "none",
            "eb_own_weight": args.eb_own_weight,
            "eb_peer_k": args.eb_peer_k if args.eb_prior == "peer" else np.nan,
            "n_foia_with_shares": int(positive.sum()),
            "n_foia_shrunk": int(shrink_mask.sum()),
            "foia_raw_exposure_sd": (
                self_raw[positive].std()
                if positive.any()
                else np.nan
            ),
            "foia_eb_exposure_sd": (
                self_eb[positive].std()
                if positive.any()
                else np.nan
            ),
            "universe_exposure_sd": float(z_hat.std()),
            "mean_sum_imputed_shares": float(sum_imputed_shares.mean()),
            "eff_n_shocks": float(eff_n),
            "n_universe_after_filters": len(df_univ),
        })

        print(f"\nSaved {out_csv}")
        print(f"Saved {out_npz}")
        print(f"Saved {out_markets}")

    # =========================================================================
    # Summary
    # =========================================================================

    summary = pd.DataFrame(summaries)

    summary_out = (
        f"{OUT_DIR}/shift_share_summary"
        f"{eb_sfx}{filter_sfx}{k_sfx}.csv"
    )

    summary.to_csv(summary_out, index=False)

    print("\n" + "=" * 78)
    print("SUMMARY")
    print("=" * 78)

    with pd.option_context(
        "display.width", 220,
        "display.max_columns", None,
        "display.float_format", "{:.4f}".format,
    ):
        print(summary.to_string(index=False))

    print(f"\nSaved {summary_out}")
    print("Done!")


if __name__ == "__main__":
    main()