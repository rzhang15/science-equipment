"""
Sanity-check the US k-static-clustering from ../us_cluster_fields against
the K-NN TF-IDF imputation.

Four questions:
  1. Who are the FOIA authors, in terms of the k=30 clusters? (Distribution +
     cluster top-terms.)
  2. Who are the non-FOIA (universe) authors, in the same clusters?
  3. Do the TF-IDF nearest-neighbor imputation weights respect the k=30
     clustering? For each universe author, the "own-cluster weight share"
     is the fraction of their W-weight that goes to FOIAs in their own
     k=30 cluster. If clustering and imputation see the same topical
     signal, this fraction should be far above chance (1/k).
  4. Aggregated to clusters, does mean imputed exposure across universe
     authors track mean true exposure across FOIA anchors? This is the
     paper-ready external validation: no holdout, one number.

Reads the US-only clustering (../us_cluster_fields/output/) so the clustering
universe and the tfidf pipeline universe are the same population — otherwise
US universe authors show up as "unmapped" simply because they weren't in the
worldwide cluster_fields corpus.

Usage:
  python cluster_sanity_check.py --tag restricted --version hc --k 30

Outputs:
  ../output/k{K}_cluster_sanity_{version}{tag}.csv
  ../output/k{K}_cluster_sanity_overall_{version}{tag}.txt
  ../output/figures/k{K}_cluster_sanity_{version}{tag}.png     bar plots + weight-share hist
  ../output/figures/k{K}_max_sim_cutoff_{version}{tag}.png     max_sim tier diagnostic
  ../output/figures/k{K}_cluster_field_scatter_{version}{tag}.png
                                                                mean_true vs mean_imputed (K-NN)
"""
import argparse
import os
import re

import numpy as np
import pandas as pd
import scipy.sparse
import matplotlib.pyplot as plt

CLUSTER_DIR = "../../us_cluster_fields/output"
OUT_DIR = "../output"
FIG_DIR = f"{OUT_DIR}/figures"
EXPOSURE_DIR = "../external/exposure_wts"


def load_cluster_descriptions(path):
    """Parse 'Cluster N (n=X,XXX): term1, term2, ...' lines into
    {cluster_id: (n_authors, top_terms)}."""
    descs = {}
    pat = re.compile(r"Cluster\s+(\d+)\s*\(n=([\d,]+)\)\s*:\s*(.+)")
    with open(path) as f:
        for line in f:
            m = pat.match(line.strip())
            if m:
                descs[int(m.group(1))] = (
                    int(m.group(2).replace(",", "")),
                    m.group(3).strip(),
                )
    return descs


def _tag(tag: str) -> str:
    if tag and not tag.startswith("_"):
        return "_" + tag
    return tag


def weighted_corr(x, y, w):
    """Pearson correlation weighted by w (>0)."""
    x = np.asarray(x, dtype=np.float64); y = np.asarray(y, dtype=np.float64)
    w = np.asarray(w, dtype=np.float64)
    m = np.isfinite(x) & np.isfinite(y) & np.isfinite(w) & (w > 0)
    x, y, w = x[m], y[m], w[m]
    if len(x) < 2:
        return float("nan")
    mx = np.average(x, weights=w); my = np.average(y, weights=w)
    cov = np.average((x - mx) * (y - my), weights=w)
    vx  = np.average((x - mx) ** 2, weights=w)
    vy  = np.average((y - my) ** 2, weights=w)
    return float(cov / np.sqrt(vx * vy)) if vx > 0 and vy > 0 else float("nan")


