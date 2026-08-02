set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

log using diag_grants.log, replace text

global SAMPSUF "_r1_r2"
global WT 0

program main
    cap mkdir ../output/tables
    cap mkdir ../output/figures/all_jrnls
    build_raw_nih
    build_panel_flag
    assemble
    coverage_tables
    raw_trends
    es_compare
end

* ---------------------------------------------------------------------------
* Author-year NIH measures rebuilt from the grant-level file, with NO
* publication-panel filter. This is the counterfactual to the shipped
* n_grants, which is merged through the (unbalanced) last-author panel.
* ---------------------------------------------------------------------------
program build_raw_nih
    use athr_id year grant_key row_key research total_cost project_start ///
        full_project_num using ../external/nih_grants/nih_grants_by_athr_id, clear
    drop if mi(year)
    duplicates drop athr_id year row_key, force

    * Award start taken from non-supplement rows, matching the derived build.
    * Computed here too so this runs before or after that rebuild.
    gen byte supplement = real(substr(strtrim(full_project_num), 1, 1)) == 3
    gen double _par = project_start if research & !supplement
    gen double _any = project_start if research
    gegen double award_start = min(_par), by(grant_key)
    gegen double _fb = min(_any), by(grant_key)
    replace award_start = _fb if mi(award_start)
    gen int start_year = year(award_start)
    drop _par _any _fb

    egen byte tag_res = tag(athr_id year grant_key) if research
    gen byte res_grant = tag_res == 1
    gen byte new_grant = res_grant & start_year == year
    gen double res_cost = total_cost if research
    gcollapse (sum) n_grants_raw = res_grant ///
              (sum) n_new_raw    = new_grant ///
              (sum) nih_cost_raw = res_cost, by(athr_id year) fast
    save ../temp/diag_nih_raw_athr_yr, replace

    use athr_id using ../external/nih_grants/nih_grants_by_athr_id, clear
    duplicates drop
    gen byte reporter_matched = 1
    save ../temp/diag_reporter_matched, replace
end

* Which PI-years actually exist in the last-author publication panel. Rows
* absent here are the ones tsfill creates and restrict_samp zero-fills.
program build_panel_flag
    use athr_id year using ../external/samp/athr_panel_full_year_last_all_jrnls_r1_r2, clear
    duplicates drop athr_id year, force
    gen byte in_pub_panel = 1
    save ../temp/diag_pub_panel_flag, replace
end

program assemble
    use ../output/prepped_samples/es_all_jrnls${SAMPSUF}, clear
    merge 1:1 athr_id year using ../temp/diag_pub_panel_flag, keep(1 3) nogen
    replace in_pub_panel = 0 if mi(in_pub_panel)
    merge 1:1 athr_id year using ../temp/diag_nih_raw_athr_yr, keep(1 3) nogen
    merge m:1 athr_id using ../temp/diag_reporter_matched, keep(1 3) nogen
    replace reporter_matched = 0 if mi(reporter_matched)

    foreach v in n_grants_raw n_new_raw nih_cost_raw {
        replace `v' = 0 if mi(`v') & reporter_matched == 1
        replace `v' = . if reporter_matched == 0
    }
    gen byte has_grant_raw = n_grants_raw > 0 if !mi(n_grants_raw)

    * Shipped-measure sample rule, restated on the raw measure so the two are
    * compared on the same PIs.
    bys athr_id: egen ever_raw = max(n_grants_raw)
    foreach v in n_grants_raw n_new_raw nih_cost_raw has_grant_raw {
        replace `v' = . if ever_raw == 0 | mi(ever_raw)
    }

    * Pre-determined version of the "ever holds a grant" rule: conditions only
    * on 2010-2013, so post-period grant arrival cannot select the sample.
    bys athr_id: egen pre_raw = max(cond(year < 2014, n_grants_raw, .))
    gen byte pre_holder = pre_raw > 0 & !mi(pre_raw)

    gen byte zero_filled_grant = in_pub_panel == 0 & reporter_matched == 1

    bys athr_id (year): gen byte pi_tag = _n == 1
    xtile _q = exposure if pi_tag == 1, nq(4)
    bys athr_id: egen exp_q4 = max(_q)
    drop _q

    compress
    save ../temp/diag_grants_samp, replace
end

