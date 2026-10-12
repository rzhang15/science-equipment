* Run from derived/nih/match_pi_athr/code after total_cost_pi is available.
* Updates the divided baseline without rerunning matching or other panels.
set more off
clear all
use athr_id year row_key research total_cost_pi ///
    using ../output/nih_grants_by_athr_id.dta, clear
drop if mi(year)
duplicates drop athr_id year row_key, force
gen double nih_cost_pre_pi = cond(inrange(year, 2010, 2013) & research == 1, total_cost_pi, 0)
collapse (sum) nih_cost_pre_pi, by(athr_id)
gen double nih_funding_baseline_pi = nih_cost_pre_pi / 4
label var nih_funding_baseline_pi "mean annual research funding per listed PI, FY2010-2013 (zeros included)"
tempfile allocated
save `allocated'
use ../output/nih_baseline_by_athr.dta, clear
capture drop nih_cost_pre_pi nih_funding_baseline_pi
merge 1:1 athr_id using `allocated', assert(3) nogen
assert nih_funding_baseline_pi <= nih_funding_baseline + 0.00001
assert nih_funding_baseline_pi >= 0 & !mi(nih_funding_baseline_pi)
assert abs(nih_funding_baseline_pi * 4 - nih_cost_pre_pi) < 0.00001
save ../output/nih_baseline_by_athr.dta, replace
di "NIH_PI_BASELINE_REBUILT"
