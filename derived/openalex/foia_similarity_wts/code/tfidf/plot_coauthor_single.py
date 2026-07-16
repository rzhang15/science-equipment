"""
One-figure coauthor validation exhibit.

Story: coauthors that are most similar to their FOIA partner — measured
either by topic (cosine of TF-IDF vectors) or by co-publication count —
should have imputed exposure values closest to the FOIA partner's true
exposure. Two-panel figure:

  LEFT   quintiles of sim_to_partner  ->  corr(imputed, true) with 95% CI
  RIGHT  copubs bins                  ->  corr(imputed, true) with 95% CI

Reads the pair CSV produced by validate_coauthors.py.

Run:
  python plot_coauthor_single.py --pairs ../../output/coauthor_validation_pairs_hc_cf_k3.csv
"""
import argparse
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

OUT_DIR = "../../output"
FIG_DIR = f"{OUT_DIR}/figures"


def _corr_ci(y, p):
    """Pearson r + Fisher-z 95% CI, for a plotted subgroup."""
    n = len(y)
    if n < 4 or np.std(y) == 0 or np.std(p) == 0:
        return np.nan, np.nan, np.nan
    r = float(np.corrcoef(y, p)[0, 1])
    if abs(r) >= 1.0:
        return r, np.nan, np.nan
    z = 0.5 * np.log((1 + r) / (1 - r))
    se = 1.0 / np.sqrt(n - 3)
    lo = np.tanh(z - 1.96 * se)
    hi = np.tanh(z + 1.96 * se)
    return r, float(lo), float(hi)


def bin_by_quintile(df, x_col):
    """Return per-quintile summary: mean x, n, r, r_lo, r_hi."""
    q = np.quantile(df[x_col].to_numpy(), np.linspace(0, 1, 6))
    q[-1] += 1e-12
    df = df.copy()
    df["bin"] = np.digitize(df[x_col].to_numpy(), q[1:-1])
    rows = []
    for b in range(5):
        sub = df[df["bin"] == b]
        r, lo, hi = _corr_ci(sub["e_foia_true"].to_numpy(),
                             sub["pred_knn"].to_numpy())
        rows.append({
            "quintile": b + 1,
            "x_lo": float(q[b]),
            "x_hi": float(q[b + 1]),
            "x_mean": float(sub[x_col].mean()) if len(sub) else np.nan,
            "n": int(len(sub)),
            "r": r, "r_lo": lo, "r_hi": hi,
        })
    return pd.DataFrame(rows)


