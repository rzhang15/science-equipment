"""
Author-level life-science mask: the same lexicon as 3_filter_life_science.py,
applied to each author's own TF-IDF vector instead of their cluster's top
terms. Cluster membership plays no role, so wet authors inside dropped
clusters survive and dry authors inside kept clusters are cut.

Keep rule (either clause suffices):
  top-terms : >= --min-core BIO_CORE hits among the author's --top-terms
              highest-TF-IDF features AND anti hits <= core hits (the cluster
              rule, applied per person).
  core-mass : core TF-IDF mass share >= --min-core-shr AND anti mass < core
              mass. This rescues bench authors whose idiosyncratic top terms
              (hcn, auxin, iga, ...) miss the lexicon stems -- TF-IDF
              downweights the generic core vocabulary (cell, protein) that
              dominated the cluster centroids the lexicon was written
              against -- while anti-dominated dry authors stay dropped.

A kept author is then vetoed by --clin-min when CLINICAL_PRACTICE mass
exceeds BENCH_METHODS mass: RCTs, case series and health-services research
are life science by subject matter (their anatomy/disease nouns sit in
BIO_CORE) but are not lab work, so neither clause above ever cuts them.
--require-bench additionally demands positive bench mass from everyone, a
much stronger cut; both are calibrated so the FOIA anchor PIs survive.

Continuous scores (share of TF-IDF mass on core / adjacent / anti features)
are saved alongside the binary keep flag for use as weights downstream.

Inputs (row-aligned, from 1_vectorize.py):
  ../output/tfidf_matrix.npz
  ../output/feature_names.pkl
  ../output/author_ids_aligned.parquet

Outputs:
  ../output/author_ls_scores_indiv.csv    athr_id, hits, mass shares, keep
  ../output/author_ls_authors_indiv.csv   kept athr_ids only -- feed to
                                          4_impute_shift_share.py --ls-filter
                                          with --ls-sfx _lsa
"""
import argparse
import importlib.util
import os
import pickle

import numpy as np
import pandas as pd
import scipy.sparse as sp

OUT_DIR = "../output"

spec = importlib.util.spec_from_file_location(
    "ls_filter", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              "3_filter_life_science.py"))
ls_filter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ls_filter)


def classify_vocab(feature_names):
    """Per-feature class flags under score_terms' token rule: core/adjacent
    are mutually exclusive (core wins), anti is independent."""
    n = len(feature_names)
    is_core = np.zeros(n, bool)
    is_adj = np.zeros(n, bool)
    is_anti = np.zeros(n, bool)
    for j, term in enumerate(feature_names):
        tokens = term.split()
        if any(t in ls_filter.BIO_CORE for t in tokens):
            is_core[j] = True
        elif any(t in ls_filter.BIO_ADJACENT for t in tokens):
            is_adj[j] = True
        if any(t in ls_filter.ANTI_LEXICON for t in tokens):
            is_anti[j] = True
    return is_core, is_adj, is_anti


