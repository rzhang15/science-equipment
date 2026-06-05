"""
NMF on (author x category) shares -> K soft buyer-type assignments.

  X (A x C)  ~=  W (A x K)  @  H (K x C)

Each row of W (after row-normalization) is the author's mixture over K
methodology archetypes. Each row of H is the "category signature" of that
archetype (how much each cat shows up for buyers of this type).

NMF naturally absorbs commodity categories (pipette tips, gloves) into one
or two components, so the remaining components capture discriminating method
signal. If commodities dominate too many components, consider TF-IDF weighting
the input -- but that's a v2 fix; let NMF try first.

Output: ../output/buyer_W.npy            (A, K) row-normalized mixture probs
        ../output/buyer_H.npy            (K, C) category loadings
        ../output/buyer_authors.csv      (athr_id order matching W)
        ../output/nmf_recon_err.json     (reconstruction diagnostic)
"""
import json
import numpy as np
import pandas as pd
from sklearn.decomposition import NMF
import config as cfg


def main():
    df = pd.read_parquet(cfg.OUT / "foia_purchase_matrix.parquet")
    athr_ids = df["athr_id"].astype(str).tolist()
    X = df.drop(columns=["athr_id"]).to_numpy(dtype=np.float32)
    print(f"input X: {X.shape}  (authors x categories)")
    print(f"sparsity: {(X == 0).mean():.1%}")

    nmf = NMF(
        n_components=cfg.K,
        init=cfg.NMF_INIT,
        max_iter=cfg.NMF_MAX_ITER,
        random_state=cfg.RNG_SEED,
        beta_loss="frobenius",
        solver="cd",
    )
    W = nmf.fit_transform(X)              # (A, K) -- mixture weights, non-negative
    H = nmf.components_                   # (K, C) -- category signatures, non-negative
    err = float(nmf.reconstruction_err_)
    print(f"reconstruction error (Frobenius): {err:.4f}   (lower = better fit)")
    print(f"n_iter: {nmf.n_iter_}   (capped at {cfg.NMF_MAX_ITER})")

    # Row-normalize W to interpret as cluster *probabilities*. NMF doesn't
    # constrain rows to sum to 1, but for downstream classification we want
    # the per-author K-vector to live on a simplex.
    row_sums = W.sum(axis=1, keepdims=True)
    row_sums[row_sums == 0] = 1.0
    W_probs = W / row_sums

    # Diagnostic: how concentrated are the mixtures? (1 = pure cluster, 1/K = uniform)
    top1 = W_probs.max(axis=1)
    print(f"\ntop-1 cluster share: mean={top1.mean():.3f}  "
          f"median={np.median(top1):.3f}  "
          f"share authors with top1>=0.5: {(top1 >= 0.5).mean():.1%}")

    # Cluster sizes by top-1 assignment
    top1_cluster = W_probs.argmax(axis=1)
    sizes = pd.Series(top1_cluster).value_counts().sort_index()
    print("\ntop-1 cluster sizes (cluster, n):")
    for k in range(cfg.K):
        print(f"  k={k:>2}  n={int(sizes.get(k, 0)):>3}")

    np.save(cfg.OUT / "buyer_W.npy", W_probs.astype(np.float32))
    np.save(cfg.OUT / "buyer_H.npy", H.astype(np.float32))
    pd.DataFrame({"athr_id": athr_ids, "top1_cluster": top1_cluster}) \
      .to_csv(cfg.OUT / "buyer_authors.csv", index=False)

    with open(cfg.OUT / "nmf_recon_err.json", "w") as f:
        json.dump({"K": cfg.K, "frobenius_err": err, "n_iter": nmf.n_iter_,
                   "n_authors": X.shape[0], "n_categories": X.shape[1]}, f, indent=2)


if __name__ == "__main__":
    main()
