import argparse
import os
import numpy as np
import pandas as pd
import scipy.sparse as sp
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

OUT_DIR = "../../output"
FIG_DIR = f"{OUT_DIR}/figures"
EXPOSURE_DIR = "../../external/exposure_wts"
DEFAULT_BETAS = ("/n/holylabs/LABS/pakes_lab/Lab/sci_eq/analysis/first_stage/"
                 "output/did_coefs_eb_price{sample}.dta")
CATEGORY_RENAMES = {"acrylamide/bis solution": "acrylamide-bis solution",
                    "dmem/f-12": "dmem-f-12"}
EBBLUE, DKORANGE = "#008BBC", "#E37E00"


def load_shocks(path):
    df = pd.read_stata(path)
    df["category"] = df["category"].replace(CATEGORY_RENAMES)
    df = df.dropna(subset=["b_eb"]).drop_duplicates("category").reset_index(drop=True)
    return df["category"].tolist(), df["b_eb"].to_numpy(float)


def build_share_matrix(path, foia_ids, markets):
    df = pd.read_stata(path)
    df["athr_id"] = df["athr_id"].astype(str)
    df["category"] = df["category"].astype(str).replace(CATEGORY_RENAMES)
    df = df.dropna(subset=["spend", "tot_shr_spend"])
    df = df[(df["spend"] > 0) & (df["tot_shr_spend"] > 0)].copy()
    df["share"] = df["spend"].astype(float) / df["tot_shr_spend"].astype(float)
    df = df[df["category"].isin(markets) & df["athr_id"].isin(set(foia_ids))]
    ipos = {a: i for i, a in enumerate(foia_ids)}
    kpos = {c: k for k, c in enumerate(markets)}
    S = sp.csr_matrix((df["share"].to_numpy(float),
                       (df["athr_id"].map(ipos).to_numpy(),
                        df["category"].map(kpos).to_numpy())),
                      shape=(len(foia_ids), len(markets)))
    return S.toarray()


def loo_knn(X, S, k, sharpen, floor):
    sim = (X @ X.T).toarray().astype(np.float64)
    np.fill_diagonal(sim, -1.0)
    n = sim.shape[0]
    topk = np.argpartition(-sim, k - 1, axis=1)[:, :k]
    vals = sim[np.arange(n)[:, None], topk]
    max_sim = sim.max(axis=1)
    vals = np.where(vals >= floor, vals, 0.0)
    vals = np.where(vals > 0, np.power(vals, sharpen), 0.0)
    rs = vals.sum(axis=1, keepdims=True)
    w = vals / np.where(rs > 0, rs, 1.0)
    pred = np.einsum("ik,ikm->im", w, S[topk])
    return pred, max_sim


def loo_mean(S):
    n = S.shape[0]
    return (S.sum(axis=0, keepdims=True) - S) / (n - 1)


def corr(a, b):
    a, b = np.asarray(a, float), np.asarray(b, float)
    if a.std() == 0 or b.std() == 0:
        return np.nan
    return float(np.corrcoef(a, b)[0, 1])


def slope(y, x):
    x, y = np.asarray(x, float), np.asarray(y, float)
    vx = x.var()
    return float(np.cov(x, y, ddof=0)[0, 1] / vx) if vx > 0 else np.nan


def rmse(a, b):
    return float(np.sqrt(np.mean((np.asarray(a) - np.asarray(b)) ** 2)))


def within_market(S, P):
    return S - S.mean(axis=0, keepdims=True), P - P.mean(axis=0, keepdims=True)


