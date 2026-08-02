set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

log using diag_supplements.log, replace text

global SAMPSUF "_r1_r2"

program main
    cap mkdir ../output/tables
    cap mkdir ../output/figures/all_jrnls
    build_measures
    grant_level_checks
    athr_year_trends
    es_compare
end

* ---------------------------------------------------------------------------
* Application type is the leading digit of full_project_num:
*   1 new, 2 competing renewal, 3 ADMINISTRATIVE SUPPLEMENT,
*   5 non-competing continuation, 7 change of institution, 9 change of activity.
* classify_grants never inspects it, so supplements are currently invisible to
* the pipeline. Everything below reconstructs what they are doing.
* ---------------------------------------------------------------------------
program build_measures
    use athr_id year grant_key row_key full_project_num subproject_id ///
        core_project_num research total_cost project_start ///
        using ../external/nih_grants/nih_grants_by_athr_id, clear
    drop if mi(year)
    gen byte appl_type  = real(substr(strtrim(full_project_num), 1, 1))
    gen byte supplement = appl_type == 3
    gen int start_year  = year(project_start)
    duplicates drop athr_id year row_key, force
    compress
    save ../temp/diag_supp_long, replace
end

* ---------------------------------------------------------------------------
* Does the supplement share trend, and can a supplement inflate n_grants?
*
* n_grants tags one row per (athr_id, year, grant_key), and grant_key is
* core_project_num + subproject_id. A supplement shares its parent's
* core_project_num, so it SHOULD collapse into the parent and add nothing to
* the count. Two ways that fails, both checked here:
*   (a) the supplement is the only row for that grant_key in that FY -- the
*       parent has no record that year, so the supplement single-handedly
*       makes the award look active;
*   (b) subproject_id differs between parent and supplement rows, splitting one
*       award into two grant_keys and double-counting it.
* ---------------------------------------------------------------------------
program grant_level_checks
    use ../temp/diag_supp_long, clear
    keep if research

    di as text _n "===== application type mix among research rows, by FY ====="
    table year appl_type, nformat(%9.0fc)
    di as text _n "===== supplement share of research rows, by FY ====="
    table year, stat(mean supplement) stat(freq) nformat(%9.4f)

    * (a) grant-years carried entirely by supplement rows
    bys athr_id year grant_key: egen byte all_supp = min(supplement)
    bys athr_id year grant_key: gen byte gk_tag = _n == 1
    di as text _n "===== share of counted grant-years with NO parent row ====="
    table year if gk_tag == 1, stat(mean all_supp) stat(freq) nformat(%9.4f)

    * Is a parent-less supplement-year extending an award past its last real
    * year? Flag grant_keys present as non-supplement in t-1 but only as a
    * supplement in t.
    preserve
        keep if gk_tag == 1
        keep athr_id year grant_key all_supp
        gen byte real_yr = all_supp == 0
        xtset, clear
        bys athr_id grant_key (year): gen byte prev_real = real_yr[_n-1] == 1 & year == year[_n-1] + 1
        gen byte tail_ext = all_supp == 1 & prev_real == 1
        di as text _n "===== supplement-only years that extend a live award ====="
        table year, stat(mean tail_ext) stat(sum tail_ext) nformat(%9.4f)
    restore

    * (b) one core project split across grant_keys by subproject_id
    bys athr_id year core_project_num grant_key: gen byte kt = _n == 1
    bys athr_id year core_project_num: egen n_keys = total(kt)
    bys athr_id year core_project_num: egen byte any_supp = max(supplement)
    di as text _n "===== core-project-years split into >1 grant_key ====="
    table year if kt == 1, stat(mean n_keys) nformat(%9.4f)
    di as text _n "  ... of which involve a supplement row:"
    table year if kt == 1 & n_keys > 1, stat(mean any_supp) stat(freq) nformat(%9.4f)

    * n_new_grants is read off whichever row wins the tag within grant_key-year.
    * If project_start varies across those rows, the flag is arbitrary and a
    * supplement can be miscoded as a brand-new award.
    bys athr_id year grant_key: egen sy_min = min(start_year)
    bys athr_id year grant_key: egen sy_max = max(start_year)
    gen byte sy_amb = sy_min != sy_max & !mi(sy_min) & !mi(sy_max)
    di as text _n "===== grant-years where project_start is ambiguous across rows ====="
    table year if gk_tag == 1, stat(mean sy_amb) stat(freq) nformat(%9.4f)
    di as text _n "===== do supplement rows carry their own start date? ====="
    table supplement, stat(mean sy_amb) stat(freq) nformat(%9.4f)
end

