set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main  
    gather_external_data
    foreach s in all_jrnls top_jrnls {
        cap mkdir "../output/figures/`s'" 
        // r1 + r2 + public
        restrict_samp, samp(`s') r1r2(1) public(1)
        desc_stats, samp(`s') r1r2(1) public(1)
        event_study, samp(`s') r1r2(1) public(1)
        long_diff, samp(`s') r1r2(1) public(1)
        first_diff, samp(`s') r1r2(1) public(1)
        pooled_did, samp(`s') r1r2(1) public(1)
        ppml_specs, samp(`s') r1r2(1) public(1)
        output_tables, samp(`s') r1r2(1) public(1)
        confidence_strat_did, samp(`s') r1r2(1) public(1)
        combine_es_graphs, samp(`s')
        robustness, samp(`s') r1r2(1) public(1)
    /*    // r1 + r2
        restrict_samp, samp(`s') r1r2(1) public(0)
        event_study, samp(`s') r1r2(1) public(0)
        // everyone
        restrict_samp, samp(`s') r1r2(0) public(0)
        event_study, samp(`s') r1r2(0) public(0)*/
    }
    joint_outcome_test, samp(all_jrnls) r1r2(1) public(1)
    joint_sample_test, r1r2(1) public(1)
end

program gather_external_data
/*    import delimited ../external/exposure/final_imputed_shift_share_restricted_ms010, clear
    rename exposure_ss imputed
    rename sum_imputed_shares imputed_mkt_spend_shr*/
   import delimited ../external/exposure/final_imputed_exposure_restricted, clear
    rename exposure imputed
    rename mkt_spend_shr imputed_mkt_spend_shr
    save ../temp/exposure, replace

    // Per-universe-author match diagnostics (max_sim to nearest FOIA PI) for
    // confidence-stratified pooled DiD. Source file is produced by running
    // derived/openalex/foia_similarity_wts/code/tfidf/export_diag_to_dta.py
    // once. If the .dta is missing we skip silently — confidence_strat_did
    // will warn at call site.
    cap noi use ../external/exposure/match_diagnostics, clear
    if !_rc {
        keep athr_id max_sim
        save ../temp/diag, replace
    }
    else {
        di as error "WARNING: match_diagnostics_restricted.dta not found. " ///
            "Run export_diag_to_dta.py in derived/openalex/foia_similarity_wts " ///
            "if you want confidence_strat_did to run."
    }

    use ../external/grants/pi_grants_clean, clear
    bys athr_id year: gen num_grants = _N
    contract athr_id year num_grants
    drop _freq
    save ../temp/athr_yr_grnt_cnt, replace

    use ../external/foias/merged_foias_with_pis,  clear
    drop if mi(athr_id)
    gen year = year(date(date, "YMD"))
    merge m:1 category using ../external/categories/categories_tfidf, assert(1 2 3) keep(1 3) 
    gen nonlab = 1 if _merge == 1
    replace nonlab = 0 if mi(nonlab)
    drop if nonlab == 0
    gcollapse (sum) spend, by(athr_id uni year)
    save ../temp/foia_spend, replace
/*    merge m:1 athr_id using  ../external/real_exposure/athr_exposure, assert(1 2 3) keep(3) nogen
    gen post = year >= 2014
    gen Z_it = exposure*post
    xtset athr_id year*/
end

program restrict_samp 
    syntax, samp(string) [, r1r2(int 0) public(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"
    use ../external/samp/athr_panel_full_year_last_`samp'`suf',clear 
    bys athr_id: egen tot_pprs = total(ppr_cnt)
    keep if tot_pprs >=15
    drop tot_pprs
    bys athr_id: egen max_year = max(year)
    keep if max_year >= 2015
    keep if inrange(year, 2010, 2019)
    bys athr_id: egen min_year = min(year)
    keep if min_year <= 2012
    merge m:1 athr_id using ../temp/exposure, assert(1 2 3) keep(3) nogen
    merge m:1 athr_id using ../external/real_exposure/athr_exposure, assert(1 2 3) keep(1 3) nogen
    gen foia_athr = 1 if !mi(exposure)
    bys athr_id : gen athr_indicator = _n == 1
   * keep if foia_athr == 1
    sum exposure if athr_indicator == 1 & exposure > 0, d 
    local mean : di %4.3f r(mean) 
    local sd: di %4.3f r(sd) 
    local p25: di %4.3f r(p25) 
    local p50: di %4.3f r(p50) 
    local p75: di %4.3f r(p75)
    local max: di %4.3f  r(max) 
    local min: di %4.3f r(min) 
    sum imputed if athr_indicator == 1 & imputed > 0, d 
    local imputed_mean : di %4.3f r(mean) 
    local imputed_sd: di %4.3f r(sd) 
    local imputed_p25: di %4.3f r(p25) 
    local imputed_p50: di %4.3f r(p50) 
    local imputed_p75: di %4.3f r(p75)
    local imputed_max: di %4.3f  r(max) 
    local imputed_min: di %4.3f r(min) 
    sum mkt_spend_shr if athr_indicator == 1 , d
    sum imputed_mkt_spend_shr if athr_indicator == 1 , d
    replace imputed = exposure if !mi(exposure)
    replace imputed_mkt_spend_shr = mkt_spend_shr if !mi(mkt_spend_shr)
    tw kdensity exposure if athr_indicator == 1 & exposure > 0 || kdensity imputed if athr_indicator == 1 & imputed > 0 , xtitle("Exposure Measure") ytitle("Density") ///
        xlab(#15) ///
        legend(on label(1 "FOIA PI Observed Exposure (mean = `mean', sd = `sd')") label(2 "Imputed Exposure (mean = `imputed_mean', sd = `imputed_sd')") pos(1) ring(0) size(small))
    graph export ../output/figures/`samp'/exposure_dist`suf'.pdf, replace
    drop exposure
    rename imputed exposure
    drop mkt_spend_shr
    rename imputed_mkt_spend_shr mkt_spend_shr
    drop if exposure <= 0 | mi(exposure)
    drop if mkt_spend_shr ==. | mkt_spend_shr <=0
    gen q1 = exposure < `imputed_p25'
    gen q2 = inrange(exposure , `imputed_p25', `imputed_p50')
    gen q3 = inrange(exposure , `imputed_p50', `imputed_p75')
    gen q4 = exposure >= `imputed_p75'
    gen median = exposure >= `imputed_p50'
    bys athr_id: gen num_yrs = _N
    bys athr_id inst_id: gen plc_cntr = _n == 1
    bys athr_id : egen num_place = total(plc_cntr)
    drop if num_yrs<=3
    keep if num_place==1
    gegen athr = group(athr_id)
    preserve
    contract athr athr_id exposure q1 q2 q3 q4 median inst_id inst msa_comb msa_c_world min_year type mkt_spend_shr
    drop _freq
    save ../temp/athr_xw, replace
    restore
    xtset athr year
    tsfill, full
    drop athr_id exposure q1 q2 q3 q4 median inst_id inst msa_comb msa_c_world min_year type mkt_spend_shr
    merge m:1 athr using ../temp/athr_xw, assert(3) keep(3) nogen
    foreach var in cite_affl_wt ppr_cnt affl_wt body_adj_wt  {
        replace `var' = 0 if mi(`var')    
    }
    bys athr_id: egen tot_pprs = total(ppr_cnt)
    drop if tot_pprs < 5 
    gen age = 2026-min_year + 30 
    gen age_2014 = 2014 - min_year + 30
    gen above_median = exposure >= `imputed_p50'
    gen below_median = exposure < `imputed_p50'
    sum age_2014, d
    local med = r(p50)
    gen young = age_2014 < `med'
    gen old = age_2014 >= `med'
    gen r1 = type == "r1" 
    gen r2 = type == "r2" 
    gen pre_ppr_cnt = ppr_cnt if year < 2014
    bys athr_id: egen pre_ppr_cnt_sum = sum(pre_ppr_cnt)
    sum pre_ppr_cnt_sum, d
    gen high_pre_ppr = pre_ppr_cnt_sum >= r(p50)
    gen low_pre_ppr = pre_ppr_cnt_sum < r(p50)
    merge 1:1 athr_id year using ../external/coathrs/avg_coathrs, keep(1 3) assert(1 2 3) nogen
    replace avg_num_coathrs = 0 if mi(avg_num_coathrs)
    merge 1:1 athr_id year using ../temp/athr_yr_grnt_cnt, keep(1 3) assert(1 2 3) nogen
    replace num_grants = 0 if mi(num_grants)
    gen pre_grants_cnt = num_grants if year < 2014
    bys athr_id: egen pre_grants_sum = total(pre_grants_cnt)
    drop pre_grants_cnt
    qui sum pre_grants_sum if athr_indicator == 1, d
    local g_cut = r(p50)
    if `g_cut' <= 0 local g_cut = 0.5
    di as text "restrict_samp `samp'`suf' pre-grant median = `g_cut'"
    gen high_grants = pre_grants_sum >= `g_cut'
    gen low_grants  = pre_grants_sum <  `g_cut'
    assert !mi(athr_id)
    assert !mi(exposure)
    assert !mi(mkt_spend_shr)
    save ../temp/es_`samp'`suf', replace
end

program desc_stats
    syntax, samp(string) [, r1r2(int 0) public(int 0)]
    local fes athr_id year  
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"
    use ../temp/es_`samp'`suf', clear 
    gen quartile = "q1" if q1 ==1
    replace quartile = "q2" if q2 ==1
    replace quartile = "q3" if q3 ==1
    replace quartile = "q4" if q4 ==1
    collapse (mean) ppr_cnt cite_affl_wt affl_wt body_adj_wt avg_num_coathrs r1 age num_grants (firstnm) quartile, by(athr_id year)
    gcollapse (mean) ppr_cnt cite_affl_wt affl_wt body_adj_wt avg_num_coathrs r1 age num_grants ,  by(quartile year)
    foreach var in ppr_cnt cite_affl_wt affl_wt body_adj_wt avg_num_coathrs r1 age num_grants {
        tw line `var' year if quartile == "q1", lcolor(lavender) || ///
        line `var' year if quartile == "q2" , lcolor(dkorange) || ///
        line `var' year if quartile == "q3" , lcolor(ebblue) || ///
        line `var' year if quartile == "q4", lcolor(dkemerald) ///
        ,  legend(on pos(1) ring(0) size(small)) xtitle("Year") ytitle("`var'") plotregion(margin(sides))
        graph export ../output/figures/`samp'/desc_`var'`suf'.pdf, replace
    }
end

program event_study
    syntax, samp(string) [, r1r2(int 0) public(int 0)]
    local fes athr_id year  
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"
    use ../temp/es_`samp'`suf', replace

    gen rel = year - 2014 
    qui sum rel, d
    local abs_lag = abs(r(max))
    qui sum rel, d
    local abs_lead = abs(r(min))
    local timeframe = max(`abs_lag', `abs_lead')
    forval i = 1/`timeframe' {
        gen int_lag`i' = exposure if rel == `i'
        gen int_lead`i' = exposure if rel == -`i'
        gen lag`i' = 1 if rel == `i'
        gen lead`i' = 1 if rel == -`i'
        gen mshr_lag`i'  = mkt_spend_shr if rel == `i'
        gen mshr_lead`i' = mkt_spend_shr if rel == -`i'
    }
    gen int_lag0 = exposure if rel == 0
    gen lag0 = 1 if rel == 0
    gen mshr_lag0 = mkt_spend_shr if rel == 0
    ds lead* lag* int_lead* int_lag* mshr_lead* mshr_lag*
    foreach var in `r(varlist)' {
        replace `var' = 0 if mi(`var')
    }
    local leads
    local int_leads
    local mshr_leads
    local lags
    local int_lags
    local mshr_lags
    forval i = 2/`abs_lead' {
        local leads lead`i' `leads'
        local int_leads int_lead`i' `int_leads'
        local mshr_leads mshr_lead`i' `mshr_leads'
    }
    forval i = 0/`abs_lag' {
        local lags `lags' lag`i'
        local int_lags `int_lags' int_lag`i'
        local mshr_lags `mshr_lags' mshr_lag`i'
    }
    foreach v in cite_affl_wt ppr_cnt {
        gen ln_`v' = ln(1+`v')
    }

    // pre-build group-suffixed event-time interactions for heterogeneity (used in pooled-interaction regressions below)
    foreach grp in young old r1 r2 above_median below_median high_pre_ppr low_pre_ppr high_grants low_grants q1 q2 q3 q4 {
        foreach v of local int_leads {
            gen `v'_`grp' = `v' * `grp'
        }
        foreach v of local int_lags {
            gen `v'_`grp' = `v' * `grp'
        }
        gen int_lead1_`grp' = int_lead1 * `grp'
        local leads_`grp'
        local lags_`grp'
        foreach v of local int_leads {
            local leads_`grp' `leads_`grp'' `v'_`grp'
        }
        foreach v of local int_lags {
            local lags_`grp' `lags_`grp'' `v'_`grp'
        }
    }

    foreach yvar in cite_affl_wt ppr_cnt ln_cite_affl_wt ln_ppr_cnt body_adj_wt avg_num_coathrs num_grants {
        if "`yvar'" == "ln_spend" local var_name = "Log Spending" 
        if "`yvar'" == "ln_spend" local gap  0.5 
        if "`yvar'" == "cite_affl_wt" local var_name = "Citation Weighted Output" 
        if "`yvar'" == "cite_affl_wt" local gap  1 
        if "`yvar'" == "ppr_cnt" local var_name = "Publication Count"
        if "`yvar'" == "ppr_cnt" local gap 0.5
        if "`yvar'" == "ppr_cnt"      & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "cite_affl_wt" & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "avg_coathrs" local var_name = "Average Team Size"
        if "`yvar'" == "avg_coathrs" local gap 0.5

        preserve
        mat drop _all
        sum `yvar' if rel <= -1 & exposure > 0, d
        local pre_mean : dis %4.3f r(mean)
        gunique athr_id
        local num_athrs = r(unique)
        gunique inst_id
        local num_insts = r(unique)
        reghdfe `yvar' `int_leads' `int_lags' int_lead1, absorb(`fes') vce(cluster athr_id)
        foreach var in `int_leads' `int_lags' int_lead1 {
            mat row = _b[`var'], _se[`var']
            if "`var'" == "int_lead1" {
                mat row = 0,0
            }
            mat es = nullmat(es) \ row
        }
        svmat es
        keep es1 es2
        drop if mi(es1)
        rename (es1 es2) (b se)
        gen ub = b + 1.96*se
        sum ub, d
        local ymax =round(r(max),`gap')
        gen lb = b - 1.96*se
        sum lb, d
        local ymin = min(-2.5,round(r(min),`gap'))
        gen rel = -4 if _n == 1
        replace rel = rel[_n-1]+1 if _n > 1
        replace rel = rel + 1 if rel >= -1
        replace rel = -1 if rel == `abs_lag' + 1
        gen year = rel + 2014
        hashsort rel
        tw rcap ub lb year if year != 2013 , lcolor(ebblue%70) msize(vsmall) || ///
          scatter b year, mcolor(ebblue) || ///
          scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
          xlab(2010(1)2019) xtitle("Year") ///
          ytitle("`var_name'") ylab(`ymin'(`gap')`ymax') ///
          yline(0, lcolor(gs10) lpattern(solid)) ///
          legend(on order(- "Num. PIs: `num_athrs'" "Num. Institutions: `num_insts'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) plotregion(margin(sides))
        graph export ../output/figures/`samp'/es_`yvar'`suf'.pdf, replace
        save ../temp/es_`yvar', replace
        restore

        // alternative spec: control for mkt_spend_shr x rel-year dummies
        preserve
        mat drop _all
        reghdfe `yvar' `int_leads' `int_lags' int_lead1 ///
                       `mshr_leads' `mshr_lags' mshr_lead1, ///
                       absorb(`fes') vce(cluster athr_id)
        foreach var in `int_leads' `int_lags' int_lead1 {
            mat row = _b[`var'], _se[`var']
            if "`var'" == "int_lead1" {
                mat row = 0,0
            }
            mat es = nullmat(es) \ row
        }
        svmat es
        keep es1 es2
        drop if mi(es1)
        rename (es1 es2) (b se)
        gen ub = b + 1.96*se
        sum ub, d
        local ymax = round(r(max),`gap')
        gen lb = b - 1.96*se
        sum lb, d
        local ymin = min(-2.5,round(r(min),`gap'))
        gen rel = -4 if _n == 1
        replace rel = rel[_n-1]+1 if _n > 1
        replace rel = rel + 1 if rel >= -1
        replace rel = -1 if rel == `abs_lag' + 1
        gen year = rel + 2014
        hashsort rel
        tw rcap ub lb year if year != 2013 , lcolor(ebblue%70) msize(vsmall) || ///
          scatter b year, mcolor(ebblue) || ///
          scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
          xlab(2010(1)2019) xtitle("Year") ///
          ytitle("`var_name'") ylab(`ymin'(`gap')`ymax') ///
          yline(0, lcolor(gs10) lpattern(solid)) ///
          legend(on order(- "Num. PIs: `num_athrs'" "Num. Institutions: `num_insts'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) plotregion(margin(sides))
        graph export ../output/figures/`samp'/es_`yvar'`suf'_mshrctrl.pdf, replace
        save ../temp/es_`yvar'`suf'_mshrctrl, replace
        restore

        // Poisson (ppmlhdfe) version — skip already-logged outcomes; coefs are semielasticities
        if !regexm("`yvar'", "^ln_") {
            foreach spec in base mshrctrl {
                preserve
                mat drop _all
                if "`spec'" == "base" {
                    cap noi ppmlhdfe `yvar' `int_leads' `int_lags', ///
                            absorb(`fes') vce(cluster athr_id)
                }
                else {
                    cap noi ppmlhdfe `yvar' `int_leads' `int_lags' ///
                                           `mshr_leads' `mshr_lags', ///
                            absorb(`fes') vce(cluster athr_id)
                }
                if _rc {
                    di as error "ppmlhdfe `yvar' `spec' failed (rc=`_rc'); skipping plot."
                    restore
                    continue
                }
                foreach var in `int_leads' `int_lags' int_lead1 {
                    if "`var'" == "int_lead1" {
                        mat row = 0,0
                    }
                    else {
                        mat row = _b[`var'], _se[`var']
                    }
                    mat es = nullmat(es) \ row
                }
                svmat es
                keep es1 es2
                drop if mi(es1)
                rename (es1 es2) (b se)
                gen ub = b + 1.96*se
                sum ub, d
                local ymax = round(r(max), 0.1)
                gen lb = b - 1.96*se
                sum lb, d
                local ymin = round(r(min), 0.1)
                gen rel = -4 if _n == 1
                replace rel = rel[_n-1]+1 if _n > 1
                replace rel = rel + 1 if rel >= -1
                replace rel = -1 if rel == `abs_lag' + 1
                gen year = rel + 2014
                hashsort rel
                local plot_suf "_ppml"
                if "`spec'" == "mshrctrl" local plot_suf "_ppml_mshrctrl"
                tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
                  scatter b year, mcolor(ebblue) || ///
                  scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                  xlab(2010(1)2019) xtitle("Year") ///
                  ytitle("`var_name' (Poisson semielasticity)") ylab(`ymin'(0.1)`ymax') ///
                  yline(0, lcolor(gs10) lpattern(solid)) ///
                  legend(on order(- "Num. PIs: `num_athrs'" "Num. Institutions: `num_insts'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) plotregion(margin(sides))
                graph export ../output/figures/`samp'/es_`yvar'`suf'`plot_suf'.pdf, replace
                save ../temp/es_`yvar'`suf'`plot_suf', replace
                restore
            }
        }

        // heterogeneity by author & inst characteristics — one regression per dummy pair, split-interaction form
        local dummy_pairs `" "young old" "r1 r2" "above_median below_median" "high_pre_ppr low_pre_ppr" "high_grants low_grants" "'
        foreach pair of local dummy_pairs {
            local g1: word 1 of `pair'
            local g2: word 2 of `pair'
            reghdfe `yvar' `leads_`g1'' `lags_`g1'' `leads_`g2'' `lags_`g2'' int_lead1_`g1' int_lead1_`g2', ///
                    absorb(`fes') vce(cluster athr_id)

            foreach grp in `g1' `g2' {
                sum `yvar' if rel <= -1 & exposure > 0 & `grp' == 1, d
                local pre_mean : dis %4.3f r(mean)
                gunique athr_id if exposure > 0 & `grp' == 1
                local num_athrs = r(unique)
                preserve
                mat drop _all
                foreach var in `leads_`grp'' `lags_`grp'' int_lead1_`grp' {
                    mat row = _b[`var'], _se[`var']
                    if "`var'" == "int_lead1_`grp'" {
                        mat row = 0,0
                    }
                    mat es = nullmat(es) \ row
                }
                svmat es
                keep es1 es2
                drop if mi(es1)
                rename (es1 es2) (b se)
                gen ub = b + 1.96*se
                sum ub, d
                local ymax = round(r(max),`gap')
                gen lb = b - 1.96*se
                sum lb, d
                local ymin = round(r(min),`gap')
                gen rel = -4 if _n == 1
                replace rel = rel[_n-1]+1 if _n > 1
                replace rel = rel + 1 if rel >= -1
                replace rel = -1 if rel == `abs_lag' + 1
                gen year = rel + 2014
                hashsort rel
                tw rcap ub lb year if year != 2013 , lcolor(ebblue%70) msize(vsmall) || ///
                  scatter b year, mcolor(ebblue) || ///
                scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                  xlab(2010(1)2019) xtitle("Year") ///
                  ytitle("`var_name'") ylab(`ymin'(`gap')`ymax') ///
                  legend(on order(- "Num. PIs: `num_athrs'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) ///
                  yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
                graph export ../output/figures/`samp'/es_`yvar'`suf'_`grp'.pdf, replace
                save ../temp/es_`yvar'`suf'_`grp', replace
                restore
            }
        }
       
        // heterogeneity by exposure quartiles — one pooled regression with all 4 quartile-interacted dummy sets
        reghdfe `yvar' `leads_q1' `lags_q1' `leads_q2' `lags_q2' ///
                       `leads_q3' `lags_q3' `leads_q4' `lags_q4' ///
                       int_lead1_q1 int_lead1_q2 int_lead1_q3 int_lead1_q4, ///
                       absorb(`fes') vce(cluster athr_id)
        forval i = 1/4 {
            preserve
            mat drop _all
            foreach var in `leads_q`i'' `lags_q`i'' int_lead1_q`i' {
                mat row = _b[`var'], _se[`var']
                if "`var'" == "int_lead1_q`i'" {
                    mat row = 0,0
                }
                mat es = nullmat(es) \ row
            }
            svmat es
            keep es1 es2
            drop if mi(es1)
            rename (es1 es2) (b se)
            gen ub = b + 1.96*se
            sum ub, d
            local ymax = round(r(max),`gap')
            gen lb = b - 1.96*se
            sum lb, d
            local ymin = round(r(min),`gap')
            gen rel = -4 if _n == 1
            replace rel = rel[_n-1]+1 if _n > 1
            replace rel = rel + 1 if rel >= -1
            replace rel = -1 if rel == `abs_lag' + 1
            gen year = rel + 2014
            hashsort rel
            tw rcap ub lb year if year != 2013 , lcolor(ebblue%70) msize(vsmall) || ///
              scatter b year, mcolor(ebblue) || ///
            scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
              xlab(2010(1)2019) xtitle("Year") ///
              ytitle("`var_name'") ylab(`ymin'(`gap')`ymax') ///
              yline(0, lcolor(gs10) lpattern(solid)) legend(off) plotregion(margin(sides))
            graph export ../output/figures/`samp'/es_`yvar'_q`i'`suf'.pdf, replace
            save ../temp/es_`yvar'_q`i', replace
            restore
        }
    }
end

program long_diff
    syntax, samp(string) [, r1r2(int 0) public(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"
    use ../temp/es_`samp'`suf', clear

    foreach v in cite_affl_wt ppr_cnt {
        cap gen ln_`v' = ln(1+`v')
    }

    local outcomes cite_affl_wt ppr_cnt ln_cite_affl_wt ln_ppr_cnt affl_wt body_adj_wt avg_num_coathrs num_grants

    gen pre  = year <  2014
    gen post = year >= 2014

    // require both pre and post obs per PI for the long difference
    bys athr_id: egen has_pre  = max(pre)
    bys athr_id: egen has_post = max(post)
    qui gunique athr_id
    local n_total = r(unique)
    qui gunique athr_id if has_pre == 0 | has_post == 0
    local n_dropped = r(unique)
    di as text "long_diff: dropping `n_dropped' / `n_total' PIs missing pre or post observations"
    keep if has_pre == 1 & has_post == 1
    drop has_pre has_post

    preserve
        keep if pre == 1
        gcollapse (mean) `outcomes', by(athr_id)
        foreach v of local outcomes {
            rename `v' `v'_pre
        }
        save ../temp/ld_pre_means_`samp'`suf', replace
    restore
    preserve
        keep if post == 1
        gcollapse (mean) `outcomes', by(athr_id)
        foreach v of local outcomes {
            rename `v' `v'_post
        }
        save ../temp/ld_post_means_`samp'`suf', replace
    restore

    // collapse to PI-level cross-section: time-invariant chars
    gcollapse (firstnm) exposure mkt_spend_shr q1 q2 q3 q4 above_median below_median ///
                       young old r1 r2 high_pre_ppr low_pre_ppr high_grants low_grants age_2014, ///
                       by(athr_id)
    merge 1:1 athr_id using ../temp/ld_pre_means_`samp'`suf',  assert(3) nogen
    merge 1:1 athr_id using ../temp/ld_post_means_`samp'`suf', assert(3) nogen

    foreach v of local outcomes {
        gen d_`v' = `v'_post - `v'_pre
    }

    save ../temp/ld_`samp'`suf', replace

    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'

    foreach yvar of local outcomes {
        local var_name "`yvar'"
        if "`yvar'" == "cite_affl_wt"    local var_name "Citation Weighted Output"
        if "`yvar'" == "ppr_cnt"         local var_name "Publication Count"
        if "`yvar'" == "ln_cite_affl_wt" local var_name "Log(1+Cite-Wtd Output)"
        if "`yvar'" == "ln_ppr_cnt"      local var_name "Log(1+Pub Count)"
        if "`yvar'" == "affl_wt"         local var_name "Affiliation Weighted Output"
        if "`yvar'" == "body_adj_wt"     local var_name "Body-Adj Weighted Output"
        if "`yvar'" == "avg_num_coathrs" local var_name "Avg Coauthors"
        if "`yvar'" == "num_grants"      local var_name "Num Grants"

        eststo clear
        eststo m1: reg d_`yvar' exposure, vce(robust)
        eststo m2: reg d_`yvar' q2 q3 q4, vce(robust)
        eststo m3: reg d_`yvar' c.exposure##i.young, vce(robust)
        eststo m4: reg d_`yvar' c.exposure##i.r1, vce(robust)
        eststo m5: reg d_`yvar' c.exposure##i.high_pre_ppr, vce(robust)
        eststo m6: reg d_`yvar' c.exposure##i.high_grants, vce(robust)

        esttab m1 m2 m3 m4 m5 m6 using ../output/tables/`samp'/ld_`yvar'`suf'.tex, ///
            replace label se r2 ///
            title("Long Difference: `var_name'`suf'") ///
            mtitles("Continuous" "Quartile" "x Young" "x R1" "x HighPrePub" "x HighGrants")

        // base vs. + market-share spec, stored in ld_<yvar> matrix for matrix_to_txt
        qui reg d_`yvar' exposure, vce(robust)
        local b_b   = _b[exposure]
        local b_se  = _se[exposure]
        local b_N   = e(N)
        local b_r2  = e(r2)
        qui reg d_`yvar' exposure mkt_spend_shr, vce(robust)
        local s_bx  = _b[exposure]
        local s_sex = _se[exposure]
        local s_bs  = _b[mkt_spend_shr]
        local s_ses = _se[mkt_spend_shr]
        local s_N   = e(N)
        local s_r2  = e(r2)
        cap mat drop ld_`yvar'
        mat ld_`yvar' = J(6,2,.)
        mat ld_`yvar'[1,1] = `b_b'
        mat ld_`yvar'[2,1] = `b_se'
        mat ld_`yvar'[5,1] = `b_N'
        mat ld_`yvar'[6,1] = `b_r2'
        mat ld_`yvar'[1,2] = `s_bx'
        mat ld_`yvar'[2,2] = `s_sex'
        mat ld_`yvar'[3,2] = `s_bs'
        mat ld_`yvar'[4,2] = `s_ses'
        mat ld_`yvar'[5,2] = `s_N'
        mat ld_`yvar'[6,2] = `s_r2'
        mat rownames ld_`yvar' = b_exposure se_exposure b_share se_share N r2
        mat colnames ld_`yvar' = base with_share

        local b_str   : dis %7.3f `b_b'
        local bse_str : dis %7.3f `b_se'
        binscatter d_`yvar' exposure, n(30) ///
            xtitle("Exposure") ytitle("Change in `var_name'") ///
            msymbol(O) mcolor(ebblue) ///
            note("{&beta} = `b_str' (SE: `bse_str')") ///
            plotregion(margin(sides))
        graph export ../output/figures/`samp'/ld_`yvar'`suf'.pdf, replace

        local s_b_str   : dis %7.3f `s_bx'
        local s_bse_str : dis %7.3f `s_sex'
        binscatter d_`yvar' exposure, n(30) controls(mkt_spend_shr) ///
            xtitle("Exposure") ytitle("Change in `var_name'") ///
            msymbol(O) mcolor(ebblue) ///
            note("{&beta} = `s_b_str' (SE: `s_bse_str')") ///
            plotregion(margin(sides))
        graph export ../output/figures/`samp'/ld_`yvar'`suf'_mshrctrl.pdf, replace
    }
end

program first_diff
    // panel first difference: D.y on exposure x Delta(post) (= exposure at t=2014, 0 elsewhere)
    // with year FE, clustered by PI. Identifies off the 2013->2014 jump.
    syntax, samp(string) [, r1r2(int 0) public(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"
    use ../temp/es_`samp'`suf', clear

    foreach v in cite_affl_wt ppr_cnt {
        cap gen ln_`v' = ln(1+`v')
    }

    local outcomes cite_affl_wt ppr_cnt ln_cite_affl_wt ln_ppr_cnt affl_wt body_adj_wt avg_num_coathrs num_grants

    xtset athr year
    gen post = year >= 2014

    foreach v of local outcomes {
        gen d_`v' = D.`v'
    }
    // Delta treatment intensity: exposure * (post_t - post_{t-1}); nonzero only at t=2014
    gen d_treat       = exposure              * (post - L.post)
    gen d_share_treat = mkt_spend_shr * (post - L.post)
    drop if mi(d_treat)

    save ../temp/fd_`samp'`suf', replace

    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'

    foreach yvar of local outcomes {
        local var_name "`yvar'"
        if "`yvar'" == "cite_affl_wt"    local var_name "Citation Weighted Output"
        if "`yvar'" == "ppr_cnt"         local var_name "Publication Count"
        if "`yvar'" == "ln_cite_affl_wt" local var_name "Log(1+Cite-Wtd Output)"
        if "`yvar'" == "ln_ppr_cnt"      local var_name "Log(1+Pub Count)"
        if "`yvar'" == "affl_wt"         local var_name "Affiliation Weighted Output"
        if "`yvar'" == "body_adj_wt"     local var_name "Body-Adj Weighted Output"
        if "`yvar'" == "avg_num_coathrs" local var_name "Avg Coauthors"
        if "`yvar'" == "num_grants"      local var_name "Num Grants"

        eststo clear
        eststo m1: reghdfe d_`yvar' d_treat,                          absorb(year) vce(cluster athr_id)
        eststo m2: reghdfe d_`yvar' c.d_treat##i.young,               absorb(year) vce(cluster athr_id)
        eststo m3: reghdfe d_`yvar' c.d_treat##i.r1,                  absorb(year) vce(cluster athr_id)
        eststo m4: reghdfe d_`yvar' c.d_treat##i.high_pre_ppr,        absorb(year) vce(cluster athr_id)
        eststo m5: reghdfe d_`yvar' c.d_treat##i.high_grants,        absorb(year) vce(cluster athr_id)

        esttab m1 m2 m3 m4 m5 using ../output/tables/`samp'/fd_`yvar'`suf'.tex, ///
            replace label se r2 ///
            title("First Difference (D.y on exposure x 1[t=2014]): `var_name'`suf'") ///
            mtitles("Continuous" "x Young" "x R1" "x HighPrePub" "x HighGrants")

        // base vs. + market-share spec, stored in fd_<yvar> matrix for matrix_to_txt
        qui reghdfe d_`yvar' d_treat,                absorb(year) vce(cluster athr_id)
        local b_b   = _b[d_treat]
        local b_se  = _se[d_treat]
        local b_N   = e(N)
        local b_r2  = e(r2)
        qui reghdfe d_`yvar' d_treat d_share_treat,  absorb(year) vce(cluster athr_id)
        local s_bx  = _b[d_treat]
        local s_sex = _se[d_treat]
        local s_bs  = _b[d_share_treat]
        local s_ses = _se[d_share_treat]
        local s_N   = e(N)
        local s_r2  = e(r2)
        cap mat drop fd_`yvar'
        mat fd_`yvar' = J(6,2,.)
        mat fd_`yvar'[1,1] = `b_b'
        mat fd_`yvar'[2,1] = `b_se'
        mat fd_`yvar'[5,1] = `b_N'
        mat fd_`yvar'[6,1] = `b_r2'
        mat fd_`yvar'[1,2] = `s_bx'
        mat fd_`yvar'[2,2] = `s_sex'
        mat fd_`yvar'[3,2] = `s_bs'
        mat fd_`yvar'[4,2] = `s_ses'
        mat fd_`yvar'[5,2] = `s_N'
        mat fd_`yvar'[6,2] = `s_r2'
        mat rownames fd_`yvar' = b_dtreat se_dtreat b_dshare se_dshare N r2
        mat colnames fd_`yvar' = base with_share

        binscatter d_`yvar' d_treat if year == 2014, n(30) ///
            xtitle("Exposure (year-2014 jump only)") ///
            ytitle("{&Delta} `var_name' (y_2014 - y_2013)") ///
            title("First Difference: `var_name'") msymbol(O) mcolor(ebblue)
        graph export ../output/figures/`samp'/fd_`yvar'`suf'.pdf, replace
    }
end

program pooled_did
    // pooled DiD: y_it = a_i + g_t + b*(exposure_i x post_t) + e_it
    // matches event-study sample/FE/cluster; gives a single post-period beta with SE.
    syntax, samp(string) [, r1r2(int 0) public(int 0)]
    local fes athr_id year
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"
    use ../temp/es_`samp'`suf', clear

    foreach v in cite_affl_wt ppr_cnt {
        cap gen ln_`v' = ln(1+`v')
    }

    gen post       = year >= 2014
    gen Z_it       = exposure              * post
    gen Z_share_it = mkt_spend_shr * post

    local outcomes cite_affl_wt ppr_cnt ln_cite_affl_wt ln_ppr_cnt body_adj_wt avg_num_coathrs num_grants

    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'

    cap mat drop results
    foreach yvar of local outcomes {
        qui sum `yvar' if year < 2014, d
        local pre_mean = r(mean)

        // base spec
        qui reghdfe `yvar' Z_it,            absorb(`fes') vce(cluster athr_id)
        local b_b   = _b[Z_it]
        local b_se  = _se[Z_it]
        local b_N   = e(N)
        local b_r2  = e(r2)

        // with shares
        qui reghdfe `yvar' Z_it Z_share_it, absorb(`fes') vce(cluster athr_id)
        local s_bx  = _b[Z_it]
        local s_sex = _se[Z_it]
        local s_bs  = _b[Z_share_it]
        local s_ses = _se[Z_share_it]
        local s_N   = e(N)
        local s_r2  = e(r2)

        di as text "pooled_did `samp'`suf' `yvar':  base b=" %7.4f `b_b' " se=" %7.4f `b_se' ///
            "    +share b=" %7.4f `s_bx' " se=" %7.4f `s_sex' ///
            "    share_b=" %7.4f `s_bs' " se=" %7.4f `s_ses' ///
            "    pre-mean=" %7.4f `pre_mean'

        cap mat drop pdid_`yvar'
        mat pdid_`yvar' = J(7,2,.)
        mat pdid_`yvar'[1,1] = `b_b'
        mat pdid_`yvar'[2,1] = `b_se'
        mat pdid_`yvar'[5,1] = `pre_mean'
        mat pdid_`yvar'[6,1] = `b_N'
        mat pdid_`yvar'[7,1] = `b_r2'
        mat pdid_`yvar'[1,2] = `s_bx'
        mat pdid_`yvar'[2,2] = `s_sex'
        mat pdid_`yvar'[3,2] = `s_bs'
        mat pdid_`yvar'[4,2] = `s_ses'
        mat pdid_`yvar'[5,2] = `pre_mean'
        mat pdid_`yvar'[6,2] = `s_N'
        mat pdid_`yvar'[7,2] = `s_r2'
        mat rownames pdid_`yvar' = b_exposure se_exposure b_share se_share pre_mean N r2
        mat colnames pdid_`yvar' = base with_share

        // accumulate one row per outcome for the summary dta
        mat row = `b_b', `b_se', `s_bx', `s_sex', `s_bs', `s_ses', `pre_mean'
        mat results = nullmat(results) \ row

        // Frisch-Waugh partial-regression binscatter: pooled DiD analog of ld plot
        local var_name "`yvar'"
        if "`yvar'" == "cite_affl_wt"    local var_name "Citation Weighted Output"
        if "`yvar'" == "ppr_cnt"         local var_name "Publication Count"
        if "`yvar'" == "ln_cite_affl_wt" local var_name "Log(1+Cite-Wtd Output)"
        if "`yvar'" == "ln_ppr_cnt"      local var_name "Log(1+Pub Count)"
        if "`yvar'" == "body_adj_wt"     local var_name "Body-Adj Weighted Output"
        if "`yvar'" == "avg_num_coathrs" local var_name "Avg Coauthors"
        if "`yvar'" == "num_grants"      local var_name "Num Grants"

        preserve
            qui reghdfe `yvar', absorb(`fes') residuals(_y_r)
            qui reghdfe Z_it,   absorb(`fes') residuals(_Z_r)
            local pd_b_str  : dis %7.3f `b_b'
            local pd_se_str : dis %7.3f `b_se'
            binscatter _y_r _Z_r, n(30) ///
                xtitle("Exposure x Post") ytitle("`var_name'") ///
                msymbol(O) mcolor(ebblue) ///
                note("{&beta} = `pd_b_str' (SE: `pd_se_str')") ///
                plotregion(margin(sides))
            graph export ../output/figures/`samp'/pdid_`yvar'`suf'.pdf, replace
        restore

        preserve
            qui reghdfe `yvar' Z_share_it, absorb(`fes') residuals(_y_r)
            qui reghdfe Z_it Z_share_it,   absorb(`fes') residuals(_Z_r)
            local pds_b_str  : dis %7.3f `s_bx'
            local pds_se_str : dis %7.3f `s_sex'
            binscatter _y_r _Z_r, n(30) ///
                xtitle("Exposure x Post") ytitle("`var_name'") ///
                msymbol(O) mcolor(ebblue) ///
                note("{&beta} = `pds_b_str' (SE: `pds_se_str')") ///
                plotregion(margin(sides))
            graph export ../output/figures/`samp'/pdid_`yvar'`suf'_mshrctrl.pdf, replace
        restore
    }

    // small dta with both specs per outcome for quoting in figure legends or text
    preserve
        clear
        svmat results
        rename (results1 results2 results3 results4 results5 results6 results7) ///
               (b_base se_base b_exp_wshr se_exp_wshr b_shr_wshr se_shr_wshr pre_mean)
        gen outcome = ""
        local i = 1
        foreach yvar of local outcomes {
            replace outcome = "`yvar'" if _n == `i'
            local ++i
        }
        order outcome b_base se_base b_exp_wshr se_exp_wshr b_shr_wshr se_shr_wshr pre_mean
        save ../temp/pooled_did_`samp'`suf', replace
        list, sep(0) noobs abbrev(20)
    restore
end

program ppml_specs
    // Poisson (ppmlhdfe) analogs of pooled_did, long_diff, first_diff.
    //   ppml_pdid: y_it on Z_it (+ Z_share_it), absorb(athr_id year)
    //   ppml_ld:   same but absorb(athr_id post)  -- collapses years into a
    //              single pre/post contrast, Poisson analog of the long diff
    //   ppml_fd:   y_it on d_treat (+ d_share_treat), absorb(athr_id year)
    //              d_treat = exposure * (post - L.post), nonzero only at t=2014
    // Skips ln_ outcomes; ppmlhdfe wrapped in cap noi (may drop separated obs
    // or fail to converge). Matrices ppml_<prog>_<yvar> have rows
    // [b_x, se_x, b_share, se_share, pre_mean, N, r2_p] and cols [base, with_share].
    syntax, samp(string) [, r1r2(int 0) public(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"
    use ../temp/es_`samp'`suf', clear

    gen post = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post
    xtset athr year
    gen d_treat       = exposure      * (post - L.post)
    gen d_share_treat = mkt_spend_shr * (post - L.post)
    replace d_treat       = 0 if mi(d_treat)
    replace d_share_treat = 0 if mi(d_share_treat)

    local outcomes cite_affl_wt ppr_cnt affl_wt body_adj_wt avg_num_coathrs num_grants

    foreach yvar of local outcomes {
        qui sum `yvar' if year < 2014, d
        local pre_mean = r(mean)

        // === ppml_pdid: athr + year FE ===
        local b_b = .
        local b_se = .
        local b_N = .
        local b_r2 = .
        local s_bx = .
        local s_sex = .
        local s_bs = .
        local s_ses = .
        local s_N = .
        local s_r2 = .
        cap noi ppmlhdfe `yvar' Z_it,            absorb(athr_id year) vce(cluster athr_id)
        if _rc == 0 {
            local b_b  = _b[Z_it]
            local b_se = _se[Z_it]
            local b_N  = e(N)
            local b_r2 = e(r2_p)
        }
        else di as error "ppml_pdid `yvar' base failed (rc=`_rc')"
        cap noi ppmlhdfe `yvar' Z_it Z_share_it, absorb(athr_id year) vce(cluster athr_id)
        if _rc == 0 {
            local s_bx  = _b[Z_it]
            local s_sex = _se[Z_it]
            local s_bs  = _b[Z_share_it]
            local s_ses = _se[Z_share_it]
            local s_N   = e(N)
            local s_r2  = e(r2_p)
        }
        else di as error "ppml_pdid `yvar' +share failed (rc=`_rc')"
        cap mat drop ppml_pdid_`yvar'
        mat ppml_pdid_`yvar' = J(7,2,.)
        mat ppml_pdid_`yvar'[1,1] = `b_b'
        mat ppml_pdid_`yvar'[2,1] = `b_se'
        mat ppml_pdid_`yvar'[5,1] = `pre_mean'
        mat ppml_pdid_`yvar'[6,1] = `b_N'
        mat ppml_pdid_`yvar'[7,1] = `b_r2'
        mat ppml_pdid_`yvar'[1,2] = `s_bx'
        mat ppml_pdid_`yvar'[2,2] = `s_sex'
        mat ppml_pdid_`yvar'[3,2] = `s_bs'
        mat ppml_pdid_`yvar'[4,2] = `s_ses'
        mat ppml_pdid_`yvar'[5,2] = `pre_mean'
        mat ppml_pdid_`yvar'[6,2] = `s_N'
        mat ppml_pdid_`yvar'[7,2] = `s_r2'
        mat rownames ppml_pdid_`yvar' = b_exposure se_exposure b_share se_share pre_mean N r2_p
        mat colnames ppml_pdid_`yvar' = base with_share

        // === ppml_ld: athr + post FE (binary pre/post) ===
        local b_b = .
        local b_se = .
        local b_N = .
        local b_r2 = .
        local s_bx = .
        local s_sex = .
        local s_bs = .
        local s_ses = .
        local s_N = .
        local s_r2 = .
        cap noi ppmlhdfe `yvar' Z_it,            absorb(athr_id post) vce(cluster athr_id)
        if _rc == 0 {
            local b_b  = _b[Z_it]
            local b_se = _se[Z_it]
            local b_N  = e(N)
            local b_r2 = e(r2_p)
        }
        else di as error "ppml_ld `yvar' base failed (rc=`_rc')"
        cap noi ppmlhdfe `yvar' Z_it Z_share_it, absorb(athr_id post) vce(cluster athr_id)
        if _rc == 0 {
            local s_bx  = _b[Z_it]
            local s_sex = _se[Z_it]
            local s_bs  = _b[Z_share_it]
            local s_ses = _se[Z_share_it]
            local s_N   = e(N)
            local s_r2  = e(r2_p)
        }
        else di as error "ppml_ld `yvar' +share failed (rc=`_rc')"
        cap mat drop ppml_ld_`yvar'
        mat ppml_ld_`yvar' = J(7,2,.)
        mat ppml_ld_`yvar'[1,1] = `b_b'
        mat ppml_ld_`yvar'[2,1] = `b_se'
        mat ppml_ld_`yvar'[5,1] = `pre_mean'
        mat ppml_ld_`yvar'[6,1] = `b_N'
        mat ppml_ld_`yvar'[7,1] = `b_r2'
        mat ppml_ld_`yvar'[1,2] = `s_bx'
        mat ppml_ld_`yvar'[2,2] = `s_sex'
        mat ppml_ld_`yvar'[3,2] = `s_bs'
        mat ppml_ld_`yvar'[4,2] = `s_ses'
        mat ppml_ld_`yvar'[5,2] = `pre_mean'
        mat ppml_ld_`yvar'[6,2] = `s_N'
        mat ppml_ld_`yvar'[7,2] = `s_r2'
        mat rownames ppml_ld_`yvar' = b_exposure se_exposure b_share se_share pre_mean N r2_p
        mat colnames ppml_ld_`yvar' = base with_share

        // === ppml_fd: athr + year FE, d_treat = exposure * 1[t=2014] ===
        local b_b = .
        local b_se = .
        local b_N = .
        local b_r2 = .
        local s_bx = .
        local s_sex = .
        local s_bs = .
        local s_ses = .
        local s_N = .
        local s_r2 = .
        cap noi ppmlhdfe `yvar' d_treat,                absorb(athr_id year) vce(cluster athr_id)
        if _rc == 0 {
            local b_b  = _b[d_treat]
            local b_se = _se[d_treat]
            local b_N  = e(N)
            local b_r2 = e(r2_p)
        }
        else di as error "ppml_fd `yvar' base failed (rc=`_rc')"
        cap noi ppmlhdfe `yvar' d_treat d_share_treat,  absorb(athr_id year) vce(cluster athr_id)
        if _rc == 0 {
            local s_bx  = _b[d_treat]
            local s_sex = _se[d_treat]
            local s_bs  = _b[d_share_treat]
            local s_ses = _se[d_share_treat]
            local s_N   = e(N)
            local s_r2  = e(r2_p)
        }
        else di as error "ppml_fd `yvar' +share failed (rc=`_rc')"
        cap mat drop ppml_fd_`yvar'
        mat ppml_fd_`yvar' = J(7,2,.)
        mat ppml_fd_`yvar'[1,1] = `b_b'
        mat ppml_fd_`yvar'[2,1] = `b_se'
        mat ppml_fd_`yvar'[5,1] = `pre_mean'
        mat ppml_fd_`yvar'[6,1] = `b_N'
        mat ppml_fd_`yvar'[7,1] = `b_r2'
        mat ppml_fd_`yvar'[1,2] = `s_bx'
        mat ppml_fd_`yvar'[2,2] = `s_sex'
        mat ppml_fd_`yvar'[3,2] = `s_bs'
        mat ppml_fd_`yvar'[4,2] = `s_ses'
        mat ppml_fd_`yvar'[5,2] = `pre_mean'
        mat ppml_fd_`yvar'[6,2] = `s_N'
        mat ppml_fd_`yvar'[7,2] = `s_r2'
        mat rownames ppml_fd_`yvar' = b_dtreat se_dtreat b_dshare se_dshare pre_mean N r2_p
        mat colnames ppml_fd_`yvar' = base with_share

        di as text "ppml_specs `samp'`suf' `yvar': pdid b=" %7.4f `b_b' ///
            "  ld b=" %7.4f ppml_ld_`yvar'[1,1] ///
            "  fd b=" %7.4f ppml_fd_`yvar'[1,1] ///
            "  pre_mean=" %7.4f `pre_mean'
    }
end

program joint_outcome_test
    // Log version. Stacked DiD that estimates beta on ln(1+ppr_cnt) and
    // beta on ln(1+cite_affl_wt) jointly, then Wald-tests
    // H0: beta_ln_ppr = beta_ln_cite. Equality says exposure shifts log paper
    // count and log cite-weighted output by the same proportional amount;
    // rejecting points to an impact tilt in the forgone papers.
    syntax, samp(string) [, r1r2(int 0) public(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"
    use ../temp/es_`samp'`suf', clear

    foreach v in cite_affl_wt ppr_cnt {
        cap gen ln_`v' = ln(1+`v')
    }

    gen post = year >= 2014
    gen Z_it = exposure * post

    keep athr_id year Z_it ln_ppr_cnt ln_cite_affl_wt

    // Stack: outcome == 0 -> log raw count; outcome == 1 -> log cite-weighted
    preserve
        gen outcome = 1
        gen y = ln_cite_affl_wt
        keep athr_id year Z_it outcome y
        save ../temp/stack_cite_`samp'`suf', replace
    restore
    gen outcome = 0
    gen y = ln_ppr_cnt
    keep athr_id year Z_it outcome y
    append using ../temp/stack_cite_`samp'`suf'

    // Outcome-specific FEs so each outcome has its own level & year trend
    egen athr_outcome = group(athr_id outcome)
    egen year_outcome = group(year outcome)
    gen Z_it_cite = Z_it * (outcome == 1)

    // Cluster on athr_id: each PI appears in both outcomes
    reghdfe y Z_it Z_it_cite, absorb(athr_outcome year_outcome) vce(cluster athr_id)

    local b_ppr   = _b[Z_it]
    local se_ppr  = _se[Z_it]
    local b_diff  = _b[Z_it_cite]
    local se_diff = _se[Z_it_cite]
    qui lincom Z_it + Z_it_cite
    local b_cite  = r(estimate)
    local se_cite = r(se)

    qui test Z_it_cite
    local F_w = r(F)
    local p_w = r(p)

    di as text "joint outcome test `samp'`suf':  H0 beta_ln_ppr_cnt = beta_ln_cite_affl_wt"
    di as text "  beta_ln_ppr_cnt      = " %9.4f `b_ppr'  "   SE = " %9.4f `se_ppr'
    di as text "  beta_ln_cite_affl_wt = " %9.4f `b_cite' "   SE = " %9.4f `se_cite'
    di as text "  diff (ln_cite - ln_ppr) = " %9.4f `b_diff' "   SE = " %9.4f `se_diff'
    di as text "  Wald F = " %9.4f `F_w' "   p = " %9.4f `p_w'

    cap mat drop joint_`samp'`suf'
    mat joint_`samp'`suf' = J(8,1,.)
    mat joint_`samp'`suf'[1,1] = `b_ppr'
    mat joint_`samp'`suf'[2,1] = `se_ppr'
    mat joint_`samp'`suf'[3,1] = `b_cite'
    mat joint_`samp'`suf'[4,1] = `se_cite'
    mat joint_`samp'`suf'[5,1] = `b_diff'
    mat joint_`samp'`suf'[6,1] = `se_diff'
    mat joint_`samp'`suf'[7,1] = `F_w'
    mat joint_`samp'`suf'[8,1] = `p_w'
    mat rownames joint_`samp'`suf' = b_ppr se_ppr b_cite se_cite b_diff se_diff Wald_F p_value
    mat colnames joint_`samp'`suf' = stacked

    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'
    qui matrix_to_txt, saving("../output/tables/`samp'/joint_outcome_test`suf'.txt") ///
        matrix(joint_`samp'`suf') title(<tab:joint_outcome_test`suf'>) format(%20.4f) replace
end

program joint_sample_test
    // Stacked DiD across the all_jrnls and top_jrnls samples (same outcome:
    // ppr_cnt) so we get the joint covariance of beta_all and beta_top and
    // can Wald-test H0: beta_all = beta_top. Rejecting => the paper-count
    // response in top-tier outlets differs from the response measured across
    // all outlets, i.e. the cut is not tier-uniform.
    syntax, [r1r2(int 0) public(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"

    cap confirm file ../temp/es_all_jrnls`suf'.dta
    if _rc {
        di as error "joint_sample_test: ../temp/es_all_jrnls`suf'.dta missing; skipping."
        exit
    }
    cap confirm file ../temp/es_top_jrnls`suf'.dta
    if _rc {
        di as error "joint_sample_test: ../temp/es_top_jrnls`suf'.dta missing; skipping."
        exit
    }

    use ../temp/es_all_jrnls`suf', clear
    keep athr_id year exposure ppr_cnt
    rename ppr_cnt y
    gen sample = 0     // all_jrnls
    save ../temp/stack_all_jrnls`suf', replace

    use ../temp/es_top_jrnls`suf', clear
    keep athr_id year exposure ppr_cnt
    rename ppr_cnt y
    gen sample = 1     // top_jrnls
    append using ../temp/stack_all_jrnls`suf'

    gen post = year >= 2014
    gen Z_it     = exposure * post
    gen Z_it_top = Z_it * (sample == 1)

    egen athr_sample = group(athr_id sample)
    egen year_sample = group(year sample)

    // Cluster on athr_id so PIs that appear in both samples are not treated
    // as independent across rows.
    reghdfe y Z_it Z_it_top, absorb(athr_sample year_sample) vce(cluster athr_id)

    local b_all   = _b[Z_it]
    local se_all  = _se[Z_it]
    local b_diff  = _b[Z_it_top]
    local se_diff = _se[Z_it_top]
    qui lincom Z_it + Z_it_top
    local b_top   = r(estimate)
    local se_top  = r(se)

    qui test Z_it_top
    local F_w = r(F)
    local p_w = r(p)

    di as text "joint sample test `suf':  H0 beta_all_jrnls = beta_top_jrnls (ppr_cnt)"
    di as text "  beta_all_jrnls   = " %9.4f `b_all'  "   SE = " %9.4f `se_all'
    di as text "  beta_top_jrnls   = " %9.4f `b_top'  "   SE = " %9.4f `se_top'
    di as text "  diff (top - all) = " %9.4f `b_diff' "   SE = " %9.4f `se_diff'
    di as text "  Wald F = " %9.4f `F_w' "   p = " %9.4f `p_w'

    cap mat drop joint_sample`suf'
    mat joint_sample`suf' = J(8,1,.)
    mat joint_sample`suf'[1,1] = `b_all'
    mat joint_sample`suf'[2,1] = `se_all'
    mat joint_sample`suf'[3,1] = `b_top'
    mat joint_sample`suf'[4,1] = `se_top'
    mat joint_sample`suf'[5,1] = `b_diff'
    mat joint_sample`suf'[6,1] = `se_diff'
    mat joint_sample`suf'[7,1] = `F_w'
    mat joint_sample`suf'[8,1] = `p_w'
    mat rownames joint_sample`suf' = b_all se_all b_top se_top b_diff se_diff Wald_F p_value
    mat colnames joint_sample`suf' = stacked

    cap mkdir ../output/tables
    qui matrix_to_txt, saving("../output/tables/joint_sample_test`suf'.txt") ///
        matrix(joint_sample`suf') title(<tab:joint_sample_test`suf'>) format(%20.4f) replace
end

program confidence_strat_did
    // Pooled DiD split by imputation-confidence quartile (max_sim to nearest
    // FOIA PI in the TF-IDF space). The identifying claim of the imputation
    // is that universe authors with HIGHER max_sim get more reliable
    // imputed exposure -> the DiD coefficient should be largest (in absolute
    // value) and most precise for the top quartile, decay toward the bottom
    // quartile, and become indistinguishable from zero for the lowest-
    // confidence authors. If beta_Q1 ~ beta_Q4 the result is not driven by
    // exposure; it's a field/cluster confounder loading through the match
    // weights.
    syntax, samp(string) [, r1r2(int 0) public(int 0)]
    local fes athr_id year
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"

    cap confirm file ../temp/diag.dta
    if _rc {
        di as error "confidence_strat_did: ../temp/diag.dta missing; skipping."
        exit
    }

    use ../temp/es_`samp'`suf', clear
    merge m:1 athr_id using ../temp/diag, keep(1 3) nogen

    foreach v in cite_affl_wt ppr_cnt {
        cap gen ln_`v' = ln(1+`v')
    }

    gen post = year >= 2014
    gen Z_it = exposure * post

    // Build quartile cut-points among one-row-per-author NON-FOIA universe
    // (FOIA PIs' exposure is observed, not imputed, so they get their own
    // bucket Q5). The cut-points are computed on the imputed pool only so
    // they reflect the distribution of match quality among the authors we
    // actually impute for.
    qui sum max_sim if athr_indicator == 1 & foia_athr != 1, d
    local c25 = r(p25)
    local c50 = r(p50)
    local c75 = r(p75)
    di as text "confidence_strat_did `samp'`suf' max_sim cuts: " ///
        "p25=`c25' p50=`c50' p75=`c75'"

    gen conf_q = .
    replace conf_q = 1 if max_sim <  `c25' & foia_athr != 1 & !mi(max_sim)
    replace conf_q = 2 if inrange(max_sim, `c25', `c50') & foia_athr != 1
    replace conf_q = 3 if inrange(max_sim, `c50', `c75') & foia_athr != 1
    replace conf_q = 4 if max_sim >= `c75' & foia_athr != 1 & !mi(max_sim)
    replace conf_q = 5 if foia_athr == 1   // observed (FOIA PIs)
    forval q = 1/5 {
        gen Z_q`q' = Z_it * (conf_q == `q')
    }

    local outcomes cite_affl_wt ppr_cnt ln_cite_affl_wt ln_ppr_cnt body_adj_wt avg_num_coathrs num_grants

    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'

    // count PIs per quartile (one row per author) for the legend
    forval q = 1/5 {
        qui gunique athr_id if conf_q == `q'
        local n_q`q' = r(unique)
    }

    eststo clear
    local model_names ""
    foreach yvar of local outcomes {
        eststo m_`yvar': reghdfe `yvar' Z_q1 Z_q2 Z_q3 Z_q4 Z_q5, ///
                                  absorb(`fes') vce(cluster athr_id)
        local model_names "`model_names' m_`yvar'"
        forval q = 1/5 {
            local b  = _b[Z_q`q']
            local se = _se[Z_q`q']
            di as text "  `yvar' Q`q' (N=`n_q`q''): " ///
                "b=" %9.4f `b' "  se=" %9.4f `se'
            mat row = `b', `se'
            mat results_`yvar' = nullmat(results_`yvar') \ row
        }
    }

    esttab `model_names' using ../output/tables/`samp'/conf_strat_did`suf'.tex, ///
        replace label se keep(Z_q1 Z_q2 Z_q3 Z_q4 Z_q5) ///
        coeflabels(Z_q1 "Q1 lowest conf" Z_q2 "Q2" Z_q3 "Q3" ///
                   Z_q4 "Q4 highest conf" Z_q5 "FOIA observed") ///
        title("Pooled DiD by imputation-confidence quartile (max cosine to nearest FOIA PI)") ///
        mtitles(`outcomes')

    foreach yvar in ppr_cnt cite_affl_wt {
        if "`yvar'" == "ppr_cnt"      local var_name "Publication Count"
        if "`yvar'" == "cite_affl_wt" local var_name "Citation Weighted Output"

        preserve
        clear
        svmat results_`yvar'
        rename (results_`yvar'1 results_`yvar'2) (b se)
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        gen q = _n
        tw rcap ub lb q, lcolor(ebblue%70) msize(small) || ///
           scatter b q, mcolor(ebblue) msize(medium) ///
           , xlab(1 "Q1 (N=`n_q1')" 2 "Q2 (N=`n_q2')" 3 "Q3 (N=`n_q3')" ///
                  4 "Q4 (N=`n_q4')" 5 "FOIA (N=`n_q5')", labsize(small)) ///
             xtitle("Imputation confidence (max cosine to nearest FOIA PI)") ///
             ytitle("`var_name': {&beta} on Exposure x Post") ///
             yline(0, lcolor(gs10) lpattern(solid)) legend(off) ///
             plotregion(margin(sides))
        graph export ../output/figures/`samp'/conf_strat_`yvar'`suf'.pdf, replace
        restore
    }
end

program combine_es_graphs
    syntax, samp(str)
    foreach yvar in cite_affl_wt ppr_cnt ln_cite_affl_wt ln_ppr_cnt body_adj_wt avg_num_coathrs {
        if "`yvar'" == "cite_affl_wt" local var_name = "Citation Weighted Output" 
        if "`yvar'" == "cite_affl_wt" local gap  1 
        if "`yvar'" == "ppr_cnt" local var_name = "Publication Count"
        if "`yvar'" == "ppr_cnt" local gap 0.5
        if "`yvar'" == "ppr_cnt"      & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "cite_affl_wt" & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "avg_coathrs" local var_name = "Average Team Size"
        if "`yvar'" == "acg_coathrs" local gap 0.5
         if "`yvar'" == "cite_affl_wt" local var_name = "Citation Weighted Output"
        use "../temp/es_`yvar'_q1", replace                                         
        gen group = "q1"                                                                             
        replace rel = rel - 0.4                                                                         
        sum b if group == "q1" & rel > 0                                                             
        local q1_mean : dis %4.3f r(mean)                                                            
        append using ../temp/es_`yvar'_q2
        replace group = "q2" if mi(group)                                                            
        replace rel = rel - 0.25 if group == "q2"                                                                         
        sum b if group == "q2" & rel > 0                                                             
        local q2_mean : dis %4.3f r(mean)                                                            
        append using ../temp/es_`yvar'_q3
        replace group = "q3" if mi(group)                                                            
        replace rel = rel - 0.1 if group == "q3"                                                                         
        sum b if group == "q3" & rel > 0                                                             
        local q3_mean : dis %4.3f r(mean)                                                            
        append using ../temp/es_`yvar'_q4
        replace group = "q4" if mi(group)
        replace rel = rel + 0.05 if group == "q4"                                                                         
        sum b if group == "q4" & rel > 0
        local q4_mean : dis %4.3f r(mean)
        cap drop year
        gen year = rel + 2014
        tw rcap ub lb year if year != 2012.6  & group == "q1",  lcolor(lavender%70) msize(small) || ///
           scatter b year if group == "q1", mcolor(lavender%70) msize(small) || ///
           rcap ub lb year if year != 2012.75 & group == "q2",  lcolor(orange%70) msize(small) || ///
           scatter b year if group == "q2", mcolor(orange%70) msymbol(smdiamond) msize(small) ||  ///
           rcap ub lb year if year != 2012.9  & group == "q3",  lcolor(dkgreen%70) msize(small) || ///
           scatter b year if group == "q3", mcolor(green%70) msymbol(smdiamond) msize(small)|| ///
           rcap ub lb year if year != 2013.05 & group == "q4",  lcolor(cranberry%70) msize(small) || ///
           scatter b year if group == "q4", mcolor(red%70) msymbol(smdiamond) msize(small)  ///
           xlab(2010(1)2019) ylab(#8) ///
              yline(0, lcolor(black) lpattern(solid)) ///
              legend(on order(2 "Q1 Exposed (Post Period Avg: `q1_mean')" 4 "Q2 Exposed (Post Period Avg: `q2_mean')" 6 "Q3 Exposed (Post Period Avg: `q3_mean')" 8 "Q4 Exposed (Post Period Avg: `q4_mean')") pos(7) ring(1) size(small) region(fcolor(none))) xtitle("Year") ytitle("`var_name'") plotregion(margin(sides))
        graph export ../output/figures/`samp'/es_`yvar'_split`suf'_`samp'.pdf, replace     

        use "../temp/es_`yvar'_r1_r2_public_below_median", replace                                         
        gen group = "below"                                                                             
        replace rel = rel - 0.1                                                                         
        sum b if group == "below" & rel > 0                                                             
        local below_mean : dis %4.3f r(mean)                                                            
        append using ../temp/es_`yvar'_r1_r2_public_above_median
        replace group = "above" if mi(group)                                                            
        sum b if group == "above" & rel > 0
        local above_mean : dis %4.3f r(mean)
        cap drop year
        gen year = rel + 2014
        tw rcap ub lb year if year != 2012.9 & group == "below",  lcolor(lavender%60) msize(small) || ///
           scatter b year if group == "below", mcolor(lavender%60) msize(small) || ///
           rcap ub lb year if year != 2013   & group == "above",  lcolor(dkorange) msize(small) || ///
           scatter b year if group == "above", mcolor(dkorange) msymbol(smdiamond) msize(small)  ///
           xlab(2010(1)2019) ylab(#8) ///
              yline(0, lcolor(black) lpattern(solid)) ///
              legend(on order(2 "Below Median Exposure (Post Period Avg: `below_mean')" 4 "Above Median Exposure (Post Period Avg: `above_mean')" ) pos(7) ring(1) size(small) region(fcolor(none))) xtitle("Year") ytitle("`var_name'") plotregion(margin(sides))
        graph export ../output/figures/`samp'/es_`yvar'_split`suf'_`samp'.pdf, replace     
        
        use "../temp/es_`yvar'_r1_r2_public_young", replace                                         
        gen group = "young"                                                                             
        replace rel = rel - 0.1                                                                         
        sum b if group == "young" & rel > 0                                                             
        local young_mean : dis %4.3f r(mean)                                                            
        append using ../temp/es_`yvar'_r1_r2_public_old
        replace group = "old" if mi(group)                                                            

        sum b if group == "old" & rel > 0
        local old_mean : dis %4.3f r(mean)
        cap drop year
        gen year = rel + 2014
        tw rcap ub lb year if year != 2012.9 & group == "young",  lcolor(lavender%60) msize(small) || ///
           scatter b year if group == "young", mcolor(lavender%60) msize(small) || ///
           rcap ub lb year if year != 2013   & group == "old",  lcolor(dkorange) msize(small) || ///
           scatter b year if group == "old", mcolor(dkorange) msymbol(smdiamond) msize(small)  ///
           xlab(2010(1)2019) ylab(#8) ///
              yline(0, lcolor(black) lpattern(solid)) ///
              legend(on order(2 "Below Median Age (Post Period Avg: `young_mean')" 4 "Above Median Age (Post Period Avg: `old_mean')" ) pos(7) ring(1) size(small) region(fcolor(none))) xtitle("Year") ytitle("`var_name'") plotregion(margin(sides))
        graph export ../output/figures/`samp'/es_`yvar'_age_split`suf'_`samp'.pdf, replace     
    }
end

program robustness
    syntax, samp(string) [, r1r2(int 0) public(int 0)]
    local fes athr_id year
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"
    cap mkdir "../output/figures/`samp'/robustness"
    cap mkdir "../output/tables"
    cap mkdir "../output/tables/`samp'"
    cap mkdir "../output/tables/`samp'/robustness"

    // (1) raw mean trajectories by pre-period group — no FE, no treatment
    foreach split in pre_ppr grants {
        if "`split'" == "pre_ppr" {
            local hi high_pre_ppr
            local lab_hi "High Pre-Pub"
            local lab_lo "Low Pre-Pub"
        }
        else {
            local hi high_grants
            local lab_hi "High Pre-Grants"
            local lab_lo "Low Pre-Grants"
        }
        use ../temp/es_`samp'`suf', clear
        preserve
            gcollapse (mean) ppr_cnt cite_affl_wt body_adj_wt avg_num_coathrs num_grants, by(year `hi')
            foreach var in ppr_cnt cite_affl_wt body_adj_wt avg_num_coathrs num_grants {
                tw line `var' year if `hi' == 1, lcolor(cranberry) lwidth(medium) || ///
                   line `var' year if `hi' == 0, lcolor(ebblue)    lwidth(medium) ///
                   , legend(on order(1 "`lab_hi'" 2 "`lab_lo'") pos(7) ring(0) size(small)) ///
                     xtitle("Year") ytitle("`var'") xline(2014, lpattern(dash) lcolor(gs10)) ///
                     plotregion(margin(sides))
                graph export ../output/figures/`samp'/robustness/raw_`var'_by_`split'`suf'.pdf, replace
            }
        restore
    }

    // (2) raw mean trajectories by exposure quartile WITHIN each pre-period group
    foreach grp in high_pre_ppr low_pre_ppr high_grants low_grants {
        preserve
            keep if `grp' == 1
            gen qrtl = 1*q1 + 2*q2 + 3*q3 + 4*q4
            gcollapse (mean) ppr_cnt cite_affl_wt, by(year qrtl)
            foreach var in ppr_cnt cite_affl_wt {
                tw line `var' year if qrtl == 1, lcolor(lavender)  || ///
                   line `var' year if qrtl == 2, lcolor(dkorange)  || ///
                   line `var' year if qrtl == 3, lcolor(ebblue)    || ///
                   line `var' year if qrtl == 4, lcolor(dkemerald) ///
                   , legend(on order(1 "Q1" 2 "Q2" 3 "Q3" 4 "Q4") pos(7) ring(0) size(small)) ///
                     xtitle("Year") ytitle("`var'") xline(2014, lpattern(dash) lcolor(gs10)) ///
                     plotregion(margin(sides))
                graph export ../output/figures/`samp'/robustness/raw_`var'_by_qrtl_`grp'`suf'.pdf, replace
            }
        restore
    }

    // (3) is exposure correlated with age within each pre-period group?
    use ../temp/es_`samp'`suf', clear
    preserve
        bys athr_id: keep if _n == 1
        eststo clear
        eststo all  : reg exposure age_2014, vce(robust)
        eststo highp: reg exposure age_2014 if high_pre_ppr == 1, vce(robust)
        eststo lowp : reg exposure age_2014 if low_pre_ppr  == 1, vce(robust)
        eststo highg: reg exposure age_2014 if high_grants  == 1, vce(robust)
        eststo lowg : reg exposure age_2014 if low_grants   == 1, vce(robust)
        esttab all highp lowp highg lowg using ../output/tables/`samp'/robustness/exposure_age_corr`suf'.tex, ///
            replace label se r2 ///
            title("Exposure on Age (2014) by pre-period group") ///
            mtitles("All" "High Pre-Pub" "Low Pre-Pub" "High Pre-Grants" "Low Pre-Grants")
    restore

    // (4) high/low pre-period event study WITH c.age_2014 # i.year controls
    use ../temp/es_`samp'`suf', clear
    cap drop rel int_lead* int_lag*
    gen rel = year - 2014
    qui sum rel
    local abs_lag  = abs(r(max))
    local abs_lead = abs(r(min))
    forval i = 1/`abs_lead' {
        gen int_lead`i' = exposure if rel == -`i'
    }
    forval i = 1/`abs_lag' {
        gen int_lag`i'  = exposure if rel == `i'
    }
    gen int_lag0 = exposure if rel == 0
    ds int_lead* int_lag*
    foreach var in `r(varlist)' {
        replace `var' = 0 if mi(`var')
    }
    local int_leads
    local int_lags
    forval i = 2/`abs_lead' {
        local int_leads int_lead`i' `int_leads'
    }
    forval i = 0/`abs_lag' {
        local int_lags `int_lags' int_lag`i'
    }
    foreach grp in high_pre_ppr low_pre_ppr high_grants low_grants {
        foreach v of local int_leads {
            gen `v'_`grp' = `v' * `grp'
        }
        foreach v of local int_lags {
            gen `v'_`grp' = `v' * `grp'
        }
        gen int_lead1_`grp' = int_lead1 * `grp'
        local leads_`grp'
        local lags_`grp'
        foreach v of local int_leads {
            local leads_`grp' `leads_`grp'' `v'_`grp'
        }
        foreach v of local int_lags {
            local lags_`grp' `lags_`grp'' `v'_`grp'
        }
    }
    save ../temp/robust_es_`samp'`suf', replace

    foreach yvar in ppr_cnt cite_affl_wt {
        if "`yvar'" == "ppr_cnt"      local var_name "Publication Count"
        if "`yvar'" == "cite_affl_wt" local var_name "Citation Weighted Output"
        if "`yvar'" == "ppr_cnt"      local gap 0.5
        if "`yvar'" == "cite_affl_wt" local gap 1
        if "`yvar'" == "ppr_cnt"      & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "cite_affl_wt" & "`samp'" == "top_jrnls" local gap 2

        foreach split in pre_ppr grants {
            if "`split'" == "pre_ppr" {
                local hi high_pre_ppr
                local lo low_pre_ppr
            }
            else {
                local hi high_grants
                local lo low_grants
            }
            use ../temp/robust_es_`samp'`suf', clear
            reghdfe `yvar' `leads_`hi'' `lags_`hi'' ///
                           `leads_`lo''  `lags_`lo'' ///
                           int_lead1_`hi' int_lead1_`lo' ///
                           c.age_2014#i.year, ///
                           absorb(`fes') vce(cluster athr_id)
            foreach grp in `hi' `lo' {
                local ref_b = _b[int_lead1_`grp']
                di as text "robustness (4) `yvar' `grp': ref _b[int_lead1_`grp'] = `ref_b' (should be 0 if Stata dropped the reference)"
                preserve
                mat drop _all
                foreach var in `leads_`grp'' `lags_`grp'' int_lead1_`grp' {
                    mat row = _b[`var'] - `ref_b', _se[`var']
                    if "`var'" == "int_lead1_`grp'" mat row = 0,0
                    mat es = nullmat(es) \ row
                }
                svmat es
                keep es1 es2
                drop if mi(es1)
                rename (es1 es2) (b se)
                gen ub = b + 1.96*se
                gen lb = b - 1.96*se
                gen rel = -4 if _n == 1
                replace rel = rel[_n-1]+1 if _n > 1
                replace rel = rel + 1 if rel >= -1
                replace rel = -1 if rel == `abs_lag' + 1
                gen year = rel + 2014
                hashsort rel
                sum ub, d
                local ymax = round(r(max),`gap')
                sum lb, d
                local ymin = round(r(min),`gap')
                tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
                  scatter b year, mcolor(ebblue) ///
                  , xlab(2010(1)2019) xtitle("Year") ytitle("`var_name'") ///
                    ylab(`ymin'(`gap')`ymax') yline(0, lcolor(gs10) lpattern(solid)) ///
                    title("With age x year controls: `grp'", size(small)) ///
                    legend(off) plotregion(margin(sides))
                graph export ../output/figures/`samp'/robustness/es_`yvar'_ageCtrl_`grp'`suf'.pdf, replace
                restore
            }
        }
    }

    // (5) high/low pre-period event study on UNBALANCED panel (no tsfill)
    use ../external/samp/athr_panel_full_year_last_`samp'`suf', clear
    bys athr_id: egen tot_pprs = total(ppr_cnt)
    keep if tot_pprs >= 10
    drop tot_pprs
    bys athr_id: egen max_year = max(year)
    keep if max_year >= 2014
    keep if inrange(year, 2010, 2019)
    bys athr_id: egen min_year = min(year)
    keep if min_year < 2013
    merge m:1 athr_id using ../temp/exposure, assert(1 2 3) keep(3) nogen
    merge m:1 athr_id using ../external/real_exposure/athr_exposure, assert(1 2 3) keep(1 3) nogen
    replace imputed = exposure if !mi(exposure)
    drop if exposure <= 0
    drop if imputed <= 0
    drop exposure
    rename imputed exposure
    bys athr_id: gen num_yrs = _N
    bys athr_id inst_id: gen plc_cntr = _n == 1
    bys athr_id : egen num_place = total(plc_cntr)
    keep if num_yrs > 1
    keep if num_place == 1
    drop if exposure <= 0
    bys athr_id: egen tot_pprs2 = total(ppr_cnt)
    drop if tot_pprs2 < 5
    drop tot_pprs2
    gen age_2014 = 2014 - min_year + 30
    gen pre_ppr_cnt = ppr_cnt if year < 2014
    bys athr_id: egen pre_ppr_cnt_sum = total(pre_ppr_cnt)
    qui sum pre_ppr_cnt_sum, d
    gen high_pre_ppr = pre_ppr_cnt_sum >= r(p75)
    gen low_pre_ppr  = pre_ppr_cnt_sum <  r(p75)
    merge 1:1 athr_id year using ../temp/athr_yr_grnt_cnt, keep(1 3) assert(1 2 3) nogen
    replace num_grants = 0 if mi(num_grants)
    gen pre_grants_cnt = num_grants if year < 2014
    bys athr_id: egen pre_grants_sum = total(pre_grants_cnt)
    drop pre_grants_cnt
    bys athr_id: gen athr_indicator2 = _n == 1
    qui sum pre_grants_sum if athr_indicator2 == 1, d
    local g_cut = r(p50)
    if `g_cut' <= 0 local g_cut = 0.5
    di as text "robustness (5) `samp'`suf' unbal pre-grant median = `g_cut'"
    gen high_grants = pre_grants_sum >= `g_cut'
    gen low_grants  = pre_grants_sum <  `g_cut'
    drop athr_indicator2
    gen rel = year - 2014
    qui sum rel
    local abs_lag  = abs(r(max))
    local abs_lead = abs(r(min))
    forval i = 1/`abs_lead' {
        gen int_lead`i' = exposure if rel == -`i'
        replace int_lead`i' = 0 if mi(int_lead`i')
    }
    forval i = 1/`abs_lag' {
        gen int_lag`i'  = exposure if rel == `i'
        replace int_lag`i' = 0 if mi(int_lag`i')
    }
    gen int_lag0 = exposure if rel == 0
    replace int_lag0 = 0 if mi(int_lag0)
    local int_leads
    local int_lags
    forval i = 2/`abs_lead' {
        local int_leads int_lead`i' `int_leads'
    }
    forval i = 0/`abs_lag' {
        local int_lags `int_lags' int_lag`i'
    }
    foreach grp in high_pre_ppr low_pre_ppr high_grants low_grants {
        foreach v of local int_leads {
            gen `v'_`grp' = `v' * `grp'
        }
        foreach v of local int_lags {
            gen `v'_`grp' = `v' * `grp'
        }
        gen int_lead1_`grp' = int_lead1 * `grp'
        local leads_`grp'
        local lags_`grp'
        foreach v of local int_leads {
            local leads_`grp' `leads_`grp'' `v'_`grp'
        }
        foreach v of local int_lags {
            local lags_`grp' `lags_`grp'' `v'_`grp'
        }
    }
    save ../temp/robust_es_unbal_`samp'`suf', replace

    foreach yvar in ppr_cnt cite_affl_wt {
        if "`yvar'" == "ppr_cnt"      local var_name "Publication Count"
        if "`yvar'" == "cite_affl_wt" local var_name "Citation Weighted Output"
        if "`yvar'" == "ppr_cnt"      local gap 0.5
        if "`yvar'" == "cite_affl_wt" local gap 1
        if "`yvar'" == "ppr_cnt"      & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "cite_affl_wt" & "`samp'" == "top_jrnls" local gap 2

        foreach split in pre_ppr grants {
            if "`split'" == "pre_ppr" {
                local hi high_pre_ppr
                local lo low_pre_ppr
            }
            else {
                local hi high_grants
                local lo low_grants
            }
            use ../temp/robust_es_unbal_`samp'`suf', clear
            reghdfe `yvar' `leads_`hi'' `lags_`hi'' ///
                           `leads_`lo''  `lags_`lo'' ///
                           int_lead1_`hi' int_lead1_`lo', ///
                           absorb(`fes') vce(cluster athr_id)
            foreach grp in `hi' `lo' {
                local ref_b = _b[int_lead1_`grp']
                di as text "robustness (5) `yvar' `grp': ref _b[int_lead1_`grp'] = `ref_b' (should be 0 if Stata dropped the reference)"
                preserve
                mat drop _all
                foreach var in `leads_`grp'' `lags_`grp'' int_lead1_`grp' {
                    mat row = _b[`var'] - `ref_b', _se[`var']
                    if "`var'" == "int_lead1_`grp'" mat row = 0,0
                    mat es = nullmat(es) \ row
                }
                svmat es
                keep es1 es2
                drop if mi(es1)
                rename (es1 es2) (b se)
                gen ub = b + 1.96*se
                gen lb = b - 1.96*se
                gen rel = -4 if _n == 1
                replace rel = rel[_n-1]+1 if _n > 1
                replace rel = rel + 1 if rel >= -1
                replace rel = -1 if rel == `abs_lag' + 1
                gen year = rel + 2014
                hashsort rel
                sum ub, d
                local ymax = round(r(max),`gap')
                sum lb, d
                local ymin = round(r(min),`gap')
                tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
                  scatter b year, mcolor(ebblue) ///
                  , xlab(2010(1)2019) xtitle("Year") ytitle("`var_name'") ///
                    ylab(`ymin'(`gap')`ymax') yline(0, lcolor(gs10) lpattern(solid)) ///
                    title("Unbalanced panel (no tsfill): `grp'", size(small)) ///
                    legend(off) plotregion(margin(sides))
                graph export ../output/figures/`samp'/robustness/es_`yvar'_unbal_`grp'`suf'.pdf, replace
                restore
            }
        }
    }

    // (6) absorption check across heterogeneity splits:
    //     for each pair, runs the heterogeneity regression with I(rel=k) x g1
    //     absorbed (uninteracted with exposure) so that exposure x group x time
    //     identifies only within-group exposure heterogeneity
    local pair_list `" "high_pre_ppr low_pre_ppr" "high_grants low_grants" "young old" "above_median below_median" "'
    foreach pair of local pair_list {
        local g1: word 1 of `pair'
        local g2: word 2 of `pair'

        use ../temp/es_`samp'`suf', clear
        cap drop rel int_lead* int_lag* g1rel_*
        gen rel = year - 2014
        qui sum rel
        local abs_lag  = abs(r(max))
        local abs_lead = abs(r(min))
        forval i = 1/`abs_lead' {
            gen int_lead`i' = exposure if rel == -`i'
        }
        forval i = 1/`abs_lag' {
            gen int_lag`i'  = exposure if rel == `i'
        }
        gen int_lag0 = exposure if rel == 0
        ds int_lead* int_lag*
        foreach var in `r(varlist)' {
            replace `var' = 0 if mi(`var')
        }
        local int_leads
        local int_lags
        forval i = 2/`abs_lead' {
            local int_leads int_lead`i' `int_leads'
        }
        forval i = 0/`abs_lag' {
            local int_lags `int_lags' int_lag`i'
        }
        foreach grp in `g1' `g2' {
            foreach v of local int_leads {
                gen `v'_`grp' = `v' * `grp'
            }
            foreach v of local int_lags {
                gen `v'_`grp' = `v' * `grp'
            }
            gen int_lead1_`grp' = int_lead1 * `grp'
            local leads_`grp'
            local lags_`grp'
            foreach v of local int_leads {
                local leads_`grp' `leads_`grp'' `v'_`grp'
            }
            foreach v of local int_lags {
                local lags_`grp' `lags_`grp'' `v'_`grp'
            }
        }
        // absorption terms: I(rel=k) x g1 (g2 is implicit reference; rel=-1 omitted)
        forval i = 2/`abs_lead' {
            gen g1rel_lead`i' = (rel == -`i') * `g1'
        }
        forval i = 0/`abs_lag' {
            gen g1rel_lag`i'  = (rel == `i')  * `g1'
        }
        local g1rel_leads
        local g1rel_lags
        forval i = 2/`abs_lead' {
            local g1rel_leads g1rel_lead`i' `g1rel_leads'
        }
        forval i = 0/`abs_lag' {
            local g1rel_lags `g1rel_lags' g1rel_lag`i'
        }
        save ../temp/robust_es_grpabsorb_`g1'_`samp'`suf', replace

        foreach yvar in ppr_cnt cite_affl_wt {
            if "`yvar'" == "ppr_cnt"      local var_name "Publication Count"
            if "`yvar'" == "cite_affl_wt" local var_name "Citation Weighted Output"
            if "`yvar'" == "ppr_cnt"      local gap 0.5
            if "`yvar'" == "cite_affl_wt" local gap 1
            if "`yvar'" == "ppr_cnt"      & "`samp'" == "top_jrnls" local gap 2
            if "`yvar'" == "cite_affl_wt" & "`samp'" == "top_jrnls" local gap 2

            use ../temp/robust_es_grpabsorb_`g1'_`samp'`suf', clear
            reghdfe `yvar' `leads_`g1'' `lags_`g1'' ///
                           `leads_`g2''  `lags_`g2'' ///
                           int_lead1_`g1' int_lead1_`g2' ///
                           `g1rel_leads' `g1rel_lags', ///
                           absorb(`fes') vce(cluster athr_id)
            foreach grp in `g1' `g2' {
                local ref_b = _b[int_lead1_`grp']
                di as text "robustness (6) `yvar' `grp' (pair `g1'/`g2'): ref _b[int_lead1_`grp'] = `ref_b'"
                preserve
                mat drop _all
                foreach var in `leads_`grp'' `lags_`grp'' int_lead1_`grp' {
                    mat row = _b[`var'] - `ref_b', _se[`var']
                    if "`var'" == "int_lead1_`grp'" mat row = 0,0
                    mat es = nullmat(es) \ row
                }
                svmat es
                keep es1 es2
                drop if mi(es1)
                rename (es1 es2) (b se)
                gen ub = b + 1.96*se
                gen lb = b - 1.96*se
                gen rel = -4 if _n == 1
                replace rel = rel[_n-1]+1 if _n > 1
                replace rel = rel + 1 if rel >= -1
                replace rel = -1 if rel == `abs_lag' + 1
                gen year = rel + 2014
                hashsort rel
                sum ub, d
                local ymax = round(r(max),`gap')
                sum lb, d
                local ymin = round(r(min),`gap')
                tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
                  scatter b year, mcolor(ebblue) ///
                  , xlab(2010(1)2019) xtitle("Year") ytitle("`var_name'") ///
                    ylab(`ymin'(`gap')`ymax') yline(0, lcolor(gs10) lpattern(solid)) ///
                    title("With group x event-time absorption: `grp' (vs `g2')", size(small)) ///
                    legend(off) plotregion(margin(sides))
                graph export ../output/figures/`samp'/robustness/es_`yvar'_grpAbsorb_`grp'`suf'.pdf, replace
                restore
            }
            // gamma_k path: g1's absorbed trajectory relative to g2 (the "common trend")
            preserve
            mat drop _all
            foreach var in `g1rel_leads' `g1rel_lags' {
                mat row = _b[`var'], _se[`var']
                mat es = nullmat(es) \ row
            }
            svmat es
            keep es1 es2
            drop if mi(es1)
            rename (es1 es2) (b se)
            gen ub = b + 1.96*se
            gen lb = b - 1.96*se
            gen rel = -`abs_lead' if _n == 1
            replace rel = rel[_n-1]+1 if _n > 1
            replace rel = rel + 1 if rel >= -1
            local nrows = `abs_lead' - 1 + `abs_lag' + 1
            set obs `=`nrows'+1'
            replace rel = -1 if _n == `nrows' + 1
            replace b   = 0  if _n == `nrows' + 1
            replace se  = 0  if _n == `nrows' + 1
            replace ub  = 0  if _n == `nrows' + 1
            replace lb  = 0  if _n == `nrows' + 1
            gen year = rel + 2014
            hashsort rel
            sum ub, d
            local ymax = round(r(max),`gap')
            sum lb, d
            local ymin = round(r(min),`gap')
            tw rcap ub lb year if year != 2013, lcolor(cranberry%70) msize(vsmall) || ///
              scatter b year, mcolor(cranberry) ///
              , xlab(2010(1)2019) xtitle("Year") ytitle("`var_name'") ///
                ylab(`ymin'(`gap')`ymax') yline(0, lcolor(gs10) lpattern(solid)) ///
                title("Absorbed `g1' minus `g2' common trend: `yvar'", size(small)) ///
                legend(off) plotregion(margin(sides))
            graph export ../output/figures/`samp'/robustness/es_`yvar'_grpAbsorbedTrend_`g1'`suf'.pdf, replace
            restore
        }
    }

    // (7) main (pooled, no-heterogeneity) event study stress tests
    //     base / + age x year controls / drop late-exit PIs / unbalanced panel
    foreach yvar in ppr_cnt cite_affl_wt {
        if "`yvar'" == "ppr_cnt"      local var_name "Publication Count"
        if "`yvar'" == "cite_affl_wt" local var_name "Citation Weighted Output"
        if "`yvar'" == "ppr_cnt"      local gap 0.5
        if "`yvar'" == "cite_affl_wt" local gap 1
        if "`yvar'" == "ppr_cnt"      & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "cite_affl_wt" & "`samp'" == "top_jrnls" local gap 2

        foreach spec in base ageCtrl noattrit unbal {
            if "`spec'" == "base"     local title "Base (replicates main)"
            if "`spec'" == "ageCtrl"  local title "Age x year controls"
            if "`spec'" == "noattrit" local title "PIs with last real pub year >= 2018"
            if "`spec'" == "unbal"    local title "Unbalanced panel (no tsfill)"

            if "`spec'" == "unbal" {
                use ../temp/robust_es_unbal_`samp'`suf', clear
            }
            else {
                use ../temp/es_`samp'`suf', clear
                cap drop rel int_lead* int_lag*
                gen rel = year - 2014
                qui sum rel
                local abs_lag  = abs(r(max))
                local abs_lead = abs(r(min))
                forval i = 1/`abs_lead' {
                    gen int_lead`i' = exposure if rel == -`i'
                }
                forval i = 1/`abs_lag' {
                    gen int_lag`i'  = exposure if rel == `i'
                }
                gen int_lag0 = exposure if rel == 0
                ds int_lead* int_lag*
                foreach var in `r(varlist)' {
                    replace `var' = 0 if mi(`var')
                }
                if "`spec'" == "noattrit" {
                    bys athr_id: egen latest_pub = max(cond(ppr_cnt > 0, year, .))
                    keep if latest_pub >= 2018
                    drop latest_pub
                }
            }
            qui sum rel
            local abs_lag  = abs(r(max))
            local abs_lead = abs(r(min))
            local int_leads
            local int_lags
            forval i = 2/`abs_lead' {
                local int_leads int_lead`i' `int_leads'
            }
            forval i = 0/`abs_lag' {
                local int_lags `int_lags' int_lag`i'
            }
            local addctrl
            if "`spec'" == "ageCtrl" local addctrl c.age_2014#i.year

            reghdfe `yvar' `int_leads' `int_lags' int_lead1 `addctrl', ///
                    absorb(`fes') vce(cluster athr_id)
            local ref_b = _b[int_lead1]
            di as text "robustness (7) `yvar' `spec': ref _b[int_lead1] = `ref_b'"
            gunique athr_id
            local n_pi = r(unique)

            preserve
            mat drop _all
            foreach var in `int_leads' `int_lags' int_lead1 {
                mat row = _b[`var'] - `ref_b', _se[`var']
                if "`var'" == "int_lead1" mat row = 0,0
                mat es = nullmat(es) \ row
            }
            svmat es
            keep es1 es2
            drop if mi(es1)
            rename (es1 es2) (b se)
            gen ub = b + 1.96*se
            gen lb = b - 1.96*se
            gen rel = -4 if _n == 1
            replace rel = rel[_n-1]+1 if _n > 1
            replace rel = rel + 1 if rel >= -1
            replace rel = -1 if rel == `abs_lag' + 1
            gen year = rel + 2014
            hashsort rel
            // persist coefs to .dta so a downstream plot crash doesn't lose results
            save ../temp/robust_es_main_`yvar'_`spec'_`samp'`suf', replace
            sum ub, d
            local ymax = round(r(max),`gap')
            sum lb, d
            local ymin = round(r(min),`gap')
            cap graph drop _all
            cap noi tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
              scatter b year, mcolor(ebblue) ///
              , xlab(2010(1)2019) xtitle("Year") ytitle("`var_name'") ///
                ylab(`ymin'(`gap')`ymax') yline(0, lcolor(gs10) lpattern(solid)) ///
                title("Main ES: `title' (N PIs = `n_pi')", size(small)) ///
                legend(off) plotregion(margin(sides))
            cap noi graph export ../output/figures/`samp'/robustness/es_`yvar'_main_`spec'`suf'.pdf, replace
            restore
        }
    }

    // (8) Field heterogeneity via openalex 100-cluster assignment
    //     build helper file once: PI -> cluster_100
    cap confirm file ../temp/athr_cluster100.dta
    if _rc {
        import delimited ../external/cluster/author_static_clusters_100.csv, clear varnames(1)
        cap tostring athr_id, replace
        rename cluster_label cluster_100
        save ../temp/athr_cluster100, replace
    }

    // merge cluster into the analysis sample once, save for (8a) and (8b)
    use ../temp/es_`samp'`suf', clear
    merge m:1 athr_id using ../temp/athr_cluster100, keep(1 3) nogen
    drop if mi(cluster_100)
    cap drop rel int_lead* int_lag*
    gen rel = year - 2014
    qui sum rel
    local abs_lag  = abs(r(max))
    local abs_lead = abs(r(min))
    forval i = 1/`abs_lead' {
        gen int_lead`i' = exposure if rel == -`i'
    }
    forval i = 1/`abs_lag' {
        gen int_lag`i'  = exposure if rel == `i'
    }
    gen int_lag0 = exposure if rel == 0
    ds int_lead* int_lag*
    foreach var in `r(varlist)' {
        replace `var' = 0 if mi(`var')
    }
    local int_leads
    local int_lags
    forval i = 2/`abs_lead' {
        local int_leads int_lead`i' `int_leads'
    }
    forval i = 0/`abs_lag' {
        local int_lags `int_lags' int_lag`i'
    }
    egen cluster_year = group(cluster_100 year)
    save ../temp/robust_es_cluster_`samp'`suf', replace

    // (8a) main pooled event study with cluster x year FE — does the effect
    //      survive after stripping out field-specific year shocks?
    foreach yvar in ppr_cnt cite_affl_wt {
        if "`yvar'" == "ppr_cnt"      local var_name "Publication Count"
        if "`yvar'" == "cite_affl_wt" local var_name "Citation Weighted Output"
        if "`yvar'" == "ppr_cnt"      local gap 0.5
        if "`yvar'" == "cite_affl_wt" local gap 1
        if "`yvar'" == "ppr_cnt"      & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "cite_affl_wt" & "`samp'" == "top_jrnls" local gap 2

        use ../temp/robust_es_cluster_`samp'`suf', clear
        cap noi reghdfe `yvar' `int_leads' `int_lags' int_lead1, ///
                absorb(athr_id cluster_year) vce(cluster athr_id)
        local ref_b = _b[int_lead1]
        di as text "robustness (8a) `yvar' clusterYrFE: ref _b[int_lead1] = `ref_b'"
        gunique athr_id
        local n_pi = r(unique)

        preserve
        mat drop _all
        foreach var in `int_leads' `int_lags' int_lead1 {
            mat row = _b[`var'] - `ref_b', _se[`var']
            if "`var'" == "int_lead1" mat row = 0,0
            mat es = nullmat(es) \ row
        }
        svmat es
        keep es1 es2
        drop if mi(es1)
        rename (es1 es2) (b se)
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        gen rel = -4 if _n == 1
        replace rel = rel[_n-1]+1 if _n > 1
        replace rel = rel + 1 if rel >= -1
        replace rel = -1 if rel == `abs_lag' + 1
        gen year = rel + 2014
        hashsort rel
        save ../temp/robust_es_main_clusterYrFE_`yvar'_`samp'`suf', replace
        sum ub, d
        local ymax = round(r(max),`gap')
        sum lb, d
        local ymin = round(r(min),`gap')
        cap graph drop _all
        cap noi tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
          scatter b year, mcolor(ebblue) ///
          , xlab(2010(1)2019) xtitle("Year") ytitle("`var_name'") ///
            ylab(`ymin'(`gap')`ymax') yline(0, lcolor(gs10) lpattern(solid)) ///
            title("Main ES: + cluster x year FE (N PIs = `n_pi')", size(small)) ///
            legend(off) plotregion(margin(sides))
        cap noi graph export ../output/figures/`samp'/robustness/es_`yvar'_main_clusterYrFE`suf'.pdf, replace
        restore
    }

    // (8b) top-10 FOIA-containing clusters: sample-split main event study
    use ../temp/robust_es_cluster_`samp'`suf', clear
    preserve
        // FOIA-containing clusters only (the ones we extrapolate exposure into)
        bys cluster_100: egen any_foia = max(foia_athr == 1)
        keep if any_foia == 1
        // count PIs per cluster
        bys cluster_100 athr_id: gen first = _n == 1
        bys cluster_100: egen n_pi_cluster = total(first)
        contract cluster_100 n_pi_cluster
        drop _freq
        gsort -n_pi_cluster
        keep if _n <= 10
        levelsof cluster_100, local(top_clusters)
        di as text "robustness (8b) `samp' top-10 FOIA-containing clusters: `top_clusters'"
    restore

    foreach c of local top_clusters {
        foreach yvar in ppr_cnt cite_affl_wt {
            if "`yvar'" == "ppr_cnt"      local var_name "Publication Count"
            if "`yvar'" == "cite_affl_wt" local var_name "Citation Weighted Output"
            if "`yvar'" == "ppr_cnt"      local gap 0.5
            if "`yvar'" == "cite_affl_wt" local gap 1
            if "`yvar'" == "ppr_cnt"      & "`samp'" == "top_jrnls" local gap 2
            if "`yvar'" == "cite_affl_wt" & "`samp'" == "top_jrnls" local gap 2

            use ../temp/robust_es_cluster_`samp'`suf', clear
            keep if cluster_100 == `c'

            qui count
            if r(N) < 50 continue
            cap noi reghdfe `yvar' `int_leads' `int_lags' int_lead1, ///
                    absorb(`fes') vce(cluster athr_id)
            if _rc continue
            local ref_b = _b[int_lead1]
            di as text "robustness (8b) `yvar' cluster_100=`c': ref _b[int_lead1] = `ref_b'"
            gunique athr_id
            local n_pi = r(unique)

            preserve
            mat drop _all
            foreach var in `int_leads' `int_lags' int_lead1 {
                mat row = _b[`var'] - `ref_b', _se[`var']
                if "`var'" == "int_lead1" mat row = 0,0
                mat es = nullmat(es) \ row
            }
            svmat es
            keep es1 es2
            drop if mi(es1)
            rename (es1 es2) (b se)
            gen ub = b + 1.96*se
            gen lb = b - 1.96*se
            gen rel = -4 if _n == 1
            replace rel = rel[_n-1]+1 if _n > 1
            replace rel = rel + 1 if rel >= -1
            replace rel = -1 if rel == `abs_lag' + 1
            gen year = rel + 2014
            hashsort rel
            save ../temp/robust_es_clusterTop_`c'_`yvar'_`samp'`suf', replace
            sum ub, d
            local ymax = round(r(max),`gap')
            sum lb, d
            local ymin = round(r(min),`gap')
            cap graph drop _all
            cap noi tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
              scatter b year, mcolor(ebblue) ///
              , xlab(2010(1)2019) xtitle("Year") ytitle("`var_name'") ///
                ylab(`ymin'(`gap')`ymax') yline(0, lcolor(gs10) lpattern(solid)) ///
                title("Main ES: cluster_100=`c' (N PIs = `n_pi')", size(small)) ///
                legend(off) plotregion(margin(sides))
            cap noi graph export ../output/figures/`samp'/robustness/es_`yvar'_clusterTop_`c'`suf'.pdf, replace
            restore
        }
    }
end

program output_tables
    // dumps the base vs. + market-share DiD matrices built by long_diff,
    // first_diff, and pooled_did. Each matrix has rows = coefs/SEs + N/R2
    // (+ pre_mean for pooled) and cols = base / with_share.
    syntax, samp(string) [, r1r2(int 0) public(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"
    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'
    local outcomes cite_affl_wt ppr_cnt ln_cite_affl_wt ln_ppr_cnt body_adj_wt avg_num_coathrs num_grants
    foreach prog in ld fd pdid ppml_ld ppml_fd ppml_pdid {
        foreach yvar of local outcomes {
            cap confirm matrix `prog'_`yvar'
            if !_rc {
                qui matrix_to_txt, saving("../output/tables/`samp'/`prog'_`yvar'`suf'.txt") ///
                    matrix(`prog'_`yvar') title(<tab:`prog'_`yvar'`suf'>) format(%20.4f) replace
            }
        }
    }
end
**
main