def block(S, P, P0, g, label):
    z, zh, z0 = S @ g, P @ g, P0 @ g
    t, th = S.sum(1), P.sum(1)
    Sw, Pw = within_market(S, P)
    return {
        "subset": label, "n_pi": S.shape[0], "n_cells": S.size,
        "cell_corr": corr(S.ravel(), P.ravel()),
        "cell_slope": slope(S.ravel(), P.ravel()),
        "cell_corr_null": corr(S.ravel(), P0.ravel()),
        "cell_within_mkt_corr": corr(Sw.ravel(), Pw.ravel()),
        "cell_within_mkt_slope": slope(Sw.ravel(), Pw.ravel()),
        "mktshr_corr": corr(t, th), "mktshr_slope": slope(t, th),
        "mktshr_rmse": rmse(t, th), "mktshr_rmse_null": rmse(t, P0.sum(1)),
        "expo_corr": corr(z, zh), "expo_slope": slope(z, zh),
        "expo_rmse": rmse(z, zh), "expo_rmse_null": rmse(z, z0),
        "expo_sd": float(z.std()),
    }


def boot_ci(S, P, g, B, seed):
    rng = np.random.default_rng(seed)
    n = S.shape[0]
    Sw, Pw = within_market(S, P)
    out = {"cell_corr": [], "cell_within_mkt_corr": [], "mktshr_corr": [], "expo_corr": []}
    for _ in range(B):
        idx = rng.integers(0, n, n)
        out["cell_corr"].append(corr(S[idx].ravel(), P[idx].ravel()))
        out["cell_within_mkt_corr"].append(corr(Sw[idx].ravel(), Pw[idx].ravel()))
        out["mktshr_corr"].append(corr(S[idx].sum(1), P[idx].sum(1)))
        out["expo_corr"].append(corr(S[idx] @ g, P[idx] @ g))
    return {k: (float(np.nanpercentile(v, 2.5)), float(np.nanpercentile(v, 97.5)))
            for k, v in out.items()}


def binscatter(ax, x, y, n_bins, color):
    q = pd.qcut(pd.Series(x).rank(method="first"), n_bins, labels=False)
    df = pd.DataFrame({"x": x, "y": y, "b": q}).groupby("b").mean()
    ax.scatter(df["x"], df["y"], s=34, color=color, zorder=3)
    return df


def make_figure(S, P, g, res, ci, sim_ref, max_sim, out_stem):
    fig, (axA, axB) = plt.subplots(1, 2, figsize=(11, 4.6))
    x, y = P.ravel(), S.ravel()
    df = binscatter(axA, x, y, 20, EBBLUE)
    lim = float(max(df["x"].max(), df["y"].max())) * 1.1
    axA.plot([0, lim], [0, lim], color="k", lw=0.8, ls=":")
    b = res["cell_slope"]
    a = y.mean() - b * x.mean()
    xs = np.linspace(0, lim, 50)
    axA.plot(xs, a + b * xs, color=DKORANGE, lw=1.4)
    axA.set_xlim(0, lim); axA.set_ylim(0, lim)
    axA.set_xlabel("Imputed treated-market share (leave-one-out)")
    axA.set_ylabel("Observed treated-market share")
    axA.set_title(f"PI x market cells (n = {res['n_pi']} PIs x {S.shape[1]} markets)", fontsize=10)
    axA.text(0.03, 0.97,
             f"corr = {res['cell_corr']:.2f} [{ci['cell_corr'][0]:.2f}, {ci['cell_corr'][1]:.2f}]\n"
             f"within-market corr = {res['cell_within_mkt_corr']:.2f} "
             f"[{ci['cell_within_mkt_corr'][0]:.2f}, {ci['cell_within_mkt_corr'][1]:.2f}]\n"
             f"slope = {b:.2f}",
             transform=axA.transAxes, va="top", fontsize=9)

    z, zh = S @ g, P @ g
    hi = max_sim >= sim_ref
    axB.scatter(zh[~hi], z[~hi], s=14, color=EBBLUE, alpha=0.35, label=f"nearest donor sim < {sim_ref:.2f}")
    axB.scatter(zh[hi], z[hi], s=14, color=EBBLUE, alpha=0.9, label=f"nearest donor sim >= {sim_ref:.2f}")
    lo_, hi_ = float(min(z.min(), zh.min())), float(max(z.max(), zh.max()))
    axB.plot([lo_, hi_], [lo_, hi_], color="k", lw=0.8, ls=":")
    b2 = res["expo_slope"]; a2 = z.mean() - b2 * zh.mean()
    xs = np.linspace(lo_, hi_, 50)
    axB.plot(xs, a2 + b2 * xs, color=DKORANGE, lw=1.4)
    axB.set_xlabel("Imputed exposure (leave-one-out)")
    axB.set_ylabel("Observed exposure")
    axB.set_title("PI-level exposure", fontsize=10)
    axB.text(0.03, 0.97,
             f"corr = {res['expo_corr']:.2f} [{ci['expo_corr'][0]:.2f}, {ci['expo_corr'][1]:.2f}]\n"
             f"slope = {b2:.2f}\n"
             f"RMSE = {res['expo_rmse']:.4f} vs {res['expo_rmse_null']:.4f} (grand mean)",
             transform=axB.transAxes, va="top", fontsize=9)
    axB.legend(fontsize=8, loc="lower right", frameon=False)
    for ax in (axA, axB):
        ax.spines[["top", "right"]].set_visible(False)
    fig.tight_layout()
    fig.savefig(f"{FIG_DIR}/{out_stem}.pdf", bbox_inches="tight")
    fig.savefig(f"{FIG_DIR}/{out_stem}.png", dpi=160, bbox_inches="tight")
    plt.close(fig)


