"""
Validation: do coauthors of FOIA authors land near their FOIA partner in
BERT-embedding space, and does the imputed-exposure prediction track the
FOIA author's true exposure?

Pipeline:
  1. Cosine sim of every coauthor embedding against every FOIA embedding.
  2. Top-K + row-normalize -> per-coauthor weights over FOIA authors.
  3. Impute coauthor exposure = W @ E_FOIA.
  4. For each known (FOIA, coauthor) pair, compare imputed coauthor exposure
     to the FOIA author's true exposure. Benchmark vs random FOIA pairings.
  5. Also report the rank of the true FOIA partner in the coauthor's nearest-
     neighbor list -- the cleanest twin test (random => mean rank ~ N_FOIA/2).

Inputs (all in ../../output/):
  bert_foia_{model_tag}.npy                       FOIA embeddings
  bert_foia_ids_{model_tag}.csv                   FOIA athr_id order
  bert_foia_{model_tag}_coauthors_unstemmed.npy   coauthor embeddings
  bert_foia_ids_{model_tag}_coauthors_unstemmed.csv  coauthor athr_id order
External:
  ../../external/exposure_wts/athr_exposure.dta   FOIA scalar exposure
  ../../external/coauthors/coauthors.dta          (athr_id, coauthor_id)

Outputs:
  ../../output/coauthor_validation_pairs.csv      per-pair diagnostics
  ../../output/coauthor_validation_summary.txt    aggregate metrics
"""
import argparse
import os
import numpy as np
import pandas as pd

OUT_DIR = "../../output"
EXPOSURE_DTA = "../../external/exposure_wts/athr_exposure.dta"
COAUTHORS_DTA = "../../external/coauthors/coauthors.dta"


