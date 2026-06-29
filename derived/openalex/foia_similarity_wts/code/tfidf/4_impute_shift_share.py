"""
Shift-share imputation. Replaces the scalar W @ exposure path in
3_impute_exposure.py with: impute the PI x market share MATRIX, then
multiply the imputed shares by the observed market-level shocks. The
shocks enter exactly (never smoothed); only the shares are imputed.

Inputs (all read via existing external symlinks in this repo):
  ../../external/exposure_wts/athr_category_spend.dta    (PI x category x year, pre-period spend)
  --betas-path (default analysis/first_stage/output/did_coefs_eb_price.dta)  per-market shocks g_k = b
  ../../output/weight_matrix{tag}.npz                    universe x FOIA W
  ../../output/foia_ids_ordered{tag}.csv                 row order of S's rows
  ../../output/universe_ids{tag}.parquet                 row order of W's universe side

Math:
  s_ik    = (PI i's pre-period spend in market k) / (PI i's pre-period TOTAL spend)
  S       sparse FOIA x K_treated, rows = FOIA PIs, cols = markets in did_coefs
  S_hat   = W @ S                  universe x K_treated, similarity-weighted shares
  z_hat   = S_hat @ g              universe x 1, shift-share exposure
  S_sum   = S_hat.sum(axis=1)      universe x 1, incomplete-shares control

Outputs:
  ../../output/final_imputed_shift_share{tag}{suffix}.csv
       columns: athr_id, exposure_ss, sum_imputed_shares
  ../../output/imputed_shares_matrix{tag}{suffix}.npz     S_hat sparse
  ../../output/imputed_shares_markets{tag}{suffix}.csv    per-market diagnostics
       columns: market_idx, category, g, s_bar, rotemberg_wt, n_foia_pis
"""
import argparse
import os
import numpy as np
import pandas as pd
import scipy.sparse as sp
from scipy.stats import norm

OUT_DIR = "../../output"
CATEGORY_SPEND_FILE = "../../external/exposure_wts/athr_category_spend.dta"
OBSERVED_EXPOSURE_FILE = "../../external/exposure_wts/athr_exposure.dta"
DEFAULT_BETAS_FILE = (
    "/n/holylabs/LABS/pakes_lab/Lab/sci_eq/analysis/first_stage/output/"
    "did_coefs_eb_price.dta"
)
PRE_PERIOD_LAST_YEAR = 2013

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


