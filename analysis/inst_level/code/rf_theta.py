"""Step 6: random forest on institution-specific exposure responses.

Reads ../temp/theta_chars.csv (written by theta_hetero.do, so the sample and
the standardized characteristics are identical to steps 4-5), tunes a weighted
forest by 5-fold CV, scores it out of sample on an outer fold, and writes SHAP
values back for Stata to plot.

Neither rforest nor pystacked is installed and Stata has no native forest, so
this runs under the system python3.
"""

import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor
from sklearn.inspection import permutation_importance
from sklearn.model_selection import GridSearchCV, KFold

SEED = 90210
# joblib reads cpu_count(), which is 1 inside the cgroup on the login node and
# would silently serialize the grid; the affinity mask is the real allocation.
NJOBS = len(os.sched_getaffinity(0))
SRC = "../temp/theta_chars.csv"
OUT_IMP = "../temp/rf_importance.csv"
OUT_MET = "../temp/rf_metrics.csv"
FIGDIR = "../output/figures"

LABELS = {
    "ln_endowment": "Log endowment",
    "ln_tot_fund": "Log total R&D funding",
    "shr_fed_fund": "Federal share of funding",
    "shr_state_fund": "State/local share of funding",
    "shr_inst_fund": "Institutional share of funding",
    "shr_bus_fund": "Business share of funding",
    "shr_nonprof_fund": "Nonprofit share of funding",
    "ln_ls_fund": "Log life-science funding",
    "shr_ls_fund": "Life-science share of funding",
    "shr_bio_in_ls": "Biology share of life science",
    "shr_fed_in_ls": "Federal share of life science",
    "shr_hhs_in_bio": "HHS share of biology",
    "ln_contracts_fund": "Log contract funding",
    "shr_contracts_fund": "Contract share of funding",
    "shr_grants_fund": "Grant share of funding",
    "shr_subrec_fund": "Subrecipient share of funding",
    "ln_basic_expend": "Log basic-research expenditure",
    "shr_basic_expend": "Basic share of R&D expenditure",
    "shr_applied_expend": "Applied share of R&D expenditure",
    "shr_fed_basic": "Federal share of basic expenditure",
    "shr_fed_applied": "Federal share of applied expenditure",
    "ln_dev_expend": "Log development expenditure",
    "ln_ls_cap_expend": "Log life-science capital expenditure",
    "shr_ls_cap": "Capital intensity of life science",
    "ln_n_pi": "Log number of PIs",
    "ln_pre_out": "Log pre-2014 publication output",
    "mean_exp": "Mean PI exposure",
    "sd_exp": "SD of PI exposure",
    "public": "Public institution",
    "r1": "R1 Carnegie classification",
    "ln_msa_size": "Log MSA research size",
}

d = pd.read_csv(SRC)
feats = [c for c in d.columns if c.startswith("z_")]
if not feats:
    sys.exit("no z_ columns in " + SRC)

d = d.dropna(subset=feats + ["beta_inst", "w_prec"])
names = [f[2:] for f in feats]
disp = [LABELS.get(n, n) for n in names]
X = d[feats].to_numpy(dtype=float)
y = d["beta_inst"].to_numpy(dtype=float)
w = d["w_prec"].to_numpy(dtype=float)
w = w / w.mean()

n, p = X.shape
print(f"random forest: n = {n} institutions, p = {p} characteristics", flush=True)
if n < 60:
    print("WARNING: thin sample; treat the forest as descriptive only", flush=True)

