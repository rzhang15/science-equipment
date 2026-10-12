This is a separate GS Lab style analysis module. Its `code/`, `external/`,
`temp/`, and `output/` directories are self-contained; existing analyses and
their outputs are read through links. The build never runs their do-files.

Run from the repository environment:

```bash
python analysis/imputation_validation/code/make.py
```

Use `--validation-only` to rebuild validation without output regressions.
`STATA_BIN` can override the Stata executable. The build uses the installed
`gslab_make`, pandas, NumPy, SciPy, and Stata 17 with the project's existing
`preliminaries`, `modern` scheme, and `ppmlhdfe` installation.

`prep_university.py` recovers purchasing universities from the small FOIA PI
mapping files. It preserves the one donor assigned to multiple universities.
`prep_validation.py` reconstructs the existing 208-PI leave-one-out exercise:
hc_all3 spending shares, K=3, squared cosine similarity weights, floor=0.05,
and fixed market-level `b_eb` estimates from `did_coefs_eb_price_all3.dta`.
The benchmark assigns each held-out PI the other 207 donors' mean exposure.
The preparation reports agreement with the archived LOO file and saves
input fingerprints and the price shocks used.

Purchasing university, cluster_30, and years since the first last-author
publication are joined to every validation PI. Career stages in 2014 are
<10, 10 to <20, and >=20 years; missing career metadata remains explicit.
The unrestricted last-author panel supplies this clock, before estimation
sample exclusions. These are publication-based lab ages, not biological ages.

The estimation support is measured using one row per PI from the current
`es_all_jrnls_r1_r2.dta` sample, not the entire text universe or PI-year weights.
FOIA PIs' LOO similarity is used in validation; their artificial similarity=1
from the estimation panel is excluded from the non-FOIA distribution.

`validation.do` writes one two-panel figure, error and calibration tables,
career-stage diagnostics, and sample coverage. Absolute nearest-donor cosine
similarity (`max_sim`) is the same measure used by the current output
robustness analysis. Broad groups have boundaries 0.15, 0.20, and 0.27.
All group error statistics use complete method/benchmark prediction pairs.
Calibration regresses observed exposure on predicted exposure with an intercept.

The candidate cutoffs are 0.20 (existing validation split) and 0.27 (working-note
split). The lowest cutoff meeting the descriptive validation criteria is chosen
before any output estimates are fit: at least 30 validation PIs in the upper
tail, at least 10% lower MAE than the remaining-donor mean, lower RMSE,
positive calibration slope, and greater MAE gain than the lower tail.
The decision is saved in `output/validation_selection.dta`, `.do`, and `.txt`.
If neither candidate qualifies, the build fits only the full-sample regression.

The paired PI-resampling interval for MAE gain uses 2,000 draws and seed 8975.
It conditions on the already fitted LOO predictions, common donor bank, and
fixed market prices; it does not refit the model or estimate donor-pool or
price uncertainty. The interval is reported without a significance gate.
An interval spanning zero leaves the prediction advantage uncertain. The
restriction is an exploratory sensitivity check, not certification of accuracy
or justification for giving similarity scores precision-weight interpretations.
Observed FOIA exposure can also be imperfect when purchasing records are incomplete.

`robustness.do` reads the frozen decision and reproduces the main unweighted
publication-count specification:

```stata
ppmlhdfe ppr_cnt Z_it Z_share_it, absorb(athr_id year) vce(cluster athr_id)
```

Here `Z_it=exposure*(year>=2014)` and
`Z_share_it=mkt_spend_shr*(year>=2014)`. The selected restriction retains all
observed FOIA PIs and applies the absolute threshold to non-FOIA PIs, as in
the existing upper-half check. The build checks that canonical panel exposures,
spending shares, and match diagnostics agree with their current sources; it
stops on disagreement rather than changing the existing panel. Sample counts
and PI-level exposure variation use the actual estimation sample. Coefficient
intervals use the existing normal 95% convention. Composition tables describe
institutions, research clusters, career stage, and FOIA status. Implied output
changes use the same full-sample mean exposure for both estimates.

Primary artifacts:

- `output/validation_pi.dta` / `.csv`: the 208-PI validation dataset.
- `output/panel_pi.dta` / `.csv`: estimation support and PI metadata.
- `output/figures/paper/validation_similarity.pdf`: the validation figure;
  a presentation version is in `output/figures/pres/`.
- `output/tables/validation_by_similarity.csv` and `validation_by_career.csv`.
- `output/tables/validation_candidates.csv`: cutoff evidence and uncertainty.
- `output/tables/output_regressions.csv`: full and selected output estimates,
  sample sizes, exposure variation, and confidence intervals.
- `output/tables/output_robustness.txt`: readable regression comparison.
- `output/tables/output_composition.csv`: composition before and after restriction.
- `output/input_manifest.json` and the build/program logs.
- `output/results.txt`: a reproducible reading of the findings and composition shifts.

University holdout is deferred as the optional second pass. This module retains
the university metadata needed for it and makes no claim of validated transfer
across institutions. Regenerate only the figure, without changing the frozen
selection or output regressions, by running `stata-mp -b do validation.do figure`
from `code/`.
