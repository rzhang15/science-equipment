"""
Phase 2: impute buyer-cluster mixtures (and exposure) for the OpenAlex universe.

This is a PLACEHOLDER that will run end-to-end once universe BERT embeddings
exist. The pipeline mirrors the FOIA training path:

  classifier (BERT -> top1 cluster, predict_proba -> mixture)
        |
        v
  for each universe author:  p_a = clf.predict_proba(BERT[a])     (A_univ, K_kept)
                              E_a = sum_k p_a[k] * mean_E_k       (scalar)

  cluster means mean_E_k come from cluster_exposure_stats.csv (the mixture-
  weighted exposure per cluster, computed from FOIA W & exposure).

Required inputs (NOT YET BUILT for the universe — see notes below):
  - universe BERT embeddings .npy + ids .csv
    Currently only built for FOIA (foia_similarity_wts/output/bert_foia_*.npy).
    To produce the universe set, run foia_similarity_wts/bert/1_vectorize.py
    with --universe (see foia_similarity_wts/bert/run_pipeline.sbatch).

Output (once unblocked):
  - ../output/universe_cluster_mixture.parquet  (athr_id, p_0..p_{K-1})
  - ../output/universe_imputed_exposure.parquet (athr_id, exposure_cluster_imp)
"""
import pickle
import sys
from pathlib import Path
import numpy as np
import pandas as pd
import config as cfg


# Expected universe BERT artifacts (produced by foia_similarity_wts/bert/1_vectorize.py --universe)
UNIV_BERT_EMB = cfg.EXT / "foia_bert" / "bert_universe_pritamdeka_S-Scibert-snli-multinli-stsb_unstemmed.npy"
UNIV_BERT_IDS = cfg.EXT / "foia_bert" / "bert_universe_ids_pritamdeka_S-Scibert-snli-multinli-stsb_unstemmed.parquet"


def main():
    # ---- check that all inputs exist; bail loudly if not ----
    missing = [p for p in [cfg.OUT / "classifier.pkl",
                           cfg.OUT / "cluster_exposure_stats.csv",
                           UNIV_BERT_EMB, UNIV_BERT_IDS] if not Path(p).exists()]
    if missing:
        print("PHASE 2 not yet runnable. Missing inputs:")
        for m in missing:
            print(f"  - {m}")
        print("\nTo unblock: run foia_similarity_wts/bert/1_vectorize.py with --universe,")
        print("then symlink the bert_universe_* outputs into ../external/foia_bert/.")
        sys.exit(0)

    print("Loading classifier")
    with open(cfg.OUT / "classifier.pkl", "rb") as f:
        bundle = pickle.load(f)
    clf = bundle["pipeline"]
    kept = np.array(bundle["kept_clusters"])
    K_total = bundle["K_total"]

    print("Loading cluster exposure stats")
    stats = pd.read_csv(cfg.OUT / "cluster_exposure_stats.csv")
    mean_E = stats.set_index("cluster")["exposure_mean"].reindex(range(K_total),
                                                                 fill_value=0.0).values

    print(f"Loading universe BERT embeddings: {UNIV_BERT_EMB}")
    Xu = np.load(UNIV_BERT_EMB)
    if UNIV_BERT_IDS.suffix == ".parquet":
        ids = pd.read_parquet(UNIV_BERT_IDS)["athr_id"].astype(str).tolist()
    else:
        ids = pd.read_csv(UNIV_BERT_IDS, dtype={"athr_id": str})["athr_id"].tolist()
    assert Xu.shape[0] == len(ids), "universe emb / id length mismatch"
    print(f"Universe: {Xu.shape[0]:,} authors  dim={Xu.shape[1]}")

    print("Predicting mixtures")
    proba = clf.predict_proba(Xu)                       # (n_univ, len(kept))
    P = np.zeros((Xu.shape[0], K_total), dtype=np.float32)
    for c_idx, c_lab in enumerate(clf.classes_):
        P[:, c_lab] = proba[:, c_idx]

    print("Imputing exposure")
    E_imp = P @ mean_E                                  # (n_univ,)

    mix = pd.DataFrame(P, columns=[f"p_{k}" for k in range(K_total)])
    mix.insert(0, "athr_id", ids)
    mix.to_parquet(cfg.OUT / "universe_cluster_mixture.parquet", index=False)

    pd.DataFrame({"athr_id": ids, "exposure_cluster_imp": E_imp}) \
        .to_parquet(cfg.OUT / "universe_imputed_exposure.parquet", index=False)

    print(f"mean E_imp = {E_imp.mean():+.5f}   median = {np.median(E_imp):+.5f}   "
          f"nonzero = {np.mean(E_imp != 0):.3f}")
    print(f"Wrote universe_cluster_mixture.parquet and universe_imputed_exposure.parquet to {cfg.OUT}/")


if __name__ == "__main__":
    main()
