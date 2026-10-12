* Diagnose age x NIH funding heterogeneity without changing production results.
* Inputs: frozen annual panel with prior labels and baseline funding continuity.
* Run from this code directory:
* do audit_nih_age_funding.do /tmp/nih_age_funding_audit output_directory
set more off
clear all
capture log close
args work out
if "`work'" == "" local work /tmp/nih_age_funding_audit
if "`out'" == "" local out ../output/nih_age_funding_audit
* Load the production period-mean helper without running the main analysis.
global HET_SKIP_MAIN 1
do analysis.do
capture mkdir "`out'"
log using "`out'/models.log", replace text

tempname effects
postfile `effects' str32 outcome str32 spec str32 contrast double b se p N n_pis ///
    using "`out'/model_results", replace
global NIH_AGE_AUDIT_HANDLE `effects'

do audit_nih_age_funding_models.do

use "`work'/audit_panel.dta", clear
gen byte old_cell = 1 + 2*(1-young) + (1-old_high) if !mi(old_high)
gen byte orig_cell = 1 + 2*(1-young) + (1-orig_high) if !mi(orig_high)
fit_age_funding ppr_cnt, spec(pub_current) group(cell)
fit_age_funding ppr_cnt, spec(pub_before_program_exclusion) group(old_cell)
fit_age_funding ppr_cnt if !mi(cell) & !mi(old_cell), spec(pub_common_old_labels) group(old_cell)
fit_age_funding ppr_cnt if !mi(cell) & !mi(old_cell), spec(pub_common_new_labels) group(cell)
fit_age_funding ppr_cnt if !mi(cell) & !mi(orig_cell), spec(pub_common_original_labels) group(orig_cell)
fit_age_funding ppr_cnt if !mi(cell) & !mi(orig_cell), spec(pub_common_current_labels) group(cell)
fit_age_funding ppr_cnt if high_nihd == old_high, spec(pub_stable_groups) group(cell)
fit_age_funding ppr_cnt, spec(pub_continuity) group(cell8)
fit_age_funding ppr_cnt, spec(pub_pre_placebo) group(cell) pre
fit_age_funding ppr_cnt, spec(pub_field_year) group(cell) fes(athr_id cluster_30#year)
fit_age_funding nih_total_cost, spec(award_period_means) group(cell) collapsed
fit_age_funding nih_total_cost, spec(award_annual_panel) group(cell)
fit_age_funding nih_total_cost if !mi(cell) & !mi(old_cell), spec(award_common_old_labels) group(old_cell) collapsed
fit_age_funding nih_total_cost, spec(award_continuity) group(cell8) collapsed

postclose `effects'
use "`out'/model_results", clear
export delimited using "`out'/model_results.csv", replace
list if strpos(contrast,"age_") | contrast == "joint_pre_placebo", noobs abbreviate(32)
di "NIH_AGE_FUNDING_AUDIT_COMPLETE"
log close
exit, clear
