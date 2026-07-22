"""
Convert match_diagnostics_{tag}.parquet -> .dta so Stata can merge max_sim.

Used by analysis/reduced_form/code/analysis.do to build confidence quartiles
for the confidence-stratified pooled DiD.

Usage:
  python export_diag_to_dta.py --tag restricted
"""
import argparse
import os
import pandas as pd

OUT_DIR = "../../output"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="")
    args = ap.parse_args()
    tag = args.tag
    if tag and not tag.startswith("_"):
        tag = "_" + tag

    src = f"{OUT_DIR}/match_diagnostics{tag}.parquet"
    dst = f"{OUT_DIR}/match_diagnostics{tag}.dta"
    if not os.path.exists(src):
        raise SystemExit(f"missing: {src}")

    df = pd.read_parquet(src)
    keep = ["athr_id", "max_sim", "mean_topk_sim", "n_foia_above_floor", "unmatched"]
    df = df[[c for c in keep if c in df.columns]].copy()
    df["athr_id"] = df["athr_id"].astype(str)
    if "unmatched" in df.columns:
        df["unmatched"] = df["unmatched"].astype("int8")
    print(f"Writing {len(df):,} rows  cols={list(df.columns)}  -> {dst}")
    df.to_stata(dst, write_index=False, version=118)
    print("Done.")


if __name__ == "__main__":
    main()
