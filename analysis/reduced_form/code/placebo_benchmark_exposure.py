import numpy as np
import pandas as pd
import scipy.sparse as sp

REN = {"acrylamide/bis solution": "acrylamide-bis solution", "dmem/f-12": "dmem-f-12"}
STEM = "hc_all3_cf_k3"

bt = pd.read_stata("../external/betas/did_coefs_eb_price_all3.dta")[["category", "b_eb", "b_eb_pl"]]
bt["category"] = bt["category"].astype(str).replace(REN)

mk = pd.read_csv(f"../external/exposure/imputed_shares_markets_{STEM}.csv").merge(bt, on="category", how="left")
assert mk["b_eb_pl"].notna().all() and np.allclose(mk["g"], mk["b_eb"])

S = sp.load_npz(f"../external/exposure/imputed_shares_matrix_{STEM}.npz").tocsr()
imp = pd.read_csv(f"../external/exposure/final_imputed_shift_share_{STEM}.csv", dtype={"athr_id": str})
assert np.allclose(S @ mk["b_eb"].to_numpy(), imp["exposure_ss"])
imp["exposure_pl"] = S @ mk["b_eb_pl"].to_numpy()

bc = pd.read_stata("../external/real_exposure/athr_exposure_by_category_hc_all3.dta")
bc["athr_id"] = bc["athr_id"].astype(str)
bc["category"] = bc["category"].astype(str).replace(REN)
bc = bc.merge(bt, on="category", how="inner")
bc["exposure_pl"] = bc["mkt_spend_shr"] * bc["b_eb_pl"]
foia = bc.groupby("athr_id", as_index=False)["exposure_pl"].sum()

out = pd.concat([foia, imp.loc[~imp["athr_id"].isin(foia["athr_id"]), ["athr_id", "exposure_pl"]]])
out.to_csv("../temp/exposure_pl.csv", index=False)
print(f"FOIA PIs: {len(foia)}  imputed PIs: {len(out) - len(foia)}")
