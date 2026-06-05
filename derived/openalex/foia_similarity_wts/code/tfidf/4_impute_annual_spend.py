"""
Impute annual lab spend for every universe author, 2010-2019, using the
same TF-IDF weight matrix as 3_impute_exposure.py.

Three target variables, all from ../../external/exposure_wts/athr_spend.dta:
  spend         total spend (consumables + non)
  lab_spend     lab portion only
  spend_keep    high-confidence subset of spend

For each (year, variable) we do a MASKED weighted average:
  numer = W @ (E * M)
  denom = W @ M
  imputed[i] = numer[i] / denom[i]   (NaN if denom == 0)
where M is the per-FOIA observed mask for that year. This re-normalizes
the top-K weights over only the FOIAs with observed spend for the year,
so an unbalanced panel doesn't bias predictions toward 0.

Output:  ../../output/imputed_annual_spend.csv
  long format: athr_id, year, spend, lab_spend, spend_keep
"""
import argparse
import os
import time
import numpy as np
import pandas as pd
import scipy.sparse

OUT_DIR           = "../../output"
ATHR_SPEND_FILE   = "../../external/exposure_wts/athr_spend.dta"

YEAR_MIN, YEAR_MAX = 2010, 2019
SPEND_VARS = ["spend", "lab_spend", "spend_keep"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="",
                    help="Suffix matching the --tag used by 1_vectorize.py, "
                         "2_similarity_wts.py, and 3_impute_exposure.py. "
                         "Empty = baseline artifacts.")
    args = ap.parse_args()

    tag = args.tag
    if tag and not tag.startswith("_"):
        tag = "_" + tag

    weights_file      = f"{OUT_DIR}/weight_matrix{tag}.npz"
    universe_ids_file = f"{OUT_DIR}/universe_ids{tag}.parquet"
    foia_ids_file     = f"{OUT_DIR}/foia_ids_ordered{tag}.csv"
    out_file          = f"{OUT_DIR}/imputed_annual_spend{tag}.csv"

    t0 = time.time()

    for p in (weights_file, universe_ids_file, foia_ids_file, ATHR_SPEND_FILE):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")

    print(f"Loading weight matrix and id alignment (tag={args.tag!r})...")
    W = scipy.sparse.load_npz(weights_file).tocsr().astype(np.float32)
    df_univ = pd.read_parquet(universe_ids_file)
    df_univ["athr_id"] = df_univ["athr_id"].astype(str)
    df_foia = pd.read_csv(foia_ids_file)
    df_foia["athr_id"] = df_foia["athr_id"].astype(str)
    print(f"  W: {W.shape}   universe: {len(df_univ):,}   FOIA: {len(df_foia)}")
    assert W.shape == (len(df_univ), len(df_foia)), \
        "weight matrix shape doesn't match id files"

    print("Loading FOIA annual spend panel...")
    df_spend = pd.read_stata(ATHR_SPEND_FILE)
    df_spend["athr_id"] = df_spend["athr_id"].astype(str)
    df_spend["year"] = df_spend["year"].astype(int)
    df_spend = df_spend[(df_spend["year"] >= YEAR_MIN) &
                        (df_spend["year"] <= YEAR_MAX)]
    in_W = df_spend["athr_id"].isin(set(df_foia["athr_id"]))
    print(f"  panel cells (FOIA, year): {len(df_spend):,}")
    print(f"  unique FOIAs in panel: {df_spend['athr_id'].nunique()}")
    print(f"  cells from FOIAs in weight matrix: {in_W.sum():,} "
          f"({in_W.mean()*100:.1f}%)")

    # ---- per-year imputation ----
    print(f"\nImputing {len(SPEND_VARS)} vars x "
          f"{YEAR_MAX - YEAR_MIN + 1} years...")
    out_blocks = []
    for year in range(YEAR_MIN, YEAR_MAX + 1):
        sub = df_spend[df_spend["year"] == year]
        # Align FOIA spend to the weight matrix's column order. Missing
        # FOIAs (not observed this year) get NaN -> filtered by mask.
        aligned = sub.set_index("athr_id").reindex(df_foia["athr_id"])

        block = pd.DataFrame({
            "athr_id": df_univ["athr_id"].values,
            "year": np.int16(year),
        })
        n_observed = (~aligned[SPEND_VARS[0]].isna()).sum()

        for var in SPEND_VARS:
            E = aligned[var].fillna(0).to_numpy(dtype=np.float32)
            M = (~aligned[var].isna()).astype(np.float32).to_numpy()
            numer = W @ (E * M)
            denom = W @ M
            with np.errstate(divide="ignore", invalid="ignore"):
                imp = np.where(denom > 0, numer / denom, np.nan)
            block[var] = imp.astype(np.float32)

        n_imputed = int(np.isfinite(block[SPEND_VARS[0]]).sum())
        print(f"  {year}: {int(n_observed):>3} FOIAs observed, "
              f"{n_imputed:>10,} universe authors imputed "
              f"({n_imputed/len(df_univ)*100:.1f}%)")
        out_blocks.append(block)

    df_out = pd.concat(out_blocks, ignore_index=True)
    print(f"\nFinal panel: {len(df_out):,} rows  "
          f"({df_out.memory_usage(deep=True).sum()/1e9:.2f} GB in memory)")

    # ---- sanity diagnostics ----
    print("\nImputed distribution across all (universe x year):")
    print(df_out[SPEND_VARS].describe().round(0).to_string())
    nan_counts = df_out[SPEND_VARS].isna().sum()
    print(f"\nNaN counts (universe rows with no qualifying neighbors):")
    for v, n in nan_counts.items():
        print(f"  {v}: {n:,} ({n / len(df_out) * 100:.2f}%)")

    print(f"\nSaving {out_file}...")
    df_out.to_csv(out_file, index=False)
    print(f"Done in {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()
