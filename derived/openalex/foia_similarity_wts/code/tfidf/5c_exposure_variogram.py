import argparse
import json
import os
import warnings

import numpy as np
import pandas as pd
import scipy.sparse
from scipy.optimize import least_squares

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

OUT_DIR = "../../output"
FIG_DIR = f"{OUT_DIR}/figures"
EXPOSURE_DIR = "../../external/exposure_wts"

def _norm_tag(tag):
    if tag and not tag.startswith("_"):
        return "_" + tag
    return tag or ""

def chordal(s):
    return np.sqrt(np.maximum(2.0 - 2.0 * np.asarray(s, float), 0.0))

def pair_frame(e, S, idx):
    sub_e = e[idx]
    a, b = np.triu_indices(len(idx), 1)
    keep = idx[a] != idx[b]
    a, b = a[keep], b[keep]
    mu = sub_e.mean()
    c = sub_e - mu
    return {
        "sim": S[idx[a], idx[b]],
        "gap": sub_e[a] - sub_e[b],
        "prod": c[a] * c[b],
        "var": float(sub_e.var(ddof=1)),
        "a": a, "b": b,
    }

def bin_curve(pf, edges):
    nb = len(edges) - 1
    k = np.clip(np.digitize(pf["sim"], edges) - 1, 0, nb - 1)
    gap, prod, sim = pf["gap"], pf["prod"], pf["sim"]

    n = np.bincount(k, minlength=nb).astype(float)
    safe = np.where(n > 0, n, np.nan)
    g2 = np.bincount(k, weights=gap ** 2, minlength=nb) / safe
    absr = np.bincount(k, weights=np.sqrt(np.abs(gap)), minlength=nb) / safe
    cov = np.bincount(k, weights=prod, minlength=nb) / safe
    smean = np.bincount(k, weights=sim, minlength=nb) / safe
    aad = np.bincount(k, weights=np.abs(gap), minlength=nb) / safe

    with np.errstate(invalid="ignore", divide="ignore"):
        ch = absr ** 4 / (2.0 * (0.457 + 0.494 / safe))

    var = pf["var"]
    return {
        "n": n, "sim_mean": smean,
        "gamma": 0.5 * g2,
        "gamma_ch": ch,
        "cov": cov,
        "rho_cov": cov / var,
        "rho_gamma": 1.0 - (0.5 * g2) / var,
        "mad": aad,
    }

def bootstrap_curves(e, S, edges, thresh_grid, B, seed):
    n = len(e)
    rng = np.random.default_rng(seed)
    nb, nt = len(edges) - 1, len(thresh_grid)
    g_reps = np.full((B, nb), np.nan)
    r_reps = np.full((B, nb), np.nan)
    t_reps = np.full((B, nt), np.nan)
    slope_reps = np.full(B, np.nan)

    for r in range(B):
        idx = rng.integers(0, n, n)
        pf = pair_frame(e, S, idx)
        if len(pf["sim"]) < 50 or pf["var"] <= 0:
            continue
        cur = bin_curve(pf, edges)
        g_reps[r] = cur["gamma"]
        r_reps[r] = cur["rho_cov"]
        t_reps[r] = threshold_rho(pf, thresh_grid)
        slope_reps[r] = gap2_slope(pf)

    return g_reps, r_reps, t_reps, slope_reps

def threshold_rho(pf, grid):
    order = np.argsort(-pf["sim"])
    s_sorted = pf["sim"][order]
    p_cum = np.cumsum(pf["prod"][order])
    counts = np.searchsorted(-s_sorted, -np.asarray(grid), side="right")
    out = np.full(len(grid), np.nan)
    ok = counts >= 30
    out[ok] = p_cum[counts[ok] - 1] / counts[ok] / pf["var"]
    return out

def gap2_slope(pf):
    s, y = pf["sim"], pf["gap"] ** 2
    sc = s - s.mean()
    denom = float(sc @ sc)
    return float(sc @ (y - y.mean()) / denom) if denom > 0 else np.nan

def gamma_model(h, c0, c1, a, kind):
    h = np.asarray(h, float)
    if kind == "exponential":
        g = c0 + c1 * (1.0 - np.exp(-h / a))
    elif kind == "spherical":
        r = np.clip(h / a, 0.0, 1.0)
        g = c0 + c1 * (1.5 * r - 0.5 * r ** 3)
    else:
        raise ValueError(kind)
    return np.where(h <= 1e-12, 0.0, g)

def fit_model(sim_mean, gamma, n, sill, kind):
    m = np.isfinite(sim_mean) & np.isfinite(gamma) & (n > 0)
    h, g, w = chordal(sim_mean[m]), gamma[m], np.sqrt(n[m])

    def resid(p):
        return w * (gamma_model(h, p[0], p[1], p[2], kind) - g)

    best, best_cost = None, np.inf
    for a0 in (0.05, 0.2, 0.5, 1.0, 3.0):
        try:
            r = least_squares(
                resid, x0=[0.3 * sill, 0.7 * sill, a0],
                bounds=([0.0, 0.0, 1e-3], [sill, 5.0 * sill, 50.0]),
                max_nfev=5000)
        except Exception:
            continue
        if r.cost < best_cost:
            best, best_cost = r, r.cost
    if best is None:
        return None
    c0, c1, a = best.x
    flat_cost = float(0.5 * np.sum((w * (sill - g)) ** 2))
    return {
        "kind": kind, "nugget": float(c0), "psill": float(c1), "range": float(a),
        "sill_fitted": float(c0 + c1), "sill_empirical": float(sill),
        "wsse": float(best.cost), "wsse_flat_null": flat_cost,
        "n_bins_used": int(m.sum()),
    }

