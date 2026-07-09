"""
02e_pi_svd_features.py

Author-level topic-mix features for the PI panel. Reuses the TF-IDF universe
matrix from foia_similarity_wts (author x 25,487 terms, pre-2013 static, L2-
normalized) and projects it to K=20 continuous dimensions via TruncatedSVD.

Why:
- The current PI representation is pi_cluster (k=30 discrete label) plus
  pi_modal_cluster_pre2013. That's a very coarse compression of the same
  25,487-term topic-mix vector already computed in ../external/sim_wts/.
- Adding a dense 20-dim projection gives LightGBM within-cluster nuance:
  two "cluster 12" authors can now differ on a continuous axis.
- Truly ex-ante: cluster_fields/0_combine_data.py filters papers to
  publication_year <= 2013 before aggregating per author, matching the
  pre-2014 training cutoff.

Inputs
------
../external/sim_wts/tfidf_universe.npz        (1.86M x 25,487, float32)
../external/sim_wts/universe_ids.parquet      (athr_id per row)

Output
------
../temp/pi_svd_features.parquet               (athr_id, pi_svd_1 ... pi_svd_20)

Notes
-----
- TruncatedSVD is not centered (works directly on the sparse matrix). For
  L2-normalized TF-IDF the resulting components are the dominant topic axes.
- We do NOT restrict the SVD fit to the 1.22M PIs in predict_impact --
  fitting on the full 1.86M universe gives more stable axes and costs the
  same because sklearn's randomized SVD is O(n * K).
- Authors not in the universe (non-US, or dropped by 0b_clean_us_corpus.py
  scraper/short-text filters) get null features, which LightGBM handles
  natively.
"""

import os
import sys
import time

import numpy as np
import polars as pl
import scipy.sparse as sp
from sklearn.decomposition import TruncatedSVD

TFIDF = "../external/sim_wts/tfidf_universe.npz"
IDS = "../external/sim_wts/universe_ids.parquet"
DST = "../temp/pi_svd_features.parquet"

K = 20
RANDOM_STATE = 8975


def main():
    for path in (TFIDF, IDS):
        if not os.path.exists(path):
            sys.exit(
                f"ERROR: missing input {path}. Run make.py to set up links or "
                f"check that foia_similarity_wts has been built."
            )

    t0 = time.time()

    print(f"loading {TFIDF}", flush=True)
    X = sp.load_npz(TFIDF)
    print(
        f"   shape {X.shape}  dtype {X.dtype}  nnz {X.nnz:,}",
        flush=True,
    )

    print(f"loading {IDS}", flush=True)
    ids = pl.read_parquet(IDS)
    if ids.height != X.shape[0]:
        sys.exit(
            f"ERROR: universe_ids has {ids.height:,} rows but tfidf_universe "
            f"has {X.shape[0]:,} rows. Alignment broken."
        )

    print(f"fitting TruncatedSVD (n_components={K}, randomized, n_iter=4)", flush=True)
    # n_iter=4 is a small quality hit vs the sklearn default of 5 (which was
    # 7 in older versions) but roughly halves the wall-clock. On L2-normalized
    # TF-IDF the top-20 components are stable well below 5 iterations.
    svd = TruncatedSVD(
        n_components=K, algorithm="randomized",
        n_iter=4, random_state=RANDOM_STATE,
    )
    Z = svd.fit_transform(X)
    print(
        f"   done in {time.time() - t0:.1f}s",
        flush=True,
    )
    print(
        f"   explained variance ratio: {svd.explained_variance_ratio_.sum():.4f} "
        f"(top 5 = {svd.explained_variance_ratio_[:5].round(4).tolist()})",
        flush=True,
    )

    col_names = [f"pi_svd_{i+1}" for i in range(K)]
    out = pl.DataFrame(
        {"athr_id": ids["athr_id"], **{c: Z[:, i].astype(np.float32) for i, c in enumerate(col_names)}}
    )

    # Sanity: no NaNs, finite everywhere.
    for c in col_names:
        finite = out[c].is_finite().sum()
        if finite != out.height:
            sys.exit(f"ERROR: non-finite values in {c}")

    print(f"writing {DST}", flush=True)
    out.write_parquet(DST, compression="snappy")
    print(f"total time {time.time() - t0:.1f}s", flush=True)


if __name__ == "__main__":
    main()