def cosine_topk_weights(sim: np.ndarray, k: int) -> np.ndarray:
    """sim: (n_co, n_foia) cosine. Return (n_co, n_foia) row-stochastic weights
    over the top-K FOIA partners (zero elsewhere)."""
    n_co, n_foia = sim.shape
    k = min(k, n_foia)
    # argpartition is O(n) per row; argsort within top-K for stable ranks
    part = np.argpartition(-sim, kth=k - 1, axis=1)[:, :k]
    rows = np.arange(n_co)[:, None]
    top_vals = sim[rows, part]
    W = np.zeros_like(sim)
    W[rows, part] = top_vals
    # clip negatives (cosine can be slightly < 0); row-normalize
    W = np.clip(W, 0, None)
    row_sums = W.sum(axis=1, keepdims=True)
    row_sums[row_sums == 0] = 1.0
    return W / row_sums


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="pritamdeka/S-Scibert-snli-multinli-stsb",
                    help="Same model passed to 1_vectorize.py")
    ap.add_argument("--foia-suffix", default="_unstemmed",
                    help="Tag suffix of existing FOIA artifacts.")
    ap.add_argument("--coauthor-suffix", default="_coauthors_unstemmed",
                    help="Tag suffix you passed when embedding coauthors.")
    ap.add_argument("--k", type=int, default=5,
                    help="Top-K FOIA neighbors used for the imputed-exposure aggregate.")
    ap.add_argument("--seed", type=int, default=8975)
    args = ap.parse_args()

    model_tag = args.model.replace("/", "_")
    foia_emb_path = f"{OUT_DIR}/bert_foia_{model_tag}{args.foia_suffix}.npy"
    foia_ids_path = f"{OUT_DIR}/bert_foia_ids_{model_tag}{args.foia_suffix}.csv"
    co_emb_path   = f"{OUT_DIR}/bert_foia_{model_tag}{args.coauthor_suffix}.npy"
    co_ids_path   = f"{OUT_DIR}/bert_foia_ids_{model_tag}{args.coauthor_suffix}.csv"
    for p in (foia_emb_path, foia_ids_path, co_emb_path, co_ids_path):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")

    print("Loading embeddings + ids")
    X_foia = np.load(foia_emb_path).astype(np.float32)
    X_co   = np.load(co_emb_path).astype(np.float32)
    foia_ids = pd.read_csv(foia_ids_path)["athr_id"].astype(str).tolist()
    co_ids   = pd.read_csv(co_ids_path)["athr_id"].astype(str).tolist()
    print(f"  FOIA: {X_foia.shape}    coauthors: {X_co.shape}")
    assert X_foia.shape[1] == X_co.shape[1]

    print("Loading exposure + coauthor map")
    df_exp = pd.read_stata(EXPOSURE_DTA)[["athr_id", "exposure"]]
    df_exp["athr_id"] = df_exp["athr_id"].astype(str)
    df_map = pd.read_stata(COAUTHORS_DTA)
    df_map["athr_id"] = df_map["athr_id"].astype(str)
    df_map["coauthor_id"] = df_map["coauthor_id"].astype(str)

    foia_idx = {a: i for i, a in enumerate(foia_ids)}
    co_idx   = {a: i for i, a in enumerate(co_ids)}
    e_foia = pd.Series(df_exp.set_index("athr_id")["exposure"]).reindex(foia_ids).fillna(0).values

    # Embeddings are L2-normalized by 1_vectorize.py, so dot product == cosine.
    print("Computing cosine sim (coauthor x FOIA)")
    norms_co   = np.linalg.norm(X_co,   axis=1, keepdims=True);   norms_co[norms_co == 0]   = 1
    norms_foia = np.linalg.norm(X_foia, axis=1, keepdims=True); norms_foia[norms_foia == 0] = 1
    sim = (X_co / norms_co) @ (X_foia / norms_foia).T   # (n_co, n_foia)

    print(f"Top-K weights (k={args.k}) and imputing exposure")
    W = cosine_topk_weights(sim, args.k)
    e_co_imputed = W @ e_foia

    # Per-pair table: for every (FOIA, coauthor) edge that has embeddings on
    # both sides, attach (true FOIA exposure, imputed coauthor exposure, rank).
    df = df_map.copy()
    df = df[df["coauthor_id"].isin(co_idx) & df["athr_id"].isin(foia_idx)].copy()
    df["foia_pos"] = df["athr_id"].map(foia_idx)
    df["co_pos"]   = df["coauthor_id"].map(co_idx)
    df["e_foia_true"]    = e_foia[df["foia_pos"].values]
    df["e_co_imputed"]   = e_co_imputed[df["co_pos"].values]
    df["sim_to_partner"] = sim[df["co_pos"].values, df["foia_pos"].values]
    # rank of the partner among all FOIA neighbors of this coauthor (0 = closest)
    ranks = (-sim).argsort(axis=1).argsort(axis=1)   # (n_co, n_foia) rank matrix
    df["partner_rank"]   = ranks[df["co_pos"].values, df["foia_pos"].values]
    df["abs_err"]        = (df["e_foia_true"] - df["e_co_imputed"]).abs()
    print(f"  usable pairs: {len(df):,}  (out of {len(df_map):,})")

    # Random benchmark: shuffle the FOIA-partner column within the coauthor set.
    rng = np.random.default_rng(args.seed)
    perm = rng.permutation(len(df))
    e_foia_random = df["e_foia_true"].values[perm]
    abs_err_rand  = np.abs(e_foia_random - df["e_co_imputed"].values)

    # ------- aggregate metrics -------
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

    out_pairs = f"{OUT_DIR}/coauthor_validation_pairs_bert_{model_tag}{args.foia_suffix}.csv"
    df[["athr_id", "coauthor_id", "e_foia_true", "e_co_imputed",
        "sim_to_partner", "partner_rank", "abs_err"]].to_csv(out_pairs, index=False)
    print(f"\nSaved per-pair diagnostics: {out_pairs}")

    out_summary = f"{OUT_DIR}/coauthor_validation_summary_bert_{model_tag}{args.foia_suffix}.txt"
    with open(out_summary, "w") as f:
        f.write(summary_str + "\n")
    print(f"Saved summary: {out_summary}")


if __name__ == "__main__":
    main()
