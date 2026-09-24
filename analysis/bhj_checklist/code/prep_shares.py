import numpy as np
import pandas as pd
import pyreadstat
import scipy.sparse as sp

STEM = "hc_all3_cf_k3"
SAMP = "all_jrnls_r1_r2"

ids, _ = pyreadstat.read_dta(f"../external/rf/prepped_samples/es_{SAMP}.dta", usecols=["athr_id"])
ids = set(ids["athr_id"].astype(str))

univ = pd.read_csv(f"../external/exposure/final_imputed_shift_share_{STEM}.csv", dtype={"athr_id": str})
S = sp.load_npz(f"../external/exposure/imputed_shares_matrix_{STEM}.npz").tocsr()
assert S.shape[0] == len(univ)

keep = univ["athr_id"].isin(ids).to_numpy()
S = S[keep].tocoo()
univ = univ.loc[keep].reset_index(drop=True)

mkts = pd.read_csv(f"../external/exposure/imputed_shares_markets_{STEM}.csv")
mkts["market_idx"] = mkts["market_idx"] + 1

long = pd.DataFrame({
    "athr_id": univ["athr_id"].to_numpy()[S.row],
    "market_idx": S.col + 1,
    "s_imp": S.data,
})
long = long[long["s_imp"] > 0].merge(mkts[["market_idx", "category"]], on="market_idx")
long.to_stata("../temp/imputed_shares_long.dta", write_index=False, version=118)

mkts.rename(columns={"g": "g_imp", "s_bar": "s_bar_universe"}).to_stata(
    "../temp/markets.dta", write_index=False, version=118)

print(f"sample PIs: {len(ids):,}; with imputed shares: {univ.shape[0]:,}; "
      f"PI-market rows: {len(long):,}; markets: {len(mkts)}")
