"""
Coauthor exposure validation for the K-NN imputation.

For every (FOIA PI, coauthor) pair from coauthors.dta:
  - true_partner_exposure = the FOIA PI's true exposure
  - pred_knn(coauthor)    = top-K weighted average of FOIA exposures using
                            cosine sim in FOIA TF-IDF space (mirrors the
                            production recipe in 2_similarity_wts.py exactly)

Then compare (pred, true) across all pairs and broken out by n_copubs
(computed against author_paper_edges.parquet).

Why this is a valid exhibit: coauthors are a natural external validation —
no holdout needed, uses ALL 208 anchors, and the "true" label (partner FOIA
exposure) is independent of the anchor pool used to fit. Strong pairs (many
copubs) should track partner exposure best; that gradient is what we're
checking.

Output:
  ../../output/coauthor_validation_pairs{tag}{out_tag}.csv
  ../../output/coauthor_validation_by_copubs{tag}{out_tag}.csv
  ../../output/coauthor_validation_summary{tag}{out_tag}.txt
"""
import argparse
import os
import pickle
import numpy as np
import pandas as pd
import polars as pl
import scipy.sparse
from sklearn.feature_extraction.text import CountVectorizer

OUT_DIR = "../../output"
COAUTHOR_CSV = f"{OUT_DIR}/coauthor_text_stemmed.csv"
COAUTHORS_DTA = "../../external/coauthors/coauthors.dta"
EDGES = "/n/home02/cxu75/sci_eq/derived/openalex/cluster_fields/output/bert/author_paper_edges.parquet"
DEFAULT_EXPOSURE = "../../external/exposure_wts/athr_exposure_hc.dta"


def _paths(tag: str, out_tag: str = "") -> dict:
    if tag and not tag.startswith("_"):
        tag = "_" + tag
    if out_tag and not out_tag.startswith("_"):
        out_tag = "_" + out_tag
    return {
        "foia_matrix":   f"{OUT_DIR}/tfidf_foia{tag}.npz",
        "foia_ids":      f"{OUT_DIR}/foia_ids_ordered{tag}.csv",
        "feature_names": f"{OUT_DIR}/feature_names{tag}.pkl",
        "feature_diag":  f"{OUT_DIR}/feature_diagnostics{tag}.parquet",
        "out_pairs":     f"{OUT_DIR}/coauthor_validation_pairs{tag}{out_tag}.csv",
        "out_bybin":     f"{OUT_DIR}/coauthor_validation_by_copubs{tag}{out_tag}.csv",
        "out_summary":   f"{OUT_DIR}/coauthor_validation_summary{tag}{out_tag}.txt",
    }


def vectorize_in_foia_space(texts, vocab, idf_values):
    """Replicate 1_vectorize.py's transform on coauthor text using saved vocab+idf."""
    cv = CountVectorizer(
        vocabulary=vocab,
        tokenizer=str.split,
        token_pattern=None,
        ngram_range=(1, 2),
        dtype=np.float32,
    )
    counts = cv.transform(texts).tocsr().astype(np.float32)
    if counts.nnz > 0:
        counts.data = np.log(counts.data) + 1.0
    tfidf = counts @ scipy.sparse.diags(idf_values.astype(np.float32))
    norms = np.sqrt(np.asarray(tfidf.multiply(tfidf).sum(axis=1)).ravel())
    inv = 1.0 / np.maximum(norms, 1e-12)
    return (scipy.sparse.diags(inv) @ tfidf).astype(np.float32).tocsr()


def knn_predict_from_sim(sim, e_foia, k, sharpen, floor):
    """Top-K, floor, sharpen, L1-normalize, weighted average. Matches
    2_similarity_wts.process_batch."""
    n_co, n_foia = sim.shape
    k = min(k, n_foia)
    topk_idx = np.argpartition(-sim, k - 1, axis=1)[:, :k]
    rows = np.arange(n_co)[:, None]
    vals = sim[rows, topk_idx].copy()
    vals = np.where(vals >= floor, vals, 0.0)
    if sharpen != 1.0:
        vals = np.where(vals > 0, np.power(vals, sharpen), 0.0)
    row_sums = vals.sum(axis=1, keepdims=True)
    row_sums = np.where(row_sums > 0, row_sums, 1.0)
    w = vals / row_sums
    return (w * e_foia[topk_idx]).sum(axis=1)


