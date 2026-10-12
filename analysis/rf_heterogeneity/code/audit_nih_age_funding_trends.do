* Continuous-funding and exposure-specific pre-trend checks, run from this directory.
set more off
clear all
capture log close
args work out
if "`work'" == "" local work /tmp/nih_age_funding_audit
if "`out'" == "" local out ../output/nih_age_funding_audit
log using "`out'/trends.log", replace text
use "`work'/audit_panel.dta", clear
keep if !mi(cell)
egen byte tag = tag(athr_id)
gen double log_funding = ln(nih_funding_baseline)
quietly summarize log_funding if tag, detail
local mu = r(mean)
local f25 = r(p25) - `mu'
local f75 = r(p75) - `mu'
replace log_funding = log_funding - `mu'
gen byte post = year >= 2014
gen double Z = exposure * post
gen double S = mkt_spend_shr * post
foreach x in Z S post {
    gen double `x'_age = `x' * young
    gen double `x'_fund = `x' * log_funding
    gen double `x'_age_fund = `x' * young * log_funding
}
tempname effects
postfile `effects' str32 spec str32 contrast double b se p N using "`out'/extra_models", replace
ppmlhdfe ppr_cnt Z Z_age Z_fund Z_age_fund S S_age S_fund S_age_fund ///
    post_age post_fund post_age_fund, absorb(athr_id year) vce(cluster athr_id)
local N = e(N)
test Z_age_fund
post `effects' ("continuous_funding") ("age_funding_interaction") (_b[Z_age_fund]) (_se[Z_age_fund]) (r(p)) (`N')
lincom Z_age + `f25' * Z_age_fund
post `effects' ("continuous_funding") ("age_at_funding_p25") (r(estimate)) (r(se)) (r(p)) (`N')
lincom Z_age + `f75' * Z_age_fund
post `effects' ("continuous_funding") ("age_at_funding_p75") (r(estimate)) (r(se)) (r(p)) (`N')

* Group x year FEs absorb each cell's general publication trajectory.
* Exposure-specific leads are measured against 2013, alongside all post leads.
local Zs
local Ss
local pre_all
forvalues k=1/4 {
    local pre`k'
    foreach yr of numlist 2010/2012 2014/2019 {
        gen double Z`yr'_`k' = exposure * (year==`yr') * (cell==`k')
        gen double S`yr'_`k' = mkt_spend_shr * (year==`yr') * (cell==`k')
        local Zs `Zs' Z`yr'_`k'
        local Ss `Ss' S`yr'_`k'
        if `yr' < 2013 {
            local pre`k' `pre`k'' Z`yr'_`k'
            local pre_all `pre_all' Z`yr'_`k'
        }
    }
}
ppmlhdfe ppr_cnt `Zs' `Ss', absorb(athr_id cell#year) vce(cluster athr_id)
local N = e(N)
test `pre_all'
post `effects' ("event_study_cell_year") ("joint_pre_trends") (r(chi2)) (.) (r(p)) (`N')
forvalues k=1/4 {
    test `pre`k''
    post `effects' ("event_study_cell_year") ("cell`k'_pre_trends") (r(chi2)) (.) (r(p)) (`N')
}
postclose `effects'
use "`out'/extra_models", clear
export delimited using "`out'/extra_models.csv", replace
list, noobs abbreviate(32)
di "NIH_AGE_FUNDING_TRENDS_COMPLETE"
log close
exit, clear