def bin_by_copubs(df, edges):
    """Copubs bins (right-inclusive). Same output schema as bin_by_quintile
    but rows keyed on the bin label."""
    rows = []
    for lo, hi in zip(edges[:-1], edges[1:]):
        mask = (df["copubs"] > lo) & (df["copubs"] <= hi)
        sub = df.loc[mask]
        r, r_lo, r_hi = _corr_ci(sub["e_foia_true"].to_numpy(),
                                 sub["pred_knn"].to_numpy())
        rows.append({
            "copub_lo": lo, "copub_hi": hi,
            "label": f"({lo}, {hi}]",
            "n": int(len(sub)),
            "x_mean": float(sub["copubs"].mean()) if len(sub) else np.nan,
            "r": r, "r_lo": r_lo, "r_hi": r_hi,
        })
    return pd.DataFrame(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pairs",
                    default=f"{OUT_DIR}/coauthor_validation_pairs_hc_cf_k3.csv",
                    help="Pair-level CSV from validate_coauthors.py.")
    ap.add_argument("--copub-edges", default="0,1,2,3,5,10,50",
                    help="Right-edges of copub bins (comma-sep).")
    ap.add_argument("--tag", default="hc_cf_k3",
                    help="Suffix on output PNG/CSVs.")
    ap.add_argument("--min-n-per-bin", type=int, default=20,
                    help="Drop bins with fewer pairs than this from the figure.")
    args = ap.parse_args()

    if not os.path.exists(args.pairs):
        raise SystemExit(f"missing pair CSV: {args.pairs}")
    os.makedirs(FIG_DIR, exist_ok=True)
    df = pd.read_csv(args.pairs)
    for col in ("e_foia_true", "pred_knn", "sim_to_partner", "copubs"):
        if col not in df.columns:
            raise SystemExit(f"missing column {col!r} in {args.pairs}")
    print(f"Loaded {len(df):,} coauthor–FOIA pairs from {args.pairs}")

    # ---- data prep ----
    sim_tab = bin_by_quintile(df, "sim_to_partner")
    edges = [int(x) for x in args.copub_edges.split(",")]
    copub_tab = bin_by_copubs(df, edges)
    copub_tab_plot = copub_tab[copub_tab["n"] >= args.min_n_per_bin].copy()

    # overall reference line
    r_all, _, _ = _corr_ci(df["e_foia_true"].to_numpy(),
                           df["pred_knn"].to_numpy())

    # ---- figure ----
    fig, (axL, axR) = plt.subplots(1, 2, figsize=(11, 4.6),
                                   gridspec_kw={"width_ratios": [1, 1]})

    # LEFT: quintiles of topical similarity
    x = sim_tab["quintile"].to_numpy()
    y = sim_tab["r"].to_numpy()
    err = np.vstack([y - sim_tab["r_lo"].to_numpy(),
                     sim_tab["r_hi"].to_numpy() - y])
    axL.errorbar(x, y, yerr=err, fmt="o-", ms=7, lw=1.8, capsize=3,
                 color="C0")
    axL.axhline(r_all, ls="--", color="gray", lw=1,
                label=f"overall  r = {r_all:+.2f}")
    axL.axhline(0, color="k", lw=0.6, alpha=0.5)
    axL.set_xticks(x)
    axL.set_xticklabels([
        f"Q{q}\n[{lo:.2f}–{hi:.2f}]\nn={n:,}"
        for q, lo, hi, n in zip(
            sim_tab["quintile"], sim_tab["x_lo"], sim_tab["x_hi"], sim_tab["n"]
        )
    ], fontsize=8)
    axL.set_xlabel("Cosine similarity to FOIA partner (quintile)")
    axL.set_ylabel("Corr(imputed coauthor exposure,\ntrue FOIA partner exposure)")
    axL.set_title("A. Higher topic similarity → tighter tracking")
    axL.legend(loc="upper left", fontsize=8)
    axL.grid(alpha=0.3)

    # RIGHT: copub bins
    xr = np.arange(len(copub_tab_plot))
    yr = copub_tab_plot["r"].to_numpy()
    errr = np.vstack([yr - copub_tab_plot["r_lo"].to_numpy(),
                      copub_tab_plot["r_hi"].to_numpy() - yr])
    axR.errorbar(xr, yr, yerr=errr, fmt="s-", ms=7, lw=1.8, capsize=3,
                 color="C3")
    axR.axhline(r_all, ls="--", color="gray", lw=1,
                label=f"overall  r = {r_all:+.2f}")
    axR.axhline(0, color="k", lw=0.6, alpha=0.5)
    axR.set_xticks(xr)
    axR.set_xticklabels([
        f"{row.label}\nn={row.n:,}"
        for row in copub_tab_plot.itertuples()
    ], fontsize=8)
    axR.set_xlabel("# copublications with FOIA partner")
    axR.set_ylabel("Corr(imputed coauthor exposure,\ntrue FOIA partner exposure)")
    axR.set_title("B. More copublications → tighter tracking")
    axR.legend(loc="upper left", fontsize=8)
    axR.grid(alpha=0.3)

    fig.suptitle(
        "Coauthor validation: imputation quality rises with closeness to FOIA partner",
        fontsize=12, fontweight="bold", y=1.02,
    )
    fig.tight_layout()

    out_png = f"{FIG_DIR}/coauthor_validation_{args.tag}.png"
    fig.savefig(out_png, dpi=150, bbox_inches="tight")
    print(f"Saved {out_png}")

    sim_tab.to_csv(f"{OUT_DIR}/coauthor_by_sim_{args.tag}.csv", index=False)
    copub_tab.to_csv(f"{OUT_DIR}/coauthor_by_copubs_{args.tag}.csv", index=False)
    print(f"Saved {OUT_DIR}/coauthor_by_sim_{args.tag}.csv")
    print(f"Saved {OUT_DIR}/coauthor_by_copubs_{args.tag}.csv")

    print("\nBy topical-similarity quintile:")
    print(sim_tab.to_string(index=False,
                            float_format=lambda x: f"{x:7.3f}"))
    print("\nBy copubs bin:")
    print(copub_tab.to_string(index=False,
                              float_format=lambda x: f"{x:7.3f}"))


if __name__ == "__main__":
    main()
