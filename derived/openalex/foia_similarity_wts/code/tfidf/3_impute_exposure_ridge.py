import argparse
import os
import numpy as np
import pandas as pd
import scipy.sparse
from sklearn.linear_model import Ridge, RidgeCV
from sklearn.model_selection import KFold
from sklearn.metrics import r2_score, mean_squared_error

OUT_DIR = "../../output"
EXPOSURE_DIR = "../../external/exposure_wts"

# Alternative to 3_impute_exposure.py's W.dot(E) K-NN averaging: fit a Ridge
# regression on the 200-odd FOIA anchors mapping TF-IDF vectors → target, then
# predict for every universe author. Ridge pools all anchors (not just top-K)
# and shrinks toward the FOIA mean — usually beats K-NN when the target is
# weakly correlated with topical similarity (e.g. mkt_spend_shr), because K-NN
# with L1-normalized weights over-shrinks by averaging.
#
# Writes final_imputed_exposure_{version}{tag}_ridge.csv keyed on athr_id, same
# schema as the K-NN output so downstream Stata code can swap files by suffix.

VERSIONS = ["hc", "all", "treated_hc"]
IMPUTE_VARS = ["exposure", "mkt_spend_shr", "hc_spend_shr"]

# Log-spaced alpha grid; RidgeCV picks the best via GCV (LOO closed-form).
# 200 anchors × ~25K TF-IDF features → strong regularization needed, but with
# unit-norm TF-IDF vectors the effective X.T X eigenvalues are small, so
# alpha as low as 1e-3 can still be meaningfully regularizing. Grid spans 8
# decades to let GCV pick the elbow of the CV curve without hitting a bound.
DEFAULT_ALPHAS = np.logspace(-3, 4, 30)


def _pooled_cluster_means(y, labels, tau):
    """Compute per-cluster shrunk means from anchors with valid labels.

    mean_shrunk_c = (n_c * y_bar_c + tau * grand_mean) / (n_c + tau)

    Returns (means_dict, grand_mean). tau=0 gives raw cluster means. Callers
    use means.get(c, grand_mean) so unlabeled or unseen-in-train clusters fall
    back to the grand mean.
    """
    grand = float(y.mean())
    means = {}
    for c in np.unique(labels[labels >= 0]):
        m = y[labels == c]
        n_c = int(m.size)
        y_bar = float(m.mean())
        means[int(c)] = (n_c * y_bar + tau * grand) / (n_c + tau)
    return means, grand


def _fe_predict(labels, means, grand_mean):
    return np.array(
        [means.get(int(c), grand_mean) if c >= 0 else grand_mean for c in labels],
        dtype=np.float64,
    )


