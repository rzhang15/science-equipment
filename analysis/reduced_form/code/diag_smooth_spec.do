*  Which spec has the smoothest post-period?  Report full event-time coeffs
*  for the top candidates: bare, bare+num_place, pre_mean>=1 — each in BASE
*  and +MSHR flavors.
set more off
capture log close
log using diag_smooth_spec.log, replace text

*==== rebuild bare positive-exposure panel ====
use athr_id year ppr_cnt cite_affl_wt affl_wt ///
    using ../external/samp/athr_panel_full_year_last_all_jrnls_r1_r2_public, clear
bys athr_id: egen min_year = min(year)
keep if min_year <= 2010
keep if inrange(year, 2010, 2019)
preserve
    import delimited ../external/exposure/final_imputed_shift_share_hc_cf, clear
    rename exposure_ss imputed
    rename sum_imputed_shares imputed_mkt_spend_shr
    tempfile _expo
    save `_expo'
restore
merge m:1 athr_id using `_expo', assert(1 2 3) keep(3) nogen
merge m:1 athr_id using ../external/real_exposure/athr_exposure_hc, assert(1 2 3) keep(1 3) nogen
gen foia_athr = 1 if !mi(exposure)
replace imputed = exposure if !mi(exposure)
replace imputed_mkt_spend_shr = mkt_spend_shr if !mi(mkt_spend_shr)
drop exposure mkt_spend_shr
rename imputed exposure
rename imputed_mkt_spend_shr mkt_spend_shr
drop if mi(exposure) | mi(mkt_spend_shr)
keep if exposure > 0
drop if mkt_spend_shr < 0
gegen athr = group(athr_id)
preserve
    contract athr athr_id exposure mkt_spend_shr min_year foia_athr
    drop _freq
    tempfile _xw
    save `_xw'
restore
xtset athr year
tsfill, full
drop athr_id exposure mkt_spend_shr min_year foia_athr
merge m:1 athr using `_xw', assert(3) keep(3) nogen
foreach v in ppr_cnt cite_affl_wt affl_wt {
    replace `v' = 0 if mi(`v')
}

*==== leads/lags ====
gen rel = year - 2014
qui sum rel
local abs_lead = abs(r(min))
local abs_lag  = r(max)
forval i = 1/`abs_lag' {
    gen int_lag`i'  = exposure      if rel == `i'
    gen mshr_lag`i' = mkt_spend_shr if rel == `i'
    replace int_lag`i'  = 0 if mi(int_lag`i')
    replace mshr_lag`i' = 0 if mi(mshr_lag`i')
}
forval i = 1/`abs_lead' {
    gen int_lead`i'  = exposure      if rel == -`i'
    gen mshr_lead`i' = mkt_spend_shr if rel == -`i'
    replace int_lead`i'  = 0 if mi(int_lead`i')
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

*==== helpers ====
gen pre_pprs = ppr_cnt if year < 2014
bys athr_id: egen pi_pre_mean = mean(pre_pprs)
bys athr_id: gen _first = _n == 1

preserve
    use athr_id year inst_id using ../external/samp/athr_panel_full_year_last_all_jrnls_r1_r2_public, clear
    keep if inrange(year, 2010, 2019)
    keep if !mi(inst_id)
    contract athr_id inst_id
    bys athr_id: gen tmp = 1
    bys athr_id: egen num_place = total(tmp)
    keep athr_id num_place
    duplicates drop athr_id, force
    tempfile _np
    save `_np'
restore
merge m:1 athr_id using `_np', keep(1 3) nogen
replace num_place = 0 if mi(num_place)

*==== run 3 candidates in base & +mshr ====
di as text _newline "======= BARE positive-exposure ======="
qui count if _first == 1
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags', absorb(athr_id year) vce(cluster athr_id)
estimates store b0
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags', absorb(athr_id year) vce(cluster athr_id)
estimates store b0_m

di as text _newline "======= BARE + num_place == 1 ======="
qui count if _first == 1 & num_place == 1
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags' if num_place == 1, absorb(athr_id year) vce(cluster athr_id)
estimates store c1
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if num_place == 1, absorb(athr_id year) vce(cluster athr_id)
estimates store c1_m

di as text _newline "======= BARE + pre_mean >= 1 ======="
qui count if _first == 1 & pi_pre_mean >= 1
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags' if pi_pre_mean >= 1, absorb(athr_id year) vce(cluster athr_id)
estimates store c3
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if pi_pre_mean >= 1, absorb(athr_id year) vce(cluster athr_id)
estimates store c3_m

di as text _newline "======= BARE + num_place == 1 + pre_mean >= 1 ======="
qui count if _first == 1 & num_place == 1 & pi_pre_mean >= 1
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags' if num_place == 1 & pi_pre_mean >= 1, absorb(athr_id year) vce(cluster athr_id)
estimates store c9
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if num_place == 1 & pi_pre_mean >= 1, absorb(athr_id year) vce(cluster athr_id)
estimates store c9_m

*==== FULL event-time paths ====
di as text _newline "======= FULL event-time paths, BASE spec ======="
estimates table b0 c1 c3 c9, keep(`ileads' `ilags') b(%9.4f) se

di as text _newline "======= FULL event-time paths, +MSHR spec ======="
estimates table b0_m c1_m c3_m c9_m, keep(`ileads' `ilags') b(%9.4f) se

log close
