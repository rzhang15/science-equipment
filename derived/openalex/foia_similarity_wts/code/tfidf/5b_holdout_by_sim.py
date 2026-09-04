import argparse
import os
import numpy as np
import pandas as pd
import scipy.sparse
import matplotlib.pyplot as plt

OUT_DIR = "../../output"
FIG_DIR = f"{OUT_DIR}/figures"
EXPOSURE_DIR = "../../external/exposure_wts"


def knn_predict_from_sim(sim, e_train, k, sharpen, floor):
    n_test, n_train = sim.shape
    k = min(k, n_train)
    topk_idx = np.argpartition(-sim, k - 1, axis=1)[:, :k]
    rows = np.arange(n_test)[:, None]
    raw = sim[rows, topk_idx].copy()
    vals = np.where(raw >= floor, raw, 0.0)
    if sharpen != 1.0:
        vals = np.where(vals > 0, np.power(vals, sharpen), 0.0)
    row_sums = vals.sum(axis=1, keepdims=True)
    row_sums = np.where(row_sums > 0, row_sums, 1.0)
    w = vals / row_sums
    return (
        (w * e_train[topk_idx]).sum(axis=1),
        sim.max(axis=1),
        raw.mean(axis=1),
    )


def corr_ci(y, p):
    n = len(y)
    if n < 4 or np.std(y) == 0 or np.std(p) == 0:
        return np.nan, np.nan, np.nan
    r = float(np.corrcoef(y, p)[0, 1])
    if abs(r) >= 1.0:
        return r, np.nan, np.nan
    z = 0.5 * np.log((1 + r) / (1 - r))
    se = 1.0 / np.sqrt(n - 3)
    return r, float(np.tanh(z - 1.96 * se)), float(np.tanh(z + 1.96 * se))


def weighted_metrics(y, p, w):
    m = np.isfinite(y) & np.isfinite(p) & np.isfinite(w) & (w > 0)
    y, p, w = y[m], p[m], w[m]
    if len(y) < 2:
        return {"n": len(y), "corr": np.nan, "mae": np.nan, "rmse": np.nan,
                "slope": np.nan}
    err = y - p
    my = np.average(y, weights=w)
    mp = np.average(p, weights=w)
    cov = np.average((y - my) * (p - mp), weights=w)
    vy = np.average((y - my) ** 2, weights=w)
    vp = np.average((p - mp) ** 2, weights=w)
    return {
        "n": int(len(y)),
        "corr": float(cov / np.sqrt(vy * vp)) if vy > 0 and vp > 0 else np.nan,
        "mae": float(np.average(np.abs(err), weights=w)),
        "rmse": float(np.sqrt(np.average(err ** 2, weights=w))),
        "slope": float(cov / vy) if vy > 0 else np.nan,
    }


def run_holdouts(X, e_foia, foia_ids, k, sharpen, floor, fracs, folds, seed):
    n = X.shape[0]
    sim_full = (X @ X.T).toarray().astype(np.float64)
    np.fill_diagonal(sim_full, -1.0)

    rows = []

    pred, max_sim, mean_topk = knn_predict_from_sim(
        sim_full, e_foia, k, sharpen, floor)
    for i in range(n):
        rows.append({
            "athr_id": foia_ids[i],
            "source": "loo",
            "n_train": n - 1,
            "max_sim_to_train": float(max_sim[i]),
            "mean_topk_sim": float(mean_topk[i]),
            "true": float(e_foia[i]),
            "pred": float(pred[i]),
        })

    rng = np.random.default_rng(seed)
    for frac in fracs:
        n_test = int(round(frac * n))
        for f in range(folds):
            perm = rng.permutation(n)
            test_idx = np.sort(perm[:n_test])
            train_idx = np.sort(perm[n_test:])
            sim = sim_full[np.ix_(test_idx, train_idx)]
            pred, max_sim, mean_topk = knn_predict_from_sim(
                sim, e_foia[train_idx], k, sharpen, floor)
            for j, i in enumerate(test_idx):
                rows.append({
                    "athr_id": foia_ids[i],
                    "source": f"frac{int(round(frac * 100))}",
                    "n_train": int(len(train_idx)),
                    "max_sim_to_train": float(max_sim[j]),
                    "mean_topk_sim": float(mean_topk[j]),
                    "true": float(e_foia[i]),
                    "pred": float(pred[j]),
                })

    return pd.DataFrame(rows)