def _slope(x, y):
    x = np.asarray(x, dtype=np.float64); y = np.asarray(y, dtype=np.float64)
    m = np.isfinite(x) & np.isfinite(y)
    return float(np.polyfit(x[m], y[m], 1)[0]) if m.sum() >= 2 else float("nan")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--k", type=int, default=30,
                    help="Number of static clusters from ../us_cluster_fields. "
                         "Default 30 (project convention — every other script "
                         "in the repo uses k=30).")
    ap.add_argument("--tag", default="restricted",
                    help="TF-IDF tag. Default 'restricted' matches production.")
    ap.add_argument("--version", default="hc",
                    choices=["hc", "all", "treated_hc"],
                    help="Exposure denominator (default 'hc').")
    ap.add_argument("--min-foia-per-cluster", type=int, default=1,
                    help="For the cluster field scatter, restrict to clusters "
                         "with >=N FOIA anchors. 1 (default) = all non-empty. "
                         "2 -> '_cf2' subset, 5 -> '_cf5' (FOIA-rich only). "
                         "Matches the --min-foia-per-cluster used in "
                         "3_impute_exposure.py / 4_impute_shift_share.py. "
                         "Output PNG name is suffixed '_cfN' when N>=2.")
    args = ap.parse_args()

    tag = _tag(args.tag)

    cluster_csv   = f"{CLUSTER_DIR}/author_static_clusters_{args.k}.csv"
    cluster_desc  = f"{CLUSTER_DIR}/static_cluster_descriptions_{args.k}.txt"
    foia_ids_path      = f"{OUT_DIR}/foia_ids_ordered{tag}.csv"
    universe_ids_path  = f"{OUT_DIR}/universe_ids{tag}.parquet"
    weight_matrix_path = f"{OUT_DIR}/weight_matrix{tag}.npz"
    diag_path          = f"{OUT_DIR}/match_diagnostics{tag}.parquet"
    exposure_dta       = f"{EXPOSURE_DIR}/athr_exposure_{args.version}.dta"

    filt_sfx = "" if args.min_foia_per_cluster <= 1 else f"_cf{args.min_foia_per_cluster}"
    stem = f"k{args.k}_cluster_sanity_{args.version}{tag}{filt_sfx}"
    out_csv     = f"{OUT_DIR}/{stem}.csv"
    out_fig     = f"{FIG_DIR}/{stem}.png"
    out_scatter = f"{FIG_DIR}/k{args.k}_cluster_field_scatter_{args.version}{tag}{filt_sfx}.png"
    out_msim    = f"{FIG_DIR}/k{args.k}_max_sim_cutoff_{args.version}{tag}{filt_sfx}.png"
    out_overall = f"{OUT_DIR}/k{args.k}_cluster_sanity_overall_{args.version}{tag}{filt_sfx}.txt"

    for p in (cluster_csv, cluster_desc, foia_ids_path, universe_ids_path,
              weight_matrix_path, diag_path, exposure_dta):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")

    os.makedirs(FIG_DIR, exist_ok=True)

    # ---- load cluster assignments + labels ----
    print(f"Loading k={args.k} cluster assignments...")
    df_clusters = pd.read_csv(cluster_csv,
                              dtype={"athr_id": str, "cluster_label": int})
    print(f"  {len(df_clusters):,} authors with clusters"
          f"   K={df_clusters['cluster_label'].nunique()}")

    print("Loading cluster top-terms...")
    descs = load_cluster_descriptions(cluster_desc)

    # ---- load pipeline IDs + weights + diagnostics ----
    print("Loading FOIA + universe IDs...")
    foia_ids = pd.read_csv(foia_ids_path, dtype={"athr_id": str})
    universe_ids = pd.read_parquet(universe_ids_path)
    universe_ids["athr_id"] = universe_ids["athr_id"].astype(str)
    print(f"  FOIAs: {len(foia_ids)}   universe: {len(universe_ids):,}")

    print("Loading weight matrix...")
    W = scipy.sparse.load_npz(weight_matrix_path).tocsr().astype(np.float32)
    print(f"  W shape: {W.shape}   nnz: {W.nnz:,}")
    if W.shape[0] != len(universe_ids) or W.shape[1] != len(foia_ids):
        raise SystemExit(
            f"shape mismatch: W={W.shape} vs universe={len(universe_ids)} "
            f"foia={len(foia_ids)}"
        )

    print("Loading diagnostics + FOIA exposure...")
    diag = pd.read_parquet(diag_path)[["athr_id", "max_sim"]]
    diag["athr_id"] = diag["athr_id"].astype(str)
    df_exp = pd.read_stata(exposure_dta)[["athr_id", "exposure"]]
    df_exp["athr_id"] = df_exp["athr_id"].astype(str)

    # ---- attach clusters ----
    df_foia = foia_ids.merge(df_clusters, on="athr_id", how="left")
    df_univ = universe_ids.merge(df_clusters, on="athr_id", how="left")

    n_foia_nc = int(df_foia["cluster_label"].isna().sum())
    n_univ_nc = int(df_univ["cluster_label"].isna().sum())
    print(f"  FOIAs without a k={args.k} cluster:  {n_foia_nc} / {len(df_foia)}")
    print(f"  Universe without a k={args.k} cluster: {n_univ_nc:,} / {len(df_univ):,}"
          f"   ({100*n_univ_nc/len(df_univ):.2f}%)")

    df_foia = df_foia.merge(df_exp, on="athr_id", how="left")
    df_foia["exposure"] = df_foia["exposure"].fillna(0)
    df_univ = df_univ.merge(diag, on="athr_id", how="left")

    # ---- per-universe-author own-cluster W share (K-NN only) ----
    print("Computing own-cluster W share for each universe author (K-NN)...")
    foia_c = df_foia["cluster_label"].to_numpy()
    univ_c = df_univ["cluster_label"].to_numpy()

    cluster_ids = sorted(int(c) for c in np.unique(foia_c[~pd.isna(foia_c)]))
    cluster_to_foia_idx = {c: np.where(foia_c == c)[0] for c in cluster_ids}

    W_row_sum = np.asarray(W.sum(axis=1)).ravel()
    W_own_sum = np.zeros(len(df_univ), dtype=np.float32)
    for c, foia_idx in cluster_to_foia_idx.items():
        univ_rows = np.where(univ_c == c)[0]
        if len(univ_rows) == 0 or len(foia_idx) == 0:
            continue
        sub = W[univ_rows][:, foia_idx]
        W_own_sum[univ_rows] = np.asarray(sub.sum(axis=1)).ravel()
    with np.errstate(divide="ignore", invalid="ignore"):
        own_share = np.where(W_row_sum > 0, W_own_sum / W_row_sum, np.nan)
    df_univ["own_cluster_weight_share"] = own_share

    # ---- imputed exposure per universe author ----
    # K-NN: from the fitted W matrix (production recipe, weighted-average form).
    print("Computing K-NN imputed exposure via W.dot(E_foia)...")
    E_foia = df_foia["exposure"].to_numpy(dtype=np.float32)
    df_univ["knn_imputed_exposure"] = W.dot(E_foia)

    # ---- per-cluster summary ----
    print("\nPer-cluster summary:")
    all_c = sorted(set(cluster_ids) |
                   set(int(c) for c in df_univ["cluster_label"].dropna().unique()))
    rows = []
    for c in all_c:
        f_mask = df_foia["cluster_label"] == c
        u_mask = df_univ["cluster_label"] == c
        n_foia = int(f_mask.sum())
        n_univ = int(u_mask.sum())
        rows.append({
            "cluster": c,
            "top_terms": descs.get(c, (0, ""))[1],
            "n_foia": n_foia,
            "n_universe": n_univ,
            "mean_foia_exposure":              df_foia.loc[f_mask, "exposure"].mean()                if n_foia else np.nan,
            "mean_max_sim_univ":               df_univ.loc[u_mask, "max_sim"].mean()                 if n_univ else np.nan,
            "mean_knn_imputed_univ":           df_univ.loc[u_mask, "knn_imputed_exposure"].mean()    if n_univ else np.nan,
            "mean_own_cluster_wt_share":       df_univ.loc[u_mask, "own_cluster_weight_share"].mean()    if n_univ else np.nan,
            "median_own_cluster_wt_share":     df_univ.loc[u_mask, "own_cluster_weight_share"].median()  if n_univ else np.nan,
        })
    df_summary = pd.DataFrame(rows).sort_values("n_foia", ascending=False)
    df_summary.to_csv(out_csv, index=False)
    print(df_summary.to_string(index=False))
    print(f"\nSaved per-cluster summary: {out_csv}")

    # ---- cross-cluster correlation: mean_true_foia vs mean_imputed_universe ----
    # Use clusters with n_foia >= min_foia_per_cluster to match the '_cfN' filter
    # applied downstream in 3_impute_exposure.py / analysis.do.
    min_n = max(1, args.min_foia_per_cluster)
    d = df_summary[df_summary["n_foia"] >= min_n].copy()
    n_ok = len(d)
    corr_knn_unw = float(d[["mean_foia_exposure", "mean_knn_imputed_univ"]].corr().iloc[0, 1]) if n_ok >= 2 else np.nan
    corr_knn_w   = weighted_corr(d["mean_foia_exposure"], d["mean_knn_imputed_univ"], d["n_universe"])
    slope_knn    = _slope(d["mean_foia_exposure"], d["mean_knn_imputed_univ"])

    # ---- headline figure: bar plots + weight-share histogram (K-NN specific) ----
    d_by_id = df_summary.sort_values("cluster")
    fig, axes = plt.subplots(2, 2, figsize=(16, 12))

    ax = axes[0, 0]
    ax.bar(d_by_id["cluster"].astype(int), d_by_id["n_foia"], color="C0")
    ax.set_xlabel("Cluster ID")
    ax.set_ylabel("# FOIA authors")
    ax.set_title(f"FOIA authors by k={args.k} cluster")
    ax.grid(alpha=0.3)

    ax = axes[0, 1]
    ax.bar(d_by_id["cluster"].astype(int), d_by_id["n_universe"], color="C1")
    ax.set_yscale("log")
    ax.set_xlabel("Cluster ID")
    ax.set_ylabel("# Universe authors (log)")
    ax.set_title(f"Universe (non-FOIA) authors by k={args.k} cluster")
    ax.grid(alpha=0.3)

    ax = axes[1, 0]
    ax.bar(d_by_id["cluster"].astype(int), d_by_id["mean_own_cluster_wt_share"], color="C2")
    ax.axhline(1.0 / args.k, color="k", ls="--", lw=1, alpha=0.6,
               label=f"chance (1/k = {1/args.k:.3f})")
    ax.set_xlabel("Cluster ID")
    ax.set_ylabel("Mean own-cluster W share (K-NN)")
    ax.set_title("Fraction of imputation weight from own-cluster FOIAs (K-NN only)")
    ax.legend()
    ax.grid(alpha=0.3)

    ax = axes[1, 1]
    vals = df_univ["own_cluster_weight_share"].dropna().to_numpy()
    ax.hist(vals, bins=50, color="C3", edgecolor="white")
    ax.axvline(1.0 / args.k, color="k", ls="--", lw=1,
               label=f"chance (1/k = {1/args.k:.3f})")
    ax.axvline(vals.mean(), color="C0", ls="-", lw=2,
               label=f"mean = {vals.mean():.3f}")
    ax.set_xlabel("Own-cluster W share (universe author, K-NN)")
    ax.set_ylabel("# universe authors")
    ax.set_title("Distribution of own-cluster imputation weight share (K-NN)")
    ax.legend()
    ax.grid(alpha=0.3)

    fig.suptitle(
        f"k={args.k} clustering sanity check   version={args.version}",
        fontsize=14, fontweight="bold",
    )
    fig.tight_layout()
    fig.savefig(out_fig, dpi=150)
    print(f"Saved figure: {out_fig}")

    # ---- cluster field scatter (K-NN, paper-ready external validation) ----
    fig3, ax = plt.subplots(figsize=(8, 7))
    x = d["mean_foia_exposure"].to_numpy()
    y = d["mean_knn_imputed_univ"].to_numpy()
    lo = min(np.nanmin(x), np.nanmin(y))
    hi = max(np.nanmax(x), np.nanmax(y))
    pad = 0.05 * (hi - lo) if hi > lo else 0.01
    lo, hi = lo - pad, hi + pad

    sizes = 20 + 60 * (d["n_universe"] / d["n_universe"].max())
    ax.scatter(x, y, s=sizes, alpha=0.75, edgecolor="k", linewidth=0.5)
    for _, row in d.iterrows():
        ax.annotate(str(int(row["cluster"])),
                    (row["mean_foia_exposure"], row["mean_knn_imputed_univ"]),
                    fontsize=7, alpha=0.7,
                    xytext=(3, 3), textcoords="offset points")
    ax.plot([lo, hi], [lo, hi], "k--", lw=1, alpha=0.5, label="45 deg")
    m = np.isfinite(x) & np.isfinite(y)
    coef = np.polyfit(x[m], y[m], 1)
    xf = np.array([lo, hi])
    ax.plot(xf, coef[0] * xf + coef[1], "-", color="C1", lw=1.5,
            label=f"fit: y = {coef[0]:.2f} x + {coef[1]:.3f}")
    ax.set_xlim(lo, hi); ax.set_ylim(lo, hi)
    ax.set_xlabel("mean FOIA-anchor exposure in cluster")
    ax.set_ylabel("mean K-NN-imputed exposure (universe)")
    ax.set_title(f"K-NN cluster field validation   "
                 f"r={corr_knn_unw:+.3f}  (weighted r={corr_knn_w:+.3f}, slope={slope_knn:+.2f})")
    ax.legend(fontsize=9, loc="upper left")
    ax.grid(alpha=0.3)

    fig3.suptitle(
        f"Cluster field validation (k={args.k})  version={args.version}  "
        f"min_foia/cluster={min_n}  n_clusters (kept) = {n_ok}",
        fontsize=13, fontweight="bold",
    )
    fig3.tight_layout()
    fig3.savefig(out_scatter, dpi=150)
    print(f"Saved figure: {out_scatter}")

    # ---- overall headline ----
    chance = 1.0 / args.k
    mapped_mask = ~np.isnan(own_share)
    mapped_share = own_share[mapped_mask]
    mean_share_mapped   = float(mapped_share.mean())    if len(mapped_share) else float("nan")
    median_share_mapped = float(np.median(mapped_share)) if len(mapped_share) else float("nan")
    frac_above_chance_mapped = float((mapped_share > chance).mean()) if len(mapped_share) else float("nan")

    n_foia_in_c = int(df_foia["cluster_label"].notna().sum())
    n_univ_in_c = int(mapped_mask.sum())

    strong_clusters = set(df_summary.loc[df_summary["n_foia"] >= 5, "cluster"].tolist())
    weak_clusters   = set(df_summary.loc[(df_summary["n_foia"] >= 1) & (df_summary["n_foia"] < 5), "cluster"].tolist())
    empty_clusters  = set(df_summary.loc[df_summary["n_foia"] == 0, "cluster"].tolist())

    strong_mask = df_univ["cluster_label"].isin(strong_clusters).to_numpy() & mapped_mask
    weak_mask   = df_univ["cluster_label"].isin(weak_clusters).to_numpy()   & mapped_mask
    empty_mask  = df_univ["cluster_label"].isin(empty_clusters).to_numpy()  & mapped_mask

    # ---- max_sim cutoff diagnostic ----
    print("\nBuilding max_sim cutoff diagnostic...")
    mx = df_univ["max_sim"].to_numpy()
    mx_valid = ~np.isnan(mx)
    strong_mem = df_univ["cluster_label"].isin(strong_clusters).to_numpy() & mx_valid
    weak_mem   = df_univ["cluster_label"].isin(weak_clusters).to_numpy()   & mx_valid
    empty_mem  = df_univ["cluster_label"].isin(empty_clusters).to_numpy()  & mx_valid
    mx_strong, mx_weak, mx_empty = mx[strong_mem], mx[weak_mem], mx[empty_mem]

    cutoffs = ({p: float(np.percentile(mx_empty, p)) for p in (50, 75, 90, 95)}
               if len(mx_empty) else {})

    fig2, axes2 = plt.subplots(1, 2, figsize=(14, 5))

    ax = axes2[0]
    ax.hist(mx[mx_valid], bins=60, color="C4", edgecolor="white")
    for p, cut in cutoffs.items():
        ax.axvline(cut, ls="--", lw=1, label=f"p{p} empty = {cut:.3f}")
    ax.set_xlabel("max_sim (best FOIA cosine per universe author)")
    ax.set_ylabel("# universe authors")
    ax.set_title("Universe max_sim distribution")
    if cutoffs:
        ax.legend()
    ax.grid(alpha=0.3)

    ax = axes2[1]
    xmax = float(np.nanmax(mx)) if mx_valid.any() else 0.5
    bins = np.linspace(0, xmax, 60)
    for arr, name, col in [(mx_strong, "FOIA-rich", "C2"),
                           (mx_weak,   "thin",      "C1"),
                           (mx_empty,  "empty",     "C3")]:
        if len(arr):
            ax.hist(arr, bins=bins, alpha=0.5, density=True,
                    label=f"{name} (n={len(arr):,})", color=col)
    for cut in cutoffs.values():
        ax.axvline(cut, color="k", ls="--", lw=1, alpha=0.4)
    ax.set_xlabel("max_sim")
    ax.set_ylabel("density")
    ax.set_title("max_sim by cluster tier (empty = noise floor)")
    ax.legend()
    ax.grid(alpha=0.3)

    fig2.suptitle(f"k={args.k}: max_sim cutoff diagnostic  version={args.version}",
                  fontsize=14, fontweight="bold")
    fig2.tight_layout()
    fig2.savefig(out_msim, dpi=150)
    print(f"Saved figure: {out_msim}")

    n_valid = int(mx_valid.sum())
    cutoff_lines = [
        "",
        "  --- max_sim cutoff candidates ---",
        "  (Empty-cluster max_sim is a noise floor; cutoffs above its upper",
        "   tail drop authors most likely to be spurious matches.)",
    ]
    for p, cut in cutoffs.items():
        n_keep = int(((mx >= cut) & mx_valid).sum())
        cutoff_lines.append(
            f"    p{p} of empty-cluster max_sim = {cut:.3f}   "
            f"keeps {n_keep:,} / {n_valid:,} "
            f"({100*n_keep/n_valid:.1f}%) of mapped universe"
        )

    def _block(name, mask):
        if not mask.any():
            return f"    {name}: n=0 universe authors"
        vals = own_share[mask]
        return (f"    {name}: n={int(mask.sum()):,}   "
                f"mean={vals.mean():.3f}   median={np.median(vals):.3f}   "
                f"pct_above_chance={100 * (vals > chance).mean():.1f}%")

    lines = [
        f"k={args.k} clustering sanity check  version={args.version}  tag={args.tag}",
        f"  Clusters: {len(strong_clusters)} FOIA-rich (>=5)   "
        f"{len(weak_clusters)} thin (1-4)   {len(empty_clusters)} empty (0 FOIAs)",
        "",
        f"  FOIAs mapped to a k={args.k} cluster:   {n_foia_in_c} / {len(df_foia)}",
        f"  Universe mapped to a k={args.k} cluster: {n_univ_in_c:,} / {len(df_univ):,} "
        f"({100*n_univ_in_c/len(df_univ):.2f}%)",
        "",
        f"  --- Own-cluster W share (K-NN only, chance = 1/k = {chance:.3f}) ---",
        f"    all mapped universe authors: "
        f"mean={mean_share_mapped:.3f}   median={median_share_mapped:.3f}   "
        f"pct_above_chance={100*frac_above_chance_mapped:.1f}%",
        _block("in FOIA-rich clusters   ", strong_mask),
        _block("in thin (1-4 FOIA) clusters", weak_mask),
        _block("in empty (0 FOIA) clusters  ", empty_mask),
        "",
        f"  --- Cross-cluster corr(mean_true_foia, mean_KNN_imputed_universe) ---",
        f"  (n_clusters used = {n_ok} / {df_clusters['cluster_label'].nunique()} — those with FOIA anchors)",
        f"    K-NN   unweighted r={corr_knn_unw:+.4f}   weighted (by n_univ) r={corr_knn_w:+.4f}   slope={slope_knn:+.3f}",
        "",
        "  Interpretation: FOIA-rich clusters carry the signal. The cross-cluster r",
        "  is the paper-ready external validation — no holdout, one number.",
        "  slope near 1 means level (not just ranking) is preserved.",
        *cutoff_lines,
    ]
    with open(out_overall, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n" + "\n".join(lines))
    print(f"\nSaved: {out_overall}")


if __name__ == "__main__":
    main()
