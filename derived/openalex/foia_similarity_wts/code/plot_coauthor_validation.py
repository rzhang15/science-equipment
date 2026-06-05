"""
Plot the FOIA-author vs imputed-coauthor exposure relationship from
coauthor_validation_pairs_{method}.csv. Adds a copublication count per
(FOIA, coauthor) pair on the fly (computed from author_paper_edges.parquet,
since get_coauthors/build.do drops _freq).

Default figure: 2x2 grid of binned scatters at increasing copub thresholds,
plus a copub-count histogram. Binned scatter is used because 30k+ raw
points obscure E[y|x]; the binned means make any 45-degree alignment
obvious.

Run:
  python plot_coauthor_validation.py --method tfidf
  python plot_coauthor_validation.py --method bert
"""
import argparse
import os
import numpy as np
import pandas as pd
import polars as pl
import matplotlib.pyplot as plt

EDGES = "/n/home02/cxu75/sci_eq/derived/openalex/cluster_fields/output/bert/author_paper_edges.parquet"
OUT_DIR = "../output"
FIG_DIR = f"{OUT_DIR}/figures"


def compute_copubs(pairs: pd.DataFrame) -> pd.Series:
    """For each (FOIA athr_id, coauthor_id) pair, return # of papers they
    BOTH authored. Counted against author_paper_edges.parquet (<=2013 cut)."""
    foia_ids = pairs["athr_id"].unique().tolist()
    co_ids   = pairs["coauthor_id"].unique().tolist()

    print(f"  counting copubs ({len(foia_ids)} FOIA x {len(co_ids):,} coauthors)...")
    foia_edges = (
        pl.scan_parquet(EDGES)
        .filter(pl.col("athr_id").is_in(foia_ids))
        .select(["athr_id", "id"])
        .rename({"athr_id": "foia_athr_id"})
    )
    co_edges = (
        pl.scan_parquet(EDGES)
        .filter(pl.col("athr_id").is_in(co_ids))
        .select(["athr_id", "id"])
        .rename({"athr_id": "coauthor_id"})
    )
    counts = (
        foia_edges.join(co_edges, on="id", how="inner")
        .group_by(["foia_athr_id", "coauthor_id"])
        .agg(pl.len().alias("copubs"))
        .collect(streaming=True)
        .to_pandas()
        .rename(columns={"foia_athr_id": "athr_id"})
    )
    return pairs.merge(counts, on=["athr_id", "coauthor_id"], how="left")["copubs"].fillna(0).astype(int)


def binned_scatter(ax, x, y, n_bins=20, label=None):
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
    ax.errorbar(xb, yb, yerr=ye, fmt="o", ms=4, lw=1, capsize=2, color="C0", label=label)


