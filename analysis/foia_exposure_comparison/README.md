This separate GS Lab style module compares observed and leave-one-out exposure
for the exact same FOIA PIs. Existing analyses and their outputs are read through
`external/` links; the build writes only this module's `temp/` and `output/`.

Run `python analysis/foia_exposure_comparison/code/make.py` in the project
environment. Stata 17, gslab_make, and the existing ppmlhdfe installation are
required. STATA_BIN can override the executable.

The sample is the observed-FOIA subset of the saved R1+R2 estimation panel,
`es_all_jrnls_r1_r2.dta`: 82 PIs and 820 PI-years in the checked version.
The code joins the recovered 208-PI leave-one-out predictions from
`analysis/imputation_validation/output/validation_pi.dta`. Each held-out PI's
prediction excludes that PI from its donor bank. Observed exposure and shares
are checked against the validation inputs to keep the price/exposure definitions
consistent.

Three comparisons are fixed in the code before their results are inspected:

1. Observed exposure and observed treated-market share.
2. Leave-one-out predicted exposure and observed treated-market share.
3. Leave-one-out predicted exposure and predicted treated-market share.

Each regression uses annual last-author publication count, PPML, PI and year
fixed effects, PI-clustered standard errors, and exposure/share interacted with
post-2014. The second comparison changes only exposure; the third changes both
parts of the recipient imputation. All three retain the same 82 PIs and 820 rows.

`output/comparison.csv` and `.dta` report coefficients, standard errors, normal
95% intervals, sample counts, and normal-approximation p-values. The full Stata
log and estimated models are saved. `output/paired_pi.dta`/`.csv` retain PI-level
inputs and metadata. None of these fits changes a cutoff or searches for a
negative coefficient.

In the checked sample, exposure coefficients are +4.128 (SE 1.674) using observed
inputs, +0.313 (SE 2.689) replacing only exposure, and +0.584 (SE 2.567) replacing
both exposure and the share control. The observed specification reproduces the
saved FOIA-only estimate. It is positive and conventionally significant under
the existing PI-clustered inference, unlike the saved no-share estimate, which
is positive and insignificant.

The imputed specifications weaken the positive association toward zero, without
reproducing the negative full-panel coefficient. This does not establish that
imputation is harmless outside the FOIA sample. Predictions may behave differently
for non-FOIA recipients, and observed FOIA purchasing records may be incomplete.
The comparison also does not establish why the measured FOIA association differs
from the full-panel association. In the checked panel, 65 of the 82 FOIA PIs are
at Michigan, and all are drawn from only five universities. Population differences,
institution-specific changes, and sensitivity to influential PIs remain plausible
explanations to examine. No coefficient-difference or influence test was run here.
