"""
For each FOIA author, dump diagnostics that explain WHY they ended up in
their isolation bucket. Useful for debugging anomalous buckets (e.g. the
mid-q50 bin that hit corr ~0 in the LOOV sweep).

Per-FOIA columns:
  athr_id, iso_bin, isolation (max-sim to other FOIA), exposure
  top3_athr_ids, top3_sims, top3_exposures
  partner_exposure_gap = |exposure - top1_partner_exposure|
  n_text_words
  text_snippet  (first 250 chars)

Produces:
  ../output/foia_isolation_diagnostics_{method}.csv   (full table)
  Prints a sample of N rows per bucket to stdout.

Usage:
  python inspect_isolation_bins.py --method tfidf --sample 8
  python inspect_isolation_bins.py --method tfidf --bin 1 --sample 30  # only mid q50
"""
import argparse
import os
import numpy as np
import pandas as pd
import scipy.sparse

OUT_DIR = "../output"
EXPOSURE_DTA = "../external/exposure_wts/athr_exposure.dta"

TFIDF_FOIA_TEXT = f"{OUT_DIR}/foia_author_text_final.csv"
BERT_FOIA_TEXT  = f"{OUT_DIR}/foia_author_text_unstemmed.csv"


def load_sim(method: str, model_tag: str) -> tuple[np.ndarray, list[str]]:
    if method == "tfidf":
        X = scipy.sparse.load_npz(f"{OUT_DIR}/tfidf_foia.npz").tocsr().astype(np.float32)
        sim = (X @ X.T).toarray().astype(np.float32)
        ids = pd.read_csv(f"{OUT_DIR}/foia_ids_ordered.csv")["athr_id"].astype(str).tolist()
    else:
        X = np.load(f"{OUT_DIR}/bert_foia_{model_tag}.npy").astype(np.float32)
        norms = np.linalg.norm(X, axis=1, keepdims=True); norms[norms == 0] = 1
        X = X / norms
        sim = (X @ X.T).astype(np.float32)
        ids = pd.read_csv(f"{OUT_DIR}/bert_foia_ids_{model_tag}.csv")["athr_id"].astype(str).tolist()
    np.fill_diagonal(sim, -np.inf)
    return sim, ids


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--method", choices=["bert", "tfidf"], default="tfidf")
    ap.add_argument("--model-tag",
                    default="pritamdeka_S-Scibert-snli-multinli-stsb_unstemmed")
    ap.add_argument("--iso-quantiles", default="0.2,0.5,0.8",
                    help="Same defaults as loov_k_sweep.py so bucket labels line up.")
    ap.add_argument("--sample", type=int, default=10,
                    help="Print this many FOIAs per bucket to stdout.")
    ap.add_argument("--bin", type=int, default=None,
                    help="If set, print ONLY this isolation bin (0..3). "
                         "Use 1 to focus on the anomalous mid-q50 bucket.")
    ap.add_argument("--snippet-chars", type=int, default=250)
    args = ap.parse_args()

    sim, foia_ids = load_sim(args.method, args.model_tag)
    n = len(foia_ids)
    print(f"FOIA pool: {n} ({args.method})")

    # Exposure
    df_exp = pd.read_stata(EXPOSURE_DTA)[["athr_id", "exposure"]]
    df_exp["athr_id"] = df_exp["athr_id"].astype(str)
    exp = pd.Series(df_exp.set_index("athr_id")["exposure"]).reindex(foia_ids).fillna(0).values

    # Text -- pull the variant that matches the embedding method
    text_csv = TFIDF_FOIA_TEXT if args.method == "tfidf" else BERT_FOIA_TEXT
    df_txt = pd.read_csv(text_csv)
    df_txt["athr_id"] = df_txt["athr_id"].astype(str)
    text_map = dict(zip(df_txt["athr_id"], df_txt["processed_text"].fillna("").astype(str)))

    # Isolation = max sim to any other FOIA (diagonal already -inf)
    sim_for_iso = np.where(np.isneginf(sim), -1, sim)
    isolation = sim_for_iso.max(axis=1)

    # Bin via quantile cuts (mirror loov_k_sweep)
    iso_q = [float(q) for q in args.iso_quantiles.split(",")]
    iso_cuts = np.quantile(isolation, iso_q)
    iso_bin = np.digitize(isolation, iso_cuts)
    bin_names = [
        "0_most_isolated",
        f"1_mid_q{int(iso_q[1]*100)}",
        f"2_mid_q{int(iso_q[2]*100)}",
        "3_best_connected",
    ]

    # Top-3 neighbors per FOIA
    top3_idx = np.argsort(-sim_for_iso, axis=1)[:, :3]    # (n, 3)
    rows = []
    for i, aid in enumerate(foia_ids):
        text = text_map.get(aid, "")
        n_words = len(text.split())
        snippet = text[:args.snippet_chars].replace("\n", " ")
        if len(text) > args.snippet_chars:
            snippet += "..."
        top3 = top3_idx[i]
        rows.append({
            "athr_id": aid,
            "iso_bin": int(iso_bin[i]),
            "iso_label": bin_names[int(iso_bin[i])],
            "isolation": float(isolation[i]),
            "exposure": float(exp[i]),
            "top1_athr_id": foia_ids[top3[0]],
            "top1_sim":      float(sim_for_iso[i, top3[0]]),
            "top1_exposure": float(exp[top3[0]]),
            "top2_athr_id": foia_ids[top3[1]],
            "top2_sim":      float(sim_for_iso[i, top3[1]]),
            "top2_exposure": float(exp[top3[1]]),
            "top3_athr_id": foia_ids[top3[2]],
            "top3_sim":      float(sim_for_iso[i, top3[2]]),
            "top3_exposure": float(exp[top3[2]]),
            "partner_exposure_gap_top1": float(abs(exp[i] - exp[top3[0]])),
            "n_text_words": n_words,
            "text_snippet": snippet,
        })
    df = pd.DataFrame(rows).sort_values(["iso_bin", "isolation"]).reset_index(drop=True)

    out_csv = f"{OUT_DIR}/foia_isolation_diagnostics_{args.method}.csv"
    df.to_csv(out_csv, index=False)
    print(f"Saved {out_csv}  ({len(df):,} FOIAs)\n")

    # ---- per-bucket summary stats ----
    print("Per-bucket summary:")
    summary = df.groupby("iso_label", observed=True).agg(
        n=("athr_id", "size"),
        mean_isolation=("isolation", "mean"),
        mean_exposure=("exposure", "mean"),
        std_exposure=("exposure", "std"),
        mean_top1_sim=("top1_sim", "mean"),
        mean_n_words=("n_text_words", "mean"),
        median_n_words=("n_text_words", "median"),
        mean_top1_gap=("partner_exposure_gap_top1", "mean"),
    ).round(4)
    print(summary.to_string())
    print()

    # ---- printout per bucket ----
    bins_to_show = [args.bin] if args.bin is not None else sorted(df["iso_bin"].unique())
    for b in bins_to_show:
        sub = df[df["iso_bin"] == b]
        if len(sub) == 0:
            continue
        n_show = min(args.sample, len(sub))
        # Show a spread: smallest, median, largest isolation in the bucket
        sub_show = pd.concat([
            sub.head(n_show // 2),
            sub.tail(n_show - n_show // 2),
        ])
        label = bin_names[b]
        print("=" * 90)
        print(f"BUCKET {b}: {label}   (n={len(sub)})   showing {len(sub_show)} examples")
        print("=" * 90)
        for _, row in sub_show.iterrows():
            print(f"\n  {row['athr_id']}   iso={row['isolation']:.3f}   "
                  f"exposure={row['exposure']:+.4f}   words={row['n_text_words']:,}")
            print(f"    top1: {row['top1_athr_id']} (sim={row['top1_sim']:.3f}, "
                  f"exp={row['top1_exposure']:+.4f})  -> gap={row['partner_exposure_gap_top1']:.4f}")
            print(f"    top2: {row['top2_athr_id']} (sim={row['top2_sim']:.3f}, "
                  f"exp={row['top2_exposure']:+.4f})")
            print(f"    top3: {row['top3_athr_id']} (sim={row['top3_sim']:.3f}, "
                  f"exp={row['top3_exposure']:+.4f})")
            print(f"    text: {row['text_snippet']}")


if __name__ == "__main__":
    main()
