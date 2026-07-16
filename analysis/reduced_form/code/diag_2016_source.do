*  Trace the 2016 spike + pretrend for ppr_cnt back to the raw data:
*    (1) Mean ppr_cnt by year x exposure quartile — does the 2016 bump only show
*        up for a specific quartile?
*    (2) FE-partialled view: after killing PI + year FEs, what does the exposure
*        slope on residual ppr_cnt look like each year (binscatter equivalent)?
*    (3) Cohort / attrition composition — how many PIs are actively publishing
*        (ppr_cnt > 0) each year within each quartile?  Any 2016 anomaly?
*    (4) Same check on cite_affl_wt to see whether the spike is a paper-count
*        artifact or a citation-driven one.
*    (5) Compare imputed vs observed FOIA PIs (foia_athr==1) side by side —
*        the spike could come from one of the two.
set more off
capture log close
capture program drop _all
log using diag_2016_source.log, replace text

use ../temp/es_all_jrnls_r1_r2_public.dta, clear
gen rel = year - 2014

*---- 1) exposure-quartile x year means of ppr_cnt --------------------------*
bys athr_id: gen _first = _n == 1
xtile exp_q_tmp = exposure if _first == 1, n(4)
bys athr_id: egen exp_q = max(exp_q_tmp)
drop exp_q_tmp _first

di as text _newline "======= 1) mean ppr_cnt by year x exposure quartile ======="
tabstat ppr_cnt, by(year) stat(mean N) col(stat)
di as text "--- Q1 (lowest exposure) ---"
tabstat ppr_cnt if exp_q == 1, by(year) stat(mean N) col(stat)
di as text "--- Q2 ---"
tabstat ppr_cnt if exp_q == 2, by(year) stat(mean N) col(stat)
di as text "--- Q3 ---"
tabstat ppr_cnt if exp_q == 3, by(year) stat(mean N) col(stat)
di as text "--- Q4 (highest exposure) ---"
tabstat ppr_cnt if exp_q == 4, by(year) stat(mean N) col(stat)

*---- 2) same for cite_affl_wt so we can see whether the story is papers vs cites --*
di as text _newline "======= 2) same for cite_affl_wt ======="
tabstat cite_affl_wt, by(year) stat(mean N) col(stat)
di as text "--- Q1 ---"
tabstat cite_affl_wt if exp_q == 1, by(year) stat(mean N) col(stat)
di as text "--- Q4 ---"
tabstat cite_affl_wt if exp_q == 4, by(year) stat(mean N) col(stat)

*---- 3) attrition / active-publisher share by quartile x year --------------*
gen active = ppr_cnt > 0
di as text _newline "======= 3) share publishing by year x quartile ======="
tabstat active, by(year) stat(mean N) col(stat)
di as text "--- Q1 ---"
tabstat active if exp_q == 1, by(year) stat(mean N) col(stat)
di as text "--- Q4 ---"
tabstat active if exp_q == 4, by(year) stat(mean N) col(stat)

*---- 4) FOIA vs imputed side by side ---------------------------------------*
di as text _newline "======= 4) FOIA-observed vs imputed PIs ======="
di as text "--- FOIA PIs only (foia_athr==1) ---"
tabstat ppr_cnt if foia_athr == 1, by(year) stat(mean N) col(stat)
di as text "--- imputed PIs only (foia_athr!=1) ---"
tabstat ppr_cnt if foia_athr != 1, by(year) stat(mean N) col(stat)

*---- 5) PPML on subsets to see who drives the 2016 spike --------------------*
qui sum rel
local abs_lead = abs(r(min))
local abs_lag  = r(max)
forval i = 1/`abs_lag' {
    gen int_lag`i' = exposure if rel == `i'
    replace int_lag`i' = 0 if mi(int_lag`i')
}
forval i = 1/`abs_lead' {
    gen int_lead`i' = exposure if rel == -`i'
    replace int_lead`i' = 0 if mi(int_lead`i')
}
gen int_lag0 = exposure if rel == 0
replace int_lag0 = 0 if mi(int_lag0)
local ileads
local ilags
forval i = 2/`abs_lead' {
    local ileads int_lead`i' `ileads'
}
forval i = 0/`abs_lag' {
    local ilags `ilags' int_lag`i'
}

di as text _newline "======= 5) ppmlhdfe on subsets ======="
di as text "--- FOIA PIs only ---"
cap noi ppmlhdfe ppr_cnt `ileads' `ilags' if foia_athr == 1, absorb(athr_id year) vce(cluster athr_id)
di as text "--- imputed PIs only ---"
cap noi ppmlhdfe ppr_cnt `ileads' `ilags' if foia_athr != 1, absorb(athr_id year) vce(cluster athr_id)
di as text "--- drop top exposure quartile (Q4) ---"
cap noi ppmlhdfe ppr_cnt `ileads' `ilags' if exp_q < 4, absorb(athr_id year) vce(cluster athr_id)
di as text "--- top exposure quartile only (Q4) ---"
cap noi ppmlhdfe ppr_cnt `ileads' `ilags' if exp_q == 4, absorb(athr_id year) vce(cluster athr_id)

*---- 6) Which PIs are the *biggest leverage* on int_lag2 (2016)? -----------*
* Leverage of PI i on int_lag2 is roughly (exposure_i - exposure_bar) * (y_i,2016 - y_i,bar).
* Look at PIs with highest exposure * (ppr_cnt_2016 - PI mean ppr).
gen pre_pprs = ppr_cnt if year < 2014
bys athr_id: egen pi_pre_mean = mean(pre_pprs)
gen leverage_2016 = exposure * (ppr_cnt - pi_pre_mean) if rel == 2
gsort -leverage_2016
di as text _newline "======= 6) top 25 PIs by leverage on int_lag2 (2016) ======="
list athr_id ppr_cnt pi_pre_mean exposure mkt_spend_shr foia_athr exp_q if rel == 2 in 1/25

*---- 7) 2016 spike also there without the mshr controls? cite_affl_wt event study ---*
gen ln_cite = ln(1 + cite_affl_wt)
di as text _newline "======= 7) ppr_cnt vs cite_affl_wt event studies (base) ======="
di as text "--- ppr_cnt base PPML ---"
qui ppmlhdfe ppr_cnt `ileads' `ilags', absorb(athr_id year) vce(cluster athr_id)
estimates store ppr_base
di as text "--- cite_affl_wt base PPML ---"
qui ppmlhdfe cite_affl_wt `ileads' `ilags', absorb(athr_id year) vce(cluster athr_id)
estimates store cite_base
estimates table ppr_base cite_base, b(%9.4f) se

*---- 8) Poisson without athr FE — how does the raw exposure x year slope look? ---*
di as text _newline "======= 8) drop athr FE — pure year x exposure ======="
cap noi ppmlhdfe ppr_cnt `ileads' `ilags', absorb(year) vce(cluster athr_id)

log close