* ---------------------------------------------------------------------------
* How much of n_grants is a publication-panel artifact, and is the artifact
* trending? A rising in_pub_panel share post-2014 would manufacture exactly
* the post-period increase we are trying to explain.
* ---------------------------------------------------------------------------
program coverage_tables
    use ../temp/diag_grants_samp, clear

    di as text _n "===== panel coverage and grant understatement, by year ====="
    table year if !mi(n_grants_raw), ///
        stat(mean in_pub_panel) stat(mean n_grants) stat(mean n_grants_raw) ///
        stat(mean zero_filled_grant) nformat(%9.4f)

    gen byte understated = n_grants < n_grants_raw if !mi(n_grants_raw) & !mi(n_grants)
    gen double gap_grants = n_grants_raw - n_grants
    di as text _n "===== share of PI-years where n_grants understates truth ====="
    table year if !mi(n_grants_raw), ///
        stat(mean understated) stat(mean gap_grants) nformat(%9.4f)

    di as text _n "===== same, split by exposure quartile (Q1 vs Q4) ====="
    table year exp_q4 if !mi(n_grants_raw) & inlist(exp_q4,1,4), ///
        stat(mean in_pub_panel) nformat(%9.4f)
    table year exp_q4 if !mi(n_grants_raw) & inlist(exp_q4,1,4), ///
        stat(mean gap_grants) nformat(%9.4f)

    di as text _n "===== sample composition under the two conditioning rules ====="
    qui gunique athr_id if !mi(n_grants_raw)
    di as text "  PIs with any grant 2010-2019 (shipped rule): " r(unique)
    qui gunique athr_id if pre_holder == 1
    di as text "  PIs with a grant in 2010-2013 (pre-determined rule): " r(unique)
    qui gunique athr_id if !mi(n_grants_raw) & pre_holder == 0
    di as text "  PIs entering only via a post-2013 grant: " r(unique)

    * Do the late entrants sit disproportionately in high-exposure cells? If so,
    * the shipped conditioning rule alone can generate the post-period rise.
    preserve
        keep if pi_tag == 1 & !mi(n_grants_raw)
        di as text _n "===== late-entrant share by exposure quartile ====="
        table exp_q4, stat(mean pre_holder) stat(freq) nformat(%9.4f)
    restore

    preserve
        collapse (mean) in_pub_panel gap_grants n_grants n_grants_raw ///
            if !mi(n_grants_raw), by(year exp_q4)
        export delimited using ../output/tables/diag_grant_coverage.csv, replace
    restore
end

