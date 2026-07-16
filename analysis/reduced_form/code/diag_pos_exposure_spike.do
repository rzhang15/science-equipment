*  Diagnostic: why does the PPML mshrctrl event study for ppr_cnt spike in 2016
*  when restricting to exposure > 0?
*
*  This do-file:
*    (1) Loads the analysis panel /temp/es_all_jrnls_r1_r2_public.dta
*    (2) Summarizes exposure = 0 vs exposure > 0 sub-samples (share of PIs,
*        pre-period ppr_cnt means, mkt_spend_shr distribution, correlation).
*    (3) Reports raw pre/post ppr_cnt means by year in each sub-sample so we
*        can see the 2016 outlier BEFORE any regression is fit.
*    (4) Refits ppmlhdfe base and mshrctrl on (a) full sample, (b) exposure > 0.
*    (5) Reports variance-inflation between int_lag2 and mshr_lag2 (2016 = rel=2)
*        under both samples so we can see collinearity blowing up.
*    (6) Checks a handful of leverage / outlier PIs that could pull the 2016 point.
set more off
capture log close
capture program drop _all
log using diag_pos_exposure_spike.log, replace text

* NOTE:  Panel is already exposure >= 0.  The "positive exposure" restriction
* below drops exposure == 0.
use ../temp/es_all_jrnls_r1_r2_public.dta, clear

di as text _newline "======= 1) sample split ======="
bys athr_id: gen _first = _n == 1
tab foia_athr _first if _first == 1, missing
count if _first == 1
scalar n_pi_total = r(N)
count if _first == 1 & exposure > 0
scalar n_pi_pos = r(N)
count if _first == 1 & exposure == 0
scalar n_pi_zero = r(N)
di as text "  n PIs total  = " scalar(n_pi_total)
di as text "  n PIs zero   = " scalar(n_pi_zero)
di as text "  n PIs pos    = " scalar(n_pi_pos)

di as text _newline "======= 2) exposure & mkt_spend_shr on PI-level ======="
sum exposure       if _first == 1, d
sum mkt_spend_shr  if _first == 1, d
sum mkt_spend_shr  if _first == 1 & exposure == 0
sum mkt_spend_shr  if _first == 1 & exposure > 0
di as text "correlation on PI level (all vs positive):"
corr exposure mkt_spend_shr if _first == 1
corr exposure mkt_spend_shr if _first == 1 & exposure > 0

di as text _newline "======= 3) raw ppr_cnt means by year x exposure group ======="
tabstat ppr_cnt, by(year) stat(mean sd N) col(stat)
di as text "  --- zero-exposure PIs (ppr_cnt mean by year) ---"
tabstat ppr_cnt if exposure == 0, by(year) stat(mean sd N) col(stat)
di as text "  --- positive-exposure PIs (ppr_cnt mean by year) ---"
tabstat ppr_cnt if exposure > 0, by(year) stat(mean sd N) col(stat)

di as text _newline "======= 4) ppmlhdfe on full sample vs positive exposure ======="
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
gen int_lag0  = exposure      if rel == 0
replace int_lag0 = 0 if mi(int_lag0)
gen mshr_lag0 = mkt_spend_shr if rel == 0
replace mshr_lag0 = 0 if mi(mshr_lag0)

local ileads
local ilags
local mleads
local mlags
forval i = 2/`abs_lead' {
    local ileads int_lead`i'  `ileads'
    local mleads mshr_lead`i' `mleads'
}
forval i = 0/`abs_lag' {
    local ilags  `ilags'  int_lag`i'
    local mlags  `mlags'  mshr_lag`i'
}

di as text "--- FULL sample, base ---"
ppmlhdfe ppr_cnt `ileads' `ilags', absorb(athr_id year) vce(cluster athr_id)
di as text "--- FULL sample, +mshr controls ---"
ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags', absorb(athr_id year) vce(cluster athr_id)

di as text "--- POSITIVE exposure, base ---"
ppmlhdfe ppr_cnt `ileads' `ilags' if exposure > 0, absorb(athr_id year) vce(cluster athr_id)
di as text "--- POSITIVE exposure, +mshr controls ---"
ppmlhdfe ppr_cnt `ileads' `ilags' `mleads' `mlags' if exposure > 0, absorb(athr_id year) vce(cluster athr_id)

di as text _newline "======= 5) VIF between int_lag2 (2016) and mshr_lag2 ======="
* Look at within-PI, within-year correlation of exposure and mkt_spend_shr in 2016.
di as text "--- FULL sample, rel==2 (2016) ---"
corr exposure mkt_spend_shr if rel == 2
di as text "--- POSITIVE exposure, rel==2 (2016) ---"
corr exposure mkt_spend_shr if rel == 2 & exposure > 0

* Partial out athr_id + year FE and regress mshr on exposure to see co-linearity in the mshrctrl regression basis.
di as text _newline "--- OLS in FE-partialled space: does mshr_lag2 track int_lag2 tightly? ---"
qui reghdfe mshr_lag2 int_lag2, absorb(athr_id year) resid
di as text "--- POSITIVE exposure ---"
qui reghdfe mshr_lag2 int_lag2 if exposure > 0, absorb(athr_id year) resid

di as text _newline "======= 6) 2016 outlier PIs ======="
* Which PIs move ppr_cnt most in 2016 relative to their own pre-period mean?
gen pre_pprs  = ppr_cnt if year < 2014
bys athr_id: egen pre_pprs_mean = mean(pre_pprs)
gen dev_2016 = ppr_cnt - pre_pprs_mean if rel == 2
gsort -dev_2016
list athr_id ppr_cnt pre_pprs_mean exposure mkt_spend_shr foia_athr if rel == 2 & exposure > 0 in 1/25
di as text "  --- flip side: PIs with biggest drops in 2016 ---"
gsort dev_2016
list athr_id ppr_cnt pre_pprs_mean exposure mkt_spend_shr foia_athr if rel == 2 & exposure > 0 in 1/25

log close
