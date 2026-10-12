version 17
clear all
set more off
set linesize 140
args repo
if "`repo'" == "" local repo "/n/holylabs/pakes_lab/Lab/sci_eq"
local out "`repo'/analysis/same_product_price/output/fbs_500ml_did"
capture log close
log using "`out'/regression.log", text replace
which reghdfe
tempname results events
postfile `results' str20 specification double b se df p ci_low ci_high N clusters treated_purchases control_purchases treated_unis using "`out'/did_results.dta", replace
postfile `events' str20 specification int year double b se ci_low ci_high using "`out'/event_study.dta", replace
foreach sample in baseline fbs500 {
    use "`out'/`sample'_panel.dta", clear
    egen uni_mkt = group(uni_id mkt)
    bys uni_mkt: egen first_year = min(year)
    bys uni_mkt: egen last_year = max(year)
    keep if first_year < 2014 & last_year > 2014
    gen byte post = year >= 2014
    gen byte posttreat = treated * post
    di as text "=== `sample': year, university and market FE; original 2013 spending weights ==="
    reghdfe avg_log_price posttreat [aw=spend_2013], absorb(year uni_id mkt) vce(cluster mkt)
    gen byte did_sample = e(sample)
    scalar model_b = _b[posttreat]
    scalar model_se = _se[posttreat]
    scalar model_df = e(df_r)
    scalar model_N = e(N)
    scalar model_clusters = e(N_clust)
    scalar model_p = 2*ttail(model_df, abs(model_b/model_se))
    scalar model_lo = model_b - invttail(model_df, .025)*model_se
    scalar model_hi = model_b + invttail(model_df, .025)*model_se
    quietly summarize obs_cnt if treated == 1 & did_sample, meanonly
    scalar treat_N = r(sum)
    quietly summarize obs_cnt if treated == 0 & did_sample, meanonly
    scalar control_N = r(sum)
    egen byte tag_uni = tag(uni_id) if treated == 1 & did_sample
    quietly count if tag_uni == 1
    post `results' ("`sample'") (model_b) (model_se) (model_df) (model_p) (model_lo) (model_hi) (model_N) (model_clusters) (treat_N) (control_N) (r(N))
    save "`out'/`sample'_estimation_panel.dta", replace
    preserve
    keep if did_sample
    collapse (sum) purchases=obs_cnt spend=raw_spend (count) university_market_years=uni_id, by(category year treated)
    export delimited using "`out'/`sample'_coverage_by_year.csv", replace
    restore
    keep if did_sample
    local rhs ""
    forvalues y = 2010/2019 {
        if `y' != 2013 {
            gen byte event_`y' = treated * (year == `y')
            local rhs "`rhs' event_`y'"
        }
    }
    reghdfe avg_log_price `rhs' [aw=spend_2013], absorb(year uni_id mkt) vce(cluster mkt)
    gen byte es_sample = e(sample)
    scalar fs_es_crit = invttail(e(df_r), .025)
    forvalues y = 2010/2019 {
        if `y' == 2013 post `events' ("`sample'") (`y') (0) (0) (0) (0)
        else {
            quietly count if treated == 1 & year == `y' & es_sample
            if r(N) == 0 post `events' ("`sample'") (`y') (.) (.) (.) (.)
            else {
                scalar fs_es_b = _b[event_`y']
                scalar fs_es_se = _se[event_`y']
                post `events' ("`sample'") (`y') (scalar(fs_es_b)) (scalar(fs_es_se)) ///
                    (scalar(fs_es_b)-scalar(fs_es_crit)*scalar(fs_es_se)) ///
                    (scalar(fs_es_b)+scalar(fs_es_crit)*scalar(fs_es_se))
            }
        }
    }
}
postclose `results'
postclose `events'
use "`out'/did_results.dta", clear
list, noobs
export delimited using "`out'/did_results.csv", replace
use "`out'/event_study.dta", clear
export delimited using "`out'/event_study.csv", replace
log close