def make_simple_figure(S, P, g, res, ci, out_stem, n_bins=5):
    z, zh = S @ g, P @ g
    df = pd.DataFrame({"x": zh, "y": z})
    df["b"] = pd.qcut(df["x"].rank(method="first"), n_bins, labels=False)
    grp = df.groupby("b").agg(x=("x", "mean"), y=("y", "mean"),
                              se=("y", lambda v: v.std(ddof=1) / np.sqrt(len(v))), n=("y", "size"))
    fig, ax = plt.subplots(figsize=(5.6, 4.6))
    lo_ = float(min(grp["x"].min(), (grp["y"] - 1.96 * grp["se"]).min())) - 0.005
    hi_ = float(max(grp["x"].max(), (grp["y"] + 1.96 * grp["se"]).max())) + 0.005
    ax.plot([lo_, hi_], [lo_, hi_], color="k", lw=0.8, ls=":", label="45-degree line")
    ax.axhline(z.mean(), color="grey", lw=0.8, ls="--", label="Predict every PI at the mean")
    ax.errorbar(grp["x"], grp["y"], yerr=1.96 * grp["se"], fmt="o", color=EBBLUE,
                ms=7, capsize=3, lw=1.2, label=f"Quintile of imputed exposure (n = {S.shape[0]} FOIA PIs)")
    b = res["expo_slope"]; a = z.mean() - b * zh.mean()
    xs = np.linspace(lo_, hi_, 50)
    ax.plot(xs, a + b * xs, color=DKORANGE, lw=1.4, label=f"Fitted line, slope = {b:.2f}")
    ax.set_xlim(lo_, hi_); ax.set_ylim(lo_, hi_)
    ax.set_xlabel("Imputed exposure (leave-one-out, from text neighbours)")
    ax.set_ylabel("Observed exposure (FOIA purchasing data)")
    ax.text(0.03, 0.97, f"corr = {res['expo_corr']:.2f}  [{ci['expo_corr'][0]:.2f}, {ci['expo_corr'][1]:.2f}]",
            transform=ax.transAxes, va="top", fontsize=10)
    ax.legend(fontsize=7.5, loc="lower right", frameon=False)
    ax.spines[["top", "right"]].set_visible(False)
    fig.tight_layout()
    fig.savefig(f"{FIG_DIR}/{out_stem}.pdf", bbox_inches="tight")
    fig.savefig(f"{FIG_DIR}/{out_stem}.png", dpi=160, bbox_inches="tight")
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="")
    ap.add_argument("--version", default="hc", choices=["hc", "all", "treated_hc"])
    ap.add_argument("--sample", default="all3")
    ap.add_argument("--k", type=int, default=3)
    ap.add_argument("--sharpen", type=float, default=2.0)
    ap.add_argument("--floor", type=float, default=0.05)
    ap.add_argument("--betas-path", default="")
    ap.add_argument("--sim-ref", type=float, default=0.20)
    ap.add_argument("--boot", type=int, default=1000)
    ap.add_argument("--seed", type=int, default=8975)
    args = ap.parse_args()

    tag = f"_{args.tag}" if args.tag and not args.tag.startswith("_") else args.tag
    samp = f"_{args.sample}" if args.sample else ""
    stem = f"{args.version}{samp}_k{args.k}"
    betas_path = args.betas_path or DEFAULT_BETAS.format(sample=samp)
    os.makedirs(FIG_DIR, exist_ok=True)

    X = sp.load_npz(f"{OUT_DIR}/tfidf_foia{tag}.npz").tocsr()
    foia_ids = pd.read_csv(f"{OUT_DIR}/foia_ids_ordered{tag}.csv", dtype={"athr_id": str})["athr_id"].tolist()
    markets, g = load_shocks(betas_path)
    S = build_share_matrix(f"{EXPOSURE_DIR}/athr_exposure_by_category_{args.version}{samp}.dta",
                           foia_ids, markets)
    keep = S.sum(1) > 0
    print(f"anchors with text: {len(foia_ids)}   with treated shares: {keep.sum()}   markets: {len(markets)}")
    X, S, ids = X[keep], S[keep], [a for a, k in zip(foia_ids, keep) if k]

    P, max_sim = loo_knn(X, S, args.k, args.sharpen, args.floor)
    P0 = loo_mean(S)
    hi = max_sim >= args.sim_ref

    rows = [block(S, P, P0, g, "all"),
            block(S[hi], P[hi], P0[hi], g, f"max_sim>={args.sim_ref}"),
            block(S[~hi], P[~hi], P0[~hi], g, f"max_sim<{args.sim_ref}")]
    res = pd.DataFrame(rows)
    ci = boot_ci(S, P, g, args.boot, args.seed)

    res.to_csv(f"{OUT_DIR}/loo_shares_summary_{stem}.csv", index=False)
    pd.DataFrame({"athr_id": ids, "max_sim": max_sim,
                  "exposure": S @ g, "exposure_loo": P @ g, "exposure_null": P0 @ g,
                  "mkt_spend_shr": S.sum(1), "mkt_spend_shr_loo": P.sum(1)}
                 ).to_csv(f"{OUT_DIR}/loo_shares_pi_{stem}.csv", index=False)
    cells = pd.DataFrame({"athr_id": np.repeat(ids, len(markets)),
                          "category": np.tile(markets, len(ids)),
                          "share": S.ravel(), "share_loo": P.ravel(), "share_null": P0.ravel()})
    cells.to_csv(f"{OUT_DIR}/loo_shares_cells_{stem}.csv", index=False)

    with open(f"{OUT_DIR}/loo_shares_summary_{stem}.txt", "w") as f:
        f.write(f"Leave-one-out KNN(k={args.k}, sharpen={args.sharpen}, floor={args.floor})  "
                f"version={args.version}{samp}   anchors={S.shape[0]}  markets={len(markets)}\n")
        f.write(f"nearest-donor sim among anchors: median={np.median(max_sim):.3f}  "
                f"IQR=[{np.percentile(max_sim,25):.3f}, {np.percentile(max_sim,75):.3f}]  "
                f"share>= {args.sim_ref}: {hi.mean():.2f}\n\n")
        f.write(res.T.to_string() + "\n\n95% PI-bootstrap CIs (all anchors):\n")
        for k_, (lo_, hi_) in ci.items():
            f.write(f"  {k_:<24s} [{lo_:.3f}, {hi_:.3f}]\n")
    print(res.T.to_string())
    print("CIs:", ci)

    make_figure(S, P, g, rows[0], ci, args.sim_ref, max_sim, f"loo_shares_{stem}")
    make_simple_figure(S, P, g, rows[0], ci, f"loo_exposure_simple_{stem}")
    print(f"Saved {FIG_DIR}/loo_shares_{stem}.pdf, {FIG_DIR}/loo_exposure_simple_{stem}.pdf, {OUT_DIR}/loo_shares_summary_{stem}.txt")


if __name__ == "__main__":
    main()
