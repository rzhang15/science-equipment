import argparse
import importlib
import os
from types import SimpleNamespace

import numpy as np
import pandas as pd
import scipy.sparse as sp

impute = importlib.import_module("4_impute_shift_share")

OUT_DIR = impute.OUT_DIR
CATEGORY_SHARE_FILE = impute.CATEGORY_SHARE_FILE
CATEGORY_RENAMES = impute.CATEGORY_RENAMES
PLACEBO_BETAS_FILE = "../../external/placebo_betas/did_coefs_placebo{sample}.dta"
ROSTER_FILE = "../../external/rf_samp/es_{samp}.dta"


def eb_shrink(df):
    df = df.dropna(subset=["b", "se"]).copy()
    df = df[df["se"] > 0]
    var_se = df["se"].to_numpy(float) ** 2
    b = df["b"].to_numpy(float)
    tau2 = max(0.0, b.var(ddof=1) - var_se.mean())
    mu_hat = np.average(b, weights=1 / var_se)
    w = tau2 / (tau2 + var_se)
    df["w_eb"] = w
    df["b_eb"] = w * b + (1 - w) * mu_hat
    df["se_eb"] = np.sqrt(w * var_se)
    return df, tau2, mu_hat


def load_all_shares(path, foia_ids):
    df = pd.read_stata(path)
    df["athr_id"] = df["athr_id"].astype(str)
    df["category"] = df["category"].astype(str).replace(CATEGORY_RENAMES)
    df = df.dropna(subset=["spend", "tot_shr_spend"])
    df = df[(df["spend"] > 0) & (df["tot_shr_spend"] > 0)]
    df = df[df["athr_id"].isin(set(foia_ids))].copy()
    df["share"] = df["spend"].astype(float) / df["tot_shr_spend"].astype(float)
    cats = sorted(df["category"].unique())
    ipos = {a: i for i, a in enumerate(foia_ids)}
    kpos = {c: k for k, c in enumerate(cats)}
    S = np.zeros((len(foia_ids), len(cats)))
    S[df["athr_id"].map(ipos).to_numpy(), df["category"].map(kpos).to_numpy()] = df["share"].to_numpy()
    return S, kpos


def cluster_keep_mask(univ_ids, foia_ids, cluster_file, min_n):
    cl = pd.read_csv(cluster_file, dtype={"athr_id": str})
    counts = cl[cl["athr_id"].isin(set(foia_ids))].groupby("cluster_label").size()
    keep_clusters = set(counts[counts >= max(1, min_n)].index)
    lab = cl.drop_duplicates("athr_id").set_index("athr_id")["cluster_label"]
    lab = lab.reindex(univ_ids)
    return (lab.notna() & lab.isin(keep_clusters)).to_numpy()