def top_term_hits(M, is_core, is_adj, is_anti, k_top):
    n = M.shape[0]
    core_hits = np.zeros(n, np.int16)
    adj_hits = np.zeros(n, np.int16)
    anti_hits = np.zeros(n, np.int16)
    indptr, indices, data = M.indptr, M.indices, M.data
    for i in range(n):
        lo, hi = indptr[i], indptr[i + 1]
        nnz = hi - lo
        if nnz == 0:
            continue
        if nnz > k_top:
            sel = np.argpartition(data[lo:hi], nnz - k_top)[nnz - k_top:]
            cols = indices[lo + sel]
        else:
            cols = indices[lo:hi]
        core_hits[i] = is_core[cols].sum()
        adj_hits[i] = is_adj[cols].sum()
        anti_hits[i] = is_anti[cols].sum()
    return core_hits, adj_hits, anti_hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--top-terms", type=int, default=15,
                    help="Number of an author's highest-TF-IDF features to "
                         "score, mirroring the 15 top terms per cluster that "
                         "3_filter_life_science.py reads.")
    ap.add_argument("--min-core", type=int, default=1,
                    help="Minimum BIO_CORE hits among the author's top terms. "
                         "Same default as the cluster rule.")
    ap.add_argument("--min-core-shr", type=float, default=0.01,
                    help="Core-mass rescue clause: also keep authors with at "
                         "least this share of TF-IDF mass on BIO_CORE features "
                         "when anti mass is smaller. Default calibrated so the "
                         "FOIA anchor PIs (known lab purchasers) are almost "
                         "never dropped. 0 disables the clause.")
    ap.add_argument("--always-keep", default="",
                    help="csv with an athr_id column; these authors are kept "
                         "regardless of the rule (e.g. the FOIA anchor "
                         "roster). Flagged in the forced column of the scores "
                         "output.")
    ap.add_argument("--clin-min", type=float, default=0.01,
                    help="Clinical-dominance veto: drop an otherwise-kept "
                         "author when CLINICAL_PRACTICE mass exceeds "
                         "BENCH_METHODS mass and is at least this share. "
                         "Targets RCTs, case series and health-services work, "
                         "which the core-vs-anti rule keeps on anatomy/disease "
                         "nouns alone. Calibrated on the FOIA anchors: 0.01 "
                         "keeps 100% of them (universe 88.3% -> 77.6%). "
                         "0 disables the veto.")
    ap.add_argument("--require-bench", type=float, default=0.0,
                    help="ALSO require this share of TF-IDF mass on "
                         "BENCH_METHODS stems (lab methods/reagents/model "
                         "systems, not biological subject matter). 0 = off, "
                         "the default: the mask then asks 'is this life "
                         "science', which clinical trials and epidemiology "
                         "pass on anatomy/disease nouns alone. Turning it on "
                         "asks 'does this person run a wet lab' -- a much "
                         "smaller sample. Calibration on the FOIA anchors "
                         "(known lab purchasers): 0.001 keeps 98.5% of them "
                         "and 52% of the universe; 0.005 keeps 97.6% and 47%; "
                         "0.01 starts cutting real labs (88%).")
    ap.add_argument("--out-sfx", default="",
                    help="Suffix for the output files, e.g. '_bench' writes "
                         "author_ls_{scores,authors}_indiv_bench.csv. Empty "
                         "overwrites the default mask.")
    args = ap.parse_args()

    print("Loading TF-IDF artifacts ...")
    M = sp.load_npz(f"{OUT_DIR}/tfidf_matrix.npz").tocsr()
    feature_names = pickle.load(open(f"{OUT_DIR}/feature_names.pkl", "rb"))
    ids = pd.read_parquet(f"{OUT_DIR}/author_ids_aligned.parquet")
    ids["athr_id"] = ids["athr_id"].astype(str)
    assert M.shape[0] == len(ids), (M.shape, len(ids))
    print(f"  matrix {M.shape[0]:,} x {M.shape[1]:,}  nnz {M.nnz:,}")

    is_core, is_adj, is_anti = classify_vocab(feature_names)
    is_bench = np.array([any(t in ls_filter.BENCH_METHODS for t in term.split())
                         for term in feature_names], bool)
    is_clin = np.array([any(t in ls_filter.CLINICAL_PRACTICE for t in term.split())
                        for term in feature_names], bool)
    print(f"  vocab classes: core={is_core.sum():,}  adj={is_adj.sum():,}  "
          f"anti={is_anti.sum():,}  bench={is_bench.sum():,}  "
          f"clin={is_clin.sum():,}")

    tot_mass = np.asarray(M.sum(axis=1)).ravel()
    safe_tot = np.maximum(tot_mass, 1e-12)
    core_shr = np.asarray(M @ is_core.astype(np.float64)).ravel() / safe_tot
    adj_shr = np.asarray(M @ is_adj.astype(np.float64)).ravel() / safe_tot
    anti_shr = np.asarray(M @ is_anti.astype(np.float64)).ravel() / safe_tot
    bench_shr = np.asarray(M @ is_bench.astype(np.float64)).ravel() / safe_tot
    clin_shr = np.asarray(M @ is_clin.astype(np.float64)).ravel() / safe_tot

    print(f"Scoring top {args.top_terms} terms per author ...")
    core_hits, adj_hits, anti_hits = top_term_hits(
        M, is_core, is_adj, is_anti, args.top_terms)

    keep_top = (core_hits >= args.min_core) & (anti_hits <= core_hits)
    keep_mass = np.zeros(len(ids), bool)
    if args.min_core_shr > 0:
        keep_mass = (core_shr >= args.min_core_shr) & (anti_shr < core_shr)
    empty = tot_mass <= 0
    keep = (keep_top | keep_mass) & ~empty
    if args.clin_min > 0:
        veto = (clin_shr > bench_shr) & (clin_shr >= args.clin_min)
        print(f"  clinical-dominance veto (clin>bench & clin >= "
              f"{args.clin_min}): {(keep & veto).sum():,} otherwise-kept "
              f"authors cut")
        keep &= ~veto
    if args.require_bench > 0:
        has_bench = bench_shr >= args.require_bench
        print(f"  bench requirement (bench_shr >= {args.require_bench}): "
              f"{(keep & ~has_bench).sum():,} otherwise-kept authors cut")
        keep &= has_bench
    forced = np.zeros(len(ids), bool)
    if args.always_keep:
        ak = set(pd.read_csv(args.always_keep, dtype={"athr_id": str})["athr_id"])
        forced = ids["athr_id"].isin(ak).to_numpy() & ~keep & ~empty
        keep |= forced
        print(f"  always-keep list ({args.always_keep}): {len(ak)} ids, "
              f"{forced.sum()} force-kept beyond the rule")
    print(f"  kept {keep.sum():,}/{len(ids):,} authors  "
          f"(top-terms clause {keep_top.sum():,}, rescued by core-mass "
          f"clause {(keep_mass & ~keep_top).sum():,}, forced {forced.sum():,}; "
          f"dropped {(~keep).sum():,}, of which {empty.sum():,} empty rows)")

    scores = pd.DataFrame({
        "athr_id": ids["athr_id"],
        "core_hits": core_hits,
        "adj_hits": adj_hits,
        "anti_hits": anti_hits,
        "core_shr": core_shr,
        "adj_shr": adj_shr,
        "anti_shr": anti_shr,
        "bench_shr": bench_shr,
        "clin_shr": clin_shr,
        "keep": keep.astype(int),
        "forced": forced.astype(int),
    })
    sfx = args.out_sfx
    scores.to_csv(f"{OUT_DIR}/author_ls_scores_indiv{sfx}.csv", index=False)
    scores.loc[scores["keep"] == 1, ["athr_id"]].to_csv(
        f"{OUT_DIR}/author_ls_authors_indiv{sfx}.csv", index=False)
    print(f"Saved {OUT_DIR}/author_ls_scores_indiv{sfx}.csv")
    print(f"Saved {OUT_DIR}/author_ls_authors_indiv{sfx}.csv")

    cl_path = f"{OUT_DIR}/author_static_clusters_30.csv"
    ls_path = f"{OUT_DIR}/author_static_clusters_30_ls.csv"
    if os.path.exists(cl_path):
        cl = pd.read_csv(cl_path, dtype={"athr_id": str})
        m = scores.merge(cl, on="athr_id", how="left")
        tab = m.groupby("cluster_label", dropna=False)["keep"].agg(["mean", "size"])
        tab.columns = ["keep_rate", "n"]
        print("\nAuthor-level keep rate by k=30 cluster:")
        print(tab.round(3).to_string())
    if os.path.exists(ls_path):
        ls = set(pd.read_csv(ls_path, dtype={"athr_id": str})["athr_id"])
        in_cluster_mask = scores["athr_id"].isin(ls)
        agree = (scores["keep"].astype(bool) == in_cluster_mask).mean()
        print(f"\nAgreement with cluster-level _ls mask: {agree:.1%}")
        print(f"  kept here but cluster-dropped: "
              f"{(scores['keep'].astype(bool) & ~in_cluster_mask).sum():,}")
        print(f"  dropped here but cluster-kept: "
              f"{(~scores['keep'].astype(bool) & in_cluster_mask).sum():,}")


if __name__ == "__main__":
    main()
