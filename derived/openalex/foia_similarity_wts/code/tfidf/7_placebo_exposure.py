
import argparse
import os

import numpy as np
import pandas as pd


OUT_DIR = "../../output"
FOIA_EXPOSURE_FILE = "../../external/exposure_wts/athr_exposure_{version}.dta"

VERSIONS = ["hc", "all", "treated_hc"]


def load_foia(version):
    df = pd.read_stata(FOIA_EXPOSURE_FILE.format(version=version))
    df["athr_id"] = df["athr_id"].astype(str)
    df = df[["athr_id", "exposure", "mkt_spend_shr"]].dropna()
    return df.drop_duplicates("athr_id").reset_index(drop=True)


def load_universe(stem):
    path = f"{OUT_DIR}/final_imputed_shift_share{stem}.csv"
    if not os.path.exists(path):
        raise SystemExit(f"missing {path} -- run 4_impute_shift_share.py first")
    df = pd.read_csv(path, dtype={"athr_id": str})
    return df[["athr_id", "exposure_ss", "sum_imputed_shares"]]


def draw(rng, univ, foia, is_foia, mode, jitter):
    n = int((~is_foia).sum())
    out = univ.copy()

    if mode == "foia":
        pick = rng.integers(0, len(foia), size=n)
        z = foia["exposure"].to_numpy()[pick]
        s = foia["mkt_spend_shr"].to_numpy()[pick]
    else:
        pool = univ.loc[~is_foia]
        pick = rng.permutation(n)
        z = pool["exposure_ss"].to_numpy()[pick]
        s = pool["sum_imputed_shares"].to_numpy()[pick]

    if jitter > 0:
        z = z + rng.normal(0, jitter * z.std(), size=n)
        s = np.clip(s + rng.normal(0, jitter * s.std(), size=n), 0, 1)

    out.loc[~is_foia, "exposure_ss"] = z
    out.loc[~is_foia, "sum_imputed_shares"] = s
    return out


def moments(label, z):
    q = np.percentile(z, [10, 50, 90])
    return {
        "series": label,
        "n": len(z),
        "mean": z.mean(),
        "sd": z.std(ddof=1),
        "p10": q[0],
        "p50": q[1],
        "p90": q[2],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", choices=VERSIONS, default="hc")
    ap.add_argument(
        "--filter",
        default="_cf_k3",
        help="EXPOSURE_FILTER of the real run to mirror (universe roster source).",
    )
    ap.add_argument("--mode", choices=["foia", "permute"], default="foia")
    ap.add_argument("--n-draws", type=int, default=10)
    ap.add_argument("--seed", type=int, default=8975)
    ap.add_argument(
        "--jitter",
        type=float,
        default=0.0,
        help=(
            "Kernel-smoothed bootstrap: Gaussian noise with sd = jitter * sd(x). "
            "0 = plain resample (213 support points across the universe)."
        ),
    )
    ap.add_argument("--summary-only", action="store_true")
    args = ap.parse_args()

    stem = f"_{args.version}{args.filter}"
    tag = "plc" if args.mode == "foia" else "plcp"

    foia = load_foia(args.version)
    univ = load_universe(stem)
    is_foia = univ["athr_id"].isin(set(foia["athr_id"])).to_numpy()

    print(f"universe {len(univ):,} PIs | FOIA in universe {is_foia.sum()} "
          f"| FOIA roster {len(foia)} | randomizing {(~is_foia).sum():,}")

    rows = [
        moments("foia_observed", foia["exposure"].to_numpy()),
        moments("real_imputed_nonfoia", univ.loc[~is_foia, "exposure_ss"].to_numpy()),
    ]

    real = univ.loc[~is_foia, "exposure_ss"].to_numpy()
    rng = np.random.default_rng(args.seed)

    for i in range(1, args.n_draws + 1):
        out = draw(rng, univ, foia, is_foia, args.mode, args.jitter)
        z = out.loc[~is_foia, "exposure_ss"].to_numpy()

        m = moments(f"{tag}{i:02d}", z)
        m["corr_with_real"] = np.corrcoef(z, real)[0, 1]
        rows.append(m)

        if not args.summary_only:
            path = f"{OUT_DIR}/final_imputed_shift_share{stem}_{tag}{i:02d}.csv"
            out.to_csv(path, index=False)
            print(f"  wrote {os.path.basename(path)}  mean={m['mean']:.5f} "
                  f"sd={m['sd']:.5f} corr={m['corr_with_real']:+.4f}")

    summary = pd.DataFrame(rows)
    summary_path = f"{OUT_DIR}/placebo_exposure_summary{stem}_{tag}.csv"
    summary.to_csv(summary_path, index=False)
    print(f"\n{summary.to_string(index=False)}\n-> {summary_path}")


if __name__ == "__main__":
    main()
