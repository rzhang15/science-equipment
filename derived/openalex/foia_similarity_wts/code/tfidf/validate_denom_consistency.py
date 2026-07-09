"""
Cross-denominator consistency check for the three imputed exposure measures:
  - all         (denom = tot_spend)
  - hc          (denom = tot_hc_spend, keep=1 categories)
  - treated_hc  (denom = tot_treated_spend, categories with a beta)

Reports:
  1. Pearson + Spearman corr matrix over the imputed universe
  2. Same corr matrix over observed FOIA PIs
  3. Sign concordance (fraction of authors with same sign across all three)
  4. Rank agreement in the top decile / bottom decile
  5. Distribution overlap (mean, sd, quartiles) side-by-side
"""
import os
import numpy as np
import pandas as pd
from scipy.stats import spearmanr

OUT_DIR = "../../output"
EXT_DIR = "../../external/exposure_wts"
DENOMS = ["all", "hc", "treated_hc"]


def load_imputed(d):
    df = pd.read_csv(f"{OUT_DIR}/final_imputed_exposure_{d}.csv",
                     dtype={"athr_id": str})
    return df[["athr_id", "exposure"]].rename(columns={"exposure": f"imp_{d}"})


def load_observed(d):
    df = pd.read_stata(f"{EXT_DIR}/athr_exposure_{d}.dta")
    df["athr_id"] = df["athr_id"].astype(str)
    return df[["athr_id", "exposure"]].rename(columns={"exposure": f"obs_{d}"})


def corr_block(df, cols, label):
    print(f"\n=== {label}  (n={len(df):,}) ===")
    print("Pearson:")
    print(df[cols].corr().round(3).to_string())
    print("Spearman:")
    rho = np.zeros((len(cols), len(cols)))
    for i, a in enumerate(cols):
        for j, b in enumerate(cols):
            rho[i, j] = spearmanr(df[a], df[b], nan_policy="omit")[0]
    print(pd.DataFrame(rho, index=cols, columns=cols).round(3).to_string())


def sign_concordance(df, cols):
    signs = np.sign(df[cols].to_numpy())
    same = (signs == signs[:, [0]]).all(axis=1) & (signs[:, 0] != 0)
    return same.mean()


def top_bot_overlap(df, cols, q=0.90):
    ranks = df[cols].rank(pct=True)
    top = (ranks >= q).all(axis=1).sum()
    bot = (ranks <= 1 - q).all(axis=1).sum()
    n_expected = int(round((1 - q) * len(df)))
    print(f"  expected under independence: ~{n_expected}")
    print(f"  top-{int((1-q)*100)}%  in ALL three: {top:,}  ({100*top/n_expected:.1f}× expected)")
    print(f"  bot-{int((1-q)*100)}%  in ALL three: {bot:,}  ({100*bot/n_expected:.1f}× expected)")


def main():
    print("Loading imputed exposures...")
    dfs = [load_imputed(d) for d in DENOMS]
    df_imp = dfs[0]
    for d in dfs[1:]:
        df_imp = df_imp.merge(d, on="athr_id", how="inner")
    imp_cols = [f"imp_{d}" for d in DENOMS]

    print("Loading observed FOIA exposures...")
    dfs = [load_observed(d) for d in DENOMS]
    df_obs = dfs[0]
    for d in dfs[1:]:
        df_obs = df_obs.merge(d, on="athr_id", how="inner")
    obs_cols = [f"obs_{d}" for d in DENOMS]

    # ---- 1-2: correlation matrices ----
    corr_block(df_imp, imp_cols, "IMPUTED (universe)")
    corr_block(df_obs, obs_cols, "OBSERVED (FOIA PIs)")

    # ---- 3: sign concordance ----
    print("\n=== SIGN CONCORDANCE ===")
    print(f"  universe: {sign_concordance(df_imp, imp_cols):.3f} "
          f"of {len(df_imp):,} authors have same sign across all 3 denominators")
    print(f"  FOIA    : {sign_concordance(df_obs, obs_cols):.3f} "
          f"of {len(df_obs):,} PIs      have same sign across all 3 denominators")

    # ---- 4: tail agreement ----
    print("\n=== TOP-10% / BOT-10% AGREEMENT (universe) ===")
    top_bot_overlap(df_imp, imp_cols, q=0.90)

    # ---- 5: distributions side-by-side ----
    print("\n=== IMPUTED DISTRIBUTIONS (universe) ===")
    print(df_imp[imp_cols].describe(percentiles=[.1, .25, .5, .75, .9]).round(5).to_string())
    print("\n=== OBSERVED DISTRIBUTIONS (FOIA) ===")
    print(df_obs[obs_cols].describe(percentiles=[.1, .25, .5, .75, .9]).round(5).to_string())

    # ---- 6: imputed vs observed for FOIA PIs (per denominator) ----
    print("\n=== IMPUTED vs OBSERVED for FOIA PIs ===")
    print("(Sanity check: FOIA PIs get their observed value replaced by imputed only")
    print(" via `replace imputed = exposure if !mi(exposure)` in analysis.do.")
    print(" Here we look at imputed values BEFORE that substitution.)")
    merged = df_imp.merge(df_obs, on="athr_id", how="inner")
    for d in DENOMS:
        a, b = f"imp_{d}", f"obs_{d}"
        m = merged[[a, b]].dropna()
        pearson = m.corr().iloc[0, 1]
        sp = spearmanr(m[a], m[b])[0]
        print(f"  {d:12s}  n={len(m):3d}   pearson={pearson:+.3f}   spearman={sp:+.3f}")


if __name__ == "__main__":
    main()