def compute_copubs(pairs, edges_path=EDGES):
    """For each (FOIA, coauthor) return their # of shared papers."""
    foia_ids = pairs["athr_id"].unique().tolist()
    co_ids   = pairs["coauthor_id"].unique().tolist()
    foia_edges = (
        pl.scan_parquet(edges_path)
        .filter(pl.col("athr_id").is_in(foia_ids))
        .select(["athr_id", "id"])
        .rename({"athr_id": "foia_athr_id"})
    )
    co_edges = (
        pl.scan_parquet(edges_path)
        .filter(pl.col("athr_id").is_in(co_ids))
        .select(["athr_id", "id"])
        .rename({"athr_id": "coauthor_id"})
    )
    counts = (
        foia_edges.join(co_edges, on="id", how="inner")
        .group_by(["foia_athr_id", "coauthor_id"])
        .agg(pl.len().alias("copubs"))
        .collect(streaming=True)
        .to_pandas()
        .rename(columns={"foia_athr_id": "athr_id"})
    )
    return pairs.merge(counts, on=["athr_id", "coauthor_id"], how="left")["copubs"].fillna(0).astype(int)


def metrics_pair(y_true, y_pred, rng_perm=None):
    """corr, MAE, MAE-random."""
    y_true = np.asarray(y_true, dtype=np.float64)
    y_pred = np.asarray(y_pred, dtype=np.float64)
    mask = np.isfinite(y_true) & np.isfinite(y_pred)
    yt, yp = y_true[mask], y_pred[mask]
    corr = float(np.corrcoef(yt, yp)[0, 1]) if len(yt) >= 2 and yt.std() > 0 and yp.std() > 0 else np.nan
    mae  = float(np.mean(np.abs(yt - yp)))
    if rng_perm is not None:
        p = rng_perm[:len(yt)]
        mae_r = float(np.mean(np.abs(yt[p] - yp)))
    else:
        mae_r = np.nan
    return {"n": int(len(yt)), "corr": corr, "mae": mae, "mae_rand": mae_r}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="restricted",
                    help="Match --tag used in the vectorize step. Default: 'restricted'.")
    ap.add_argument("--exposure-dta", default=DEFAULT_EXPOSURE,
                    help="FOIA exposure .dta (default: athr_exposure_hc.dta).")
    ap.add_argument("--out-tag", default="",
                    help="Suffix on output filenames to distinguish denominators/K, "
                         "e.g. --out-tag hc_k3.")
    ap.add_argument("--k", type=int, default=3,
                    help="Top-K for K-NN (production default 3).")
    ap.add_argument("--sharpen", type=float, default=2.0)
    ap.add_argument("--floor", type=float, default=0.05)
    ap.add_argument("--seed", type=int, default=8975)
    ap.add_argument("--copub-bins", default="0,1,2,3,5,10,20,50",
                    help="Right-edges for non-overlapping n_copubs bins in the by-bin table.")
    ap.add_argument("--cluster-filter", default="",
                    help="Path to author_static_clusters_K.csv (e.g. from "
                         "openalex/us_cluster_fields). When set together with "
                         "--min-foia-per-cluster N, restrict the validation to "
                         "coauthor pairs whose coauthor sits in a cluster with "
                         ">=N FOIA anchors. This mirrors the '_cfN' filter used "
                         "in 3_impute_exposure.py / 4_impute_shift_share.py, so "
                         "the validation numbers reflect the analysis sample "
                         "the downstream analysis.do actually uses.")
    ap.add_argument("--min-foia-per-cluster", type=int, default=0,
                    help="With --cluster-filter, drop coauthor pairs whose "
                         "coauthor's cluster has fewer than N FOIA anchors. "
                         "1 -> '_cf' (drops only fully empty clusters), "
                         "2 -> '_cf2', 5 -> '_cf5' (FOIA-rich only). Default 0 "
                         "= no filter (backward compatible).")
    args = ap.parse_args()

    paths = _paths(args.tag, args.out_tag)
    for p in (paths["foia_matrix"], paths["foia_ids"], paths["feature_names"],
              paths["feature_diag"], COAUTHOR_CSV, COAUTHORS_DTA,
              args.exposure_dta, EDGES):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")

    print(f"tag={args.tag!r}  exposure={args.exposure_dta!r}")
    print(f"KNN: K={args.k} sharpen={args.sharpen} floor={args.floor}")

    # ---- Load artifacts ----
    X_foia = scipy.sparse.load_npz(paths["foia_matrix"]).tocsr().astype(np.float64)
    foia_ids = pd.read_csv(paths["foia_ids"])["athr_id"].astype(str).tolist()
    with open(paths["feature_names"], "rb") as f:
        feature_names = list(pickle.load(f))
    diag = pd.read_parquet(paths["feature_diag"])
    assert list(diag["feature"]) == feature_names, "feature ordering mismatch"
    idf_values = diag["idf"].to_numpy().astype(np.float32)
    print(f"  X_foia: {X_foia.shape}   vocab: {len(feature_names):,}")

    df_co = pd.read_csv(COAUTHOR_CSV)
    df_co["processed_text"] = df_co["processed_text"].fillna("").astype(str)
    df_co["athr_id"] = df_co["athr_id"].astype(str)
    X_co = vectorize_in_foia_space(df_co["processed_text"].tolist(),
                                   feature_names, idf_values).astype(np.float64)
    print(f"  X_co: {X_co.shape}   nnz/row mean: {X_co.nnz / X_co.shape[0]:.1f}")

    df_exp = pd.read_stata(args.exposure_dta)[["athr_id", "exposure"]]
    df_exp["athr_id"] = df_exp["athr_id"].astype(str)
    e_foia = (pd.Series(df_exp.set_index("athr_id")["exposure"])
              .reindex(foia_ids).fillna(0).values.astype(np.float64))
    print(f"  Exposure (anchors): mean={e_foia.mean():.4f} sd={e_foia.std():.4f}")

    # ---- KNN predictions for every coauthor row ----
    print("Cosine sim (coauthors -> FOIA)...")
    sim = (X_co @ X_foia.T).toarray().astype(np.float64)
    print("Predicting via K-NN...")
    pred_knn_all = knn_predict_from_sim(sim, e_foia, args.k, args.sharpen, args.floor)

    # ---- Attach to (FOIA, coauthor) pairs ----
    df_map = pd.read_stata(COAUTHORS_DTA)
    df_map["athr_id"] = df_map["athr_id"].astype(str)
    df_map["coauthor_id"] = df_map["coauthor_id"].astype(str)

    foia_idx_by_id = {a: i for i, a in enumerate(foia_ids)}
    co_idx_by_id   = {a: i for i, a in enumerate(df_co["athr_id"].tolist())}

    df = df_map[df_map["coauthor_id"].isin(co_idx_by_id) &
                df_map["athr_id"].isin(foia_idx_by_id)].copy()
    df["foia_pos"] = df["athr_id"].map(foia_idx_by_id)
    df["co_pos"]   = df["coauthor_id"].map(co_idx_by_id)
    df["e_foia_true"] = e_foia[df["foia_pos"].values]
    df["pred_knn"]    = pred_knn_all[df["co_pos"].values]
    df["sim_to_partner"] = sim[df["co_pos"].values, df["foia_pos"].values]
    ranks = (-sim).argsort(axis=1).argsort(axis=1)
    df["partner_rank"] = ranks[df["co_pos"].values, df["foia_pos"].values]
    print(f"  usable pairs: {len(df):,}  (out of {len(df_map):,})")

    print("Counting copubs against author_paper_edges.parquet...")
    df["copubs"] = compute_copubs(df[["athr_id", "coauthor_id"]].copy())
    print(f"  copub distribution: {df['copubs'].value_counts().head().to_dict()}")

    # ---- Optional cluster filter (mirror the '_cfN' subset used downstream) ----
    if args.cluster_filter and args.min_foia_per_cluster >= 1:
        if not os.path.exists(args.cluster_filter):
            raise SystemExit(f"--cluster-filter not found: {args.cluster_filter}")
        cl = pd.read_csv(args.cluster_filter,
                         dtype={"athr_id": str, "cluster_label": int})
        foia_cluster_counts = (
            pd.DataFrame({"athr_id": foia_ids}).merge(cl, on="athr_id", how="inner")
              ["cluster_label"].value_counts()
        )
        kept_clusters = set(
            foia_cluster_counts[foia_cluster_counts >= args.min_foia_per_cluster].index
        )
        n_before = len(df)
        df = df.merge(cl, left_on="coauthor_id", right_on="athr_id",
                      how="left", suffixes=("", "_cl")).drop(columns=["athr_id_cl"])
        n_no_cluster = int(df["cluster_label"].isna().sum())
        keep = df["cluster_label"].notna() & df["cluster_label"].isin(kept_clusters)
        n_kept_clusters = len(kept_clusters)
        n_total_clusters = int(cl["cluster_label"].nunique())
        df = df.loc[keep].drop(columns=["cluster_label"])
        print(f"  cluster filter ({args.cluster_filter}, "
              f"min-foia-per-cluster={args.min_foia_per_cluster}): "
              f"kept {n_kept_clusters}/{n_total_clusters} clusters; "
              f"dropped {n_before - len(df):,}/{n_before:,} pairs "
              f"({100*(n_before-len(df))/n_before:.2f}%; "
              f"{n_no_cluster:,} had no cluster assignment).")

    # ---- Overall metrics ----
    rng = np.random.default_rng(args.seed)
    perm = rng.permutation(len(df))
    m_knn_all = metrics_pair(df["e_foia_true"].values, df["pred_knn"].values, rng_perm=perm)

    # ---- By-copubs table ----
    bins = sorted(set(int(x) for x in args.copub_bins.split(",")))
    print(f"By-copubs bin edges (right-inclusive): {bins}")

    def bin_label(lo, hi):
        return f"({lo}, {hi}]"

    rows_bin = []
    for lo, hi in zip(bins[:-1], bins[1:]):
        mask = (df["copubs"] > lo) & (df["copubs"] <= hi)
        sub = df.loc[mask]
        if len(sub) == 0:
            continue
        m_k = metrics_pair(sub["e_foia_true"].values, sub["pred_knn"].values)
        rows_bin.append({
            "copub_bin": bin_label(lo, hi),
            "n_pairs": len(sub),
            "mean_copubs": sub["copubs"].mean(),
            "corr_knn":   m_k["corr"], "mae_knn":   m_k["mae"],
            "median_rank": float(sub["partner_rank"].median()),
            "pct_top5":   float((sub["partner_rank"] < 5).mean()),
        })
    df_bin = pd.DataFrame(rows_bin)
    df_bin.to_csv(paths["out_bybin"], index=False)
    print(f"Saved by-copubs table: {paths['out_bybin']}")

    # ---- Save pair-level csv (columns needed for downstream figures) ----
    df[["athr_id", "coauthor_id", "e_foia_true", "pred_knn",
        "sim_to_partner", "partner_rank", "copubs"]].to_csv(paths["out_pairs"], index=False)
    print(f"Saved pair-level CSV: {paths['out_pairs']}")

    # ---- Summary txt ----
    n_foia_pool = len(foia_ids)
    filter_line = (
        f"  cluster filter: {args.cluster_filter}   min-foia-per-cluster="
        f"{args.min_foia_per_cluster}"
        if args.cluster_filter and args.min_foia_per_cluster >= 1
        else "  cluster filter: (none)"
    )
    lines = [
        f"Coauthor validation (K-NN)",
        f"  tag={args.tag}   exposure={args.exposure_dta}   K={args.k}   sharpen={args.sharpen}   floor={args.floor}",
        filter_line,
        f"  n_pairs={len(df):,}   n_unique_coauthors={df['coauthor_id'].nunique():,}   "
        f"n_unique_foia={df['athr_id'].nunique()}   n_foia_pool={n_foia_pool}",
        "",
        "--- Overall (all coauthor-FOIA pairs) ---",
        f"  KNN:    corr={m_knn_all['corr']:+.4f}   MAE={m_knn_all['mae']:.5f}   "
        f"MAE(random)={m_knn_all['mae_rand']:.5f}   "
        f"improvement={m_knn_all['mae']-m_knn_all['mae_rand']:+.5f}",
        "",
        "--- Twin-test (partner in coauthor's NN list) ---",
        f"  median partner rank: {float(df['partner_rank'].median()):.1f}   "
        f"(random ~ {n_foia_pool/2:.1f})",
        f"  %% partner is #1 nearest: {100 * (df['partner_rank'] == 0).mean():.1f}%%",
        f"  %% partner in top-5:      {100 * (df['partner_rank'] < 5).mean():.1f}%%",
        "",
        "--- By copubs (right-inclusive bins) ---",
    ]
    for r in rows_bin:
        lines.append(
            f"  {r['copub_bin']:>10s}  n={r['n_pairs']:>6d}  mean_copubs={r['mean_copubs']:5.2f}   "
            f"KNN corr={r['corr_knn']:+.3f} MAE={r['mae_knn']:.4f}   "
            f"median_rank={r['median_rank']:.0f}  pct_top5={r['pct_top5']*100:.1f}%%"
        )
    text = "\n".join(lines) + "\n"
    with open(paths["out_summary"], "w") as f:
        f.write(text)
    print()
    print(text)
    print(f"Saved summary: {paths['out_summary']}")


if __name__ == "__main__":
    main()
