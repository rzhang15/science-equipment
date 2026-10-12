set more off
use /n/home02/cxu75/sci_eq/analysis/rf_heterogeneity/temp/es_all_jrnls_r1_r2.dta, clear
cap drop train_yrs
cap drop y_longtrain
cap drop y_shorttrain
gen train_yrs = min_year - min_year_any
qui sum train_yrs if athr_indicator == 1 & young == 1, d
local train_med = r(p50)
di as text "training yrs among early-career PIs: p10=" r(p10) " p25=" r(p25) " p50=" r(p50) " p75=" r(p75) " p90=" r(p90) " mean=" %5.2f r(mean)
qui sum train_yrs if athr_indicator == 1 & old == 1, d
di as text "training yrs among late-career PIs: p50=" r(p50) " mean=" %5.2f r(mean)
tab train_yrs if athr_indicator == 1 & young == 1
gen byte y_longtrain  = train_yrs >  `train_med' if young == 1 & !mi(train_yrs)
gen byte y_shorttrain = train_yrs <= `train_med' if young == 1 & !mi(train_yrs)
qui count if athr_indicator == 1 & y_longtrain == 1
di as text "long training (> `train_med' yrs): " r(N)
qui count if athr_indicator == 1 & y_shorttrain == 1
di as text "short training (<= `train_med' yrs): " r(N)
qui sum train_yrs if athr_indicator == 1 & y_longtrain == 1
di as text "  mean yrs long = " %5.2f r(mean)
qui sum train_yrs if athr_indicator == 1 & y_shorttrain == 1
di as text "  mean yrs short = " %5.2f r(mean)
qui sum min_year if athr_indicator == 1 & y_longtrain == 1
di as text "  mean first last-author yr long = " %6.1f r(mean)
qui sum min_year if athr_indicator == 1 & y_shorttrain == 1
di as text "  mean first last-author yr short = " %6.1f r(mean)

gen post       = year >= 2014
gen Z_it       = exposure      * post
gen Z_share_it = mkt_spend_shr * post
foreach pair in "y_longtrain y_shorttrain" {
    local g1 : word 1 of `pair'
    local g2 : word 2 of `pair'
    gen Z_`g1'  = Z_it       * `g1'
    gen Z_`g2'  = Z_it       * `g2'
    gen S_`g1'  = Z_share_it * `g1'
    gen S_`g2'  = Z_share_it * `g2'
    gen PT_`g1' = post * `g1'
    ppmlhdfe ppr_cnt Z_`g1' Z_`g2' S_`g1' S_`g2' PT_`g1', absorb(athr_id year) vce(cluster athr_id)
    gunique athr_id if e(sample)
    local npi = r(unique)
    lincom Z_`g1' - Z_`g2'
    di as result _n "== `pair': N=" e(N) " PIs=`npi'"
    di as result "   `g1' = " %7.4f _b[Z_`g1'] " (" %6.4f _se[Z_`g1'] ")"
    di as result "   `g2' = " %7.4f _b[Z_`g2'] " (" %6.4f _se[Z_`g2'] ")"
    di as result "   diff = " %7.4f r(estimate) " (" %6.4f r(se) ")  p=" %5.3f r(p)
}
* continuous version: interaction with training years among early-career PIs
gen Z_y     = Z_it * young
gen Z_ytr   = Z_it * young * train_yrs
gen S_y     = Z_share_it * young
gen S_ytr   = Z_share_it * young * train_yrs
gen PT_y    = post * young
gen PT_ytr  = post * young * train_yrs
gen Z_o     = Z_it * old
gen S_o     = Z_share_it * old
ppmlhdfe ppr_cnt Z_y Z_ytr Z_o S_y S_ytr S_o PT_y PT_ytr, absorb(athr_id year) vce(cluster athr_id)
di as result _n "== continuous: early-career response at 0 training yrs = " %7.4f _b[Z_y] " (" %6.4f _se[Z_y] ")"
di as result "   change per training yr = " %7.4f _b[Z_ytr] " (" %6.4f _se[Z_ytr] ")  p=" %5.3f (2*normal(-abs(_b[Z_ytr]/_se[Z_ytr])))
