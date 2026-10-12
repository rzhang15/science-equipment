"""Check saved RF funding groups against independently computed baseline medians.

Run after analysis.do splits full or analysis.do splits pi.
"""
from pathlib import Path
import argparse
import numpy as np
import pandas as pd

parser = argparse.ArgumentParser()
parser.add_argument("measure", choices=["full", "pi"])
parser.add_argument("--reference", type=Path)
parser.add_argument("--save", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
rows = []
for suffix in ("", "_public"):
    panel = root / f"analysis/rf_heterogeneity/temp/es_all_jrnls_r1_r2{suffix}.dta"
    cols = ["athr_id", "nih_name_matched", "nih_funding_baseline", "nih_funding_baseline_pi",
            "nih_baseline_measure", "pre_nihd", "high_nihd", "low_nihd", "nih_grants_baseline", "pre_nihg"]
    d = pd.read_stata(panel, columns=cols, convert_categoricals=False).drop_duplicates("athr_id")
    assert d.nih_baseline_measure.eq(args.measure).all()
    selected = d["nih_funding_baseline_pi" if args.measure == "pi" else "nih_funding_baseline"]
    matched = d.nih_name_matched.eq(1)
    positive = matched & selected.gt(0) & selected.notna()
    median = selected[positive].median()
    expected_high = pd.Series(np.nan, index=d.index)
    expected_high[matched] = 0
    expected_high[positive] = selected[positive].ge(median).astype(int)
    np.testing.assert_allclose(d.high_nihd, expected_high, equal_nan=True)
    np.testing.assert_allclose(d.low_nihd, 1 - expected_high, equal_nan=True)
    np.testing.assert_allclose(d.pre_nihd, selected.where(positive), equal_nan=True)
    np.testing.assert_allclose(d.pre_nihg, d.nih_grants_baseline.where(matched & d.nih_grants_baseline.gt(0)), equal_nan=True)
    assert (d.nih_funding_baseline_pi.dropna() >= 0).all()
    available = d.nih_funding_baseline_pi.notna() & d.nih_funding_baseline.notna()
    assert (d.loc[available, "nih_funding_baseline_pi"] <= d.loc[available, "nih_funding_baseline"] + 1e-5).all()
    d["sample"] = "all" + suffix
    rows.append(d[["sample", "athr_id", "high_nihd"]])
    print(args.measure, "all" + suffix, "median", median, "matched PIs", matched.sum(), "high", d.high_nihd.sum())
result = pd.concat(rows)
if args.reference:
    reference = pd.read_csv(args.reference, dtype={"athr_id": str})
    z = result.merge(reference, on=["sample", "athr_id"], validate="one_to_one", suffixes=("", "_ref"))
    assert len(z) == len(reference) == len(result)
    changed = z.high_nihd.notna() & z.high_nihd_ref.notna() & z.high_nihd.ne(z.high_nihd_ref)
    print("PIs switching funding groups:", z.loc[changed].groupby("sample").size().to_dict())
if args.save:
    result.to_csv(args.save, index=False)
print("NIH baseline selection checks passed")
