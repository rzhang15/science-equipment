"""
Describe NMF buyer clusters: top categories, exposure mean per cluster,
within- vs between-cluster variance, and an F-test against the topic
clusters (to confirm we're separating on a different dimension).

Output: ../output/cluster_descriptions.txt
        ../output/cluster_exposure_stats.csv
        ../output/figs/cluster_sizes.png
        ../output/figs/exposure_by_cluster.png
"""
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from scipy import stats
import config as cfg


def main():
    cfg.FIG.mkdir(parents=True, exist_ok=True)

    W = np.load(cfg.OUT / "buyer_W.npy")          # (A, K) probabilities
    H = np.load(cfg.OUT / "buyer_H.npy")          # (K, C) loadings
    authors = pd.read_csv(cfg.OUT / "buyer_authors.csv", dtype={"athr_id": str})
    categories = [l.strip() for l in open(cfg.OUT / "category_names.txt")]
    assert H.shape[1] == len(categories), "category count mismatch"

    exp = pd.read_stata(cfg.EXPOSURE_DTA)
    exp["athr_id"] = exp["athr_id"].astype(str)
    df = authors.merge(exp[["athr_id", "exposure"]], on="athr_id", how="left")
    print(f"authors w/ exposure: {df['exposure'].notna().sum()} / {len(df)}")

    # ----- per-cluster exposure stats: weighted by mixture probability -----
    # exposure_k = sum_a W[a,k] * E[a] / sum_a W[a,k]    (NaN-safe)
    E = df["exposure"].values
    valid = ~np.isnan(E)
    Wv = W[valid]
    Ev = E[valid]

    cluster_mean = (Wv * Ev[:, None]).sum(axis=0) / Wv.sum(axis=0).clip(min=1e-9)
    # effective N per cluster = (sum w)^2 / sum w^2
    eff_n = (Wv.sum(axis=0) ** 2) / (Wv ** 2).sum(axis=0).clip(min=1e-9)

    # also a hard top-1 view for ANOVA
    top1 = W.argmax(axis=1)
    df["top1"] = top1

    print("\n--- per-cluster exposure (mixture-weighted) ---")
    summary = pd.DataFrame({
        "cluster": np.arange(cfg.K),
        "top1_n": pd.Series(top1).value_counts().reindex(range(cfg.K), fill_value=0).values,
        "weighted_n_eff": eff_n.round(1),
        "exposure_mean": cluster_mean.round(4),
    })
    print(summary.to_string(index=False))
    summary.to_csv(cfg.OUT / "cluster_exposure_stats.csv", index=False)

    # ----- ANOVA on top-1 cluster labels (sanity: do clusters differ in exposure?) -----
    groups = [df.loc[(df["top1"] == k) & valid, "exposure"].values
              for k in range(cfg.K)]
    groups = [g for g in groups if len(g) >= 2]
    if len(groups) >= 2:
        F, p = stats.f_oneway(*groups)
        print(f"\nOne-way ANOVA on top-1 clusters: F={F:.2f}, p={p:.3g}")
    else:
        F, p = float("nan"), float("nan")

    # Variance decomposition
    overall_var = np.var(Ev, ddof=0)
    within = np.array([np.var(g, ddof=0) * len(g) for g in groups]).sum() / len(Ev)
    between = overall_var - within
    print(f"  total var={overall_var:.6f}  within={within:.6f}  between={between:.6f}")
    print(f"  between/total = {between/overall_var:.1%}")

    # ----- top categories per cluster (by H loadings) -----
    # IDF-weight the loadings so commodity cats don't dominate every cluster's description.
    cat_freq = (W.T @ (W > 0.05).astype(float)) > 0  # rough: cat used in cluster?
    # simpler: IDF = log(K / (1 + # clusters where cat is top-15))
    is_top = np.zeros_like(H)
    for k in range(cfg.K):
        top_idx = np.argsort(H[k])[::-1][:15]
        is_top[k, top_idx] = 1
    df_cat = is_top.sum(axis=0)            # in how many cluster top-15 lists does cat appear?
    idf = np.log((cfg.K + 1) / (1 + df_cat))
    H_idf = H * idf[None, :]

    with open(cfg.OUT / "cluster_descriptions.txt", "w") as f:
        f.write(f"K={cfg.K}  authors={len(authors)}  cats={len(categories)}\n")
        f.write(f"ANOVA top-1 cluster -> exposure: F={F:.2f}, p={p:.3g}\n")
        f.write(f"between/total exposure var = {between/overall_var:.1%}\n\n")
        for k in range(cfg.K):
            top_idx = np.argsort(H_idf[k])[::-1][:10]
            top_raw = np.argsort(H[k])[::-1][:5]
            f.write(f"--- cluster {k}  "
                    f"top1_n={int(pd.Series(top1).value_counts().get(k, 0))}  "
                    f"eff_n={eff_n[k]:.1f}  "
                    f"exposure={cluster_mean[k]:+.4f} ---\n")
            f.write("  discriminating cats (IDF-weighted):\n")
            for j in top_idx:
                f.write(f"    {H_idf[k, j]:>6.3f}  {categories[j]}\n")
            f.write("  raw top cats (often commodity):\n")
            for j in top_raw:
                f.write(f"    {H[k, j]:>6.3f}  {categories[j]}\n")
            f.write("\n")
    print(f"\nWrote {cfg.OUT}/cluster_descriptions.txt")

    # ----- plots -----
    fig, ax = plt.subplots(figsize=(8, 4))
    sizes = pd.Series(top1).value_counts().sort_index().reindex(range(cfg.K), fill_value=0)
    ax.bar(sizes.index, sizes.values, color="steelblue")
    ax.set_xlabel("cluster"); ax.set_ylabel("# authors (top-1)")
    ax.set_title(f"Cluster sizes (top-1 assignment, N={len(authors)})")
    fig.tight_layout()
    fig.savefig(cfg.FIG / "cluster_sizes.png", dpi=120)
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(10, 5))
    box_data = [df.loc[df["top1"] == k, "exposure"].dropna().values for k in range(cfg.K)]
    ax.boxplot(box_data, positions=range(cfg.K))
    ax.axhline(0, color="grey", linestyle="--", alpha=0.4)
    ax.set_xlabel("cluster"); ax.set_ylabel("exposure")
    ax.set_title(f"Exposure by buyer cluster (ANOVA F={F:.2f}, p={p:.3g})")
    fig.tight_layout()
    fig.savefig(cfg.FIG / "exposure_by_cluster.png", dpi=120)
    plt.close(fig)
    print(f"Wrote figs to {cfg.FIG}/")


if __name__ == "__main__":
    main()