def production_weights(s0, sharpen, floor):
    v = np.where(s0 >= floor, s0, 0.0).astype(float) ** sharpen
    tot = v.sum()
    return v / tot if tot > 0 else np.full(len(s0), 1.0 / len(s0))

def ok_weights(Gam, g0):
    k = len(g0)
    A = np.zeros((k + 1, k + 1))
    A[:k, :k] = Gam
    A[:k, k] = 1.0
    A[k, :k] = 1.0
    rhs = np.append(g0, 1.0)
    try:
        sol = np.linalg.solve(A, rhs)
    except np.linalg.LinAlgError:
        sol = np.linalg.lstsq(A, rhs, rcond=None)[0]
    return sol[:k], float(sol[k])

def anchor_ksweep(e, S, gfun, ks, sharpen, floor):
    n = len(e)
    Sm = S.copy()
    np.fill_diagonal(Sm, -np.inf)
    ks = sorted({k for k in ks if 1 <= k <= n - 1})
    rows = []
    for i in range(n):
        order = np.argsort(-Sm[i])
        max_sim = float(Sm[i, order[0]])
        for k in ks:
            don = order[:k]
            s0 = Sm[i, don]
            g0 = gfun(s0)
            Gam = gfun(S[np.ix_(don, don)])
            np.fill_diagonal(Gam, 0.0)

            wp = production_weights(s0, sharpen, floor)
            mse_p = float(2.0 * wp @ g0 - wp @ Gam @ wp)

            wk, lam = ok_weights(Gam, g0)
            mse_k = float(wk @ g0 + lam)

            rows.append({
                "i": i, "max_sim": max_sim, "k": k,
                "mse_prod": max(mse_p, 0.0),
                "mse_ok": max(mse_k, 0.0),
                "ok_neg_share": float((wk < 0).mean()),
            })
    return pd.DataFrame(rows)

def sample_profile_from_weights(weight_npz, universe_ids_parquet, sample_ids,
                                max_sim_by_id, sharpen):
    W = scipy.sparse.load_npz(weight_npz).tocsr()
    uids = pd.read_parquet(universe_ids_parquet)["athr_id"].astype(str)
    pos = pd.Series(np.arange(len(uids)), index=uids.to_numpy())
    row_of = pos.reindex(sample_ids)
    have = np.isfinite(row_of.to_numpy(dtype=float))
    kept = [i for i, h in zip(sample_ids, have) if h]
    Wm = W[row_of.dropna().astype(int).to_numpy()]

    indptr, indices, data = Wm.indptr, Wm.indices, Wm.data
    nnz = np.diff(indptr)
    smax = np.array([max_sim_by_id[i] for i in kept], float)

    groups = {}
    for k in np.unique(nnz):
        if k == 0:
            continue
        sel = np.where(nnz == k)[0]
        don = np.empty((len(sel), k), np.int64)
        w = np.empty((len(sel), k), np.float64)
        for j, r in enumerate(sel):
            a, b = indptr[r], indptr[r + 1]
            don[j] = indices[a:b]
            w[j] = data[a:b]
        o = np.argsort(-w, axis=1)
        don = np.take_along_axis(don, o, 1)
        w = np.take_along_axis(w, o, 1)
        s0 = smax[sel][:, None] * (w / w[:, :1]) ** (1.0 / sharpen)
        groups[int(k)] = {"sel": sel, "don": don, "w": w, "s0": s0}
    return groups, kept, int((~have).sum()), int((nnz == 0).sum())

def profile_mse(don, w, s0, Saa, gfun, chunk=4000):
    n, k = don.shape
    mp = np.empty(n)
    mo = np.empty(n)
    neg = np.empty(n)
    diag = np.arange(k)
    for a in range(0, n, chunk):
        b = min(a + chunk, n)
        d = don[a:b]
        G0 = gfun(s0[a:b])
        Gam = gfun(Saa[d[:, :, None], d[:, None, :]])
        Gam[:, diag, diag] = 0.0
        ww = w[a:b]
        mp[a:b] = (2.0 * (ww * G0).sum(1)
                   - np.einsum("ik,ikl,il->i", ww, Gam, ww))
        A = np.zeros((b - a, k + 1, k + 1))
        A[:, :k, :k] = Gam
        A[:, :k, k] = 1.0
        A[:, k, :k] = 1.0
        rhs = np.concatenate([G0, np.ones((b - a, 1))], axis=1)
        try:
            sol = np.linalg.solve(A, rhs)
        except np.linalg.LinAlgError:
            sol = np.stack([np.linalg.lstsq(A[i], rhs[i], rcond=None)[0]
                            for i in range(b - a)])
        wk = sol[:, :k]
        mp[a:b] = np.maximum(mp[a:b], 0.0)
        mo[a:b] = np.maximum((wk * G0).sum(1) + sol[:, k], 0.0)
        neg[a:b] = (wk < 0).mean(1)
    return mp, mo, neg