def load_panel_sims(panel_csv, diag_parquet, foia_ids):
    panel = pd.read_csv(panel_csv, dtype={"athr_id": str})[["athr_id"]]
    diag = pd.read_parquet(diag_parquet, columns=["athr_id", "max_sim"])
    diag["athr_id"] = diag["athr_id"].astype(str)
    panel = panel[~panel["athr_id"].isin(set(foia_ids))]
    panel = panel.merge(diag, on="athr_id", how="left")
    n_miss = int(panel["max_sim"].isna().sum())
    if n_miss:
        print(f"  WARN: {n_miss:,} panel PIs missing from diagnostics; dropped.")
    return panel.dropna(subset=["max_sim"])["max_sim"].to_numpy(np.float64)


def bin_curve(df, n_bins):
    q = np.quantile(df["max_sim_to_train"], np.linspace(0, 1, n_bins + 1))
    q[-1] += 1e-12
    bins = np.digitize(df["max_sim_to_train"], q[1:-1])
    rows = []
    for b in range(n_bins):
        sub = df[bins == b]
        y = sub["true"].to_numpy()
        p = sub["pred"].to_numpy()
        r, lo, hi = corr_ci(y, p)
        err = y - p
        rows.append({
            "bin": b + 1,
            "sim_lo": float(q[b]),
            "sim_hi": float(q[b + 1]),
            "sim_mean": float(sub["max_sim_to_train"].mean()),
            "n": int(len(sub)),
            "corr": r, "corr_lo": lo, "corr_hi": hi,
            "mae": float(np.abs(err).mean()),
            "rmse": float(np.sqrt((err ** 2).mean())),
        })
    return pd.DataFrame(rows)


def panel_reweight(df, panel_sims, width):
    hi = max(df["max_sim_to_train"].max(), panel_sims.max()) + width
    edges = np.arange(0, hi + width, width)
    h_idx = np.digitize(df["max_sim_to_train"], edges) - 1
    p_idx = np.digitize(panel_sims, edges) - 1
    n_bins = len(edges) - 1
    h_mass = np.bincount(h_idx, minlength=n_bins) / len(df)
    p_mass = np.bincount(p_idx, minlength=n_bins) / len(panel_sims)
    covered = h_mass > 0
    coverage = float(p_mass[covered].sum())
    ratio = np.zeros(n_bins)
    ratio[covered] = p_mass[covered] / h_mass[covered]
    return ratio[h_idx], coverage


