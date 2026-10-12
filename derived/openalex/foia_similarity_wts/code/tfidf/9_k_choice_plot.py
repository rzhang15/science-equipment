import argparse
import os
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

OUT_DIR = "../../output"
FIG_DIR = f"{OUT_DIR}/figures"
EBBLUE, DKORANGE, LAVENDER = "#008BBC", "#E37E00", "#938DD2"


def load_loo(stem, ks):
    rows = []
    for k in ks:
        p = f"{OUT_DIR}/loo_shares_summary_{stem}_k{k}.csv"
        if not os.path.exists(p):
            continue
        d = pd.read_csv(p)
        d = d[d["subset"] == "all"].iloc[0]
        pi = pd.read_csv(f"{OUT_DIR}/loo_shares_pi_{stem}_k{k}.csv")
        z, zh = pi["exposure"], pi["exposure_loo"]
        b = d["expo_slope"]
        rows.append({"k": k, "expo_rmse": d["expo_rmse"], "expo_rmse_null": d["expo_rmse_null"],
                     "expo_corr": d["expo_corr"], "expo_slope": b,
                     "expo_intercept": z.mean() - b * zh.mean(),
                     "mean_true": z.mean(), "mean_loo": zh.mean(),
                     "sd_true": z.std(), "sd_loo": zh.std(), "signal_sd_loo": b * zh.std()})
    return pd.DataFrame(rows)


def load_universe_sd(stem, filt, ks):
    rows = []
    for k in ks:
        p = f"{OUT_DIR}/final_imputed_shift_share_{stem}{filt}_k{k}.csv"
        if not os.path.exists(p):
            continue
        e = pd.read_csv(p, usecols=["exposure_ss"])["exposure_ss"]
        q = e.quantile([.1, .9])
        rows.append({"k": k, "sd": e.std(), "p90_p10": q[.9] - q[.1]})
    return pd.DataFrame(rows)


def load_variogram(version, kmax):
    p = f"{OUT_DIR}/exposure_variogram_ksweep_{version}.csv"
    if not os.path.exists(p):
        return pd.DataFrame()
    d = pd.read_csv(p)
    return d[d["k"] <= kmax][["k", "rmse_prod_panel", "rmse_ok_panel"]]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", default="hc")
    ap.add_argument("--sample", default="all3")
    ap.add_argument("--filter", default="_cf")
    ap.add_argument("--ks", type=int, nargs="+", default=[1, 2, 3, 4, 5])
    ap.add_argument("--k-star", type=int, default=3)
    ap.add_argument("--variogram-kmax", type=int, default=20)
    args = ap.parse_args()

    stem = f"{args.version}_{args.sample}"
    loo = load_loo(stem, args.ks)
    usd = load_universe_sd(stem, args.filter, args.ks)
    vg = load_variogram(args.version, args.variogram_kmax)
    os.makedirs(FIG_DIR, exist_ok=True)

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(10, 4))

    if len(vg):
        ax1.plot(vg["k"], vg["rmse_prod_panel"], "o-", color=EBBLUE, lw=2, ms=6,
                 label="Variogram: expected RMSE of imputed exposure, RF panel")
        ax1.plot(vg["k"], vg["rmse_ok_panel"], ":", color=EBBLUE, lw=1.4,
                 label="Variogram: kriging-optimal weights (floor)")
    if len(loo):
        ax1b = ax1.twinx()
        ax1b.plot(loo["k"], loo["expo_rmse"], "s--", color=DKORANGE, lw=1.6, ms=5,
                  label="Leave-one-out RMSE, FOIA anchors")
        ax1b.axhline(loo["expo_rmse_null"].iloc[0], color=DKORANGE, ls=":", lw=1.2,
                     label="LOO RMSE, grand-mean null")
        ax1b.set_ylabel("LOO RMSE, anchors", color=DKORANGE)
        ax1b.tick_params(axis="y", colors=DKORANGE)
        ax1b.spines[["top"]].set_visible(False)
        h1, l1 = ax1.get_legend_handles_labels()
        h2, l2 = ax1b.get_legend_handles_labels()
        ax1.legend(h1 + h2, l1 + l2, fontsize=7.5, frameon=False, loc="upper right")
    else:
        ax1.legend(fontsize=8, frameon=False, loc="upper right")
    ax1.axvline(args.k_star, color="black", ls="--", lw=1, alpha=.6)
    ax1.set_xlabel("K nearest donors")
    ax1.set_ylabel("Expected RMSE of imputed exposure", color=EBBLUE)
    ax1.tick_params(axis="y", colors=EBBLUE)
    ax1.set_title("A. Imputation error", loc="left", fontsize=11)
    ax1.set_xscale("log")
    xt = sorted(set(args.ks) | set(vg["k"].tolist() if len(vg) else []))
    ax1.set_xticks(xt); ax1.set_xticklabels([str(k) for k in xt]); ax1.minorticks_off()
    ax1.spines[["top"]].set_visible(False)

    if len(loo):
        ax2.plot(loo["k"], loo["sd_loo"], "s--", color=DKORANGE, lw=1.6, ms=5,
                 label="SD of LOO-imputed exposure, FOIA anchors")
        ax2.plot(loo["k"], loo["signal_sd_loo"], "^-", color=LAVENDER, lw=1.8, ms=6,
                 label="Signal SD: slope x SD (part that tracks true exposure)")
        ax2.axhline(loo["sd_true"].iloc[0], color="gray", ls=":", lw=1.2,
                    label="SD of true exposure, FOIA anchors")
    if len(usd):
        ax2.plot(usd["k"], usd["sd"], "o-", color=EBBLUE, lw=2, ms=6,
                 label="SD of imputed exposure, universe PIs")
    ax2.legend(fontsize=8, frameon=False, loc="upper right")
    ax2.set_ylim(bottom=0)
    ax2.axvline(args.k_star, color="black", ls="--", lw=1, alpha=.6)
    ax2.set_xlabel("K nearest donors")
    ax2.set_ylabel("SD of exposure")
    ax2.set_title("B. Variation retained: total vs. signal", loc="left", fontsize=11)
    ax2.set_xticks(args.ks)
    ax2.spines[["top"]].set_visible(False)

    fig.suptitle(f"Choice of K: production K={args.k_star}  (version={stem}{args.filter})",
                 fontsize=10, y=1.02)
    fig.tight_layout()
    out = f"{FIG_DIR}/k_choice_{stem}{args.filter}"
    fig.savefig(f"{out}.pdf", bbox_inches="tight")
    fig.savefig(f"{out}.png", dpi=160, bbox_inches="tight")

    tab = loo.merge(usd, on="k", how="outer")
    if len(vg):
        tab = tab.merge(vg, on="k", how="left")
    tab.to_csv(f"{OUT_DIR}/k_choice_{stem}{args.filter}.csv", index=False)
    print(tab.round(4).to_string(index=False))
    print(f"Saved {out}.pdf/.png and {OUT_DIR}/k_choice_{stem}{args.filter}.csv")


if __name__ == "__main__":
    main()
