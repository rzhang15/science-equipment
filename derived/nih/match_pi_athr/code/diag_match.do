set more off
clear all
capture log close
program drop _all
set scheme modern
version 17
set maxvar 120000
log using ../output/diag_match.log, replace text

program main
    pi_side
    author_side
end

* Of the PIs we fail to place, how many were blocked by the institution bridge
* rather than by the name test? That sizes how much is left to win by widening
* the bridge versus by loosening the name comparison.
program pi_side
    use ../temp/pi_grant_long, clear
    keep pi_name org_ipf_code
    gduplicates drop
    count
    di as text "PI-org pairs in RePORTER: `r(N)'"

    merge m:1 pi_name org_ipf_code using ../temp/pi_athr_crosswalk, keep(1 3) nogen
    gen byte matched = !mi(athr_id)

    preserve
        import delimited using ../output/inst_crosswalk.csv, ///
            varn(1) stringcols(_all) case(lower) clear
        keep org_ipf_code
        gduplicates drop
        gen byte org_bridged = 1
        save ../temp/_orgs_bridged, replace
    restore
    merge m:1 org_ipf_code using ../temp/_orgs_bridged, keep(1 3) nogen
    replace org_bridged = 0 if mi(org_bridged)

    di as text _n "{hline 60}"
    di as text "match rate by whether the grantee org bridged to OpenAlex"
    tab org_bridged matched, row
    * inst  = string-bridged institution   name  = globally unique name
    * inst2 = institution bridge learned from the name-unique matches
    di as text _n "match route"
    tab match_src, missing
    di as text _n "route x whether the org bridged by string match"
    tab org_bridged match_src

    preserve
        keep if matched
        keep pi_name
        gduplicates drop
        di as text _n "distinct PIs matched: `=_N'"
    restore
end

* The reduced-form denominator: most panel authors are not NIH PIs at all, so
* read the rate on last authors before reading it on everyone.
program author_side
    foreach s in athr_panel_full_year_all_jrnls_r1_r2_public ///
                 athr_panel_full_year_last_all_jrnls_r1_r2_public {
        capture confirm file ../output/`s'_with_nih.dta
        if _rc continue
        use athr_id year has_nih n_grants_ever country_code using ///
            ../output/`s'_with_nih.dta, clear
        gen byte ever_nih = n_grants_ever > 0
        gen byte us = country_code == "US"
        di as text _n "{hline 60}"
        di as text "`s'"
        di as text "author-years with an active grant:"
        tab has_nih
        di as text "authors ever linked to a grant, US only:"
        preserve
            keep if us
            gcollapse (max) ever_nih, by(athr_id) fast
            tab ever_nih
        restore
    }
end

main
log close
