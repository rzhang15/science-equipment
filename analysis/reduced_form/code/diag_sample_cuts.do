*  Which SAMPLE CUTS (not observation-level trimming) reduce the 2016 spike?
*  Tests each cut, reports int_lag2 for base & +mshr specs, plus the pretrend
*  int_lead2, and sample size.
set more off
capture log close
capture program drop _all
log using diag_sample_cuts.log, replace text

use ../temp/es_all_jrnls_r1_r2_public.dta, clear
keep if exposure > 0
gen rel = year - 2014

* Precompute leads/lags & mshr
qui sum rel
local abs_lead = abs(r(min))
local abs_lag  = r(max)
forval i = 1/`abs_lag' {
    gen int_lag`i' = exposure if rel == `i'
    replace int_lag`i' = 0 if mi(int_lag`i')
    gen mshr_lag`i' = mkt_spend_shr if rel == `i'
    replace mshr_lag`i' = 0 if mi(mshr_lag`i')
}
forval i = 1/`abs_lead' {
    gen int_lead`i' = exposure if rel == -`i'
    replace int_lead`i' = 0 if mi(int_lead`i')
    gen mshr_lead`i' = mkt_spend_shr if rel == -`i'
    replace mshr_lead`i' = 0 if mi(mshr_lead`i')
}
gen int_lag0 = exposure if rel == 0
replace int_lag0 = 0 if mi(int_lag0)
gen mshr_lag0 = mkt_spend_shr if rel == 0
replace mshr_lag0 = 0 if mi(mshr_lag0)
local ileads
local ilags
local mleads
local mlags
forval i = 2/`abs_lead' {
    local ileads int_lead`i' `ileads'
    local mleads mshr_lead`i' `mleads'
}
forval i = 0/`abs_lag' {
    local ilags `ilags' int_lag`i'
    local mlags `mlags' mshr_lag`i'
}

* Precompute pre-period stats used for cuts
gen pre_pprs = ppr_cnt if year < 2014
bys athr_id: egen pi_pre_mean  = mean(pre_pprs)
bys athr_id: egen pi_pre_min   = min(pre_pprs)
bys athr_id: egen pi_pre_years_active = total(pre_pprs > 0 & !mi(pre_pprs))
bys athr_id: gen _first = _n == 1
xtile exp_q_tmp = exposure if _first == 1, n(4)
bys athr_id: egen exp_q = max(exp_q_tmp)
drop exp_q_tmp

program est_and_store
    syntax, name(string) [ if_expr(string) ]
    if "`if_expr'" == "" local if_expr "1==1"
    qui count if _first == 1 & `if_expr'
    local n_pi = r(N)
    qui ppmlhdfe ppr_cnt `1' if `if_expr', absorb(athr_id year) vce(cluster athr_id)
    estimates store `name'
    di as text "  `name'  N_PI=`n_pi'"
end

*==== baseline (positive-exposure only, no cut) ====
di as text _newline "======= BASELINE ======="
qui count if _first == 1
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags', absorb(athr_id year) vce(cluster athr_id)
estimates store base
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags', absorb(athr_id year) vce(cluster athr_id)
estimates store base_m

*==== CUT 1: require pre-period active in ALL 4 years (balanced publishers) ====
di as text _newline "======= CUT 1: pre-period active every year 2010-2013 ======="
qui count if _first == 1 & pi_pre_years_active == 4
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags' if pi_pre_years_active == 4, absorb(athr_id year) vce(cluster athr_id)
estimates store c1
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if pi_pre_years_active == 4, absorb(athr_id year) vce(cluster athr_id)
estimates store c1_m

*==== CUT 2: require pi_pre_mean >= 2 ====
di as text _newline "======= CUT 2: pre_ppr_mean >= 2 ======="
qui count if _first == 1 & pi_pre_mean >= 2
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags' if pi_pre_mean >= 2, absorb(athr_id year) vce(cluster athr_id)
estimates store c2
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if pi_pre_mean >= 2, absorb(athr_id year) vce(cluster athr_id)
estimates store c2_m

