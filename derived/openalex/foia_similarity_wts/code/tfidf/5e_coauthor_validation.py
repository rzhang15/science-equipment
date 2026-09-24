import argparse
import os
import pickle
import numpy as np
import pandas as pd
import scipy.sparse as sp
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from k_sweep import (_vectorize_in_foia_space, _compute_copubs, knn_predict_from_sim,
                     OUT_DIR, FIG_DIR, EXPOSURE_DIR, COAUTHOR_CSV, COAUTHORS_DTA)
from plot_coauthor_single import _corr_ci

EBBLUE, DKORANGE = "#008BBC", "#E37E00"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="")
    ap.add_argument("--version", default="hc_all3")
    ap.add_argument("--k", type=int, default=3)
    ap.add_argument("--sharpen", type=float, default=2.0)
    ap.add_argument("--floor", type=float, default=0.05)
    ap.add_argument("--copub-edges", default="0,1,2,4,9,100000")
    ap.add_argument("--min-n-per-bin", type=int, default=20)
    args = ap.parse_args()

    tag = f"_{args.tag}" if args.tag and not args.tag.startswith("_") else args.tag
    stem = f"{args.version}_k{args.k}"
    os.makedirs(FIG_DIR, exist_ok=True)

    X_foia = sp.load_npz(f"{OUT_DIR}/tfidf_foia{tag}.npz").tocsr().astype(np.float32)
    foia_ids = pd.read_csv(f"{OUT_DIR}/foia_ids_ordered{tag}.csv", dtype={"athr_id": str})["athr_id"].tolist()
    exp = pd.read_stata(f"{EXPOSURE_DIR}/athr_exposure_{args.version}.dta")[["athr_id", "exposure"]]
    exp["athr_id"] = exp["athr_id"].astype(str)
    e = pd.Series(exp.set_index("athr_id")["exposure"]).reindex(foia_ids)
    keep = e.notna().to_numpy()
    X_foia, foia_ids, e_foia = X_foia[keep], [a for a, k in zip(foia_ids, keep) if k], e[keep].to_numpy(np.float32)
    print(f"FOIA donors with text and exposure: {len(foia_ids)}")

    with open(f"{OUT_DIR}/feature_names{tag}.pkl", "rb") as f:
        feature_names = list(pickle.load(f))
    diag = pd.read_parquet(f"{OUT_DIR}/feature_diagnostics{tag}.parquet")
    assert list(diag["feature"]) == feature_names
    idf = diag["idf"].to_numpy().astype(np.float32)

    df_co = pd.read_csv(COAUTHOR_CSV, dtype={"athr_id": str})
    df_co["processed_text"] = df_co["processed_text"].fillna("").astype(str)
    X_co = _vectorize_in_foia_space(df_co["processed_text"].tolist(), feature_names, idf)
    sim = (X_co @ X_foia.T).toarray().astype(np.float64)

    df_map = pd.read_stata(COAUTHORS_DTA)
    df_map["athr_id"] = df_map["athr_id"].astype(str)
    df_map["coauthor_id"] = df_map["coauthor_id"].astype(str)
    foia_pos = {a: i for i, a in enumerate(foia_ids)}
    co_pos = {a: i for i, a in enumerate(df_co["athr_id"].tolist())}
    df = df_map[df_map["coauthor_id"].isin(co_pos) & df_map["athr_id"].isin(foia_pos)].copy()
    df = df[df["coauthor_id"] != df["athr_id"]]
    df["foia_pos"] = df["athr_id"].map(foia_pos)
    df["co_pos"] = df["coauthor_id"].map(co_pos)
    df["e_foia_true"] = e_foia[df["foia_pos"].to_numpy()]
    df["sim_to_partner"] = sim[df["co_pos"].to_numpy(), df["foia_pos"].to_numpy()]
    print(f"coauthor-FOIA pairs: {len(df):,}   coauthors: {df['coauthor_id'].nunique():,}")

    sim_pairs = sim[df["co_pos"].to_numpy()].copy()
    partners = df.groupby("co_pos")["foia_pos"].apply(list)
    for r, cp in enumerate(df["co_pos"].to_numpy()):
        sim_pairs[r, partners[cp]] = -1.0
    df["pred_knn"], df["max_sim_excl"] = knn_predict_from_sim(sim_pairs, e_foia, args.k, args.sharpen, args.floor)
    naive, _ = knn_predict_from_sim(sim[df["co_pos"].to_numpy()], e_foia, args.k, args.sharpen, args.floor)
    df["pred_knn_naive"] = naive
    df["copubs"] = _compute_copubs(df[["athr_id", "coauthor_id"]].copy()).to_numpy()

    df = df[["athr_id", "coauthor_id", "e_foia_true", "pred_knn", "pred_knn_naive",
             "sim_to_partner", "max_sim_excl", "copubs"]]
    df.to_csv(f"{OUT_DIR}/coauthor_validation_pairs_{stem}.csv", index=False)

    edges = [int(x) for x in args.copub_edges.split(",")]
    rows = []
    for lo, hi in zip(edges[:-1], edges[1:]):
        sub = df[(df["copubs"] > lo) & (df["copubs"] <= hi)]
        r, rlo, rhi = _corr_ci(sub["e_foia_true"].to_numpy(), sub["pred_knn"].to_numpy())
        rn, _, _ = _corr_ci(sub["e_foia_true"].to_numpy(), sub["pred_knn_naive"].to_numpy())
        rows.append({"copub_lo": lo, "copub_hi": hi,
                     "label": f"{lo + 1}" if hi == lo + 1 else (f"{lo + 1}+" if hi >= 1000 else f"{lo + 1}-{hi}"),
                     "n": len(sub), "n_coauthors": sub["coauthor_id"].nunique(),
                     "r": r, "r_lo": rlo, "r_hi": rhi, "r_naive": rn})
    tab = pd.DataFrame(rows)
    r_all, r_all_lo, r_all_hi = _corr_ci(df["e_foia_true"].to_numpy(), df["pred_knn"].to_numpy())
    r_naive_all, _, _ = _corr_ci(df["e_foia_true"].to_numpy(), df["pred_knn_naive"].to_numpy())
    tab.to_csv(f"{OUT_DIR}/coauthor_by_copubs_{stem}.csv", index=False)
    with open(f"{OUT_DIR}/coauthor_validation_summary_{stem}.txt", "w") as f:
        f.write(f"Coauthor validation, FOIA partners excluded from donor set  k={args.k} version={args.version}\n")
        f.write(f"pairs={len(df):,}  overall r={r_all:.3f} [{r_all_lo:.3f}, {r_all_hi:.3f}]  "
                f"(partner-included naive r={r_naive_all:.3f})\n\n")
        f.write(tab.to_string(index=False, float_format=lambda x: f"{x:7.3f}") + "\n")
    print(open(f"{OUT_DIR}/coauthor_validation_summary_{stem}.txt").read())

    plot = tab[tab["n"] >= args.min_n_per_bin].reset_index(drop=True)
    fig, ax = plt.subplots(figsize=(5.6, 4.4))
    x = np.arange(len(plot))
    y = plot["r"].to_numpy()
    ax.errorbar(x, y, yerr=np.vstack([y - plot["r_lo"], plot["r_hi"] - y]), fmt="o-", color=EBBLUE,
                ms=7, lw=1.6, capsize=3)
    ax.axhline(0, color="k", lw=0.7)
    ax.axhline(r_all, color=DKORANGE, ls="--", lw=1.1, label=f"All pairs, r = {r_all:.2f}")
    ax.set_xticks(x)
    ax.set_xticklabels([f"{row.label}\nn = {row.n:,}" for row in plot.itertuples()], fontsize=8.5)
    ax.set_xlabel("Papers coauthored with the FOIA PI")
    ax.set_ylabel("Corr(coauthor's imputed exposure,\nFOIA PI's observed exposure)")
    ax.legend(fontsize=8.5, loc="upper left", frameon=False)
    ax.spines[["top", "right"]].set_visible(False)
    fig.tight_layout()
    fig.savefig(f"{FIG_DIR}/coauthor_validation_{stem}.pdf", bbox_inches="tight")
    fig.savefig(f"{FIG_DIR}/coauthor_validation_{stem}.png", dpi=160, bbox_inches="tight")
    print(f"Saved {FIG_DIR}/coauthor_validation_{stem}.pdf")


if __name__ == "__main__":
    main()