def renormalize_columns(W, active):
    Wc = W.tocsc()[:, np.flatnonzero(active)].tocsr()
    rs = np.asarray(Wc.sum(axis=1)).ravel()
    good = rs > 0
    inv = np.zeros_like(rs)
    inv[good] = 1 / rs[good]
    return sp.diags(inv) @ Wc, good


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", choices=impute.VERSIONS, default="hc")
    ap.add_argument("--all3", action="store_true")
    ap.add_argument("--k", type=int, default=3)
    ap.add_argument("--tag-k", action="store_true")
    ap.add_argument("--cluster-filter", default="")
    ap.add_argument("--min-foia-per-cluster", type=int, default=1)
    ap.add_argument("--roster-samp", default="all_jrnls_r1_r2")
    ap.add_argument("--iters", type=int, nargs="*", default=None)
    ap.add_argument("--no-anchor-renorm", action="store_true")
    args = ap.parse_args()

    sample_sfx = "_all3" if args.all3 else ""
    sfx_args = SimpleNamespace(
        k=args.k, tag_k=args.tag_k, cluster_filter=args.cluster_filter,
        min_foia_per_cluster=args.min_foia_per_cluster, ls_filter="",
        ls_sfx="_ls", min_max_sim=0.0, eb_own_weight=1.0, eb_prior="peer", eb_peer_k=5,
    )
    _, filter_sfx, k_sfx = impute.build_suffixes(sfx_args)
    stem = f"_{args.version}{sample_sfx}{filter_sfx}{k_sfx}"

    df_univ = pd.read_parquet(f"{OUT_DIR}/universe_ids.parquet")
    univ_ids = df_univ["athr_id"].astype(str).to_numpy()
    foia_ids = pd.read_csv(f"{OUT_DIR}/foia_ids_ordered.csv", dtype={"athr_id": str})["athr_id"].tolist()
    W = sp.load_npz(f"{OUT_DIR}/weight_matrix{k_sfx}.npz").tocsr()
    if W.shape != (len(univ_ids), len(foia_ids)):
        raise SystemExit(f"W shape {W.shape} != ({len(univ_ids)}, {len(foia_ids)})")

    S_all, kpos = load_all_shares(CATEGORY_SHARE_FILE.format(version=args.version, sample=sample_sfx), foia_ids)

    betas = pd.read_stata(PLACEBO_BETAS_FILE.format(sample=sample_sfx))
    betas["category"] = betas["category"].astype(str).replace(CATEGORY_RENAMES)
    missing = set(betas["category"]) - set(kpos)
    if missing:
        raise SystemExit(f"placebo markets absent from share file: {sorted(missing)}")
    betas["iter"] = betas["iter"].astype(int)
    iters = sorted(betas["iter"].unique().tolist()) if args.iters is None else args.iters

    keep = np.ones(len(univ_ids), dtype=bool)
    if args.cluster_filter:
        keep = cluster_keep_mask(univ_ids, foia_ids, args.cluster_filter, args.min_foia_per_cluster)
    print(f"universe {len(univ_ids):,} | after filter {keep.sum():,} | anchors {len(foia_ids)}")

    roster = pd.read_stata(ROSTER_FILE.format(samp=args.roster_samp), columns=["athr_id"])["athr_id"].astype(str)
    roster = set(roster.unique())
    in_roster = np.isin(univ_ids, list(roster))
    print(f"roster {len(roster):,} PIs | in universe {in_roster.sum():,}")

    real_path = f"{OUT_DIR}/final_imputed_shift_share{stem}.csv"
    real = None
    if os.path.exists(real_path):
        real = pd.read_csv(real_path, dtype={"athr_id": str}).set_index("athr_id")["exposure_ss"]
        real = real.reindex(univ_ids).to_numpy()

    foia_pos = {a: i for i, a in enumerate(foia_ids)}
    long_rows, eb_rows, summary = [], [], []

    for it in iters:
        bi, tau2, mu_hat = eb_shrink(betas[betas["iter"] == it])
        bi = bi.drop_duplicates("category")
        eb_rows.append(bi.assign(iter=it)[["iter", "category", "b", "se", "w_eb", "b_eb", "se_eb"]])
        cols = bi["category"].map(kpos).to_numpy()
        g = bi["b_eb"].to_numpy(float)
        S = S_all[:, cols]
        anchor_share = S.sum(axis=1)
        anchor_z = S @ g
        active = anchor_share > 0

        if args.no_anchor_renorm:
            Wi, good = W, np.asarray(W.sum(axis=1)).ravel() > 0
            S_use = S
        else:
            Wi, good = renormalize_columns(W, active)
            S_use = S[active]

        S_hat = Wi @ sp.csr_matrix(S_use)
        z = np.asarray(S_hat @ g).ravel()
        shr = np.asarray(S_hat.sum(axis=1)).ravel()
        z[~good] = np.nan
        shr[~good] = np.nan

        sel = keep & in_roster & good
        out = pd.DataFrame({
            "athr_id": univ_ids[sel],
            "exposure_ss": z[sel],
            "sum_imputed_shares": shr[sel],
            "foia_athr": 0,
        })
        anchors = pd.DataFrame({
            "athr_id": np.array(foia_ids)[active],
            "exposure_ss": anchor_z[active],
            "sum_imputed_shares": anchor_share[active],
            "foia_athr": 1,
        })
        out = pd.concat([out[~out["athr_id"].isin(set(anchors["athr_id"]))], anchors], ignore_index=True)
        out.insert(0, "iter", it)
        long_rows.append(out)

        zf = z[keep & good]
        row = {
            "iter": it,
            "n_markets": len(g),
            "tau2": tau2,
            "mu_hat": mu_hat,
            "mean_b_eb": g.mean(),
            "n_anchors_active": int(active.sum()),
            "n_universe_filtered": int((keep & good).sum()),
            "univ_mean": zf.mean(),
            "univ_sd": zf.std(),
            "univ_mean_share": shr[keep & good].mean(),
            "n_roster_rows": len(out),
        }
        if real is not None:
            m = keep & good & np.isfinite(real)
            row["corr_with_real"] = np.corrcoef(z[m], real[m])[0, 1]
        summary.append(row)
        print(f"iter {it:3d}: anchors {active.sum():3d} | mean z {zf.mean():+.5f} sd {zf.std():.5f}"
              + (f" | corr real {row['corr_with_real']:+.3f}" if real is not None else ""))

    pd.concat(long_rows, ignore_index=True).to_csv(f"{OUT_DIR}/placebo_shift_share{stem}.csv", index=False)
    pd.concat(eb_rows, ignore_index=True).to_csv(f"{OUT_DIR}/placebo_betas_eb{sample_sfx}.csv", index=False)
    pd.DataFrame(summary).to_csv(f"{OUT_DIR}/placebo_shift_share_summary{stem}.csv", index=False)
    print(f"saved placebo_shift_share{stem}.csv")


if __name__ == "__main__":
    main()
