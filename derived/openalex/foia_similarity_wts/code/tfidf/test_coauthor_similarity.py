"""
TF-IDF analog of bert/test_coauthor_similarity.py.

Coauthor vectors are computed in the SAME TF-IDF space as the saved FOIA
matrix (vocab + IDF reconstructed from feature_names.pkl and
feature_diagnostics.parquet). Cosine sim is a sparse matmul; downstream
top-K / impute / per-pair diagnostics mirror the BERT version exactly so
the two methods are directly comparable.

Pipeline:
  1. Load saved FOIA TF-IDF artifacts (matrix, ids, vocab, idf).
  2. Reconstruct the TF-IDF transformer (CountVectorizer + sublinear_tf + idf
     + L2-norm) and vectorize the stemmed coauthor texts.
  3. Sparse cosine sim (n_co x n_foia).
  4. Top-K, row-normalize -> per-coauthor weights over FOIA authors.
  5. Impute coauthor exposure = W @ E_FOIA.
  6. Per-pair: imputed-vs-true exposure, partner rank, random benchmark.

Inputs (all in ../../output/):
  tfidf_foia.npz                 FOIA tfidf matrix (n_foia, V)
  foia_ids_ordered.csv           FOIA athr_id order
  feature_names.pkl              vocab (V,)
  feature_diagnostics.parquet    feature, foia_df, idf
  coauthor_text_stemmed.csv      built by ../0c_get_coauthor_stemmed.py
External:
  ../../external/exposure_wts/athr_exposure.dta
  ../../external/coauthors/coauthors.dta

Outputs:
  ../../output/coauthor_validation_pairs_tfidf.csv
  ../../output/coauthor_validation_summary_tfidf.txt
"""
import argparse
import os
import pickle
import numpy as np
import pandas as pd
import scipy.sparse
from sklearn.feature_extraction.text import CountVectorizer

OUT_DIR = "../../output"
COAUTHOR_CSV = f"{OUT_DIR}/coauthor_text_stemmed.csv"
EXPOSURE_DTA = "../../external/exposure_wts/athr_exposure.dta"
COAUTHORS_DTA = "../../external/coauthors/coauthors.dta"


def _paths(tag: str) -> dict:
    """Resolve tag-suffixed input/output paths. tag='' uses baseline names."""
    if tag and not tag.startswith("_"):
        tag = "_" + tag
    return {
        "foia_matrix":   f"{OUT_DIR}/tfidf_foia{tag}.npz",
        "foia_ids":      f"{OUT_DIR}/foia_ids_ordered{tag}.csv",
        "feature_names": f"{OUT_DIR}/feature_names{tag}.pkl",
        "feature_diag":  f"{OUT_DIR}/feature_diagnostics{tag}.parquet",
        "out_pairs":     f"{OUT_DIR}/coauthor_validation_pairs_tfidf{tag}.csv",
        "out_summary":   f"{OUT_DIR}/coauthor_validation_summary_tfidf{tag}.txt",
    }


def vectorize_in_foia_space(texts: list[str], vocab: list[str],
                            idf_values: np.ndarray) -> scipy.sparse.csr_matrix:
    """Transform texts using the saved vocab + idf. Mirrors what
    tfidf/1_vectorize.py applied to the FOIA rows:
      - tokenizer = str.split, ngram_range = (1, 2)  (matches sklearn fit step;
        bigrams in vocab need ngram_range=(1,2) or they're never matched)
      - sublinear_tf: log(tf) + 1 on nonzero entries
      - tfidf = counts * idf
      - L2 normalize rows
    """
    cv = CountVectorizer(
        vocabulary=vocab,
        tokenizer=str.split,
        token_pattern=None,
        ngram_range=(1, 2),
        dtype=np.float32,
    )
    counts = cv.transform(texts).tocsr().astype(np.float32)
    if counts.nnz > 0:
        counts.data = np.log(counts.data) + 1.0   # sublinear_tf
    tfidf = counts @ scipy.sparse.diags(idf_values.astype(np.float32))
    norms = np.sqrt(np.asarray(tfidf.multiply(tfidf).sum(axis=1)).ravel())
    inv = 1.0 / np.maximum(norms, 1e-12)
    return (scipy.sparse.diags(inv) @ tfidf).astype(np.float32).tocsr()


