import argparse
import importlib
import os
import numpy as np
import pandas as pd
import scipy.sparse as sp
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

loo = importlib.import_module("5d_loo_shares")
OUT_DIR, FIG_DIR, EXPOSURE_DIR = loo.OUT_DIR, loo.FIG_DIR, loo.EXPOSURE_DIR
EBBLUE, DKORANGE, LAVENDER, DKEMERALD = "#008BBC", "#E37E00", "#938DD2", "#007A5E"


def sweep(X, S, g, ks, sharpen, floor, boot, seed):
    z = S @ g
    sim = (X @ X.T).toarray()
    np.fill_diagonal(sim, -1.0)
    sim_sorted = -np.sort(-sim, axis=1)
    rng = np.random.default_rng(seed)
    n = len(z)
    idx_boot = [rng.integers(0, n, n) for _ in range(boot)]
    rows = []
    for k in ks:
        P, _ = loo.loo_knn(X, S, k, sharpen, floor)
        zh = P @ g
        b = loo.slope(z, zh)
        bs = [loo.corr(z[i], zh[i]) for i in idx_boot]
        v = sim_sorted[:, :k]
        v = np.where(v >= floor, v, 0.0) ** sharpen
        w = v / np.where(v.sum(1, keepdims=True) > 0, v.sum(1, keepdims=True), 1.0)
        rows.append({
            "effective_donors": float(np.median(1.0 / np.maximum((w ** 2).sum(1), 1e-12))),
            "weight_share_beyond_rank3": float(np.median(w[:, 3:].sum(1))) if k > 3 else 0.0,
            "k": k, "corr": loo.corr(z, zh), "corr_lo": np.nanpercentile(bs, 2.5),
            "corr_hi": np.nanpercentile(bs, 97.5), "rmse": loo.rmse(z, zh),
            "slope_true_on_imputed": b, "sd_true": z.std(), "sd_imputed": zh.std(),
            "signal_sd": b * zh.std(), "noise_sd": np.sqrt(max(zh.var() - (b * zh.std()) ** 2, 0)),
            "median_sim_kth_donor": float(np.median(sim_sorted[:, k - 1])),
            "share_kth_donor_below_floor": float((sim_sorted[:, k - 1] < floor).mean()),
        })
    return pd.DataFrame(rows), loo.rmse(z, loo.loo_mean(S) @ g)


def make_figure(df, null_rmse, k_star, out_stem):
    fig, ax = plt.subplots(figsize=(7, 4.2))
    ax.plot(df["k"], df["rmse"], "o-", color=EBBLUE, lw=2, ms=5, label="LOO RMSE of imputed exposure")
    ax.axhline(null_rmse, color=EBBLUE, ls=":", lw=1.2, label="RMSE, grand-mean null")
    ax.plot(df["k"], df["sd_imputed"], "s--", color=DKORANGE, lw=1.6, ms=5, label="SD of imputed exposure")
    sd_true = df["sd_true"].iloc[0]
    ax.fill_between(df["k"], df["corr_lo"] * sd_true, df["corr_hi"] * sd_true,
                    color=LAVENDER, alpha=.18, lw=0)
    ax.plot(df["k"], df["signal_sd"], "^-", color=LAVENDER, lw=2, ms=6,
            label="Signal SD = corr x SD(true); band = 95% bootstrap CI")
    ax.axhline(df["sd_true"].iloc[0], color="gray", ls=":", lw=1.2, label="SD of true exposure")
    ax.axvline(k_star, color="black", ls="--", lw=1, alpha=.6)
    ax.set_xscale("log")
    ax.set_xticks(df["k"])
    ax.set_xticklabels([f"{k}\n({e:.1f})" for k, e in zip(df["k"], df["effective_donors"])], fontsize=8)
    ax.minorticks_off()
    ax.set_xlabel("K nearest donors (log scale); median effective donors in parentheses")
    ax.set_ylabel("Exposure units")
    ax.set_ylim(bottom=0)
    ax.set_title(f"Leave-one-out across K, {df.attrs['stem']}  (production K={k_star})", fontsize=10)
    ax.legend(fontsize=8, frameon=False, loc="center right")
    ax.spines[["top"]].set_visible(False)
    ax2 = ax.twinx()
    ax2.set_ylim(ax.get_ylim()[0] / sd_true, ax.get_ylim()[1] / sd_true)
    ax2.set_ylabel("Correlation of imputed with true exposure", color=LAVENDER)
    ax2.tick_params(axis="y", colors=LAVENDER)
    ax2.spines[["top"]].set_visible(False)
    fig.tight_layout()
    fig.savefig(f"{FIG_DIR}/{out_stem}.pdf", bbox_inches="tight")
    fig.savefig(f"{FIG_DIR}/{out_stem}.png", dpi=160, bbox_inches="tight")
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="")
    ap.add_argument("--version", default="hc", choices=["hc", "all", "treated_hc"])
    ap.add_argument("--sample", default="all3")
    ap.add_argument("--ks", type=int, nargs="+", default=[1, 2, 3, 4, 5, 7, 10, 15, 20, 30])
    ap.add_argument("--k-star", type=int, default=5)
    ap.add_argument("--sharpen", type=float, default=2.0)
    ap.add_argument("--floor", type=float, default=0.05)
    ap.add_argument("--betas-path", default="")
    ap.add_argument("--boot", type=int, default=1000)
    ap.add_argument("--seed", type=int, default=8975)
    args = ap.parse_args()

    tag = f"_{args.tag}" if args.tag and not args.tag.startswith("_") else args.tag
    samp = f"_{args.sample}" if args.sample else ""
    stem = f"{args.version}{samp}"
    betas_path = args.betas_path or loo.DEFAULT_BETAS.format(sample=samp)
    os.makedirs(FIG_DIR, exist_ok=True)

    X = sp.load_npz(f"{OUT_DIR}/tfidf_foia{tag}.npz").tocsr()
    foia_ids = pd.read_csv(f"{OUT_DIR}/foia_ids_ordered{tag}.csv", dtype={"athr_id": str})["athr_id"].tolist()
    markets, g = loo.load_shocks(betas_path)
    S = loo.build_share_matrix(f"{EXPOSURE_DIR}/athr_exposure_by_category_{stem}.dta", foia_ids, markets)
    keep = S.sum(1) > 0
    X, S = X[keep], S[keep]
    print(f"anchors={S.shape[0]}  markets={len(markets)}  ks={args.ks}")

    df, null_rmse = sweep(X, S, g, args.ks, args.sharpen, args.floor, args.boot, args.seed)
    df["rmse_null"] = null_rmse
    df.attrs["stem"] = stem
    df.to_csv(f"{OUT_DIR}/loo_k_sweep_{stem}.csv", index=False)
    print(df.round(4).to_string(index=False))
    make_figure(df, null_rmse, args.k_star, f"loo_k_sweep_{stem}")
    print(f"Saved {FIG_DIR}/loo_k_sweep_{stem}.pdf and {OUT_DIR}/loo_k_sweep_{stem}.csv")


if __name__ == "__main__":
    main()
