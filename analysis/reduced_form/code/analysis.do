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
        combine_es_graphs, samp(`s')
        robustness, samp(`s') r1r2(1) public(1)
    /*    // r1 + r2
        restrict_samp, samp(`s') r1r2(1) public(0)
        event_study, samp(`s') r1r2(1) public(0)
        // everyone
        restrict_samp, samp(`s') r1r2(0) public(0)
        event_study, samp(`s') r1r2(0) public(0)*/
    }
end

program gather_external_data
    import delimited ../external/exposure/final_imputed_exposure_restricted, clear
    rename exposure imputed
    rename mkt_spend_shr imputed_mkt_spend_shr
    save ../temp/exposure, replace

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
    keep if tot_pprs >= 20
    drop tot_pprs
    bys athr_id: egen max_year = max(year)
    keep if max_year >= 2014
    keep if inrange(year, 2010, 2019)
    bys athr_id: egen min_year = min(year)
    keep if min_year <= 2013
    merge m:1 athr_id using ../temp/exposure, assert(1 2 3) keep(3) nogen
    merge m:1 athr_id using ../external/real_exposure/athr_exposure, assert(1 2 3) keep(1 3) nogen
    gen foia_athr = 1 if !mi(exposure)
    bys athr_id : gen athr_indicator = _n == 1
    drop if exposure <= 0
    drop if imputed <= 0
   * keep if foia_athr == 1
    sum exposure if athr_indicator == 1 , d 
    local mean : di %4.3f r(mean) 
    local sd: di %4.3f r(sd) 
    local p25: di %4.3f r(p25) 
    local p50: di %4.3f r(p50) 
    local p75: di %4.3f r(p75)
    local max: di %4.3f  r(max) 
    local min: di %4.3f r(min) 
    sum imputed if athr_indicator == 1 , d 
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
    tw kdensity exposure if athr_indicator == 1 || kdensity imputed if athr_indicator == 1, xtitle("Exposure Measure") ytitle("Density") ///
        xlab(#15) ///
        legend(on label(1 "FOIA PI Observed Exposure (mean = `mean', sd = `sd')") label(2 "Imputed Exposure (mean = `imputed_mean', sd = `imputed_sd')") pos(1) ring(0) size(small))
    graph export ../output/figures/`samp'/exposure_dist`suf'.pdf, replace
    drop exposure
    rename imputed exposure
    gen q1 = exposure < `imputed_p25'
    gen q2 = inrange(exposure , `imputed_p25', `imputed_p50')
    gen q3 = inrange(exposure , `imputed_p50', `imputed_p75')
    gen q4 = exposure >= `imputed_p75'
    gen median = exposure >= `imputed_p50'
    bys athr_id: gen num_yrs = _N
    bys athr_id inst_id: gen plc_cntr = _n == 1
    bys athr_id : egen num_place = total(plc_cntr)
    keep if num_yrs > 1
    keep if num_place==1
    gegen athr = group(athr_id)
    preserve
    contract athr athr_id exposure q1 q2 q3 q4 median inst_id inst msa_comb msa_c_world min_year type
    drop _freq
    save ../temp/athr_xw, replace
    restore
    xtset athr year
    tsfill, full
    drop athr_id exposure q1 q2 q3 q4 median inst_id inst msa_comb msa_c_world min_year type
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
    bys athr_id: egen pre_ppr_cnt_sum = mean(pre_ppr_cnt)
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
        gen mshr_lag`i'  = imputed_mkt_spend_shr if rel == `i'
        gen mshr_lead`i' = imputed_mkt_spend_shr if rel == -`i'
    }
    gen int_lag0 = exposure if rel == 0
    gen lag0 = 1 if rel == 0
    gen mshr_lag0 = imputed_mkt_spend_shr if rel == 0
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
        if "`yvar'" == "ppr_cnt" & "`samp'" == "top_jrnls" local gap 1
        if "`yvar'" == "avg_coathrs" local var_name = "Average Team Size" 
        if "`yvar'" == "avg_coathrs" local gap 0.5 

        preserve
        mat drop _all
        sum `yvar' if rel <= -1 & exposure > 0, d
        local pre_mean : dis %4.3f r(mean)
        gunique athr_id
        local num_athrs = r(unique)
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
        tw rcap ub lb rel if rel != -1 , lcolor(ebblue%70) msize(vsmall) || ///
          scatter b rel, mcolor(ebblue) || ///
          scatteri `ymax' -0.25 `ymax' 0.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
          xlab(-4(1)5) xtitle("Relative Year") ///
          ytitle("`var_name'") ylab(`ymin'(`gap')`ymax') ///
          yline(0, lcolor(gs10) lpattern(solid)) ///
          legend(on order(- "Num. PIs: `num_athrs'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) plotregion(margin(sides))
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
        tw rcap ub lb rel if rel != -1 , lcolor(ebblue%70) msize(vsmall) || ///
          scatter b rel, mcolor(ebblue) || ///
          scatteri `ymax' -0.25 `ymax' 0.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
          xlab(-4(1)5) xtitle("Relative Year") ///
          ytitle("`var_name'") ylab(`ymin'(`gap')`ymax') ///
          yline(0, lcolor(gs10) lpattern(solid)) ///
          legend(on order(- "Num. PIs: `num_athrs'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) plotregion(margin(sides))
        graph export ../output/figures/`samp'/es_`yvar'`suf'_mshrctrl.pdf, replace
        save ../temp/es_`yvar'`suf'_mshrctrl, replace
        restore
/*
        preserve
        mat drop _all 
        *ppmlhdfe `yvar' `int_leads' `int_lags' int_lead1, absorb(`fes') vce(cluster athr_id)
        reghdfe ln_`yvar' `int_leads' `int_lags' int_lead1, absorb(`fes') vce(cluster athr_id)
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
        local ymax = round(r(max),.1)
        gen lb = b - 1.96*se
        sum lb, d
        local ymin = round(r(min),.1)
        gen rel = -5 if _n == 1
        replace rel = rel[_n-1]+1 if _n > 1
        replace rel = rel + 1 if rel >= -1 
        replace rel = -1 if rel == `abs_lag' + 1
        gen year = rel + 2014
        hashsort rel
        tw rcap ub lb rel if rel != -1 , lcolor(ebblue%70) msize(vsmall) || ///
          scatter b rel, mcolor(ebblue) || ///
        scatteri 1 -0.25 1 0.25 , bcolor(gs12%10) recast(area) base(-1) ///
          xlab(-5(1)5) xtitle("Relative Year") ///
          ytitle("`var_name'") ylab(-1(.2)1, labsize(vsmall)) ///
          yline(0, lcolor(gs10) lpattern(solid))  legend(off) plotregion(margin(sides))
        graph export ../output/figures/`samp'/es_ln_`yvar'`suf'.pdf, replace
        save ../temp/es_ln_`yvar', replace
        restore*/

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
                tw rcap ub lb rel if rel != -1 , lcolor(ebblue%70) msize(vsmall) || ///
                  scatter b rel, mcolor(ebblue) || ///
                scatteri `ymax' -0.25 `ymax' 0.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                  xlab(-4(1)5) xtitle("Relative Year") ///
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
            tw rcap ub lb rel if rel != -1 , lcolor(ebblue%70) msize(vsmall) || ///
              scatter b rel, mcolor(ebblue) || ///
            scatteri `ymax' -0.25 `ymax' 0.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
              xlab(-4(1)5) xtitle("Relative Year") ///
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
    gcollapse (firstnm) exposure q1 q2 q3 q4 above_median below_median ///
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

        binscatter d_`yvar' exposure, n(30) ///
            xtitle("Exposure") ytitle("{&Delta} `var_name' (post mean - pre mean)") ///
            title("Long Difference: `var_name'") msymbol(O) mcolor(ebblue)
        graph export ../output/figures/`samp'/ld_`yvar'`suf'.pdf, replace
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
    gen d_treat = exposure * (post - L.post)
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

    gen post = year >= 2014
    gen Z_it = exposure * post

    local outcomes cite_affl_wt ppr_cnt ln_cite_affl_wt ln_ppr_cnt body_adj_wt avg_num_coathrs num_grants

    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'

    eststo clear
    mat drop _all
    local model_names ""
    foreach yvar of local outcomes {
        qui sum `yvar' if year < 2014, d
        local pre_mean = r(mean)
        eststo m_`yvar': reghdfe `yvar' Z_it, absorb(`fes') vce(cluster athr_id)
        estadd scalar pre_mean = `pre_mean'
        local model_names "`model_names' m_`yvar'"
        local b  = _b[Z_it]
        local se = _se[Z_it]
        di as text "pooled_did `samp'`suf' `yvar': beta = " %7.4f `b' "  se = " %7.4f `se' "  pre-mean = " %7.4f `pre_mean'
        mat row = `b', `se', `pre_mean'
        mat results = nullmat(results) \ row
    }

    esttab `model_names' using ../output/tables/`samp'/pooled_did`suf'.tex, ///
        replace label se keep(Z_it) ///
        coeflabels(Z_it "Exposure x Post") ///
        title("Pooled DiD: y_it on exposure_i x post_t (athr & year FE, cluster athr)") ///
        scalars("pre_mean Pre-Period Mean") ///
        mtitles(`outcomes')

    // small dta with beta/SE per outcome for quoting in figure legends or text
    preserve
        clear
        svmat results
        rename (results1 results2 results3) (b se pre_mean)
        gen outcome = ""
        local i = 1
        foreach yvar of local outcomes {
            replace outcome = "`yvar'" if _n == `i'
            local ++i
        }
        order outcome b se pre_mean
        save ../temp/pooled_did_`samp'`suf', replace
        list, sep(0) noobs abbrev(20)
    restore
end

program combine_es_graphs
    syntax, samp(str)
    foreach yvar in cite_affl_wt ppr_cnt ln_cite_affl_wt ln_ppr_cnt body_adj_wt avg_num_coathrs {
        if "`yvar'" == "cite_affl_wt" local var_name = "Citation Weighted Output" 
        if "`yvar'" == "cite_affl_wt" local gap  1 
        if "`yvar'" == "ppr_cnt" local var_name = "Publication Count"
        if "`yvar'" == "ppr_cnt" local gap 0.5
        if "`yvar'" == "ppr_cnt" & "`samp'" == "top_jrnls" local gap 1
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
        tw rcap ub lb rel if rel != -1.4 & group == "q1",  lcolor(lavender%70) msize(small) || ///   
           scatter b rel if group == "q1", mcolor(lavender%70) msize(small) || ///                   
           rcap ub lb rel if rel != -1.25 & group == "q2",  lcolor(orange%70) msize(small) || ///     
           scatter b rel if group == "q2", mcolor(orange%70) msymbol(smdiamond) msize(small) ||  ///  
           rcap ub lb rel if rel != -1.1 & group == "q3",  lcolor(dkgreen%70) msize(small) || ///     
           scatter b rel if group == "q3", mcolor(green%70) msymbol(smdiamond) msize(small)|| ///  
           rcap ub lb rel if rel != -.95 & group == "q4",  lcolor(cranberry%70) msize(small) || ///     
           scatter b rel if group == "q4", mcolor(red%70) msymbol(smdiamond) msize(small)  ///  
           xlab(-4(1)5) ylab(#8) ///                         
              yline(0, lcolor(black) lpattern(solid)) ///                                               
              legend(on order(2 "Q1 Exposed (Post Period Avg: `q1_mean')" 4 "Q2 Exposed (Post Period Avg: `q2_mean')" 6 "Q3 Exposed (Post Period Avg: `q3_mean')" 8 "Q4 Exposed (Post Period Avg: `q4_mean')") pos(7) ring(1) size(small) region(fcolor(none))) xtitle("Relative Year") ytitle("`var_name'") plotregion(margin(sides))
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
        tw rcap ub lb rel if rel != -1.1 & group == "below",  lcolor(lavender%60) msize(small) || ///   
           scatter b rel if group == "below", mcolor(lavender%60) msize(small) || ///                   
           rcap ub lb rel if rel != -1 & group == "above",  lcolor(dkorange) msize(small) || ///     
           scatter b rel if group == "above", mcolor(dkorange) msymbol(smdiamond) msize(small)  ///  
           xlab(-4(1)5) ylab(#8) ///                         
              yline(0, lcolor(black) lpattern(solid)) ///                                               
              legend(on order(2 "Below Median Exposure (Post Period Avg: `below_mean')" 4 "Above Median Exposure (Post Period Avg: `above_mean')" ) pos(7) ring(1) size(small) region(fcolor(none))) xtitle("Relative Year") ytitle("`var_name'") plotregion(margin(sides))
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
        tw rcap ub lb rel if rel != -1.1 & group == "young",  lcolor(lavender%60) msize(small) || ///   
           scatter b rel if group == "young", mcolor(lavender%60) msize(small) || ///                   
           rcap ub lb rel if rel != -1 & group == "old",  lcolor(dkorange) msize(small) || ///     
           scatter b rel if group == "old", mcolor(dkorange) msymbol(smdiamond) msize(small)  ///  
           xlab(-4(1)5) ylab(#8) ///                         
              yline(0, lcolor(black) lpattern(solid)) ///                                               
              legend(on order(2 "Below Median Age (Post Period Avg: `young_mean')" 4 "Above Median Age (Post Period Avg: `old_mean')" ) pos(7) ring(1) size(small) region(fcolor(none))) xtitle("Relative Year") ytitle("`var_name'") plotregion(margin(sides))
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
        if "`yvar'" == "ppr_cnt" & "`samp'" == "top_jrnls" local gap 1

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
                hashsort rel
                sum ub, d
                local ymax = round(r(max),`gap')
                sum lb, d
                local ymin = round(r(min),`gap')
                tw rcap ub lb rel if rel != -1, lcolor(ebblue%70) msize(vsmall) || ///
                  scatter b rel, mcolor(ebblue) ///
                  , xlab(-4(1)5) xtitle("Relative Year") ytitle("`var_name'") ///
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
        if "`yvar'" == "ppr_cnt" & "`samp'" == "top_jrnls" local gap 1

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
                hashsort rel
                sum ub, d
                local ymax = round(r(max),`gap')
                sum lb, d
                local ymin = round(r(min),`gap')
                tw rcap ub lb rel if rel != -1, lcolor(ebblue%70) msize(vsmall) || ///
                  scatter b rel, mcolor(ebblue) ///
                  , xlab(-4(1)5) xtitle("Relative Year") ytitle("`var_name'") ///
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
                hashsort rel
                sum ub, d
                local ymax = round(r(max),`gap')
                sum lb, d
                local ymin = round(r(min),`gap')
                tw rcap ub lb rel if rel != -1, lcolor(ebblue%70) msize(vsmall) || ///
                  scatter b rel, mcolor(ebblue) ///
                  , xlab(-4(1)5) xtitle("Relative Year") ytitle("`var_name'") ///
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
            hashsort rel
            sum ub, d
            local ymax = round(r(max),`gap')
            sum lb, d
            local ymin = round(r(min),`gap')
            tw rcap ub lb rel if rel != -1, lcolor(cranberry%70) msize(vsmall) || ///
              scatter b rel, mcolor(cranberry) ///
              , xlab(-4(1)5) xtitle("Relative Year") ytitle("`var_name'") ///
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
        if "`yvar'" == "ppr_cnt" & "`samp'" == "top_jrnls" local gap 1

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
            hashsort rel
            // persist coefs to .dta so a downstream plot crash doesn't lose results
            save ../temp/robust_es_main_`yvar'_`spec'_`samp'`suf', replace
            sum ub, d
            local ymax = round(r(max),`gap')
            sum lb, d
            local ymin = round(r(min),`gap')
            cap graph drop _all
            cap noi tw rcap ub lb rel if rel != -1, lcolor(ebblue%70) msize(vsmall) || ///
              scatter b rel, mcolor(ebblue) ///
              , xlab(-4(1)5) xtitle("Relative Year") ytitle("`var_name'") ///
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
        if "`yvar'" == "ppr_cnt" & "`samp'" == "top_jrnls" local gap 1

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
        hashsort rel
        save ../temp/robust_es_main_clusterYrFE_`yvar'_`samp'`suf', replace
        sum ub, d
        local ymax = round(r(max),`gap')
        sum lb, d
        local ymin = round(r(min),`gap')
        cap graph drop _all
        cap noi tw rcap ub lb rel if rel != -1, lcolor(ebblue%70) msize(vsmall) || ///
          scatter b rel, mcolor(ebblue) ///
          , xlab(-4(1)5) xtitle("Relative Year") ytitle("`var_name'") ///
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
            hashsort rel
            save ../temp/robust_es_clusterTop_`c'_`yvar'_`samp'`suf', replace
            sum ub, d
            local ymax = round(r(max),`gap')
            sum lb, d
            local ymin = round(r(min),`gap')
            cap graph drop _all
            cap noi tw rcap ub lb rel if rel != -1, lcolor(ebblue%70) msize(vsmall) || ///
              scatter b rel, mcolor(ebblue) ///
              , xlab(-4(1)5) xtitle("Relative Year") ytitle("`var_name'") ///
                ylab(`ymin'(`gap')`ymax') yline(0, lcolor(gs10) lpattern(solid)) ///
                title("Main ES: cluster_100=`c' (N PIs = `n_pi')", size(small)) ///
                legend(off) plotregion(margin(sides))
            cap noi graph export ../output/figures/`samp'/robustness/es_`yvar'_clusterTop_`c'`suf'.pdf, replace
            restore
        }
    }
end

program output_tables
    foreach tab in did_impact_cite_affl_wt did_ppr_cnt {
    qui matrix_to_txt, saving("../output/tables/`tab'.txt") matrix(`tab') ///
       title(<tab:`tab'>) format(%20.4f) replace
    }
end
**
main