# ------------------------------------------------------------------ tuning
# Depth and leaf size are the binding hyperparameters at n in the low
# hundreds -- deep trees on ~100 rows memorize, so the grid is deliberately
# shallow-leaning and n_estimators is only large enough to stabilize.
grid = {
    "n_estimators": [300, 1000],
    "max_depth": [2, 3, 5, None],
    "min_samples_leaf": [3, 5, 10],
    "max_features": [max(1, p // 3), max(1, int(np.sqrt(p))), 1.0],
}
inner = KFold(n_splits=5, shuffle=True, random_state=SEED)
search = GridSearchCV(
    RandomForestRegressor(bootstrap=True, oob_score=True, random_state=SEED, n_jobs=1),
    grid,
    cv=inner,
    scoring="r2",
    n_jobs=NJOBS,
    refit=True,
)
search.fit(X, y, sample_weight=w)
best = search.best_params_
print("tuned by 5-fold CV:", best, flush=True)
print(f"  best inner CV R2 = {search.best_score_:8.4f}", flush=True)

rf = search.best_estimator_

# --------------------------------------------------------------- performance
# The tuned model's own CV score is optimistic (the grid was picked on it), so
# out-of-sample fit is taken from predictions made by a forest that never saw
# the held-out institution, with the tuning held fixed.
outer = KFold(n_splits=5, shuffle=True, random_state=SEED + 1)
yhat = np.empty_like(y)
for tr, te in outer.split(X):
    f = RandomForestRegressor(bootstrap=True, random_state=SEED, n_jobs=NJOBS, **best)
    f.fit(X[tr], y[tr], sample_weight=w[tr])
    yhat[te] = f.predict(X[te])

ybar = np.average(y, weights=w)
sse = np.sum(w * (y - yhat) ** 2)
sst = np.sum(w * (y - ybar) ** 2)
cv_r2 = 1 - sse / sst
cv_rmse = np.sqrt(sse / w.sum())
in_rmse = np.sqrt(np.sum(w * (y - rf.predict(X)) ** 2) / w.sum())

print(f"OOB R2               = {rf.oob_score_:8.4f}", flush=True)
print(f"OOS R2 (5-fold CV)   = {cv_r2:8.4f}", flush=True)
print(f"OOS RMSE (5-fold CV) = {cv_rmse:8.4f}", flush=True)
print(f"in-sample RMSE       = {in_rmse:8.4f}", flush=True)
print(f"SD of beta_inst      = {np.sqrt(sst / w.sum()):8.4f}", flush=True)
if cv_r2 <= 0:
    print(
        "OOS R2 <= 0: the weighted mean predicts held-out institutions at least\n"
        "as well as the forest, so the 31 characteristics carry no detectable\n"
        "out-of-sample signal about beta_inst. Read the SHAP exhibits as a\n"
        "description of the in-sample fit only.",
        flush=True,
    )

pd.DataFrame(
    {
        "metric": ["n_inst", "n_chars", "oob_r2", "cv_r2", "cv_rmse",
                   "in_rmse", "sd_beta", "best_cv_r2_inner"],
        "value": [n, p, rf.oob_score_, cv_r2, cv_rmse, in_rmse,
                  np.sqrt(sst / w.sum()), search.best_score_],
    }
).to_csv(OUT_MET, index=False)

# --------------------------------------------------------------------- SHAP
import shap  # noqa: E402

expl = shap.TreeExplainer(rf)
sv = expl.shap_values(X, check_additivity=False)
mean_abs = np.abs(sv).mean(axis=0)

perm = permutation_importance(
    rf, X, y, sample_weight=w, n_repeats=50, random_state=SEED,
    scoring="neg_mean_squared_error", n_jobs=NJOBS,
)

imp = pd.DataFrame(
    {
        "vname": names,
        "vlabel": disp,
        "mean_abs_shap": mean_abs,
        "perm_importance": perm.importances_mean,
        "perm_importance_sd": perm.importances_std,
        "impurity_importance": rf.feature_importances_,
    }
).sort_values("mean_abs_shap", ascending=False)
imp.to_csv(OUT_IMP, index=False)
print(f"\nwrote {OUT_IMP}", flush=True)
print(imp.head(15).to_string(index=False), flush=True)

Xd = pd.DataFrame(X, columns=disp)

shap.summary_plot(sv, Xd, max_display=15, show=False)
plt.gcf().set_size_inches(7.5, 8)
plt.xlabel("SHAP value (effect on predicted $\\beta_{inst}$)")
plt.tight_layout()
plt.savefig(f"{FIGDIR}/ex6_shap_summary.pdf")
plt.close("all")

shap.summary_plot(sv, Xd, plot_type="bar", max_display=15, show=False)
plt.gcf().set_size_inches(7.5, 8)
plt.xlabel("Mean |SHAP| (units of $\\beta_{inst}$)")
plt.tight_layout()
plt.savefig(f"{FIGDIR}/ex6_shap_bar.pdf")
plt.close("all")

top = imp.head(3)["vname"].tolist()
for k, v in enumerate(top, start=1):
    j = names.index(v)
    shap.dependence_plot(j, sv, Xd, interaction_index="auto", show=False)
    plt.gcf().set_size_inches(6.5, 5)
    plt.tight_layout()
    plt.savefig(f"{FIGDIR}/ex6_shap_dep{k}_{v}.pdf")
    plt.close("all")
print("wrote SHAP summary, bar and dependence figures to " + FIGDIR, flush=True)
