"""
Plot the FOIA-author vs imputed-coauthor exposure relationship for the K-NN
imputation, using the pair-level CSV written by
tfidf/validate_coauthors.py:

  ../output/coauthor_validation_pairs{tag}{k_sfx}_{version}.csv
     columns: athr_id, coauthor_id, e_foia_true, pred_knn,
              sim_to_partner, partner_rank, copubs

Layout: a grid of binned scatters at increasing copubs thresholds, then two
trend panels (corr vs threshold, twin-test metrics vs threshold), then a
copubs histogram.

Run:
  python plot_coauthor_validation.py --version hc --k 3
  python plot_coauthor_validation.py --version treated_hc --tag restricted --k 3
"""
import argparse
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

OUT_DIR = "../output"
FIG_DIR = f"{OUT_DIR}/figures"

KNN_COLOR = "C0"


def binned_scatter(ax, x, y, color, label, n_bins=20):
    """Equal-count bins on x; plot mean y per bin with 95% CI bars."""
    if len(x) < n_bins * 5:
        n_bins = max(5, len(x) // 5)
    qs = np.linspace(0, 1, n_bins + 1)
    cuts = np.quantile(x, qs)
    cuts[-1] += 1e-9
    idx = np.digitize(x, cuts[1:-1])
    xb = np.array([x[idx == i].mean() if (idx == i).sum() else np.nan for i in range(n_bins)])
    yb = np.array([y[idx == i].mean() if (idx == i).sum() else np.nan for i in range(n_bins)])
    ye = np.array([
        1.96 * y[idx == i].std() / np.sqrt(max(1, (idx == i).sum()))
        if (idx == i).sum() else np.nan
        for i in range(n_bins)
    ])
    ax.errorbar(xb, yb, yerr=ye, fmt="o", ms=4, lw=1, capsize=2,
                color=color, label=label)


def panel_knn(ax, df, title):
    """One scatter panel showing the K-NN prediction vs true exposure."""
    x = df["e_foia_true"].values
    y = df["pred_knn"].values
    lo = float(np.nanmin(np.concatenate([x, y])))
    hi = float(np.nanmax(np.concatenate([x, y])))
    binned_scatter(ax, x, y, color=KNN_COLOR, label="K-NN")
    m = np.isfinite(x) & np.isfinite(y)
    if m.sum() >= 2 and x[m].std() > 0 and y[m].std() > 0:
        corr  = float(np.corrcoef(x[m], y[m])[0, 1])
        slope = float(np.polyfit(x[m], y[m], 1)[0])
    else:
        corr, slope = float("nan"), float("nan")
    pad = 0.05 * (hi - lo) if hi > lo else 0.01
    lo, hi = lo - pad, hi + pad
    ax.plot([lo, hi], [lo, hi], "k--", lw=1, alpha=0.6, label="45 deg")
    ax.set_xlabel("FOIA true exposure")
    ax.set_ylabel("Imputed coauthor exposure (K-NN)")
    ax.set_title(f"{title}   n={len(df):,}\nK-NN: r={corr:+.3f}  slope={slope:+.2f}",
                 fontsize=10)
    ax.legend(fontsize=8, loc="best")
    ax.grid(alpha=0.3)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", default="hc",
                    choices=["hc", "all", "treated_hc"],
                    help="Exposure denominator matching validate_coauthors --out-tag.")
    ap.add_argument("--tag", default="restricted",
                    help="TF-IDF tag. Default 'restricted' matches production.")
    ap.add_argument("--k", type=int, default=None,
                    help="If set, load the K-tagged pairs file "
                         "coauthor_validation_pairs{tag}_{version}_k{k}.csv "
                         "(produced by validate_coauthors.py --k {k} "
                         "--out-tag {version}_k{k}). Otherwise falls back to "
                         "the untagged production file. Also appended to the "
                         "output PNG/CSV names.")
    ap.add_argument("--scatter-thresholds", default="2,3,5,10,20,50",
                    help="Copub thresholds (>=N) shown as scatter panels (comma-sep). "
                         "'All pairs' is always added first.")
    ap.add_argument("--bins", default="0,1,2,3,5,10,20,50",
                    help="Right-edges for non-overlapping bin summary CSV. "
                         "Last bin is open-ended.")
    ap.add_argument("--sweep-max", type=int, default=50,
                    help="Trend curves sweep thresholds 1..sweep-max for the "
                         "per-method corr/slope plots.")
    args = ap.parse_args()

    tag_sfx = f"_{args.tag}" if args.tag and not args.tag.startswith("_") else args.tag
    k_sfx = f"_k{args.k}" if args.k is not None else ""
    pairs_csv = f"{OUT_DIR}/coauthor_validation_pairs{tag_sfx}_{args.version}{k_sfx}.csv"
    if not os.path.exists(pairs_csv):
        run_out_tag = f"{args.version}{k_sfx}" if args.k is not None else args.version
        run_k_arg = f" --k {args.k}" if args.k is not None else ""
        raise SystemExit(
            f"missing: {pairs_csv}\n"
            f"Run tfidf/validate_coauthors.py --tag {args.tag}{run_k_arg} "
            f"--exposure-dta ../../external/exposure_wts/athr_exposure_{args.version}.dta "
            f"--out-tag {run_out_tag} first."
        )
    os.makedirs(FIG_DIR, exist_ok=True)

    print(f"Loading {pairs_csv}")
    df = pd.read_csv(pairs_csv)
    print(f"  pairs loaded: {len(df):,}")
    for col in ("pred_knn", "e_foia_true", "partner_rank", "copubs"):
        if col not in df.columns:
            raise SystemExit(f"{pairs_csv} lacks required column {col!r}")
    print(f"  copub distribution:\n{df['copubs'].describe().round(2)}")

    scatter_ts = [int(t.strip()) for t in args.scatter_thresholds.split(",")]
    panels_specs = [("All pairs", df)] + [
        (f"copubs >= {t}", df[df["copubs"] >= t]) for t in scatter_ts
    ]
    panels_specs = [(t, d) for (t, d) in panels_specs if len(d) >= 30]

    # ---- figure layout: scatter grid + 3 diag panels ----
    n_scatter = len(panels_specs)
    n_diag = 3
    n_total = n_scatter + n_diag
    n_cols = 3
    n_rows = int(np.ceil(n_total / n_cols))
    fig, axes = plt.subplots(n_rows, n_cols, figsize=(15, 4.5 * n_rows))
    axes = axes.ravel()

    for ax, (title, sub) in zip(axes, panels_specs):
        panel_knn(ax, sub, title)

    # ---- trend curves: sweep thresholds 1..sweep_max ----
    ts = list(range(1, args.sweep_max + 1))
    rows = []
    for t in ts:
        sub = df[df["copubs"] >= t]
        row = {"t": t, "n": len(sub)}
        if len(sub) < 30:
            row["corr_knn"] = np.nan
            row["slope_knn"] = np.nan
            row["median_rank"] = np.nan
            row["pct_top5"] = np.nan
        else:
            x = sub["e_foia_true"].values
            y = sub["pred_knn"].values
            row["corr_knn"]  = float(np.corrcoef(x, y)[0, 1])
            row["slope_knn"] = float(np.polyfit(x, y, 1)[0])
            row["median_rank"] = float(sub["partner_rank"].median())
            row["pct_top5"]    = float((sub["partner_rank"] < 5).mean())
        rows.append(row)
    trend = pd.DataFrame(rows)

    # trend panel 1: corr and slope vs threshold
    ax = axes[n_scatter]
    ax.plot(trend["t"], trend["corr_knn"],  "o-", color=KNN_COLOR, label="corr(true, pred_knn)")
    ax2 = ax.twinx()
    ax2.plot(trend["t"], trend["slope_knn"], "s--", color="C3", label="slope(true → pred_knn)")
    ax.axhline(0.0, color="k", ls=":", lw=0.6, alpha=0.4)
    ax2.axhline(1.0, color="k", ls=":", lw=0.6, alpha=0.4)
    ax.set_xlabel("Min copubs threshold")
    ax.set_ylabel("corr", color=KNN_COLOR)
    ax2.set_ylabel("slope", color="C3")
    ax.set_title("Trend: K-NN corr & slope vs copubs threshold")
    ax.grid(alpha=0.3)

    # trend panel 2: twin-test (partner rank / top-5, method-independent)
    ax = axes[n_scatter + 1]
    ax.plot(trend["t"], trend["pct_top5"] * 100, "o-", color="C2", label="% partner top-5")
    ax2 = ax.twinx()
    ax2.plot(trend["t"], trend["median_rank"], "s-", color="C1", label="median rank")
    ax.set_xlabel("Min copubs threshold")
    ax.set_ylabel("% partner is top-5 NN", color="C2")
    ax2.set_ylabel("median partner rank", color="C1")
    ax.set_title("Trend: twin-test metrics vs copubs threshold\n(pure TF-IDF geometry)")
    ax.grid(alpha=0.3)

    # trend panel 3: copubs histogram
    ax = axes[n_scatter + 2]
    hist_bins = np.arange(0, df["copubs"].max() + 2) - 0.5
    ax.hist(df["copubs"], bins=hist_bins, color=KNN_COLOR, edgecolor="white")
    ax.set_yscale("log")
    ax.set_xlabel("# copublications with FOIA partner")
    ax.set_ylabel("# pairs (log)")
    ax.set_title("Copublication distribution")
    ax.grid(alpha=0.3)
    for t in scatter_ts:
        ax.axvline(t, color="C3", ls=":", lw=0.7, alpha=0.5)

    for ax in axes[n_total:]:
        ax.set_visible(False)

    fig.suptitle(
        f"Imputed coauthor exposure vs FOIA exposure — K-NN  "
        f"(version={args.version}, tag={args.tag}"
        + (f", K={args.k}" if args.k is not None else "") + ")",
        fontsize=14, fontweight="bold",
    )
    fig.tight_layout()
    out_png = f"{FIG_DIR}/coauthor_validation_{args.version}{tag_sfx}{k_sfx}.png"
    fig.savefig(out_png, dpi=150)
    print(f"\nSaved {out_png}")

    # ---- non-overlapping bin summary CSV ----
    bin_edges = [float(x.strip()) for x in args.bins.split(",")] + [np.inf]
    df["copub_bin"] = pd.cut(df["copubs"], bins=bin_edges, right=True, include_lowest=True)

    def _row(g):
        out = {"n": len(g), "mean_copubs": g["copubs"].mean()}
        if len(g) > 1:
            out["corr_knn"]  = float(np.corrcoef(g["e_foia_true"], g["pred_knn"])[0, 1])
            out["slope_knn"] = float(np.polyfit(g["e_foia_true"], g["pred_knn"], 1)[0])
            out["mae_knn"]   = float((g["e_foia_true"] - g["pred_knn"]).abs().mean())
        else:
            out["corr_knn"] = out["slope_knn"] = out["mae_knn"] = np.nan
        out["median_rank"] = g["partner_rank"].median()
        out["pct_top5"]    = (g["partner_rank"] < 5).mean()
        return pd.Series(out)

    summary = df.groupby("copub_bin", observed=True).apply(_row).round(4)
    print("\nPer-bin summary (non-overlapping):")
    print(summary.to_string())
    out_csv = f"{OUT_DIR}/coauthor_validation_by_copubs_plot_{args.version}{tag_sfx}{k_sfx}.csv"
    summary.to_csv(out_csv)
    print(f"Saved {out_csv}")

    out_trend = f"{OUT_DIR}/coauthor_validation_trend_{args.version}{tag_sfx}{k_sfx}.csv"
    trend.to_csv(out_trend, index=False)
    print(f"Saved {out_trend}")


if __name__ == "__main__":
    main()