def grid_reweight(anchor_vals, anchor_sim, panel_sim, width):
    hi = max(float(np.max(anchor_sim)), float(np.max(panel_sim))) + width
    edges = np.arange(0.0, hi + width, width)
    nb = len(edges) - 1
    ai = np.clip(np.digitize(anchor_sim, edges) - 1, 0, nb - 1)
    pi = np.clip(np.digitize(panel_sim, edges) - 1, 0, nb - 1)

    cnt = np.bincount(ai, minlength=nb).astype(float)
    tot = np.bincount(ai, weights=anchor_vals, minlength=nb)
    have = cnt > 0
    bin_mean = np.divide(tot, cnt, out=np.full(nb, np.nan), where=have)

    p_mass = np.bincount(pi, minlength=nb).astype(float) / len(panel_sim)
    covered = have & (p_mass > 0)
    mass = p_mass[covered]
    if mass.sum() <= 0:
        return np.nan, 0.0
    return float(np.average(bin_mean[covered], weights=mass)), float(mass.sum())

def load_panel_sims(panel_csv, diag_parquet, foia_ids):
    panel = pd.read_csv(panel_csv, usecols=["athr_id"], dtype={"athr_id": str})
    panel = panel.drop_duplicates("athr_id")
    panel = panel[~panel["athr_id"].isin(set(foia_ids))]
    diag = pd.read_parquet(diag_parquet, columns=["athr_id", "max_sim"])
    diag["athr_id"] = diag["athr_id"].astype(str)
    panel = panel.merge(diag, on="athr_id", how="left")
    n_miss = int(panel["max_sim"].isna().sum())
    if n_miss:
        print(f"  WARN: {n_miss:,} panel PIs missing from diagnostics; dropped.")
    return panel.dropna(subset=["max_sim"])["max_sim"].to_numpy(np.float64)

