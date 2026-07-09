// Cheap pre-trend diagnostic: does S_i (= mkt_spend_shr) predict differential
// output trends in the pre-period 2010-2013?
set more off
capture log close

log using ../temp/diag_pretrend_on_S.log, text replace

use ../temp/es_all_jrnls_r1_r2_public, clear

di as text _newline "===== S_i distribution (author level, one row per PI) ====="
preserve
    bys athr_id: keep if _n == 1
    sum mkt_spend_shr, d
    sum exposure, d
    corr mkt_spend_shr exposure
restore

// -------------------------------------------------------------
// (1) PANEL SPEC: pre-period only, y on year * S_i, athr+year FE
// -------------------------------------------------------------
di as text _newline "===== (1) PANEL: reghdfe y (year x S_i) if year<=2013, absorb(athr_id year) ====="
preserve
    keep if year <= 2013
    gen yr_x_S = year * mkt_spend_shr
    foreach yvar in ppr_cnt cite_affl_wt {
        di as text _newline "--- `yvar' ---"
        reghdfe `yvar' yr_x_S, absorb(athr_id year) vce(cluster athr_id)
    }
restore

// -------------------------------------------------------------
// (2) PI-LEVEL DELTA: growth_i = y_i,2013 - y_i,2010 regressed on S_i alone.
// -------------------------------------------------------------
di as text _newline "===== (2) PI-LEVEL: reg (y2013 - y2010) on S_i ====="
foreach yvar in ppr_cnt cite_affl_wt {
    preserve
        keep if inlist(year, 2010, 2013)
        keep athr_id year mkt_spend_shr `yvar'
        reshape wide `yvar', i(athr_id mkt_spend_shr) j(year)
        gen d_`yvar'    = `yvar'2013 - `yvar'2010
        gen ln_d_`yvar' = ln(1 + `yvar'2013) - ln(1 + `yvar'2010)
        di as text _newline "--- `yvar' level delta ---"
        reg d_`yvar' mkt_spend_shr, vce(robust)
        di as text _newline "--- `yvar' log delta ---"
        reg ln_d_`yvar' mkt_spend_shr, vce(robust)
    restore
}

log close