* ---------------------------------------------------------------------------
* Author-year measures with and without supplement rows.
* ---------------------------------------------------------------------------
program athr_year_trends
    use ../temp/diag_supp_long, clear

    egen byte tag_all = tag(athr_id year grant_key) if research
    egen byte tag_ns  = tag(athr_id year grant_key) if research & !supplement
    gen byte g_all  = tag_all == 1
    gen byte g_ns   = tag_ns  == 1
    gen byte new_all = g_all & start_year == year
    gen byte new_ns  = g_ns  & start_year == year
    gen double c_all = total_cost if research
    gen double c_ns  = total_cost if research & !supplement
    gen byte supp_row = research & supplement

    gcollapse (sum) n_grants_all = g_all  (sum) n_grants_ns = g_ns ///
              (sum) n_new_all    = new_all (sum) n_new_ns   = new_ns ///
              (sum) cost_all     = c_all  (sum) cost_ns     = c_ns ///
              (sum) n_supp_rows  = supp_row, by(athr_id year) fast
    save ../temp/diag_supp_athr_yr, replace

    use ../output/prepped_samples/es_all_jrnls${SAMPSUF}, clear
    merge 1:1 athr_id year using ../temp/diag_supp_athr_yr, keep(1 3) gen(_msupp)
    gen byte reporter_matched = 0
    bys athr_id: egen _any = max(_msupp == 3)
    replace reporter_matched = 1 if _any == 1
    drop _any _msupp
    keep if reporter_matched == 1
    foreach v in n_grants_all n_grants_ns n_new_all n_new_ns cost_all cost_ns n_supp_rows {
        replace `v' = 0 if mi(`v')
    }
    gen double supp_effect = n_grants_all - n_grants_ns

    bys athr_id (year): gen byte pi_tag = _n == 1
    xtile _q = exposure if pi_tag == 1, nq(4)
    bys athr_id: egen exp_q4 = max(_q)
    drop _q
    compress
    save ../temp/diag_supp_samp, replace

    di as text _n "===== analysis-sample PIs: with vs without supplements ====="
    table year, stat(mean n_grants_all) stat(mean n_grants_ns) ///
                stat(mean supp_effect) stat(mean n_supp_rows) nformat(%9.4f)
    di as text _n "===== supplement contribution by exposure quartile ====="
    table year exp_q4 if inlist(exp_q4, 1, 4), ///
        stat(mean supp_effect) stat(mean n_supp_rows) nformat(%9.4f)

    preserve
        gcollapse (mean) n_grants_all n_grants_ns n_new_all n_new_ns ///
                         cost_all cost_ns n_supp_rows, by(year exp_q4) fast
        sort exp_q4 year
        export delimited using ../output/tables/diag_supp_trends.csv, replace
        foreach y in n_grants_all n_grants_ns n_new_all n_new_ns n_supp_rows {
            if "`y'" == "n_grants_all" local yt "# active grants (supplements in)"
            if "`y'" == "n_grants_ns"  local yt "# active grants (supplements out)"
            if "`y'" == "n_new_all"    local yt "# new grants (supplements in)"
            if "`y'" == "n_new_ns"     local yt "# new grants (supplements out)"
            if "`y'" == "n_supp_rows"  local yt "# supplement rows per PI-year"
            tw (line `y' year if exp_q4 == 1, lcolor(ebblue) lwidth(medthick)) ///
               (line `y' year if exp_q4 == 4, lcolor(dkorange) lwidth(medthick)), ///
               xlab(2010(1)2019) xtitle("Year") ytitle("`yt'") ///
               xline(2014, lpattern(dash) lcolor(gs10)) ///
               legend(order(1 "Q1 exposure" 2 "Q4 exposure") pos(6) ring(1) rows(1)) ///
               plotregion(margin(sides))
            graph export ../output/figures/all_jrnls/diag_supp_`y'.pdf, replace
        }
    restore
end

program es_compare
    use ../temp/diag_supp_samp, clear
    bys athr_id: egen ever_g = max(n_grants_all)
    keep if ever_g > 0 & !mi(ever_g)

    gen rel = year - 2014
    forval i = 1/4 {
        gen int_lead`i'  = exposure      if rel == -`i'
        gen mshr_lead`i' = mkt_spend_shr if rel == -`i'
    }
    forval i = 0/5 {
        gen int_lag`i'  = exposure      if rel == `i'
        gen mshr_lag`i' = mkt_spend_shr if rel == `i'
    }
    ds int_lead* int_lag* mshr_lead* mshr_lag*
    foreach v in `r(varlist)' {
        replace `v' = 0 if mi(`v')
    }
    save ../temp/diag_supp_es, replace

    foreach y in n_grants_all n_grants_ns n_new_all n_new_ns cost_all cost_ns {
        run_one, y(`y')
    }
end

program run_one
    syntax, y(string)
    use ../temp/diag_supp_es, clear
    local rhs int_lead4 int_lead3 int_lead2 int_lag0 int_lag1 int_lag2 int_lag3 int_lag4 int_lag5
    local ctl mshr_lead4 mshr_lead3 mshr_lead2 mshr_lag0 mshr_lag1 mshr_lag2 mshr_lag3 mshr_lag4 mshr_lag5

    di as text _n "===== ES `y' ====="
    cap noi reghdfe `y' `rhs' `ctl', absorb(athr_id year) vce(cluster athr_id)
    if _rc {
        di as error "  reghdfe failed rc=" _rc
        exit
    }
    qui gunique athr_id if e(sample)
    local npi = r(unique)

    cap mat drop es
    foreach v of local rhs {
        mat es = nullmat(es) \ (_b[`v'], _se[`v'])
    }
    preserve
        clear
        svmat es
        rename (es1 es2) (b se)
        gen year = 2009 + _n
        replace year = year + 1 if _n >= 4
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        set obs `=_N+1'
        replace year = 2013 if mi(year)
        foreach v in b se ub lb {
            replace `v' = 0 if year == 2013
        }
        sort year
        gen yvar = "`y'"
        export delimited using ../output/tables/diag_supp_es_`y'.csv, replace
        list year b se ub lb, sep(0) noobs

        tw (rcap ub lb year, lcolor(ebblue%70) msize(vsmall)) ///
           (scatter b year, mcolor(ebblue)), ///
           xlab(2010(1)2019) xtitle("Year") ytitle("`y'") ///
           yline(0, lcolor(gs10)) xline(2013.5, lpattern(dash) lcolor(gs10)) ///
           legend(order(- "Num. PIs: `npi'") pos(7) ring(1) size(small)) ///
           plotregion(margin(sides))
        graph export ../output/figures/all_jrnls/diag_supp_es_`y'.pdf, replace
    restore
end

main
log close