* ---------------------------------------------------------------------------
* Raw (no-regression) trends: shipped vs corrected measure, top vs bottom
* exposure quartile.
* ---------------------------------------------------------------------------
program raw_trends
    use ../temp/diag_grants_samp, clear
    keep if !mi(n_grants_raw)
    gcollapse (mean) m_ship = n_grants (mean) m_raw = n_grants_raw ///
              (mean) m_new = n_new_raw (mean) m_cost = nih_cost_raw ///
              (mean) m_has = has_grant_raw (mean) m_cov = in_pub_panel, ///
              by(year exp_q4) fast
    sort exp_q4 year

    foreach y in m_ship m_raw m_new m_cost m_has m_cov {
        if "`y'" == "m_ship" local yt "# active grants (as coded, panel-merged)"
        if "`y'" == "m_raw"  local yt "# active grants (raw RePORTER)"
        if "`y'" == "m_new"  local yt "# new grants (flow)"
        if "`y'" == "m_cost" local yt "NIH award dollars"
        if "`y'" == "m_has"  local yt "Share holding >=1 active grant"
        if "`y'" == "m_cov"  local yt "Share of PI-years in publication panel"
        tw (line `y' year if exp_q4 == 1, lcolor(ebblue) lwidth(medthick)) ///
           (line `y' year if exp_q4 == 4, lcolor(dkorange) lwidth(medthick)), ///
           xlab(2010(1)2019) xtitle("Year") ytitle("`yt'") ///
           xline(2014, lpattern(dash) lcolor(gs10)) ///
           legend(order(1 "Q1 exposure" 2 "Q4 exposure") pos(6) ring(1) rows(1)) ///
           plotregion(margin(sides))
        graph export ../output/figures/all_jrnls/diag_grants_`y'.pdf, replace
    }
    export delimited using ../output/tables/diag_grant_raw_trends.csv, replace
end

* ---------------------------------------------------------------------------
* Event study run five ways on the same PIs. If the post-period rise is real
* it should survive (1) the corrected measure, (2) pre-determined sample
* conditioning, (3) field-by-year FE, and it should show up in the flow.
* ---------------------------------------------------------------------------
program es_compare
    use ../temp/diag_grants_samp, clear
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
    local rhs int_lead4 int_lead3 int_lead2 int_lag0 int_lag1 int_lag2 int_lag3 int_lag4 int_lag5
    local ctl mshr_lead4 mshr_lead3 mshr_lead2 mshr_lag0 mshr_lag1 mshr_lag2 mshr_lag3 mshr_lag4 mshr_lag5
    save ../temp/diag_grants_es, replace

    run_one, y(n_grants)      cond()               fe(athr_id year) tag(ship)
    run_one, y(n_grants_raw)  cond()               fe(athr_id year) tag(raw)
    run_one, y(n_grants_raw)  cond(pre_holder==1)  fe(athr_id year) tag(raw_preholder)
    run_one, y(n_grants_raw)  cond()               fe(athr_id i.cluster_30#i.year) tag(raw_fldyr)
    run_one, y(n_new_raw)     cond()               fe(athr_id year) tag(new_flow)
    run_one, y(has_grant_raw) cond()               fe(athr_id year) tag(extensive)
    run_one, y(nih_cost_raw)  cond()               fe(athr_id year) tag(cost)
end

program run_one
    syntax, y(string) fe(string) tag(string) [cond(string)]
    use ../temp/diag_grants_es, clear
    local rhs int_lead4 int_lead3 int_lead2 int_lag0 int_lag1 int_lag2 int_lag3 int_lag4 int_lag5
    local ctl mshr_lead4 mshr_lead3 mshr_lead2 mshr_lag0 mshr_lag1 mshr_lag2 mshr_lag3 mshr_lag4 mshr_lag5
    local wt ""
    if "$WT" == "1" local wt "[pw=max_sim]"
    local ifc ""
    if "`cond'" != "" local ifc "if `cond'"

    di as text _n "===== ES `tag': `y' | FE(`fe') `ifc' ====="
    cap noi reghdfe `y' `rhs' `ctl' `ifc' `wt', absorb(`fe') vce(cluster athr_id)
    if _rc {
        di as error "  reghdfe failed rc=" _rc
        exit
    }
    qui gunique athr_id if e(sample)
    local npi = r(unique)
    qui sum `y' if rel <= -1 & e(sample)
    local premean : di %6.4f r(mean)

    cap mat drop es
    foreach v in int_lead4 int_lead3 int_lead2 int_lag0 int_lag1 int_lag2 int_lag3 int_lag4 int_lag5 {
        mat es = nullmat(es) \ (_b[`v'], _se[`v'])
    }
    preserve
        clear
        svmat es
        rename (es1 es2) (b se)
        gen year = .
        replace year = 2010 in 1
        replace year = 2011 in 2
        replace year = 2012 in 3
        forval i = 4/9 {
            replace year = 2010 + `i' in `i'
        }
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        set obs `=_N+1'
        replace year = 2013 if mi(year)
        foreach v in b se ub lb {
            replace `v' = 0 if year == 2013
        }
        sort year
        gen spec = "`tag'"
        gen yvar = "`y'"
        export delimited using ../output/tables/diag_es_`tag'.csv, replace
        list year b se ub lb, sep(0) noobs

        qui sum ub
        local ymax = r(max)
        qui sum lb
        local ymin = min(r(min), 0)
        tw (rcap ub lb year, lcolor(ebblue%70) msize(vsmall)) ///
           (scatter b year, mcolor(ebblue)), ///
           xlab(2010(1)2019) xtitle("Year") ytitle("`y' (`tag')") ///
           yline(0, lcolor(gs10)) xline(2013.5, lpattern(dash) lcolor(gs10)) ///
           legend(order(- "Num. PIs: `npi'" "Pre-period mean: `premean'") ///
                  pos(7) ring(1) rows(2) size(small)) ///
           plotregion(margin(sides))
        graph export ../output/figures/all_jrnls/diag_es_`tag'.pdf, replace
    restore
end

main
log close
