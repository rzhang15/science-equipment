"""
Seed-stability evidence for the chosen K.

Inertia falls and silhouette rises monotonically in K on this corpus, so
neither picks a stopping point. Stability does: a K whose partition
reproduces under different random seeds is recovering real structure, while
a K that reshuffles is splitting noise.

For each K, clusters the same embedding under several seeds and reports the
mean pairwise adjusted Rand index across seed pairs. ARI is 1.0 for identical
partitions and ~0 for independent ones, and is chance-corrected so it does
not drift mechanically with K.

The SVD is computed once and reused across every (K, seed), so the cost is
one SVD plus n_k * n_seeds K-means fits.

Output: ../output/k_stability{SUF}.csv
"""
import argparse
import itertools
import pickle

import numpy as np
import pandas as pd
import scipy.sparse
from sklearn.cluster import MiniBatchKMeans
from sklearn.decomposition import TruncatedSVD
from sklearn.metrics import adjusted_rand_score
from sklearn.preprocessing import normalize

ap = argparse.ArgumentParser()
ap.add_argument("--ks", type=int, nargs="+", default=[25, 30, 35, 40])
ap.add_argument("--seeds", type=int, nargs="+", default=[42, 1, 2, 3])
ap.add_argument("--svd-dim", type=int, default=256)
ap.add_argument("--suffix", default="_ls")
args = ap.parse_args()
SUF = args.suffix

print(f"--- K STABILITY: ks={args.ks} seeds={args.seeds} ---", flush=True)

matrix = scipy.sparse.load_npz(f"../output/tfidf_matrix{SUF}.npz")
print(f"TF-IDF shape: {matrix.shape}", flush=True)

print(f"TruncatedSVD -> {args.svd_dim} dims (once, reused for all runs)...", flush=True)
svd = TruncatedSVD(n_components=args.svd_dim, random_state=42,
                   algorithm="randomized", n_iter=7)
X = normalize(svd.fit_transform(matrix).astype(np.float32), norm="l2", axis=1)
print(f"  cumulative explained variance: {svd.explained_variance_ratio_.sum():.3f}", flush=True)

rows = []
for k in args.ks:
    labels = {}
    for s in args.seeds:
        print(f"  K={k} seed={s} ...", flush=True)
        km = MiniBatchKMeans(n_clusters=k, random_state=s, batch_size=16384,
                             n_init=3, init="k-means++", max_iter=300,
                             reassignment_ratio=0.01)
        labels[s] = km.fit_predict(X)

    aris = [adjusted_rand_score(labels[a], labels[b])
            for a, b in itertools.combinations(args.seeds, 2)]
    rows.append({
        "k": k,
        "n_seeds": len(args.seeds),
        "n_pairs": len(aris),
        "mean_ari": float(np.mean(aris)),
        "min_ari": float(np.min(aris)),
        "max_ari": float(np.max(aris)),
        "sd_ari": float(np.std(aris)),
    })
    print(f"  K={k}: mean ARI={np.mean(aris):.4f}  min={np.min(aris):.4f}", flush=True)

out = pd.DataFrame(rows)
path = f"../output/k_stability{SUF}.csv"
out.to_csv(path, index=False)
print(f"\nSaved {path}")
print(out.to_string(index=False))
print("\nHigher mean ARI = the partition reproduces across seeds. The K with "
      "the highest stability is the defensible choice; a sharp drop above some "
      "K means those extra clusters are splitting noise.")
