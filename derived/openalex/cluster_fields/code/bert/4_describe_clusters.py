"""
Descriptives for the per-paper BERT clustering.

Usage:
  python 4_describe_clusters.py --clusters 50

Reads:
  ../../output/bert/paper_clusters_K{K}.parquet
  ../../output/bert/author_field_dist_K{K}.parquet
  ../../output/bert/paper_embeddings.npy
  ../../output/bert/cluster_centroids_K{K}.npy
  ../../output/bert/papers_aligned.parquet

Writes:
  ../../output/bert/cluster_descriptives_K{K}.txt   (one-screen summary)
  ../../output/bert/cluster_descriptives_K{K}.png   (size + entropy + modal-share histograms)
"""
import argparse
import numpy as np
import polars as pl

OUT_DIR = "../../output/bert"

parser = argparse.ArgumentParser()
parser.add_argument("--clusters", type=int, required=True)
parser.add_argument("--sample", type=int, default=50_000,
                    help="Sample size for intra/inter cosine comparison.")
args = parser.parse_args()
K = args.clusters
print(f"--- DESCRIPTIVES: K={K} ---")

# 1. Paper cluster sizes ------------------------------------------------------
clusters = pl.read_parquet(f"{OUT_DIR}/paper_clusters_K{K}.parquet")
sizes = (
    clusters.group_by("cluster_label").agg(pl.len().alias("n"))
    .sort("n", descending=True)
)
n_papers = int(sizes["n"].sum())
size_arr = sizes["n"].to_numpy()
top5_share = float(sizes.head(5)["n"].sum()) / n_papers

print(f"\n[Paper cluster sizes]  N = {n_papers:,}, K = {K}")
print(f"  min:    {size_arr.min():>10,}  ({size_arr.min()/n_papers:.3%})")
print(f"  p25:    {int(np.percentile(size_arr, 25)):>10,}")
print(f"  median: {int(np.median(size_arr)):>10,}")
print(f"  p75:    {int(np.percentile(size_arr, 75)):>10,}")
print(f"  max:    {size_arr.max():>10,}  ({size_arr.max()/n_papers:.3%})")
print(f"  top-5 clusters cover {top5_share:.1%} of papers")

# 2. Author-level concentration ----------------------------------------------
adist = pl.read_parquet(f"{OUT_DIR}/author_field_dist_K{K}.parquet")
ent = adist["entropy"].to_numpy()
modal = adist["modal_share"].to_numpy()
n_per_author = adist["n_papers"].to_numpy()
H_max = float(np.log(K))

print(f"\n[Author-level concentration]  N authors = {len(adist):,}")
print(f"  papers/author median:       {int(np.median(n_per_author))}")
print(f"  modal_share  mean / median: {modal.mean():.3f} / {np.median(modal):.3f}")
print(f"  entropy      mean / median: {ent.mean():.3f} / {np.median(ent):.3f}")
print(f"  entropy/Hmax mean:          {(ent/H_max).mean():.3f}   (0 = pure, 1 = uniform)")
print(f"  share modal >= 0.5:         {(modal >= 0.5).mean():.3%}")
print(f"  share modal >= 0.8:         {(modal >= 0.8).mean():.3%}")

# 3. Intra- vs inter-cluster cosine on a sample ------------------------------
print(f"\n[Cosine separation]  sample = {args.sample:,}")
embeddings = np.load(f"{OUT_DIR}/paper_embeddings.npy", mmap_mode="r")
centroids = np.load(f"{OUT_DIR}/cluster_centroids_K{K}.npy")
papers_aligned = pl.read_parquet(f"{OUT_DIR}/papers_aligned.parquet")
N = embeddings.shape[0]
assert len(papers_aligned) == N, "papers_aligned length != embedding count"

# paper_clusters_K{K}.parquet was written from papers_aligned, so row order matches.
labels = clusters["cluster_label"].to_numpy()
rng = np.random.default_rng(42)
idx = np.sort(rng.choice(N, size=min(args.sample, N), replace=False))
X = embeddings[idx].astype(np.float32)
X /= np.linalg.norm(X, axis=1, keepdims=True).clip(min=1e-12)
lbl = labels[idx]

sims = X @ centroids.T                          # (sample, K)
intra = sims[np.arange(len(idx)), lbl]
sims_masked = sims.copy()
sims_masked[np.arange(len(idx)), lbl] = -np.inf
inter = sims_masked.max(axis=1)
gap = intra - inter

print(f"  intra (assigned)        mean / median: {intra.mean():.3f} / {np.median(intra):.3f}")
print(f"  inter (next-best)       mean / median: {inter.mean():.3f} / {np.median(inter):.3f}")
print(f"  gap (intra - next-best) mean / median: {gap.mean():.3f} / {np.median(gap):.3f}")
print(f"  share gap > 0:          {(gap > 0).mean():.3%}   (well-assigned)")

# 4. Save terse text summary --------------------------------------------------
summary_path = f"{OUT_DIR}/cluster_descriptives_K{K}.txt"
with open(summary_path, "w") as f:
    f.write(f"K={K} | papers={n_papers:,} | authors={len(adist):,}\n")
    f.write(f"sizes min/median/max = {size_arr.min():,}/{int(np.median(size_arr)):,}/{size_arr.max():,}"
            f"   top-5 cover {top5_share:.1%}\n")
    f.write(f"modal_share median = {np.median(modal):.3f}"
            f"   entropy/Hmax mean = {(ent/H_max).mean():.3f}\n")
    f.write(f"intra cosine mean = {intra.mean():.3f}"
            f"   inter mean = {inter.mean():.3f}"
            f"   gap mean = {gap.mean():.3f}"
            f"   share well-assigned = {(gap > 0).mean():.3%}\n")
print(f"\nWrote {summary_path}")

# 5. Histograms ---------------------------------------------------------------
try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(1, 3, figsize=(15, 4))
    axes[0].hist(size_arr, bins=40)
    axes[0].set_title("Papers per cluster"); axes[0].set_xlabel("size")
    axes[1].hist(modal, bins=40)
    axes[1].set_title("Author modal share"); axes[1].set_xlabel("modal_share")
    axes[2].hist(ent / H_max, bins=40)
    axes[2].set_title("Author entropy / log(K)"); axes[2].set_xlabel("normalized entropy")
    fig.suptitle(f"K = {K}")
    fig.tight_layout()
    png_path = f"{OUT_DIR}/cluster_descriptives_K{K}.png"
    fig.savefig(png_path, dpi=120)
    print(f"Wrote {png_path}")
except Exception as e:
    print(f"Skipping plots ({e})")

print("Done.")