*==== CUT 3: require pi_pre_mean >= 3 ====
di as text _newline "======= CUT 3: pre_ppr_mean >= 3 ======="
qui count if _first == 1 & pi_pre_mean >= 3
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags' if pi_pre_mean >= 3, absorb(athr_id year) vce(cluster athr_id)
estimates store c3
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if pi_pre_mean >= 3, absorb(athr_id year) vce(cluster athr_id)
estimates store c3_m

*==== CUT 4: drop bottom quartile of exposure (low-signal PIs) ====
di as text _newline "======= CUT 4: exposure Q >= 2 (drop bottom Q) ======="
qui count if _first == 1 & exp_q >= 2
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags' if exp_q >= 2, absorb(athr_id year) vce(cluster athr_id)
estimates store c4
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if exp_q >= 2, absorb(athr_id year) vce(cluster athr_id)
estimates store c4_m

*==== CUT 5: drop top quartile of exposure (removes high-mass driver) ====
di as text _newline "======= CUT 5: exposure Q <= 3 (drop top Q) ======="
qui count if _first == 1 & exp_q <= 3
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags' if exp_q <= 3, absorb(athr_id year) vce(cluster athr_id)
estimates store c5
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if exp_q <= 3, absorb(athr_id year) vce(cluster athr_id)
estimates store c5_m

*==== CUT 6: middle 2 quartiles only ====
di as text _newline "======= CUT 6: exposure Q in {2,3} ======="
qui count if _first == 1 & inrange(exp_q, 2, 3)
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags' if inrange(exp_q, 2, 3), absorb(athr_id year) vce(cluster athr_id)
estimates store c6
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if inrange(exp_q, 2, 3), absorb(athr_id year) vce(cluster athr_id)
estimates store c6_m

*==== CUT 7: require no zero years in pre-period AND pre_mean >= 2 ====
di as text _newline "======= CUT 7: balanced pre-period AND pre_mean >= 2 ======="
qui count if _first == 1 & pi_pre_years_active == 4 & pi_pre_mean >= 2
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags' if pi_pre_years_active == 4 & pi_pre_mean >= 2, absorb(athr_id year) vce(cluster athr_id)
estimates store c7
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if pi_pre_years_active == 4 & pi_pre_mean >= 2, absorb(athr_id year) vce(cluster athr_id)
estimates store c7_m

*==== CUT 8: drop PIs whose ppr_cnt is zero in 2013 (baseline year) ====
gen ppr_2013 = ppr_cnt if year == 2013
bys athr_id: egen pi_ppr_2013 = max(ppr_2013)
di as text _newline "======= CUT 8: nonzero ppr in 2013 (baseline year) ======="
qui count if _first == 1 & pi_ppr_2013 > 0
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags' if pi_ppr_2013 > 0, absorb(athr_id year) vce(cluster athr_id)
estimates store c8
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if pi_ppr_2013 > 0, absorb(athr_id year) vce(cluster athr_id)
estimates store c8_m

*==== summary tables ====
di as text _newline "======= SUMMARY: int_lead2 (2012 pretrend) & int_lag2 (2016 spike), BASE spec ======="
estimates table base c1 c2 c3 c4 c5 c6 c7 c8, keep(int_lead2 int_lag2) b(%9.4f) se

di as text _newline "======= SUMMARY: int_lead2 & int_lag2, +MSHR spec ======="
estimates table base_m c1_m c2_m c3_m c4_m c5_m c6_m c7_m c8_m, keep(int_lead2 int_lag2) b(%9.4f) se

di as text _newline "======= FULL event-time coefs, best candidate (BASE spec) ======="
estimates table base c1 c2 c3 c7 c8, keep(`ileads' `ilags') b(%9.4f) se

log close