def make_figure(curve, df, panel_sims, out_png, k, version):
    fig, (axL, axR) = plt.subplots(1, 2, figsize=(12, 4.8))

    x = curve["sim_mean"].to_numpy()
    y = curve["corr"].to_numpy()
    err = np.vstack([y - curve["corr_lo"].to_numpy(),
                     curve["corr_hi"].to_numpy() - y])
    axL.errorbar(x, y, yerr=err, fmt="o-", ms=6, lw=1.8, capsize=3, color="C0")
    axL.axhline(0, color="k", lw=0.6, alpha=0.5)
    p25, p50, p75 = np.percentile(panel_sims, [25, 50, 75])
    axL.axvspan(p25, p75, color="C2", alpha=0.12, label="panel IQR")
    axL.axvline(p50, color="C2", ls="--", lw=1.2, label="panel median")
    axL.set_xlabel("Max cosine similarity to available anchors")
    axL.set_ylabel("Corr(true, predicted) in bin")
    axL.set_title("A. Held-out accuracy vs match similarity")
    axL.legend(fontsize=8)
    axL.grid(alpha=0.3)

    axR.plot(x, curve["mae"], "s-", ms=6, lw=1.8, color="C3", label="held-out MAE")
    axR.axvspan(p25, p75, color="C2", alpha=0.12)
    axR.axvline(p50, color="C2", ls="--", lw=1.2)
    axR.set_xlabel("Max cosine similarity to available anchors")
    axR.set_ylabel("MAE in bin", color="C3")
    ax2 = axR.twinx()
    ax2.hist(panel_sims, bins=40, density=True, color="C2", alpha=0.25,
             label="panel max_sim")
    ax2.hist(df["max_sim_to_train"], bins=40, density=True, histtype="step",
             color="C0", lw=1.4, label="held-out anchors")
    ax2.set_ylabel("Density")
    lines, labels = axR.get_legend_handles_labels()
    lines2, labels2 = ax2.get_legend_handles_labels()
    axR.legend(lines + lines2, labels + labels2, fontsize=8)
    axR.set_title("B. Error curve and similarity distributions")
    axR.grid(alpha=0.3)

    fig.suptitle(
        f"Held-out prediction error conditional on match similarity   "
        f"(K={k}, version={version})",
        fontsize=12, fontweight="bold",
    )
    fig.tight_layout()
    fig.savefig(out_png, dpi=150, bbox_inches="tight")
    print(f"Saved {out_png}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="",
                    help="TF-IDF artifact tag; empty = production.")
    ap.add_argument("--version", default="hc",
                    choices=["hc", "all", "treated_hc"])
    ap.add_argument("--k", type=int, default=3)
    ap.add_argument("--sharpen", type=float, default=2.0)
    ap.add_argument("--floor", type=float, default=0.05)
    ap.add_argument("--holdout-fracs", type=float, nargs="+",
                    default=[0.2, 0.5],
                    help="Subsample folds to populate the low-sim range.")
    ap.add_argument("--folds", type=int, default=20)
    ap.add_argument("--seed", type=int, default=8975)
    ap.add_argument("--n-bins", type=int, default=8,
                    help="Quantile bins for the error curve.")
    ap.add_argument("--reweight-width", type=float, default=0.02,
                    help="Fixed bin width for panel reweighting.")
    ap.add_argument("--panel-csv",
                    default=f"{OUT_DIR}/final_imputed_shift_share_hc_cf_k3.csv",
                    help="Imputed file defining the panel (analysis.do input).")
    ap.add_argument("--panel-dta", default="",
                    help="Prepped RF sample .dta (needs athr_id, max_sim, "
                         "foia_athr); overrides --panel-csv.")
    ap.add_argument("--out-tag", default="",
                    help="Suffix on output filenames, e.g. r1_r2.")
    ap.add_argument("--diag-parquet",
                    default=f"{OUT_DIR}/match_diagnostics_k3.parquet")
    args = ap.parse_args()

    tag = args.tag if not args.tag or args.tag.startswith("_") else "_" + args.tag
    foia_matrix = f"{OUT_DIR}/tfidf_foia{tag}.npz"
    foia_ids_csv = f"{OUT_DIR}/foia_ids_ordered{tag}.csv"
    exposure_dta = f"{EXPOSURE_DIR}/athr_exposure_{args.version}.dta"
    panel_src = args.panel_dta if args.panel_dta else args.panel_csv
    for p in (foia_matrix, foia_ids_csv, exposure_dta, panel_src,
              args.diag_parquet):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")
    os.makedirs(FIG_DIR, exist_ok=True)

    X = scipy.sparse.load_npz(foia_matrix).tocsr().astype(np.float64)
    foia_ids = pd.read_csv(foia_ids_csv, dtype={"athr_id": str})["athr_id"].tolist()
    df_exp = pd.read_stata(exposure_dta)[["athr_id", "exposure"]]
    df_exp["athr_id"] = df_exp["athr_id"].astype(str)
    e_foia = (pd.Series(df_exp.set_index("athr_id")["exposure"])
              .reindex(foia_ids).fillna(0).values.astype(np.float64))
    print(f"Anchors: {X.shape[0]}   recipe: K={args.k} sharpen={args.sharpen} "
          f"floor={args.floor}")

    df = run_holdouts(X, e_foia, foia_ids, args.k, args.sharpen, args.floor,
                      args.holdout_fracs, args.folds, args.seed)
    print(f"Held-out predictions: {len(df):,} "
          f"({df.groupby('source').size().to_dict()})")

    if args.panel_dta:
        d = pd.read_stata(args.panel_dta,
                          columns=["athr_id", "max_sim", "foia_athr"])
        d = (d[d["foia_athr"] != 1]
             .drop_duplicates("athr_id")
             .dropna(subset=["max_sim"]))
        panel_sims = d["max_sim"].to_numpy(np.float64)
    else:
        panel_sims = load_panel_sims(args.panel_csv, args.diag_parquet,
                                     foia_ids)
    p25, p50, p75 = np.percentile(panel_sims, [25, 50, 75])
    print(f"Panel: {len(panel_sims):,} PIs   max_sim median={p50:.3f} "
          f"IQR=[{p25:.3f}, {p75:.3f}]")
    print(f"Held-out max_sim: median={df['max_sim_to_train'].median():.3f} "
          f"range=[{df['max_sim_to_train'].min():.3f}, "
          f"{df['max_sim_to_train'].max():.3f}]")

    curve = bin_curve(df, args.n_bins)
    print("\n--- Error curve (quantile bins of held-out max_sim) ---")
    print(curve.to_string(index=False,
                          float_format=lambda v: f"{v:8.4f}"))

    y = df["true"].to_numpy()
    p = df["pred"].to_numpy()
    raw = weighted_metrics(y, p, np.ones(len(df)))
    w, coverage = panel_reweight(df, panel_sims, args.reweight_width)
    rew = weighted_metrics(y, p, w)

    iqr_mask = ((df["max_sim_to_train"] >= p25)
                & (df["max_sim_to_train"] <= p75)).to_numpy()
    iqr = weighted_metrics(y[iqr_mask], p[iqr_mask], np.ones(iqr_mask.sum()))

    out_tag = args.out_tag if not args.out_tag or args.out_tag.startswith("_") \
        else "_" + args.out_tag
    stem = f"{args.version}{tag}{out_tag}"
    df.to_csv(f"{OUT_DIR}/holdout_by_sim_pairs_{stem}.csv", index=False)
    curve.to_csv(f"{OUT_DIR}/holdout_by_sim_bins_{stem}.csv", index=False)

    lines = [
        f"Conditional-on-similarity holdout  K={args.k} sharpen={args.sharpen} "
        f"floor={args.floor}  version={args.version}  tag={args.tag!r}",
        f"  held-out predictions: {len(df):,} "
        f"(LOO + subsample fracs {args.holdout_fracs} x {args.folds} folds)",
        f"  panel: {os.path.basename(panel_src)}  n={len(panel_sims):,}  "
        f"max_sim median={p50:.3f}  IQR=[{p25:.3f}, {p75:.3f}]",
        "",
        f"  raw pooled (composition NOT panel-like):        "
        f"corr={raw['corr']:+.3f}  MAE={raw['mae']:.4f}  RMSE={raw['rmse']:.4f}",
        f"  reweighted to panel similarity distribution:    "
        f"corr={rew['corr']:+.3f}  MAE={rew['mae']:.4f}  RMSE={rew['rmse']:.4f}  "
        f"slope={rew['slope']:.3f}",
        f"  within panel IQR of similarity (n={iqr['n']:,}): "
        f"corr={iqr['corr']:+.3f}  MAE={iqr['mae']:.4f}  RMSE={iqr['rmse']:.4f}",
        f"  panel mass covered by holdout support: {coverage:.1%}",
    ]
    text = "\n".join(lines) + "\n"
    with open(f"{OUT_DIR}/holdout_by_sim_summary_{stem}.txt", "w") as f:
        f.write(text)
    print("\n" + text)

    make_figure(curve, df, panel_sims,
                f"{FIG_DIR}/holdout_by_sim_{stem}.png", args.k, args.version)

    print(f"Saved {OUT_DIR}/holdout_by_sim_pairs_{stem}.csv")
    print(f"Saved {OUT_DIR}/holdout_by_sim_bins_{stem}.csv")
    print(f"Saved {OUT_DIR}/holdout_by_sim_summary_{stem}.txt")


if __name__ == "__main__":
    main()