def build_share_matrix(spend_path, foia_ids, market_index, denom="total"):
    cols = ["athr_id", "category", "year", "spend"]
    if denom in ("lab", "hc"):
        cols.append("keep")
    df = pd.read_stata(spend_path, columns=cols)
    df = df[df["year"] <= PRE_PERIOD_LAST_YEAR]
    df["category"] = df["category"].replace(CATEGORY_RENAMES)
    df = df.dropna(subset=["spend"])
    df = df[df["spend"] > 0]

    if denom == "total":
        denom_df = df
    elif denom == "lab":
        denom_df = df[df["category"] != "Non-Lab"]
    elif denom == "hc":
        denom_df = df[(df["category"] != "Non-Lab") & (df["keep"] == 1)]
    else:
        raise ValueError(f"unknown denom: {denom}")

    pi_total = (
        denom_df.groupby("athr_id", as_index=False)["spend"].sum()
        .rename(columns={"spend": "pi_total"})
    )
    pi_cat = df.groupby(["athr_id", "category"], as_index=False)["spend"].sum()
    pi_cat = pi_cat.merge(pi_total, on="athr_id")
    pi_cat["share"] = pi_cat["spend"] / pi_cat["pi_total"]

    pi_cat = pi_cat[pi_cat["category"].isin(market_index)]

    foia_id_set = set(foia_ids)
    pi_cat = pi_cat[pi_cat["athr_id"].isin(foia_id_set)]

    foia_pos = {aid: i for i, aid in enumerate(foia_ids)}
    market_pos = {c: i for i, c in enumerate(market_index)}
    rows = pi_cat["athr_id"].map(foia_pos).to_numpy()
    cols = pi_cat["category"].map(market_pos).to_numpy()
    data = pi_cat["share"].to_numpy(dtype=np.float64)

    S = sp.csr_matrix(
        (data, (rows, cols)),
        shape=(len(foia_ids), len(market_index)),
    )

    coverage = pd.Series(
        np.asarray((S != 0).sum(axis=0)).ravel(),
        index=market_index,
        name="n_foia_pis",
    )
    return S, coverage, pi_total


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
    print("  X_bar_k    = Sum_i s_ik * X_i / Sum_i s_ik   (market-mean of X)")
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
            "weighted SUMS, not averages. Either re-run 2_similarity_wts.py "
            "with L1 normalization on, or treat the diagnostic numbers below "
            "with caution."
        )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--tag", default="",
        help="Suffix matching --tag in 1_vectorize.py / 2_similarity_wts.py. "
             "Empty = baseline artifacts.",
    )
    ap.add_argument(
        "--betas-path", default=DEFAULT_BETAS_FILE,
        help="Stata file with columns [category, b] giving per-market shocks.",
    )
    ap.add_argument(
        "--denom", choices=["total", "lab", "hc"], default="hc",
        help="Per-PI denominator for s_ik = spend / denom. "
             "hc (default) = sum across kept categories only — matches build.do's "
             "tot_hc_spend so exposure_ss is on the same scale as the observed "
             "exposure. lab and total are sensitivity options with broader denominators.",
    )
    ap.add_argument(
        "--cluster-filter", default="",
        help="author_static_clusters_K.csv from openalex/cluster_fields. "
             "After imputation, drop universe authors whose K-cluster has "
             "zero FOIA PIs (same logic as 3_impute_exposure.py).",
    )
    ap.add_argument(
        "--min-max-sim", type=float, default=0.0,
        help="Drop universe authors whose max cosine to any FOIA PI is below "
             "this threshold. Default 0.0 = keep all.",
    )
    args = ap.parse_args()

    tag = args.tag
    if tag and not tag.startswith("_"):
        tag = "_" + tag

    weights_file = f"{OUT_DIR}/weight_matrix{tag}.npz"
    universe_ids_file = f"{OUT_DIR}/universe_ids{tag}.parquet"
    foia_ids_file = f"{OUT_DIR}/foia_ids_ordered{tag}.csv"
    diag_file = f"{OUT_DIR}/match_diagnostics{tag}.parquet"
    for p in (weights_file, universe_ids_file, foia_ids_file):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")
    if not os.path.exists(CATEGORY_SPEND_FILE):
        raise SystemExit(f"missing: {CATEGORY_SPEND_FILE}")
    if not os.path.exists(args.betas_path):
        raise SystemExit(f"missing: {args.betas_path}")

    out_suffix = "" if args.denom == "hc" else f"_d{args.denom}"
    if args.cluster_filter:
        out_suffix += "_cf"
    if args.min_max_sim > 0:
        out_suffix += f"_ms{int(round(args.min_max_sim * 100)):03d}"
    out_csv = f"{OUT_DIR}/final_imputed_shift_share{tag}{out_suffix}.csv"
    out_npz = f"{OUT_DIR}/imputed_shares_matrix{tag}{out_suffix}.npz"
    out_markets = f"{OUT_DIR}/imputed_shares_markets{tag}{out_suffix}.csv"

    print(f"Loading W (tag={args.tag!r}) ...")
    W = sp.load_npz(weights_file)
    print(f"  W shape: {W.shape}  nnz: {W.nnz:,}")
    report_W_health(W)

    print("Loading universe + FOIA id orders ...")
    df_univ = pd.read_parquet(universe_ids_file)
    df_foia = pd.read_csv(foia_ids_file, dtype={"athr_id": str})
    foia_ids = df_foia["athr_id"].astype(str).tolist()
    if W.shape != (len(df_univ), len(foia_ids)):
        raise SystemExit(
            f"W shape {W.shape} != (n_universe={len(df_univ)}, n_foia={len(foia_ids)})"
        )

    print(f"Loading shocks from {args.betas_path} ...")
    market_index, g = load_shocks(args.betas_path)
    print(f"  markets with shocks: {len(market_index)}")
    print(
        f"  g_k stats: mean={g.mean():.4f}  sd={g.std():.4f}  "
        f"min={g.min():.4f}  max={g.max():.4f}"
    )

    print(f"Building FOIA share matrix S (denom={args.denom}) ...")
    S, coverage, pi_total = build_share_matrix(
        CATEGORY_SPEND_FILE, foia_ids, market_index, denom=args.denom
    )
    print(
        f"  S shape: {S.shape}  nnz: {S.nnz:,}  "
        f"density: {S.nnz / max(S.shape[0]*S.shape[1], 1):.4f}"
    )
    print(
        f"  FOIA PIs with >=1 treated-market share: "
        f"{(np.asarray(S.sum(axis=1)).ravel() > 0).sum():,} / {S.shape[0]:,}"
    )
    cov = coverage.to_numpy()
    print(
        f"  per-market coverage (n FOIA PIs in market): "
        f"min={cov.min()}  p5={int(np.percentile(cov,5))}  "
        f"p50={int(np.percentile(cov,50))}  "
        f"p95={int(np.percentile(cov,95))}  max={cov.max()}"
    )
    thin = (coverage < 5).sum()
    if thin > 0:
        print(
            f"  WARN: {thin} markets have <5 FOIA PIs. S_hat columns for "
            "those markets are noisy — consider collapsing into SIC3-style "
            "groups before imputing."
        )

    print("Imputing share matrix: S_hat = W @ S ...")
    S_hat = (W @ S).tocsr()

    print("Computing exposure: z_hat = S_hat @ g ...")
    z_hat = np.asarray(S_hat @ g).ravel()

    print("Computing incomplete-shares control: S_sum = rowsum(S_hat) ...")
    S_sum = np.asarray(S_hat.sum(axis=1)).ravel()

    s_bar = np.asarray(S_hat.mean(axis=0)).ravel()
    ss = (s_bar ** 2).sum()
    eff_n_raw = 1.0 / ss if ss > 0 else 0.0
    sbar_sum = s_bar.sum()
    eff_n_norm = (sbar_sum ** 2) / ss if ss > 0 else 0.0
    print(f"  effective number of shocks (raw 1/sum s_bar^2):     {eff_n_raw:.2f}")
    print(f"  effective number of shocks (normalized, BHJ-style): {eff_n_norm:.2f}")
    print(f"    (raw is inflated because shares don't sum to 1; "
          f"normalized = (sum s_bar)^2 / sum s_bar^2 is bounded by #markets)")

    print("\n--- Exposure level comparison ---")
    self_z = np.asarray(S @ g).ravel()
    foia_mask = self_z != 0
    print(f"  Self-imputed FOIA exposure (S @ g, new denom = total spend):")
    print(f"    n nonzero PIs: {foia_mask.sum()}/{len(self_z)}")
    print(f"    mean={self_z[foia_mask].mean():+.5f}  "
          f"sd={self_z[foia_mask].std():.5f}  "
          f"med={np.median(self_z[foia_mask]):+.5f}")
    print(f"  Universe imputed exposure (W @ S @ g):")
    z_nz = z_hat != 0
    print(f"    n nonzero authors: {z_nz.sum():,}/{len(z_hat):,}")
    print(f"    mean={z_hat[z_nz].mean():+.5f}  "
          f"sd={z_hat[z_nz].std():.5f}  "
          f"med={np.median(z_hat[z_nz]):+.5f}")
    if os.path.exists(OBSERVED_EXPOSURE_FILE):
        df_obs = pd.read_stata(OBSERVED_EXPOSURE_FILE, columns=["athr_id", "exposure"])
        df_obs = df_obs.dropna(subset=["exposure"])
        print(f"  Observed FOIA exposure (build.do, denom = tot_hc_spend):")
        print(f"    n PIs: {len(df_obs)}")
        print(f"    mean={df_obs['exposure'].mean():+.5f}  "
              f"sd={df_obs['exposure'].std():.5f}  "
              f"med={df_obs['exposure'].median():+.5f}")
        df_self = pd.DataFrame({"athr_id": foia_ids, "self_z": self_z})
        merged = df_obs.merge(df_self, on="athr_id", how="inner")
        if len(merged) > 0:
            ratio = merged["self_z"] / merged["exposure"].replace(0, np.nan)
            print(f"  PI-level ratio (self_z / observed) on {len(merged)} matched PIs:")
            print(f"    mean={ratio.mean():.3f}  med={ratio.median():.3f}  "
                  f"(<1 because new denom is larger)")
    else:
        print(f"  (skip observed comparison: {OBSERVED_EXPOSURE_FILE} not found)")

    print("\nComputing FOIA pre-period characteristics for shock balance ...")
    pi_chars = compute_pi_characteristics(CATEGORY_SPEND_FILE, foia_ids)
    balance_df = shock_balance(
        S, g, pi_chars,
        char_cols=["log_total_spend", "log_lab_spend", "n_cats", "lab_share"],
        market_index=market_index,
    )

    rot_num = s_bar * g
    rot_den = rot_num.sum()
    rot_wt = rot_num / rot_den if rot_den != 0 else np.zeros_like(rot_num)
    top = np.argsort(np.abs(rot_wt))[::-1][:10]
    print("  top-10 |Rotemberg weight| markets:")
    for j in top:
        print(
            f"    {market_index[j]:<40s}  alpha_k={rot_wt[j]:+.3f}  "
            f"s_bar={s_bar[j]:.4f}  g={g[j]:+.4f}"
        )

    df_univ = df_univ.copy()
    df_univ["exposure_ss"] = z_hat
    df_univ["sum_imputed_shares"] = S_sum

    if args.min_max_sim > 0:
        if not os.path.exists(diag_file):
            raise SystemExit(
                f"--min-max-sim needs {diag_file}; run 2_similarity_wts.py first."
            )
        diag = pd.read_parquet(diag_file)[["athr_id", "max_sim"]]
        n_before = len(df_univ)
        df_univ = df_univ.merge(diag, on="athr_id", how="left")
        keep_mask = df_univ["max_sim"] >= args.min_max_sim
        keep_idx_mask = keep_mask.to_numpy()
        df_univ = df_univ.loc[keep_mask].drop(columns=["max_sim"])
        S_hat = S_hat[keep_idx_mask]
        print(
            f"\nmax_sim filter (>= {args.min_max_sim}): "
            f"kept {len(df_univ):,}/{n_before:,}"
        )

    if args.cluster_filter:
        if not os.path.exists(args.cluster_filter):
            raise SystemExit(f"--cluster-filter file not found: {args.cluster_filter}")
        cl = pd.read_csv(args.cluster_filter)
        if "cluster_label" not in cl.columns or "athr_id" not in cl.columns:
            raise SystemExit(
                f"--cluster-filter file must have columns [athr_id, cluster_label]: "
                f"got {list(cl.columns)}"
            )
        foia_in_cl = df_foia.merge(cl, on="athr_id", how="inner")
        foia_clusters = set(foia_in_cl["cluster_label"].unique())
        n_before = len(df_univ)
        df_univ = df_univ.merge(cl, on="athr_id", how="left")
        keep_mask = (
            df_univ["cluster_label"].notna()
            & df_univ["cluster_label"].isin(foia_clusters)
        )
        keep_idx_mask = keep_mask.to_numpy()
        df_univ = df_univ.loc[keep_mask].drop(columns=["cluster_label"])
        S_hat = S_hat[keep_idx_mask]
        print(
            f"cluster filter ({args.cluster_filter}): "
            f"kept {len(df_univ):,}/{n_before:,}"
        )

    df_univ[["athr_id", "exposure_ss", "sum_imputed_shares"]].to_csv(out_csv, index=False)
    sp.save_npz(out_npz, S_hat)
    pd.DataFrame({
        "market_idx": np.arange(len(market_index)),
        "category": market_index,
        "g": g,
        "s_bar": s_bar,
        "rotemberg_wt": rot_wt,
        "n_foia_pis": coverage.to_numpy(),
    }).to_csv(out_markets, index=False)

    if balance_df is not None:
        out_balance = f"{OUT_DIR}/shock_balance{tag}{out_suffix}.csv"
        balance_df.to_csv(out_balance, index=False)
        print(f"Saved {out_balance}")

    print(f"\nSaved {out_csv}")
    print(f"Saved {out_npz}  (universe x K_treated imputed share matrix)")
    print(f"Saved {out_markets}")


if __name__ == "__main__":
    main()