def panel(ax, df, title):
    x = df["e_foia_true"].values
    y = df["e_co_imputed"].values
    binned_scatter(ax, x, y)
    lo = min(x.min(), y.min())
    hi = max(x.max(), y.max())
    ax.plot([lo, hi], [lo, hi], "k--", lw=1, alpha=0.6, label="45 deg")
    corr = np.corrcoef(x, y)[0, 1]
    # OLS slope of y on x (just for the title; not plotted)
    slope = np.polyfit(x, y, 1)[0]
    ax.set_xlabel("FOIA true exposure")
    ax.set_ylabel("Imputed coauthor exposure")
    ax.set_title(f"{title}\nn={len(df):,}   corr={corr:.3f}   slope={slope:.2f}")
    ax.legend(fontsize=8, loc="best")
    ax.grid(alpha=0.3)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--method", choices=["bert", "tfidf"], default="tfidf")
    ap.add_argument("--scatter-thresholds", default="2,3,5,10,20,50",
                    help="Copub thresholds (>=N) shown as scatter panels (comma-sep). "
                         "'All pairs' is always added first.")
    ap.add_argument("--bins", default="0,1,2,3,5,10,20,50",
                    help="Right-edges for non-overlapping bin summary CSV. "
                         "Last bin is open-ended.")
    ap.add_argument("--sweep-max", type=int, default=50,
                    help="Trend curves sweep thresholds 1..sweep-max for the corr/slope plots.")
    args = ap.parse_args()

    suffix = "_tfidf" if args.method == "tfidf" else ""
    pairs_csv = f"{OUT_DIR}/coauthor_validation_pairs{suffix}.csv"
    if not os.path.exists(pairs_csv):
        raise SystemExit(f"missing: {pairs_csv}")
    os.makedirs(FIG_DIR, exist_ok=True)

    print(f"Loading {pairs_csv}")
    df = pd.read_csv(pairs_csv)
    print(f"  pairs loaded: {len(df):,}")
    df["copubs"] = compute_copubs(df)
    print(f"  copub distribution:\n{df['copubs'].describe().round(2)}")

    scatter_ts = [int(t.strip()) for t in args.scatter_thresholds.split(",")]
    panels_specs = [("All pairs", df)] + [
        (f"copubs >= {t}", df[df["copubs"] >= t]) for t in scatter_ts
    ]
    # Drop scatter panels with too few points (<30) to keep them readable.
    panels_specs = [(t, d) for (t, d) in panels_specs if len(d) >= 30]

    # ---- figure layout: scatter grid + 3 diag panels (trend, rank, hist) ----
    n_scatter = len(panels_specs)
    n_diag = 3
    n_total = n_scatter + n_diag
    n_cols = 3
    n_rows = int(np.ceil(n_total / n_cols))
    fig, axes = plt.subplots(n_rows, n_cols, figsize=(15, 4.5 * n_rows))
    axes = axes.ravel()

    for ax, (title, sub) in zip(axes, panels_specs):
        panel(ax, sub, title)

    # ---- trend curves: sweep thresholds 1..sweep_max ----
    ts = list(range(1, args.sweep_max + 1))
    rows = []
    for t in ts:
        sub = df[df["copubs"] >= t]
        if len(sub) < 30:
            rows.append({"t": t, "n": len(sub),
                         "corr": np.nan, "slope": np.nan,
                         "median_rank": np.nan, "pct_top5": np.nan})
            continue
        x, y = sub["e_foia_true"].values, sub["e_co_imputed"].values
        rows.append({
            "t": t, "n": len(sub),
            "corr": np.corrcoef(x, y)[0, 1],
            "slope": np.polyfit(x, y, 1)[0],
            "median_rank": sub["partner_rank"].median(),
            "pct_top5": (sub["partner_rank"] < 5).mean(),
        })
    trend = pd.DataFrame(rows)

    ax = axes[n_scatter]
    ax.plot(trend["t"], trend["corr"], "o-", color="C0", label="corr")
    ax.plot(trend["t"], trend["slope"], "s-", color="C3", label="slope")
    ax.axhline(1.0, color="k", ls="--", lw=0.7, alpha=0.5)
    ax.set_xlabel("Min copubs threshold")
    ax.set_ylabel("corr / slope")
    ax.set_title("Trend: corr & slope vs copubs threshold")
    ax.legend(fontsize=9)
    ax.grid(alpha=0.3)

    ax = axes[n_scatter + 1]
    ax.plot(trend["t"], trend["pct_top5"] * 100, "o-", color="C2", label="% partner top-5")
    ax2 = ax.twinx()
    ax2.plot(trend["t"], trend["median_rank"], "s-", color="C1", label="median rank")
    ax.set_xlabel("Min copubs threshold")
    ax.set_ylabel("% partner is top-5 NN", color="C2")
    ax2.set_ylabel("median partner rank", color="C1")
    ax.set_title("Trend: twin-test metrics vs copubs threshold")
    ax.grid(alpha=0.3)

    ax = axes[n_scatter + 2]
    hist_bins = np.arange(0, df["copubs"].max() + 2) - 0.5
    ax.hist(df["copubs"], bins=hist_bins, color="C0", edgecolor="white")
    ax.set_yscale("log")
    ax.set_xlabel("# copublications with FOIA partner")
    ax.set_ylabel("# pairs (log)")
    ax.set_title("Copublication distribution")
    ax.grid(alpha=0.3)
    for t in scatter_ts:
        ax.axvline(t, color="C3", ls=":", lw=0.7, alpha=0.5)

    # hide any extra axes
    for ax in axes[n_total:]:
        ax.set_visible(False)

    fig.suptitle(f"Imputed coauthor exposure vs FOIA exposure  ({args.method.upper()})",
                 fontsize=14, fontweight="bold")
    fig.tight_layout()
    out_png = f"{FIG_DIR}/coauthor_validation_{args.method}.png"
    fig.savefig(out_png, dpi=150)
    print(f"\nSaved {out_png}")

    # ---- non-overlapping bin summary CSV ----
    bin_edges = [float(x.strip()) for x in args.bins.split(",")] + [np.inf]
    df["copub_bin"] = pd.cut(df["copubs"], bins=bin_edges, right=True, include_lowest=True)
    summary = df.groupby("copub_bin", observed=True).apply(lambda g: pd.Series({
        "n": len(g),
        "mean_copubs": g["copubs"].mean(),
        "corr": np.corrcoef(g["e_foia_true"], g["e_co_imputed"])[0, 1] if len(g) > 1 else np.nan,
        "slope": np.polyfit(g["e_foia_true"], g["e_co_imputed"], 1)[0] if len(g) > 1 else np.nan,
        "mae": g["abs_err"].mean(),
        "median_rank": g["partner_rank"].median(),
        "pct_top5": (g["partner_rank"] < 5).mean(),
    })).round(4)
    print("\nPer-bin summary (non-overlapping):")
    print(summary.to_string())
    out_csv = f"{OUT_DIR}/coauthor_validation_by_copubs_{args.method}.csv"
    summary.to_csv(out_csv)
    print(f"Saved {out_csv}")

    # cumulative-threshold trend CSV (matches the curves on the figure)
    out_trend = f"{OUT_DIR}/coauthor_validation_trend_{args.method}.csv"
    trend.to_csv(out_trend, index=False)
    print(f"Saved {out_trend}")


if __name__ == "__main__":
    main()
