* Reconstruct older eligibility and k2 covariates on the frozen current sample.
* Run from this directory after audit_nih_age_funding.py and the composition audit.
set more off
clear all
capture log close
args work out
if "`work'" == "" local work /tmp/nih_age_funding_audit
if "`out'" == "" local out ../output/nih_age_funding_audit
log using "`out'/history_models.log", replace text
tempname effects
postfile `effects' str32 outcome str32 spec str32 contrast double b se p N n_pis using "`out'/history_models", replace
global NIH_AGE_AUDIT_HANDLE `effects'
do audit_nih_age_funding_models.do
use "`work'/audit_panel.dta", clear
merge m:1 athr_id using "`out'/historical_covariates.dta", assert(3) nogen
fit_age_funding ppr_cnt, spec(legacy_ever_eligibility) group(legacy_cell)
fit_age_funding ppr_cnt if !mi(cell), spec(legacy_labels_current_sample) group(legacy_cell)
fit_age_funding ppr_cnt, spec(legacy_fixed_cutoff) group(legacy_fixed_cell)
preserve
replace exposure = exposure_k2
replace mkt_spend_shr = share_k2
fit_age_funding ppr_cnt, spec(k2_current_groups) group(cell)
restore
gen byte complete_cell6 = cell
replace complete_cell6 = 5 if mi(cell) & young == 1
replace complete_cell6 = 6 if mi(cell) & young == 0
fit_age_funding ppr_cnt, spec(all_pi_pre_only_categories) group(complete_cell6)
fit_age_funding ppr_cnt if !mi(cell) | (!mi(nih_cost_ever) & nih_cost_ever>0), spec(future_only_award_diagnostic) group(complete_cell6)
postclose `effects'
use "`out'/history_models", clear
export delimited using "`out'/history_models.csv", replace
di "NIH_AGE_HISTORY_COMPLETE"
log close
exit, clear