def cosine_topk_weights(sim: np.ndarray, k: int) -> np.ndarray:
    n_co, n_foia = sim.shape
    k = min(k, n_foia)
    part = np.argpartition(-sim, kth=k - 1, axis=1)[:, :k]
    rows = np.arange(n_co)[:, None]
    top_vals = sim[rows, part]
    W = np.zeros_like(sim)
    W[rows, part] = top_vals
    W = np.clip(W, 0, None)
    row_sums = W.sum(axis=1, keepdims=True)
    row_sums[row_sums == 0] = 1.0
    return W / row_sums


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--k", type=int, default=5,
                    help="Top-K FOIA neighbors for the imputed-exposure aggregate.")
    ap.add_argument("--seed", type=int, default=8975)
    ap.add_argument("--tag", default="",
                    help="Suffix matching the --tag passed to 1_vectorize.py. "
                         "Empty = baseline artifacts.")
    args = ap.parse_args()

    paths = _paths(args.tag)
    for p in (paths["foia_matrix"], paths["foia_ids"], paths["feature_names"],
              paths["feature_diag"], COAUTHOR_CSV):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")

    print(f"Loading FOIA artifacts (tag={args.tag!r})")
    X_foia = scipy.sparse.load_npz(paths["foia_matrix"]).tocsr().astype(np.float32)
    foia_ids = pd.read_csv(paths["foia_ids"])["athr_id"].astype(str).tolist()
    with open(paths["feature_names"], "rb") as f:
        feature_names = list(pickle.load(f))
    diag = pd.read_parquet(paths["feature_diag"])
    # feature_diagnostics rows are written in the same order as feature_names
    # (both indexed by keep_idx in tfidf/1_vectorize.py), so this assert is
    # really just a sanity check on file pairing.
    assert list(diag["feature"]) == feature_names, "feature ordering mismatch"
    idf_values = diag["idf"].to_numpy().astype(np.float32)
    print(f"  FOIA matrix: {X_foia.shape}   vocab: {len(feature_names):,}")

    print("Loading coauthor stemmed text")
    df_co = pd.read_csv(COAUTHOR_CSV)
    df_co["processed_text"] = df_co["processed_text"].fillna("").astype(str)
    df_co["athr_id"] = df_co["athr_id"].astype(str)
    print(f"  coauthors: {len(df_co):,}")

    print("Vectorizing coauthors in FOIA TF-IDF space")
    X_co = vectorize_in_foia_space(
        df_co["processed_text"].tolist(), feature_names, idf_values
    )
    print(f"  coauthor matrix: {X_co.shape}   nnz/row mean: {X_co.nnz / X_co.shape[0]:.1f}")

    print("Loading exposure + coauthor map")
    df_exp = pd.read_stata(EXPOSURE_DTA)[["athr_id", "exposure"]]
    df_exp["athr_id"] = df_exp["athr_id"].astype(str)
    df_map = pd.read_stata(COAUTHORS_DTA)
    df_map["athr_id"] = df_map["athr_id"].astype(str)
    df_map["coauthor_id"] = df_map["coauthor_id"].astype(str)

    foia_idx = {a: i for i, a in enumerate(foia_ids)}
    co_idx   = {a: i for i, a in enumerate(df_co["athr_id"].tolist())}
    e_foia = pd.Series(df_exp.set_index("athr_id")["exposure"]).reindex(foia_ids).fillna(0).values

    print("Cosine sim (sparse matmul)")
    sim = (X_co @ X_foia.T).toarray()   # (n_co, n_foia); 32k x 208 fits trivially
    print(f"  sim shape: {sim.shape}   nonzero rows: {(sim.sum(axis=1) > 0).sum():,}")

    print(f"Top-K weights (k={args.k}) and imputing exposure")
    W = cosine_topk_weights(sim, args.k)
    e_co_imputed = W @ e_foia

    df = df_map.copy()
    df = df[df["coauthor_id"].isin(co_idx) & df["athr_id"].isin(foia_idx)].copy()
    df["foia_pos"] = df["athr_id"].map(foia_idx)
    df["co_pos"]   = df["coauthor_id"].map(co_idx)
    df["e_foia_true"]    = e_foia[df["foia_pos"].values]
    df["e_co_imputed"]   = e_co_imputed[df["co_pos"].values]
    df["sim_to_partner"] = sim[df["co_pos"].values, df["foia_pos"].values]
    ranks = (-sim).argsort(axis=1).argsort(axis=1)
    df["partner_rank"]   = ranks[df["co_pos"].values, df["foia_pos"].values]
    df["abs_err"]        = (df["e_foia_true"] - df["e_co_imputed"]).abs()
    print(f"  usable pairs: {len(df):,}  (out of {len(df_map):,})")

    rng = np.random.default_rng(args.seed)
    perm = rng.permutation(len(df))
    abs_err_rand = np.abs(df["e_foia_true"].values[perm] - df["e_co_imputed"].values)

    corr_pair = df[["e_foia_true", "e_co_imputed"]].corr().iloc[0, 1]
    mae_pair  = df["abs_err"].mean()
    mae_rand  = abs_err_rand.mean()
    n_foia    = len(foia_ids)
    rank_mean = df["partner_rank"].mean()
    rank_med  = df["partner_rank"].median()
    pct_top5  = (df["partner_rank"] < 5).mean()
    pct_top1  = (df["partner_rank"] == 0).mean()

    summary = [
        f"n_pairs: {len(df):,}   n_unique_coauthors: {df['coauthor_id'].nunique():,}   "
        f"n_unique_foia: {df['athr_id'].nunique()}   n_foia_pool: {n_foia}",
        "",
        "--- Imputed-exposure tracking ---",
        f"  corr(imputed_coauthor_exposure, true_FOIA_exposure):       {corr_pair:.4f}",
        f"  MAE (true coauthor pairing):                               {mae_pair:.5f}",
        f"  MAE (random FOIA reshuffled):                              {mae_rand:.5f}",
        f"  improvement vs random (lower is better):                   {(mae_pair - mae_rand):+.5f}",
        "",
        "--- Twin-test: rank of true FOIA partner in coauthor's NN list ---",
        f"  mean rank:                                                 {rank_mean:.1f}  (random ~ {n_foia/2:.1f})",
        f"  median rank:                                               {rank_med:.1f}",
        f"  % pairs where partner is the #1 nearest FOIA:              {pct_top1*100:.1f}%",
        f"  % pairs where partner is in the top-5 nearest FOIA:        {pct_top5*100:.1f}%",
    ]
    summary_str = "\n".join(summary)
    print()
    print(summary_str)

    df[["athr_id", "coauthor_id", "e_foia_true", "e_co_imputed",
        "sim_to_partner", "partner_rank", "abs_err"]].to_csv(paths["out_pairs"], index=False)
    print(f"\nSaved per-pair diagnostics: {paths['out_pairs']}")

    with open(paths["out_summary"], "w") as f:
        f.write(summary_str + "\n")
    print(f"Saved summary: {paths['out_summary']}")


if __name__ == "__main__":
    main()
