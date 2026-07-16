*  Bare positive-exposure sample + sample cuts to see which reduce the 2016
*  spike.  Reuses ../temp/bare_pos_sample.dta built by the first run of this
*  do-file (only requirements: min_year <= 2010, year in [2010,2019],
*  non-missing exposure & mkt_spend_shr, exposure > 0).
set more off
capture log close
capture program drop _all
log using diag_bare_sample_cuts.log, replace text

*==== rebuild bare positive-exposure panel ====

* 1) raw last-author panel
use athr_id year ppr_cnt cite_affl_wt affl_wt ///
    using ../external/samp/athr_panel_full_year_last_all_jrnls_r1_r2_public, clear

* 2) PI appears by 2010 & restrict to 2010-2019
bys athr_id: egen min_year = min(year)
bys athr_id: egen max_year = max(year)
keep if min_year <= 2010
keep if inrange(year, 2010, 2019)

* 3) merge exposure & real FOIA exposure
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

* 4) positive exposure
drop if mi(exposure) | mi(mkt_spend_shr)
keep if exposure > 0
drop if mkt_spend_shr < 0

* 5) balance
gegen athr = group(athr_id)
preserve
    contract athr athr_id exposure mkt_spend_shr min_year max_year foia_athr
    drop _freq
    tempfile _xw
    save `_xw'
restore
xtset athr year
tsfill, full
drop athr_id exposure mkt_spend_shr min_year max_year foia_athr
merge m:1 athr using `_xw', assert(3) keep(3) nogen
foreach v in ppr_cnt cite_affl_wt affl_wt {
    replace `v' = 0 if mi(`v')
}

di as text _newline "======= BARE sample state ======="
bys athr_id: gen _first = _n == 1
qui count if _first == 1
di as text "  N PIs (bare): " r(N)

*==== build event-time interactions ====
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

*==== pre-period stats for cuts ====
gen pre_pprs = ppr_cnt if year < 2014
bys athr_id: egen pi_pre_mean  = mean(pre_pprs)
bys athr_id: egen pi_pre_sum   = sum(pre_pprs)
bys athr_id: egen pi_pre_years_active = total(pre_pprs > 0 & !mi(pre_pprs))
gen ppr_2013 = ppr_cnt if year == 2013
bys athr_id: egen pi_ppr_2013 = max(ppr_2013)
drop ppr_2013

*  num_place from raw last-author panel (not in bare sample)
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

xtile exp_q_tmp = exposure if _first == 1, n(4)
bys athr_id: egen exp_q = max(exp_q_tmp)
drop exp_q_tmp

*==== BASELINE ====
di as text _newline "======= BASELINE: bare positive-exposure ======="
qui count if _first == 1
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags', absorb(athr_id year) vce(cluster athr_id)
estimates store b0
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags', absorb(athr_id year) vce(cluster athr_id)
estimates store b0_m

*==== CUT 1: num_place == 1 ====
di as text _newline "======= CUT 1: num_place == 1 (single-institution) ======="
qui count if _first == 1 & num_place == 1
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags' if num_place == 1, absorb(athr_id year) vce(cluster athr_id)
estimates store c1
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if num_place == 1, absorb(athr_id year) vce(cluster athr_id)
estimates store c1_m

*==== CUT 2: balanced pre-period ====
di as text _newline "======= CUT 2: balanced pre-period (active every 2010-2013) ======="
qui count if _first == 1 & pi_pre_years_active == 4
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags' if pi_pre_years_active == 4, absorb(athr_id year) vce(cluster athr_id)
estimates store c2
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if pi_pre_years_active == 4, absorb(athr_id year) vce(cluster athr_id)
estimates store c2_m

*==== CUT 3: pre_mean >= 1 ====
di as text _newline "======= CUT 3: pre_mean >= 1 ======="
qui count if _first == 1 & pi_pre_mean >= 1
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags' if pi_pre_mean >= 1, absorb(athr_id year) vce(cluster athr_id)
estimates store c3
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if pi_pre_mean >= 1, absorb(athr_id year) vce(cluster athr_id)
estimates store c3_m

*==== CUT 4: pre_mean >= 2 ====
di as text _newline "======= CUT 4: pre_mean >= 2 ======="
qui count if _first == 1 & pi_pre_mean >= 2
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags' if pi_pre_mean >= 2, absorb(athr_id year) vce(cluster athr_id)
estimates store c4
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if pi_pre_mean >= 2, absorb(athr_id year) vce(cluster athr_id)
estimates store c4_m

*==== CUT 5: nonzero ppr in 2013 ====
di as text _newline "======= CUT 5: nonzero ppr in 2013 (baseline year) ======="
qui count if _first == 1 & pi_ppr_2013 > 0
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags' if pi_ppr_2013 > 0, absorb(athr_id year) vce(cluster athr_id)
estimates store c5
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if pi_ppr_2013 > 0, absorb(athr_id year) vce(cluster athr_id)
estimates store c5_m

*==== CUT 6: drop top exposure quartile ====
di as text _newline "======= CUT 6: exp_q <= 3 (drop top exposure quartile) ======="
qui count if _first == 1 & exp_q <= 3
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags' if exp_q <= 3, absorb(athr_id year) vce(cluster athr_id)
estimates store c6
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if exp_q <= 3, absorb(athr_id year) vce(cluster athr_id)
estimates store c6_m

*==== CUT 7: drop bottom exposure quartile ====
di as text _newline "======= CUT 7: exp_q >= 2 (drop bottom exposure quartile) ======="
qui count if _first == 1 & exp_q >= 2
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags' if exp_q >= 2, absorb(athr_id year) vce(cluster athr_id)
estimates store c7
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if exp_q >= 2, absorb(athr_id year) vce(cluster athr_id)
estimates store c7_m

*==== CUT 8: combined ====
di as text _newline "======= CUT 8: balanced + pre_mean>=1 + num_place==1 ======="
qui count if _first == 1 & pi_pre_years_active == 4 & pi_pre_mean >= 1 & num_place == 1
di as text "  N_PI = " r(N)
qui ppmlhdfe ppr_cnt `ileads' `ilags' if pi_pre_years_active == 4 & pi_pre_mean >= 1 & num_place == 1, absorb(athr_id year) vce(cluster athr_id)
estimates store c8
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if pi_pre_years_active == 4 & pi_pre_mean >= 1 & num_place == 1, absorb(athr_id year) vce(cluster athr_id)
estimates store c8_m

*==== SUMMARY ====
di as text _newline "======= SUMMARY: int_lead2 & int_lag2, BASE spec ======="
estimates table b0 c1 c2 c3 c4 c5 c6 c7 c8, keep(int_lead2 int_lag2) b(%9.4f) se

di as text _newline "======= SUMMARY: int_lead2 & int_lag2, +MSHR spec ======="
estimates table b0_m c1_m c2_m c3_m c4_m c5_m c6_m c7_m c8_m, keep(int_lead2 int_lag2) b(%9.4f) se

di as text _newline "======= FULL event-time, base spec ======="
estimates table b0 c1 c2 c3 c4 c5 c8, keep(`ileads' `ilags') b(%9.4f) se

log close