def kfold_cv_r2(X, y, alpha, n_splits=5, seed=42, foia_labels=None, tau=0.0):
    """K-fold CV R^2 at a fixed alpha. Sparse-input safe.

    If foia_labels (int array with -1 for missing) is provided, applies the
    two-stage partialing-out: per fold, compute (optionally shrunk) cluster
    means on the training y, subtract to form the residual, fit ridge on the
    residual, then predict on the test fold as
    (test_cluster_mean_from_train + ridge_residual_pred). Cluster means for
    held-out labels use the train grand mean as fallback.
    """
    kf = KFold(n_splits=n_splits, shuffle=True, random_state=seed)
    preds = np.zeros_like(y, dtype=np.float64)
    for tr, te in kf.split(np.arange(len(y))):
        if foia_labels is not None:
            y_tr = y[tr]
            means, grand = _pooled_cluster_means(y_tr, foia_labels[tr], tau)
            fe_tr = _fe_predict(foia_labels[tr], means, grand)
            fe_te = _fe_predict(foia_labels[te], means, grand)
            m = Ridge(alpha=alpha, fit_intercept=True)
            m.fit(X[tr], y_tr - fe_tr)
            preds[te] = fe_te + m.predict(X[te])
        else:
            m = Ridge(alpha=alpha, fit_intercept=True)
            m.fit(X[tr], y[tr])
            preds[te] = m.predict(X[te])
    return r2_score(y, preds), preds


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="",
                    help="Suffix matching --tag used by 1_vectorize.py.")
    ap.add_argument("--versions", nargs="+", default=VERSIONS, choices=VERSIONS,
                    help="Which exposure-denominator versions to impute.")
    ap.add_argument("--alphas", nargs="+", type=float, default=None,
                    help="Alpha grid for RidgeCV. Default: logspace(-1, 4, 25).")
    ap.add_argument("--cv-folds", type=int, default=5,
                    help="K for K-fold CV R^2 diagnostic (default 5). Uses "
                         "GCV for alpha selection regardless.")
    ap.add_argument("--clip-nonneg-shares", action="store_true", default=True,
                    help="Clip share predictions (mkt_spend_shr, hc_spend_shr) "
                         "to >= 0. Ridge can produce small negatives near zero "
                         "for bounded shares. Exposure is NEVER clipped because "
                         "it can be legitimately negative (b_c coefficients "
                         "in exposure = sum b_c * shr_c can be negative).")
    ap.add_argument("--alpha-scale", type=float, default=1.0,
                    help="Multiply the GCV-picked alpha by this factor before "
                         "fitting the final model. <1 sharpens (less shrinkage, "
                         "more spread, may match observed distribution better); "
                         ">1 softens (more shrinkage, tighter around mean). "
                         "Applied uniformly across variables. Default 1.0.")
    ap.add_argument("--alpha-override", nargs="+", default=None, metavar="VAR=A",
                    help="Per-variable alpha override, e.g. "
                         "'--alpha-override exposure=0.001 mkt_spend_shr=0.5'. "
                         "Skips GCV for listed variables. Combines with "
                         "--alpha-scale (scale applied to override values too).")
    ap.add_argument("--suffix", default="_ridge",
                    help="Output filename suffix (default '_ridge').")
    ap.add_argument("--cluster-filter", default="",
                    help="Path to author_static_clusters_K.csv. If set, drops "
                         "universe authors whose cluster contains fewer FOIA "
                         "PIs than --min-foia-per-cluster from the OUTPUT csv "
                         "(post-hoc filter — ridge fit/predict is unchanged). "
                         "Mirrors 3_impute_exposure.py so K-NN and Ridge outputs "
                         "line up 1:1 by suffix.")
    ap.add_argument("--min-foia-per-cluster", type=int, default=1,
                    help="Minimum FOIA count required for a cluster to be kept "
                         "under --cluster-filter. 1 -> '_cf', 2 -> '_cf2', "
                         "5 -> '_cf5'. Matches the K-NN suffix convention.")
    ap.add_argument("--cluster-indicators", default="",
                    help="Path to author_static_clusters_K.csv. If set, use "
                         "cluster indicators as UNPENALIZED fixed effects via "
                         "two-stage partialing-out: (1) subtract FOIA-anchor "
                         "cluster mean from y; (2) fit ridge on TF-IDF to the "
                         "residual; (3) predict on universe as "
                         "cluster_mean + ridge_pred. Output suffix gains '_ci'. "
                         "Universe authors without a cluster label get "
                         "grand_mean(y_foia) as the FE stage.")
    ap.add_argument("--fe-shrinkage", type=float, default=0.0, metavar="TAU",
                    help="Shrink FOIA-cluster means toward the grand mean by "
                         "empirical-Bayes-style partial pooling: "
                         "mean_shrunk_c = (n_c * y_bar_c + TAU * grand_mean) / "
                         "(n_c + TAU). TAU=0 is raw cluster means (default, "
                         "matches --cluster-indicators without pooling); TAU=5 "
                         "makes a singleton cluster's mean = 83% grand_mean + "
                         "17% raw cluster mean; TAU=inf collapses to grand mean "
                         "everywhere. Useful when the anchor distribution has "
                         "many singleton or doubleton clusters that overfit in "
                         "CV. Ignored unless --cluster-indicators is set.")
    args = ap.parse_args()
    alpha_override = {}
    if args.alpha_override:
        for spec in args.alpha_override:
            k, v = spec.split("=")
            alpha_override[k.strip()] = float(v)

    tag = args.tag
    if tag and not tag.startswith("_"):
        tag = "_" + tag
    alphas = np.asarray(args.alphas) if args.alphas else DEFAULT_ALPHAS

    # cluster-filter suffix, matches 3_impute_exposure.py exactly so K-NN and
    # Ridge outputs are diff-able by suffix:
    #   min=1 -> "_cf",  min>=2 -> "_cf{N}"
    cf_suffix = ""
    if args.cluster_filter:
        cf_suffix = "_cf" if args.min_foia_per_cluster <= 1 else f"_cf{args.min_foia_per_cluster}"
    ci_suffix = "_ci" if args.cluster_indicators else ""

    foia_matrix_file = f"{OUT_DIR}/tfidf_foia{tag}.npz"
    univ_matrix_file = f"{OUT_DIR}/tfidf_universe{tag}.npz"
    foia_ids_file    = f"{OUT_DIR}/foia_ids_ordered{tag}.csv"
    univ_ids_file    = f"{OUT_DIR}/universe_ids{tag}.parquet"

    for p in (foia_matrix_file, univ_matrix_file, foia_ids_file, univ_ids_file):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")
    for v in args.versions:
        f = f"{EXPOSURE_DIR}/athr_exposure_{v}.dta"
        if not os.path.exists(f):
            raise SystemExit(f"missing exposure file for version {v!r}: {f}")

    print(f"Loading TF-IDF matrices (tag={args.tag!r})...", flush=True)
    # X_foia is tiny (~200 rows) so cast to float64 for numeric stability in
    # RidgeCV GCV. X_univ is huge (~2.7M rows, ~4GB float32); keep it float32
    # to halve peak memory. sklearn Ridge.predict handles the type mixing.
    X_foia = scipy.sparse.load_npz(foia_matrix_file).tocsr().astype(np.float64)
    print(f"  X_foia loaded: {X_foia.shape}  nnz={X_foia.nnz:,}", flush=True)
    X_univ = scipy.sparse.load_npz(univ_matrix_file).tocsr()
    print(f"  X_univ loaded: {X_univ.shape}  nnz={X_univ.nnz:,}  dtype={X_univ.dtype}", flush=True)
    df_foia_ids = pd.read_csv(foia_ids_file)
    df_univ_ids = pd.read_parquet(univ_ids_file)
    df_foia_ids["athr_id"] = df_foia_ids["athr_id"].astype(str)
    df_univ_ids["athr_id"] = df_univ_ids["athr_id"].astype(str)
    print(f"  alpha grid: {len(alphas)} points in [{alphas.min():.3g}, {alphas.max():.3g}]", flush=True)

    # --- OPTIONAL: cluster-fixed-effects two-stage residual ---
    # For coarse targets like mkt_spend_shr the topical signal is dominated by
    # between-cluster shifts (ANOVA ceiling ~0.18 vs ridge-on-TF-IDF ~0.01).
    # We handle this by partialling out cluster means from y BEFORE ridge, then
    # adding the cluster mean back on the universe side. Ridge only has to
    # explain the within-cluster residual, which is what TF-IDF is actually
    # good at. Cluster indicators effectively act as unpenalized fixed effects.
    cluster_fe = None  # (foia_labels, univ_labels) as int arrays with -1 for missing
    if args.cluster_indicators:
        if not os.path.exists(args.cluster_indicators):
            raise SystemExit(f"--cluster-indicators file not found: {args.cluster_indicators}")
        print(f"Loading cluster indicators from {args.cluster_indicators}...", flush=True)
        ci = pd.read_csv(args.cluster_indicators,
                         dtype={"athr_id": str, "cluster_label": int})

        def _labels(df_ids):
            merged = df_ids[["athr_id"]].merge(ci, on="athr_id", how="left")
            return merged["cluster_label"].fillna(-1).astype(int).to_numpy()

        foia_labels = _labels(df_foia_ids)
        univ_labels = _labels(df_univ_ids)
        n_foia_lab = int((foia_labels >= 0).sum())
        n_univ_lab = int((univ_labels >= 0).sum())
        print(f"  FOIA labeled: {n_foia_lab}/{len(foia_labels)}   "
              f"universe labeled: {n_univ_lab:,}/{len(univ_labels):,}   "
              f"K = {ci['cluster_label'].nunique()}")
        cluster_fe = (foia_labels, univ_labels)

    # Precompute the kept-cluster set for post-hoc filtering. Same audit lines
    # as 3_impute_exposure.py so the two runs can be compared line by line.
    cluster_info = None
    if args.cluster_filter:
        if not os.path.exists(args.cluster_filter):
            raise SystemExit(f"--cluster-filter file not found: {args.cluster_filter}")
        cl = pd.read_csv(args.cluster_filter)
        if "cluster_label" not in cl.columns or "athr_id" not in cl.columns:
            raise SystemExit(
                f"--cluster-filter file must have columns [athr_id, cluster_label]: "
                f"got {list(cl.columns)}"
            )
        min_n = args.min_foia_per_cluster
        foia_counts = (
            df_foia_ids.merge(cl, on="athr_id", how="inner")["cluster_label"]
            .value_counts()
        )
        kept_clusters  = set(foia_counts[foia_counts >= min_n].index)
        thin_clusters  = set(foia_counts[foia_counts <  min_n].index)
        empty_clusters = set(cl["cluster_label"].unique()) - set(foia_counts.index)
        print(f"\nCluster filter: {args.cluster_filter}  (min-foia-per-cluster={min_n})")
        print(f"  total clusters: {cl['cluster_label'].nunique()}  "
              f"kept (>={min_n} FOIA): {len(kept_clusters)}  "
              f"thin (1-{min_n-1} FOIA): {len(thin_clusters)}  "
              f"empty: {len(empty_clusters)}")
        cluster_info = (cl, kept_clusters, thin_clusters, empty_clusters, min_n)

    summary_rows = []

    for version in args.versions:
        exposure_file = f"{EXPOSURE_DIR}/athr_exposure_{version}.dta"
        output_file   = f"{OUT_DIR}/final_imputed_exposure_{version}{tag}{cf_suffix}{ci_suffix}{args.suffix}.csv"
        print(f"\n========== version={version} ==========")
        df_values  = pd.read_stata(exposure_file)
        df_aligned = pd.merge(df_foia_ids, df_values, on="athr_id", how="left")

        missing = [v for v in IMPUTE_VARS if v not in df_aligned.columns]
        if missing:
            raise SystemExit(f"IMPUTE_VARS missing from {exposure_file}: {missing}")

        df_out = df_univ_ids.copy()

        for var in IMPUTE_VARS:
            y = df_aligned[var].fillna(0).to_numpy().astype(np.float64)
            print(f"\n  --- {var} ---")
            print(f"    anchors: n={len(y)}  mean={y.mean():.5f}  sd={y.std():.5f}  "
                  f"min={y.min():.4f}  max={y.max():.4f}  n_zero={(y==0).sum()}")

            # Two-stage cluster-FE setup: subtract FOIA-anchor cluster means
            # from y so ridge only fits within-cluster residuals. On the
            # universe side we'll add the cluster mean back post-prediction.
            if cluster_fe is not None:
                foia_labels, univ_labels = cluster_fe
                cluster_means, grand_mean = _pooled_cluster_means(
                    y, foia_labels, args.fe_shrinkage,
                )
                y_fe_foia = _fe_predict(foia_labels, cluster_means, grand_mean)
                y_fit = y - y_fe_foia
                y_univ_fe = _fe_predict(univ_labels, cluster_means, grand_mean)
                r2_fe_only = 1.0 - float(
                    np.sum((y - y_fe_foia) ** 2) /
                    max(np.sum((y - y.mean()) ** 2), 1e-12)
                )
                tau_note = f" (tau={args.fe_shrinkage})" if args.fe_shrinkage > 0 else ""
                print(f"    cluster-FE in-sample R^2 (before ridge){tau_note}: {r2_fe_only:.4f}")
            else:
                y_fit = y
                y_univ_fe = None

            # 1. Pick alpha via GCV on y_fit (the residual if --cluster-indicators).
            if var in alpha_override:
                gcv_alpha = float(alpha_override[var])
                print(f"    (alpha override for {var}: skipping GCV)")
            else:
                gcv = RidgeCV(alphas=alphas, fit_intercept=True,
                              scoring=None, cv=None)
                gcv.fit(X_foia, y_fit)
                gcv_alpha = float(gcv.alpha_)
            best_alpha = gcv_alpha * float(args.alpha_scale)

            # 2. In-sample R^2 measured against the ORIGINAL y (add FE back).
            ridge_in = Ridge(alpha=best_alpha, fit_intercept=True).fit(X_foia, y_fit).predict(X_foia)
            in_sample_pred = ridge_in + (y_fe_foia if cluster_fe is not None else 0.0)
            r2_in = r2_score(y, in_sample_pred)

            # 3. Honest K-fold CV R^2 (two-stage inside the loop when FE is on).
            r2_cv, cv_preds = kfold_cv_r2(
                X_foia, y, best_alpha,
                n_splits=args.cv_folds,
                foia_labels=(cluster_fe[0] if cluster_fe is not None else None),
                tau=args.fe_shrinkage,
            )
            scale_note = "" if args.alpha_scale == 1.0 and var not in alpha_override else \
                         f"  (gcv={gcv_alpha:.4g}, scale={args.alpha_scale})"
            print(f"    alpha* = {best_alpha:.4g}{scale_note}   in-sample R2 = {r2_in:.4f}   "
                  f"{args.cv_folds}-fold CV R2 = {r2_cv:.4f}")

            # 4. Fit on full anchor set (on residuals if FE) and predict for universe.
            model = Ridge(alpha=best_alpha, fit_intercept=True)
            model.fit(X_foia, y_fit)
            coef = model.coef_.astype(np.float64, copy=False)
            y_univ = X_univ.dot(coef) + float(model.intercept_)
            if y_univ_fe is not None:
                y_univ = y_univ + y_univ_fe
            if args.clip_nonneg_shares and var in ("mkt_spend_shr", "hc_spend_shr"):
                y_univ = np.clip(y_univ, 0.0, None)

            df_out[var] = y_univ
            nz = (y_univ != 0).sum()
            print(f"    universe pred: mean={y_univ.mean():.5f}  sd={y_univ.std():.5f}  "
                  f"min={y_univ.min():.5f}  max={y_univ.max():.5f}  nonzero={nz:,}/{len(y_univ):,}")

            summary_rows.append({
                "version": version, "var": var,
                "n_anchors": len(y),
                "obs_mean": y.mean(), "obs_sd": y.std(),
                "alpha": best_alpha,
                "r2_in_sample": r2_in, f"r2_cv{args.cv_folds}": r2_cv,
                "pred_mean": y_univ.mean(), "pred_sd": y_univ.std(),
                "pred_min": y_univ.min(), "pred_max": y_univ.max(),
                "shrinkage_ratio": (y_univ.std() / y.std()) if y.std() > 0 else np.nan,
            })

        if cluster_info is not None:
            cl, kept_clusters, thin_clusters, empty_clusters, min_n = cluster_info
            n_before = len(df_out)
            df_out = df_out.merge(cl, on="athr_id", how="left")
            n_no_cluster = int(df_out["cluster_label"].isna().sum())
            cluster_col = df_out["cluster_label"]
            keep_mask   = cluster_col.notna() & cluster_col.isin(kept_clusters)
            n_in_thin   = int((cluster_col.notna() & cluster_col.isin(thin_clusters)).sum())
            n_in_empty  = int((cluster_col.notna() & cluster_col.isin(empty_clusters)).sum())
            df_out = df_out.loc[keep_mask].drop(columns=["cluster_label"])
            print(f"  cluster filter: dropped {n_before - len(df_out):,}/{n_before:,} "
                  f"({100*(n_before-len(df_out))/n_before:.2f}%)  "
                  f"(thin: {n_in_thin:,}, empty: {n_in_empty:,}, "
                  f"no cluster: {n_no_cluster:,})")

        df_out.to_csv(output_file, index=False)
        print(f"\n  Saved {output_file}")

    print("\n" + "=" * 78)
    print("Ridge imputation summary")
    print("=" * 78)
    df_summary = pd.DataFrame(summary_rows)
    with pd.option_context("display.width", 200,
                           "display.max_columns", None,
                           "display.float_format", "{:.4f}".format):
        print(df_summary.to_string(index=False))

    summary_out = f"{OUT_DIR}/ridge_impute_summary{tag}.csv"
    df_summary.to_csv(summary_out, index=False)
    print(f"\nSaved summary: {summary_out}")
    print("\nDone!")


if __name__ == "__main__":
    main()
