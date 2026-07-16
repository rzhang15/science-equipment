*  Is the 2016 spike (positive exposure subsample) driven by outliers?
*  Cheapest tests: winsorize ppr_cnt, trim top-leverage PIs, drop known individuals,
*  jackknife over top-exposure PIs.
set more off
capture log close
capture program drop _all
log using diag_2016_outliers.log, replace text

use ../temp/es_all_jrnls_r1_r2_public.dta, clear
keep if exposure > 0
gen rel = year - 2014

*---- build lead/lag ----*
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

*---- 1) distribution of ppr_cnt in 2016 ----*
di as text _newline "======= 1) ppr_cnt distribution by year, positive-exposure subsample ======="
sum ppr_cnt if rel == 2, d
di as text "--- upper tail counts ---"
count if rel == 2 & ppr_cnt >= 5
count if rel == 2 & ppr_cnt >= 10
count if rel == 2 & ppr_cnt >= 15
count if rel == 2 & ppr_cnt >= 20
count if rel == 2 & ppr_cnt >= 30
list athr_id ppr_cnt exposure if rel == 2 & ppr_cnt >= 15

*---- 2) baseline (positive-exposure, no outlier treatment) ----*
di as text _newline "======= 2) BASELINE: positive exposure, no trim ======="
di as text "--- base PPML ---"
qui ppmlhdfe ppr_cnt `ileads' `ilags', absorb(athr_id year) vce(cluster athr_id)
estimates store base_none
di as text "--- +mshr controls ---"
qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags', absorb(athr_id year) vce(cluster athr_id)
estimates store base_mshr

*---- 3) winsorize ppr_cnt at various percentiles ----*
foreach p in 99 97 95 {
    preserve
    qui sum ppr_cnt, d
    local cap = r(p`p')
    di as text "  winsorize ppr_cnt at p`p' = " `cap'
    replace ppr_cnt = `cap' if ppr_cnt > `cap' & !mi(ppr_cnt)
    di as text "--- winsor p`p' base ---"
    qui ppmlhdfe ppr_cnt `ileads' `ilags', absorb(athr_id year) vce(cluster athr_id)
    estimates store wp`p'_base
    di as text "--- winsor p`p' +mshr ---"
    qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags', absorb(athr_id year) vce(cluster athr_id)
    estimates store wp`p'_mshr
    restore
}

*---- 4) trim top N PIs by leverage on int_lag2 ----*
gen pre_pprs = ppr_cnt if year < 2014
bys athr_id: egen pi_pre_mean = mean(pre_pprs)
gen dev_2016 = ppr_cnt - pi_pre_mean if rel == 2
gen leverage_2016 = exposure * dev_2016 if rel == 2
bys athr_id: egen leverage_pi = max(leverage_2016)
gsort -leverage_pi athr_id

* Rank PIs by leverage_pi and try dropping top 10 / 25 / 50 / 100.
bys athr_id: gen _first = _n == 1
gen lev_rank = .
qui replace lev_rank = sum(_first) if _first == 1
bys athr_id: egen pi_lev_rank = max(lev_rank)

foreach n in 10 25 50 100 {
    preserve
    di as text _newline "======= 4) drop top `n' PIs by leverage on int_lag2 ======="
    drop if pi_lev_rank <= `n'
    di as text "--- base ---"
    qui ppmlhdfe ppr_cnt `ileads' `ilags', absorb(athr_id year) vce(cluster athr_id)
    estimates store trim`n'_base
    di as text "--- +mshr ---"
    qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags', absorb(athr_id year) vce(cluster athr_id)
    estimates store trim`n'_mshr
    restore
}

*---- 5) drop PIs whose 2016 ppr_cnt exceeds 3x their pre-period mean (Cook-style) ----*
gen mult_2016 = ppr_cnt / pi_pre_mean if rel == 2 & pi_pre_mean > 0
bys athr_id: egen pi_mult = max(mult_2016)
foreach thresh in 5 3 2 {
    preserve
    di as text _newline "======= 5) drop PIs with 2016/pre_mean >= `thresh' ======="
    count if pi_mult >= `thresh' & _first == 1
    drop if pi_mult >= `thresh'
    di as text "--- base ---"
    qui ppmlhdfe ppr_cnt `ileads' `ilags', absorb(athr_id year) vce(cluster athr_id)
    estimates store mult`thresh'_base
    di as text "--- +mshr ---"
    qui ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags', absorb(athr_id year) vce(cluster athr_id)
    estimates store mult`thresh'_mshr
    restore
}

*---- 6) side-by-side coefficient table on int_lag2 across all variants ----*
di as text _newline "======= 6) int_lag2 across variants (base spec) ======="
estimates table base_none wp99_base wp97_base wp95_base trim10_base trim25_base trim50_base trim100_base mult5_base mult3_base mult2_base, keep(int_lag2) b(%9.4f) se

di as text _newline "======= 7) int_lag2 across variants (mshrctrl spec) ======="
estimates table base_mshr wp99_mshr wp97_mshr wp95_mshr trim10_mshr trim25_mshr trim50_mshr trim100_mshr mult5_mshr mult3_mshr mult2_mshr, keep(int_lag2) b(%9.4f) se

di as text _newline "======= 8) full event-time coeffs, best trim variant ======="
estimates table base_none trim25_base trim50_base trim100_base wp95_base, keep(`ileads' `ilags') b(%9.4f) se

log close