def make_figure(bins_panel, thr, ks_summary, pair_sim, panel_sims, fit, sill,
                gfun, out_png, stem, prod_k, exact=None, pop="panel"):
    fig, axes = plt.subplots(2, 2, figsize=(13, 9))
    axA, axB, axC, axD = axes.ravel()
    p25, p50, p75 = np.percentile(panel_sims, [25, 50, 75])

    sg = np.linspace(max(pair_sim.min(), 0.0), np.percentile(pair_sim, 99.9), 300)

    x = bins_panel["sim_mean"].to_numpy()
    y = bins_panel["rho_cov"].to_numpy()
    axA.fill_between(x, bins_panel["rho_lo"], bins_panel["rho_hi"],
                     color="C0", alpha=0.18, label="95% CI (PI bootstrap)")
    axA.plot(x, y, "o-", color="C0", ms=5, lw=1.8, label=r"$\hat\rho(s)$")
    axA.plot(sg, 1.0 - gfun(sg) / sill, "-", color="C1", lw=1.4,
             label=f"fitted ({fit['kind']})")
    axA.axhline(0, color="k", lw=0.7, alpha=0.6)
    axA.axvspan(p25, p75, color="C2", alpha=0.12, label=f"{pop} IQR")
    axA.axvline(p50, color="C2", ls="--", lw=1.2, label=f"{pop} median")
    axA.set_xlabel("Cosine similarity between PIs")
    axA.set_ylabel(r"Exposure agreement  $\rho(s)$")
    axA.set_title(f"A. Agreement decay (bins = {pop} max_sim quantiles)")
    axA.legend(fontsize=8)
    axA.grid(alpha=0.3)

    axB.plot(x, bins_panel["gamma"], "o-", color="C3", ms=5, lw=1.8,
             label=r"$\hat\gamma(s)$")
    axB.plot(x, bins_panel["gamma_ch"], "^--", color="C4", ms=5, lw=1.3,
             label="Cressie-Hawkins")
    axB.plot(sg, gfun(sg), "-", color="C1", lw=1.4, label="fitted")
    axB.axhline(sill, color="k", ls=":", lw=1.2, label=r"sill $=\sigma^2$")
    axB.axvspan(p25, p75, color="C2", alpha=0.12)
    axB.set_xlabel("Cosine similarity between PIs")
    axB.set_ylabel(r"Semivariance $\gamma(s)$")
    ax2 = axB.twinx()
    ax2.hist(pair_sim, bins=60, color="C0", alpha=0.18)
    ax2.set_ylabel("anchor pairs per bin")
    ax2.set_yscale("log")
    axB.set_zorder(ax2.get_zorder() + 1)
    axB.patch.set_visible(False)
    axB.set_title("B. Semivariance and pair support")
    axB.legend(fontsize=8, loc="lower left")
    axB.grid(alpha=0.3)

    axC.fill_between(thr["s_star"], thr["rho_lo"], thr["rho_hi"],
                     color="C0", alpha=0.18)
    axC.plot(thr["s_star"], thr["rho"], "-", color="C0", lw=1.8,
             label=r"$\hat\rho(s \geq s^*)$")
    axC.axhline(0, color="k", lw=0.7, alpha=0.6)
    axC.set_xlabel(r"Similarity cutoff $s^*$")
    axC.set_ylabel(r"Agreement among pairs with $s \geq s^*$")
    ax3 = axC.twinx()
    ax3.plot(thr["s_star"], 100 * thr["panel_share_above"], "-", color="C2",
             lw=1.4, label=f"{pop} share retained")
    ax3.set_ylim(0, 100)
    ax3.set_ylabel(f"% of {pop} with max_sim " + r"$\geq s^*$", color="C2")
    lines, labels = axC.get_legend_handles_labels()
    l3, lb3 = ax3.get_legend_handles_labels()
    axC.legend(lines + l3, labels + lb3, fontsize=8, loc="upper left")
    axC.set_title("C. Where agreement stops being flat")
    axC.grid(alpha=0.3)

    axD.plot(ks_summary["k"], np.sqrt(ks_summary["rmse2_prod_panel"]), "o-",
             color="C0", ms=5, lw=1.8,
             label=f"production weights ($s^{{sharpen}}$, floored)")
    axD.plot(ks_summary["k"], np.sqrt(ks_summary["rmse2_ok_panel"]), "s-",
             color="C1", ms=5, lw=1.8, label="ordinary kriging weights")
    axD.axhline(np.sqrt(sill), color="k", ls=":", lw=1.2,
                label=r"$\sigma$ (predict the mean)")
    axD.axvline(prod_k, color="C3", ls="--", lw=1.2,
                label=f"production K={prod_k}")
    if exact is not None:
        axD.plot([prod_k], [np.sqrt(exact["mse_prod"])], "*", color="C3",
                 ms=18, zorder=5, mec="k", mew=0.6,
                 label="exact, sample donor profiles")
    axD.set_xlabel("K neighbours")
    axD.set_ylabel(f"Implied RMSE at {pop} match quality")
    axD.set_title(f"D. K and weights, read at the {pop}'s similarity")
    axD.legend(fontsize=8)
    axD.grid(alpha=0.3)

    fig.suptitle(f"Exposure variogram in TF-IDF text space   ({stem})",
                 fontsize=13, fontweight="bold")
    fig.tight_layout()
    fig.savefig(out_png, dpi=150, bbox_inches="tight")
    print(f"Saved {out_png}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="",
                    help="TF-IDF artifact tag; empty = production.")
    ap.add_argument("--version", default="hc",
                    choices=["hc", "all", "treated_hc"])
    ap.add_argument("--k", type=int, default=3,
                    help="Production K, marked on the K sweep.")
    ap.add_argument("--sharpen", type=float, default=2.0)
    ap.add_argument("--floor", type=float, default=0.05)
    ap.add_argument("--k-grid", type=int, nargs="+",
                    default=[1, 2, 3, 4, 5, 6, 8, 10, 15, 20, 30, 50, 100])
    ap.add_argument("--n-bins", type=int, default=10,
                    help="Bins, taken as quantiles of the PANEL max_sim.")
    ap.add_argument("--boot", type=int, default=1000,
                    help="PI-level bootstrap replicates.")
    ap.add_argument("--seed", type=int, default=8975)
    ap.add_argument("--reweight-width", type=float, default=0.01,
                    help="Grid width for averaging over the panel max_sim.")
    ap.add_argument("--panel-csv",
                    default=f"{OUT_DIR}/final_imputed_shift_share_hc_cf_k3.csv")
    ap.add_argument("--panel-dta", default="",
                    help="Prepped RF sample .dta (athr_id, max_sim, foia_athr); "
                         "overrides --panel-csv.")
    ap.add_argument("--diag-parquet",
                    default=f"{OUT_DIR}/match_diagnostics_k3.parquet")
    ap.add_argument("--weight-npz", default=f"{OUT_DIR}/weight_matrix_k3.npz",
                    help="Production weight matrix. With --panel-dta this gives "
                         "each sample PI's exact donor set, weights and "
                         "1st/2nd/3rd-nearest similarities.")
    ap.add_argument("--universe-ids",
                    default=f"{OUT_DIR}/universe_ids.parquet",
                    help="Row order of the weight matrix.")
    ap.add_argument("--out-tag", default="")
    args = ap.parse_args()

    tag = _norm_tag(args.tag)
    foia_matrix = f"{OUT_DIR}/tfidf_foia{tag}.npz"
    foia_ids_csv = f"{OUT_DIR}/foia_ids_ordered{tag}.csv"
    exposure_dta = f"{EXPOSURE_DIR}/athr_exposure_{args.version}.dta"
    panel_src = args.panel_dta or args.panel_csv
    for p in (foia_matrix, foia_ids_csv, exposure_dta, panel_src):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")
    if not args.panel_dta and not os.path.exists(args.diag_parquet):
        raise SystemExit(f"missing: {args.diag_parquet}")
    os.makedirs(FIG_DIR, exist_ok=True)

    X = scipy.sparse.load_npz(foia_matrix).tocsr().astype(np.float64)
    foia_ids = pd.read_csv(foia_ids_csv,
                           dtype={"athr_id": str})["athr_id"].tolist()
    nrm = np.sqrt(X.multiply(X).sum(axis=1)).A.ravel()
    if not np.allclose(nrm, 1.0, atol=1e-6):
        raise SystemExit("TF-IDF rows are not L2-normalized; S is not cosine.")

    exp_df = pd.read_stata(exposure_dta)[["athr_id", "exposure"]]
    exp_df["athr_id"] = exp_df["athr_id"].astype(str)
    e_all = (exp_df.set_index("athr_id")["exposure"].reindex(foia_ids))
    n_miss = int(e_all.isna().sum())
    keep = ~e_all.isna().to_numpy()
    if n_miss:
        print(f"  WARN: {n_miss} anchors have no exposure; dropped "
              f"(not zero-filled -- a fabricated 0 is a fabricated gap).")
    X = X[keep]
    e = e_all.to_numpy(float)[keep]
    foia_ids = [i for i, k in zip(foia_ids, keep) if k]
    n = len(e)

    S = (X @ X.T).toarray()
    np.clip(S, 0.0, 1.0, out=S)
    pf = pair_frame(e, S, np.arange(n))
    sill = pf["var"]
    n_pairs = len(pf["sim"])
    print(f"Anchors: {n}   pairs: {n_pairs:,}   "
          f"sill = Var(exposure) = {sill:.6f}  (sd = {np.sqrt(sill):.4f})")

    pooled_gamma = 0.5 * float(np.mean(pf["gap"] ** 2))
    if not np.isclose(pooled_gamma, sill, rtol=1e-6):
        raise SystemExit(f"identity check failed: pooled gamma {pooled_gamma} "
                         f"!= sill {sill}")

    panel_ids = None
    if args.panel_dta:
        d = pd.read_stata(args.panel_dta,
                          columns=["athr_id", "max_sim", "foia_athr"])
        d["athr_id"] = d["athr_id"].astype(str)
        d = (d[d["foia_athr"] != 1].drop_duplicates("athr_id")
             .dropna(subset=["max_sim"]))
        panel_sims = d["max_sim"].to_numpy(np.float64)
        panel_ids = d["athr_id"].tolist()
    else:
        panel_sims = load_panel_sims(args.panel_csv, args.diag_parquet,
                                     foia_ids)
        print("  NOTE this is the full imputed panel, not the estimation "
              "sample. Pass --panel-dta <reduced_form/temp/athr_xw.dta> to "
              "read the curve where the analysis sample actually sits.")
    pq = np.percentile(panel_sims, [10, 25, 50, 75, 90])
    print(f"Panel: {len(panel_sims):,} PIs   max_sim p10/p25/p50/p75/p90 = "
          + "/".join(f"{v:.3f}" for v in pq))

    inner = np.unique(np.percentile(panel_sims,
                                    np.linspace(0, 100, args.n_bins + 1)))
    edges_panel = np.unique(np.concatenate(
        ([0.0], inner, [max(pf["sim"].max(), panel_sims.max()) + 1e-9])))
    edges_pair = np.unique(np.percentile(pf["sim"],
                                         np.linspace(0, 100, args.n_bins + 1)))
    edges_pair[0], edges_pair[-1] = 0.0, edges_pair[-1] + 1e-9

    thr_grid = np.unique(np.round(np.concatenate([
        np.percentile(pf["sim"], np.linspace(1, 99, 60)),
        np.percentile(panel_sims, np.linspace(5, 99, 20)),
    ]), 5))

    cur_panel = bin_curve(pf, edges_panel)
    cur_pair = bin_curve(pf, edges_pair)

    print(f"Bootstrapping {args.boot} PI-level replicates ...")
    g_reps, r_reps, t_reps, slope_reps = bootstrap_curves(
        e, S, edges_panel, thr_grid, args.boot, args.seed)

    def pct(a, q):
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", RuntimeWarning)
            return np.nanpercentile(a, q, axis=0)

    bins_panel = pd.DataFrame({
        "scheme": "panel_quantile",
        "bin": np.arange(1, len(edges_panel)),
        "sim_lo": edges_panel[:-1], "sim_hi": edges_panel[1:],
        "sim_mean": cur_panel["sim_mean"], "n_pairs": cur_panel["n"],
        "gamma": cur_panel["gamma"], "gamma_ch": cur_panel["gamma_ch"],
        "gamma_lo": pct(g_reps, 2.5), "gamma_hi": pct(g_reps, 97.5),
        "rho_cov": cur_panel["rho_cov"], "rho_gamma": cur_panel["rho_gamma"],
        "rho_lo": pct(r_reps, 2.5), "rho_hi": pct(r_reps, 97.5),
        "mad": cur_panel["mad"],
    })
    bins_panel["panel_share"] = [
        float(np.mean((panel_sims >= lo) & (panel_sims < hi)))
        for lo, hi in zip(edges_panel[:-1], edges_panel[1:])]
    bins_panel = bins_panel[bins_panel["n_pairs"] > 0].reset_index(drop=True)
    bins_panel["n_pairs"] = bins_panel["n_pairs"].astype(int)

    bins_pair = pd.DataFrame({
        "scheme": "pair_quantile",
        "bin": np.arange(1, len(edges_pair)),
        "sim_lo": edges_pair[:-1], "sim_hi": edges_pair[1:],
        "sim_mean": cur_pair["sim_mean"], "n_pairs": cur_pair["n"],
        "gamma": cur_pair["gamma"], "gamma_ch": cur_pair["gamma_ch"],
        "gamma_lo": np.nan, "gamma_hi": np.nan,
        "rho_cov": cur_pair["rho_cov"], "rho_gamma": cur_pair["rho_gamma"],
        "rho_lo": np.nan, "rho_hi": np.nan,
        "mad": cur_pair["mad"], "panel_share": np.nan,
    })
    bins_pair = bins_pair[bins_pair["n_pairs"] > 0].reset_index(drop=True)
    bins_pair["n_pairs"] = bins_pair["n_pairs"].astype(int)

    print("\n--- Agreement curve at the panel's own similarity levels ---")
    show = bins_panel[["sim_lo", "sim_hi", "sim_mean", "n_pairs", "panel_share",
                       "gamma", "rho_cov", "rho_lo", "rho_hi"]]
    print(show.to_string(index=False, float_format=lambda v: f"{v:9.4f}"))

    fits = [f for f in (fit_model(cur_pair["sim_mean"], cur_pair["gamma"],
                                  cur_pair["n"], sill, kind)
                        for kind in ("exponential", "spherical")) if f]
    if not fits:
        raise SystemExit("variogram fit failed")
    fit = min(fits, key=lambda f: f["wsse"])
    gfun = lambda s: gamma_model(chordal(s), fit["nugget"], fit["psill"],
                                 fit["range"], fit["kind"])
    n_high = int((pf["sim"] > 0.5).sum())
    h_span = float(chordal(pf["sim"].min()) - chordal(pf["sim"].max()))
    range_unidentified = fit["range"] > chordal(pf["sim"].min())
    fit["range_unidentified"] = bool(range_unidentified)
    fit["h_span_observed"] = h_span
    print(f"\nFitted {fit['kind']}: nugget={fit['nugget']:.6f} "
          f"psill={fit['psill']:.6f} range={fit['range']:.4f}  "
          f"wSSE={fit['wsse']:.4g} vs flat-null {fit['wsse_flat_null']:.4g}")
    if range_unidentified:
        print("  WARN: fitted range exceeds the observed distance span; read "
              "the curve, not the parameters.")

    panel_share_above = np.array([float(np.mean(panel_sims >= s))
                                  for s in thr_grid])
    thr = pd.DataFrame({
        "s_star": thr_grid,
        "n_pairs_above": [int((pf["sim"] >= s).sum()) for s in thr_grid],
        "rho": threshold_rho(pf, thr_grid),
        "rho_lo": pct(t_reps, 2.5), "rho_hi": pct(t_reps, 97.5),
        "panel_share_above": panel_share_above,
    })
    thr["panel_pct_cut"] = 100.0 * thr["panel_share_above"]

    valid = thr[np.isfinite(thr["rho_lo"])].reset_index(drop=True)
    s_star, share_star = np.nan, np.nan
    if len(valid):
        pos = (valid["rho_lo"] > 0).to_numpy()
        run = pos[::-1].cumprod()[::-1].astype(bool)
        if run.any():
            j = int(np.argmax(run))
            s_star = float(valid["s_star"].iloc[j])
            share_star = float(valid["panel_share_above"].iloc[j])

    slope = gap2_slope(pf)
    slope_lo, slope_hi = pct(slope_reps, [2.5, 97.5])

    print("Sweeping K with model-implied error ...")
    ks = anchor_ksweep(e, S, gfun, args.k_grid, args.sharpen, args.floor)
    anchor_max_sim = ks.groupby("i")["max_sim"].first().to_numpy()
    rows = []
    for k, grp in ks.groupby("k"):
        grp = grp.sort_values("i")
        pp, cov_p = grid_reweight(grp["mse_prod"].to_numpy(), anchor_max_sim,
                                  panel_sims, args.reweight_width)
        ok, _ = grid_reweight(grp["mse_ok"].to_numpy(), anchor_max_sim,
                              panel_sims, args.reweight_width)
        rows.append({
            "k": int(k),
            "rmse2_prod_panel": pp, "rmse2_ok_panel": ok,
            "rmse_prod_panel": np.sqrt(pp), "rmse_ok_panel": np.sqrt(ok),
            "rmse2_prod_pooled": float(grp["mse_prod"].mean()),
            "rmse2_ok_pooled": float(grp["mse_ok"].mean()),
            "ok_neg_share": float(grp["ok_neg_share"].mean()),
            "panel_coverage": cov_p,
        })
    ks_summary = pd.DataFrame(rows).sort_values("k").reset_index(drop=True)
    for c in ("prod", "ok"):
        ks_summary[f"rel_{c}"] = 1.0 - ks_summary[f"rmse2_{c}_panel"] / sill
    best_prod = ks_summary.loc[ks_summary["rmse2_prod_panel"].idxmin()]
    best_ok = ks_summary.loc[ks_summary["rmse2_ok_panel"].idxmin()]

    print("\n--- K sweep (model-implied, read at panel match quality) ---")
    print(ks_summary[["k", "rmse_prod_panel", "rmse_ok_panel", "rel_prod",
                      "rel_ok", "ok_neg_share"]]
          .to_string(index=False, float_format=lambda v: f"{v:9.4f}"))

    exact = None
    if panel_ids is not None and n_miss:
        print("  SKIP exact donor profiles: anchors were dropped for missing "
              "exposure, so weight-matrix columns no longer align.")
    elif panel_ids is not None and os.path.exists(args.weight_npz):
        print("Recovering exact donor profiles from the weight matrix ...")
        msim_by_id = dict(zip(panel_ids, panel_sims))
        groups, kept, n_nomatch, n_zero = sample_profile_from_weights(
            args.weight_npz, args.universe_ids, panel_ids, msim_by_id,
            args.sharpen)
        parts, s_cols = [], []
        for k, g in sorted(groups.items()):
            mp, mo, neg = profile_mse(g["don"], g["w"], g["s0"], S, gfun)
            parts.append(pd.DataFrame({
                "n_donors": k, "mse_prod": mp, "mse_ok": mo,
                "ok_neg_share": neg, "s1": g["s0"][:, 0]}))
            s_cols.append(g["s0"])
        ex = pd.concat(parts, ignore_index=True)
        kmax = max(g["s0"].shape[1] for g in groups.values())
        prof = np.full((sum(s.shape[0] for s in s_cols), kmax), np.nan)
        r = 0
        for s in s_cols:
            prof[r:r + s.shape[0], :s.shape[1]] = s
            r += s.shape[0]
        exact = {
            "df": ex, "prof": prof,
            "n": len(ex), "n_nomatch": n_nomatch, "n_zero": n_zero,
            "mse_prod": float(ex["mse_prod"].mean()),
            "mse_ok": float(ex["mse_ok"].mean()),
            "donor_counts": ex["n_donors"].value_counts().sort_index().to_dict(),
        }
        ex.to_csv(f"{OUT_DIR}/exposure_variogram_sample_"
                  f"{args.version}{tag}{_norm_tag(args.out_tag)}.csv",
                  index=False)
        print(f"  sample PIs with donors: {exact['n']:,}  "
              f"(no universe row: {n_nomatch}, zero weights: {n_zero})")

    g_panel = gfun(panel_sims)
    rho_panel = 1.0 - g_panel / sill
    mse_1nn = float(np.mean(2.0 * g_panel))
    mse_shrunk = float(np.mean(sill * (1.0 - rho_panel ** 2)))
    prod_row = ks_summary.loc[ks_summary["k"] == args.k]
    mse_prod = float(prod_row["rmse2_prod_panel"].iloc[0]) if len(prod_row) \
        else np.nan
    sd = np.sqrt(sill)

    q_lbl = [10, 25, 50, 75, 90]
    q_vals = np.percentile(panel_sims, q_lbl)
    at_q = [(q, s, float(gfun(s)), float(1.0 - gfun(s) / sill),
             int((pf["sim"] >= s).sum())) for q, s in zip(q_lbl, q_vals)]

    stem = f"{args.version}{tag}{_norm_tag(args.out_tag)}"
    pd.DataFrame({
        "athr_id_i": [foia_ids[i] for i in pf["a"]],
        "athr_id_j": [foia_ids[j] for j in pf["b"]],
        "sim": pf["sim"],
        "exposure_i": e[pf["a"]], "exposure_j": e[pf["b"]],
        "gap": pf["gap"], "sq_gap": pf["gap"] ** 2, "prod_dev": pf["prod"],
    }).to_csv(f"{OUT_DIR}/exposure_variogram_pairs_{stem}.csv", index=False)
    pd.concat([bins_panel, bins_pair], ignore_index=True).to_csv(
        f"{OUT_DIR}/exposure_variogram_bins_{stem}.csv", index=False)
    thr.to_csv(f"{OUT_DIR}/exposure_variogram_threshold_{stem}.csv", index=False)
    ks_summary.to_csv(f"{OUT_DIR}/exposure_variogram_ksweep_{stem}.csv",
                      index=False)
    with open(f"{OUT_DIR}/exposure_variogram_fit_{stem}.json", "w") as f:
        json.dump({**fit, "n_anchors": n, "n_pairs": n_pairs,
                   "n_pairs_sim_gt_0.5": n_high,
                   "panel_n": int(len(panel_sims)),
                   "s_star": s_star, "panel_share_above_s_star": share_star},
                  f, indent=2)

    L = [
        f"Exposure variogram in TF-IDF text space   version={args.version}  "
        f"tag={args.tag!r}",
        f"  anchors={n}  pairs={n_pairs:,}  bootstrap={args.boot} (PI-level)",
        f"  panel={os.path.basename(panel_src)}  n={len(panel_sims):,}",
        "",
        "SILL",
        f"  Var(anchor exposure) = {sill:.6f}   sd = {sd:.4f}",
        f"  pooled gamma over all pairs reproduces it exactly (identity check "
        f"passed)",
        "",
        f"FITTED MODEL ({fit['kind']}, chordal distance)",
        f"  nugget = {fit['nugget']:.6f}   partial sill = {fit['psill']:.6f}   "
        f"range = {fit['range']:.4f}",
        f"  weighted SSE {fit['wsse']:.4g} vs flat-null {fit['wsse_flat_null']:.4g}",
        f"  NOTE nugget is extrapolated: only {n_high} of {n_pairs:,} pairs "
        f"have s > 0.5, so the irreducible error at a perfect text match is "
        f"not pinned down by these data.",
    ] + ([
        f"  NOTE fitted range {fit['range']:.3f} exceeds the observed chordal "
        f"span; nugget/psill/range are not separately identified. Read the "
        f"fitted curve inside support, not the parameters.",
    ] if range_unidentified else []) + [
        f"  slope of squared gap on similarity = {slope:+.6f} "
        f"[{slope_lo:+.6f}, {slope_hi:+.6f}]  (negative = agreement rises)",
        "",
        "CURVE READ AT THE PANEL'S OWN SIMILARITY LEVELS (not pooled)",
        f"  {'panel pct':>10}  {'max_sim':>8}  {'gamma':>9}  {'rho':>7}  "
        f"{'anchor pairs at/above':>22}",
    ]
    for q, s, g, r, npair in at_q:
        L.append(f"  {('p%d' % q):>10}  {s:8.4f}  {g:9.6f}  {r:7.3f}  "
                 f"{npair:22,}")
    if np.isfinite(mse_prod):
        prod_line = (f"  production K={args.k} sharpen={args.sharpen}   "
                     f"RMSE = {np.sqrt(mse_prod):.4f}  "
                     f"= {np.sqrt(mse_prod)/sd:.2f} x sd")
    else:
        prod_line = f"  production K={args.k}: not in --k-grid"

    L += [
        "",
        "EXPECTED MEASUREMENT ERROR, INTEGRATED OVER THE PANEL max_sim "
        "DISTRIBUTION",
        f"  single nearest donor       RMSE = {np.sqrt(mse_1nn):.4f}  "
        f"= {np.sqrt(mse_1nn)/sd:.2f} x sd(true exposure)",
        prod_line,
        f"  shrinkage-optimal 1 donor  RMSE = {np.sqrt(mse_shrunk):.4f}  "
        f"= {np.sqrt(mse_shrunk)/sd:.2f} x sd",
        f"  best K, production weights : K={int(best_prod['k'])}  "
        f"RMSE = {best_prod['rmse_prod_panel']:.4f}",
        f"  best K, kriging weights    : K={int(best_ok['k'])}  "
        f"RMSE = {best_ok['rmse_ok_panel']:.4f}  "
        f"(reliability {best_ok['rel_ok']:.3f})",
        f"  reliability = 1 - MSE/Var; 0 means the imputation carries no more "
        f"information than predicting the mean.",
    ]

    if exact is not None:
        rel_p = 1.0 - exact["mse_prod"] / sill
        rel_o = 1.0 - exact["mse_ok"] / sill
        verdict = ("BEATS predicting the mean" if rel_p > 0
                   else "does NOT beat predicting the mean")
        L += [
            "",
            "EXACT, OVER THE SAMPLE'S OWN DONOR PROFILES "
            "(not max_sim alone, not anchors as stand-ins)",
            f"  sample PIs with donors: {exact['n']:,}   donor counts: "
            f"{exact['donor_counts']}",
            f"  realized nearest-donor similarities:",
        ]
        for j in range(min(3, exact["prof"].shape[1])):
            col = exact["prof"][:, j]
            col = col[np.isfinite(col)]
            q = np.percentile(col, [25, 50, 75])
            L.append(f"    s{j+1}: median {q[1]:.4f}   IQR "
                     f"[{q[0]:.4f}, {q[2]:.4f}]   n={len(col):,}")
        L += [
            f"  production weights   RMSE = {np.sqrt(exact['mse_prod']):.4f}  "
            f"= {np.sqrt(exact['mse_prod'])/sd:.3f} x sd   "
            f"reliability = {rel_p:+.4f}",
            f"  kriging weights      RMSE = {np.sqrt(exact['mse_ok']):.4f}  "
            f"= {np.sqrt(exact['mse_ok'])/sd:.3f} x sd   "
            f"reliability = {rel_o:+.4f}",
            f"  VERDICT: at the sample's realized match quality, the "
            f"production imputation {verdict}.",
        ]

    L += [
        "",
        "DEFENSIBLE SAMPLE CUT",
    ]
    if np.isfinite(s_star):
        L += [f"  smallest s* with rho bounded away from 0 from there up: "
              f"s* = {s_star:.4f}",
              f"  retains {share_star:.1%} of the panel "
              f"(equivalently a top-{100*share_star:.1f}% max_sim cut)"]
    else:
        L += ["  NONE: the lower CI bound on rho never clears 0 at any cutoff.",
              "  Text similarity does not identify exposure agreement anywhere "
              "in the supported range; a top-N% max_sim cut cannot fix this."]
    text = "\n".join(L) + "\n"
    with open(f"{OUT_DIR}/exposure_variogram_summary_{stem}.txt", "w") as f:
        f.write(text)
    print("\n" + text)

    make_figure(bins_panel, thr, ks_summary, pf["sim"], panel_sims, fit, sill,
                gfun, f"{FIG_DIR}/exposure_variogram_{stem}.png", stem, args.k,
                exact, "analysis sample" if panel_ids is not None else "panel")

    for p in ("pairs", "bins", "threshold", "ksweep", "summary"):
        ext = "txt" if p == "summary" else "csv"
        print(f"Saved {OUT_DIR}/exposure_variogram_{p}_{stem}.{ext}")

if __name__ == "__main__":
    main()
