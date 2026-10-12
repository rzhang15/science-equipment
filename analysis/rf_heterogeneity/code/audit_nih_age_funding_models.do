capture program drop fit_age_funding
program fit_age_funding
    syntax varname [if], Spec(string) Group(varname) [Collapsed PRE FES(string)]
    marksample touse
    preserve
    keep if `touse' & !mi(`group')
    gen byte post = year >= 2014
    if "`pre'" != "" {
        keep if year <= 2013
        replace post = year >= 2012
    }
    if "`collapsed'" != "" nih_award_period_means
    if "`fes'" == "" local fes athr_id year
    levelsof `group', local(cells)
    local Zs
    local Ss
    local Ps
    local base : word 1 of `cells'
    foreach k of local cells {
        gen double Z`k' = exposure * post * (`group' == `k')
        gen double S`k' = mkt_spend_shr * post * (`group' == `k')
        local Zs `Zs' Z`k'
        local Ss `Ss' S`k'
        if `k' != `base' {
            gen double P`k' = post * (`group' == `k')
            local Ps `Ps' P`k'
        }
    }
    capture noisily ppmlhdfe `varlist' `Zs' `Ss' `Ps', absorb(`fes') vce(cluster athr_id)
    local rc = _rc
    if `rc' {
        di as error "AUDIT_MODEL_FAILED: `varlist' `spec' rc=`rc'"
        restore
        exit
    }
    local N = e(N)
    egen byte tag = tag(athr_id) if e(sample)
    quietly count if tag == 1
    local np = r(N)
    foreach k of local cells {
        local b = _b[Z`k']
        local se = _se[Z`k']
        local p = 2 * normal(-abs(`b'/`se'))
        post $NIH_AGE_AUDIT_HANDLE ("`varlist'") ("`spec'") ("cell`k'") (`b') (`se') (`p') (`N') (`np')
    }
    local names age_high age_low funding_early funding_late
    local lefts 1 2 1 3
    local rights 3 4 2 4
    if "`group'" == "cell8" {
        local names age_high_persistent age_low_persistent age_high_intermittent age_low_intermittent
        local lefts 1 3 2 4
        local rights 5 7 6 8
    }
    forvalues j = 1/4 {
        local name : word `j' of `names'
        local l : word `j' of `lefts'
        local r : word `j' of `rights'
        capture noisily lincom Z`l' - Z`r'
        if !_rc post $NIH_AGE_AUDIT_HANDLE ("`varlist'") ("`spec'") ("`name'") (r(estimate)) (r(se)) (r(p)) (`N') (`np')
    }
    if "`group'" == "complete_cell6" {
        lincom Z5 - Z6
        post $NIH_AGE_AUDIT_HANDLE ("`varlist'") ("`spec'") ("age_no_baseline_award") (r(estimate)) (r(se)) (r(p)) (`N') (`np')
    }
    if "`pre'" != "" {
        test `Zs'
        post $NIH_AGE_AUDIT_HANDLE ("`varlist'") ("`spec'") ("joint_pre_placebo") (r(chi2)) (.) (r(p)) (`N') (`np')
    }
    restore
end

