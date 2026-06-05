"""
Side-by-side compare two coauthor-validation runs (baseline vs --tag-suffixed).

Usage:
  python compare_validation.py                       # compares '' vs 'restricted'
  python compare_validation.py --b '' --r my_tag     # compares '' vs 'my_tag'

Reads `coauthor_validation_pairs_tfidf{tag}.csv` for each tag and recomputes
metrics (so we don't depend on summary-file formatting). Prints a delta table
and writes `compare_validation_<b>_vs_<r>.txt`.
"""
import argparse
import os
import numpy as np
import pandas as pd

OUT_DIR = "../../output"


def _norm_tag(tag: str) -> str:
    if tag and not tag.startswith("_"):
        tag = "_" + tag
    return tag


def metrics_from_pairs(pairs_csv: str, n_foia: int, seed: int = 8975) -> dict:
    df = pd.read_csv(pairs_csv)
    rng = np.random.default_rng(seed)
    perm = rng.permutation(len(df))
    abs_err_rand = np.abs(df["e_foia_true"].values[perm] - df["e_co_imputed"].values)
    return {
        "n_pairs":           len(df),
        "n_unique_coauthors":df["coauthor_id"].nunique(),
        "n_unique_foia":     df["athr_id"].nunique(),
        "corr_imputed_true": df[["e_foia_true", "e_co_imputed"]].corr().iloc[0, 1],
        "mae_paired":        df["abs_err"].mean(),
        "mae_random":        abs_err_rand.mean(),
        "mean_rank":         df["partner_rank"].mean(),
        "median_rank":       float(df["partner_rank"].median()),
        "pct_top1":          (df["partner_rank"] == 0).mean(),
        "pct_top5":          (df["partner_rank"] < 5).mean(),
        "pct_top10":         (df["partner_rank"] < 10).mean(),
        "random_rank_mean":  (n_foia - 1) / 2.0,
    }


def fmt(v, kind):
    if kind == "int":     return f"{int(v):,}"
    if kind == "pct":     return f"{v*100:.2f}%"
    if kind == "f4":      return f"{v:.4f}"
    if kind == "f5":      return f"{v:.5f}"
    if kind == "f1":      return f"{v:.1f}"
    return str(v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--b", default="", help="Baseline tag (default = '').")
    ap.add_argument("--r", default="restricted", help="Restricted tag.")
    args = ap.parse_args()

    tag_b = _norm_tag(args.b)
    tag_r = _norm_tag(args.r)

    pairs_b = f"{OUT_DIR}/coauthor_validation_pairs_tfidf{tag_b}.csv"
    pairs_r = f"{OUT_DIR}/coauthor_validation_pairs_tfidf{tag_r}.csv"
    foia_ids_b = f"{OUT_DIR}/foia_ids_ordered{tag_b}.csv"
    foia_ids_r = f"{OUT_DIR}/foia_ids_ordered{tag_r}.csv"

    for p in (pairs_b, pairs_r, foia_ids_b, foia_ids_r):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")

    n_foia_b = len(pd.read_csv(foia_ids_b))
    n_foia_r = len(pd.read_csv(foia_ids_r))

    m_b = metrics_from_pairs(pairs_b, n_foia_b)
    m_r = metrics_from_pairs(pairs_r, n_foia_r)

    rows = [
        ("n_pairs",                          "int", "higher=more coverage"),
        ("n_unique_coauthors",               "int", "higher=more coverage"),
        ("n_unique_foia",                    "int", "higher=more coverage"),
        ("corr_imputed_true",                "f4",  "higher=better"),
        ("mae_paired",                       "f5",  "lower=better"),
        ("mae_random",                       "f5",  "benchmark"),
        ("mean_rank",                        "f1",  "lower=better"),
        ("median_rank",                      "f1",  "lower=better"),
        ("pct_top1",                         "pct", "higher=better"),
        ("pct_top5",                         "pct", "higher=better"),
        ("pct_top10",                        "pct", "higher=better"),
        ("random_rank_mean",                 "f1",  "benchmark"),
    ]

    lines = []
    header = f"{'metric':<22} {'baseline':>14} {'restricted':>14} {'delta':>14}   direction"
    lines.append(header)
    lines.append("-" * len(header))
    for key, kind, direction in rows:
        b, r = m_b[key], m_r[key]
        delta = r - b
        delta_s = (f"{delta*100:+.2f}pp" if kind == "pct"
                   else f"{int(delta):+,}" if kind == "int"
                   else f"{delta:+.4f}" if kind == "f4"
                   else f"{delta:+.5f}" if kind == "f5"
                   else f"{delta:+.1f}")
        lines.append(
            f"{key:<22} {fmt(b,kind):>14} {fmt(r,kind):>14} {delta_s:>14}   {direction}"
        )

    body = "\n".join(lines)
    print(body)

    out_path = (
        f"{OUT_DIR}/compare_validation"
        f"_{args.b or 'baseline'}_vs_{args.r or 'restricted'}.txt"
    )
    with open(out_path, "w") as f:
        f.write(body + "\n")
    print(f"\nSaved: {out_path}")


if __name__ == "__main__":
    main()
