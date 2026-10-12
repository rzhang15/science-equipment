* Run from analysis/foia_case_study/code; preserves full-credit funding.
set more off
clear all
capture log close
log using ../output/pi_allocation_rerun.log, text replace
use ../../../derived/nih/match_pi_athr/temp/pi_grant_long.dta, clear
assert !mi(strtrim(pi_name))
gen byte listed_pi = 1
collapse (sum) n_listed_pis=listed_pi, by(grant_id)
isid grant_id
assert n_listed_pis >= 1
tempfile counts
save `counts'
use ../external/nih/nih_grants_by_athr_id.dta, clear
capture drop n_listed_pis total_cost_pi
merge m:1 grant_id using `counts', keep(1 3) assert(2 3) nogen
assert n_listed_pis >= 1 & !mi(n_listed_pis)
gen double total_cost_pi = total_cost / n_listed_pis
assert total_cost_pi <= total_cost if !mi(total_cost) & total_cost >= 0
assert abs(total_cost_pi*n_listed_pis-total_cost) < 0.00001 if !mi(total_cost)
label var total_cost_pi "total award cost divided by all listed PIs"
label var n_listed_pis "number of nonblank PIs listed before author matching"
save ../external/nih/nih_grants_by_athr_id.dta, replace
* Load program definitions without running the full analysis.
// INSERT_ANALYSIS_PROGRAMS
gather_nih
foreach suf in "" "_public" {
    local opt = cond("`suf'" == "", "", "suf(_public)")
    foreach samp in all foia {
        prod_per_dollar, samp(`samp') `opt'
    }
}
di "PI_ALLOCATION_RERUN_PASSED"
log close
