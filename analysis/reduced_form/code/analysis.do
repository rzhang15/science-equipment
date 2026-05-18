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
        combine_es_graphs, samp(`s')
    /*    // r1 + r2
        restrict_samp, samp(`s') r1r2(1) public(0)
        event_study, samp(`s') r1r2(1) public(0)
        // everyone
        restrict_samp, samp(`s') r1r2(0) public(0)
        event_study, samp(`s') r1r2(0) public(0)*/
    }
end

program gather_external_data
    import delimited ../external/exposure/final_imputed_exposure, clear
    rename exposure imputed
    save ../temp/exposure, replace

    use ../external/grants/pi_grants, clear
    bys athr_id year: gen num_grants = _N
    contract athr_id year num_grants
    drop _freq
    save ../temp/athr_yr_grnt_cnt, replace

    use ../external/grants/pi_grants, clear
    keep if funder_name == "National Institutes of Health"
    bys athr_id year: gen num_nih_grants = _N
    contract athr_id year num_nih_grants
    drop _freq
    save ../temp/athr_yr_nih_grnt_cnt, replace

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
    keep if tot_pprs >= 10
    drop tot_pprs
    bys athr_id: egen min_year = min(year)
    keep if min_year < 2013
    bys athr_id: egen max_year = max(year)
    keep if max_year >= 2014
    keep if inrange(year, 2010, 2019)
    merge m:1 athr_id using ../temp/exposure, assert(1 2 3) keep(3) nogen
    merge m:1 athr_id using ../external/real_exposure/athr_exposure, assert(1 2 3) keep(1 3) nogen
    gen foia_athr = 1 if !mi(exposure)
    replace imputed = exposure if !mi(exposure)
    drop if exposure <= 0
    drop if imputed <= 0
    sum exposure , d 
    local mean : di %4.3f r(mean) 
    local sd: di %4.3f r(sd) 
    local p25: di %4.3f r(p25) 
    local p50: di %4.3f r(p50) 
    local p75: di %4.3f r(p75)
    local max: di %4.3f  r(max) 
    local min: di %4.3f r(min) 
    sum imputed, d 
    local imputed_mean : di %4.3f r(mean) 
    local imputed_sd: di %4.3f r(sd) 
    local imputed_p25: di %4.3f r(p25) 
    local imputed_p50: di %4.3f r(p50) 
    local imputed_p75: di %4.3f r(p75)
    local imputed_max: di %4.3f  r(max) 
    local imputed_min: di %4.3f r(min) 
    tw kdensity exposure || kdensity imputed, xtitle("Exposure Measure") ytitle("Density") ///
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
   * keep if num_place==1
    *drop if exposure <= 0
    gegen athr = group(athr_id)
    xtset athr year
    tsfill
    hashsort athr year
    foreach var in athr_id exposure q1 q2 q3 q4 median  inst_id inst msa_comb msa_c_world min_year {
        by athr: replace `var' = `var'[_n-1] if mi(`var')    
    }
    foreach var in cite_affl_wt ppr_cnt affl_wt body_adj_wt  {
        replace `var' = 0 if mi(`var')    
    }
    bys athr_id: egen tot_pprs = total(ppr_cnt)
    drop if tot_pprs < 7 
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
    merge 1:1 athr_id year using ../external/coathrs/avg_coathrs, keep(1 3) assert(1 2 3) nogen
    replace avg_num_coathrs = 0 if mi(avg_num_coathrs)
    merge 1:1 athr_id year using ../temp/athr_yr_grnt_cnt, keep(1 3) assert(1 2 3) nogen
    replace num_grants = 0 if mi(num_grants)
    merge 1:1 athr_id year using ../temp/athr_yr_nih_grnt_cnt, keep(1 3) assert(1 2 3) nogen
    replace num_nih_grants = 0 if mi(num_nih_grants)
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
    collapse (mean) ppr_cnt cite_affl_wt affl_wt body_adj_wt avg_num_coathrs r1 age num_grants num_nih_grants (firstnm) quartile, by(athr_id year)
    gcollapse (mean) ppr_cnt cite_affl_wt affl_wt body_adj_wt avg_num_coathrs r1 age num_grants num_nih_grants ,  by(quartile year)
    foreach var in ppr_cnt cite_affl_wt affl_wt body_adj_wt avg_num_coathrs r1 age num_grants num_nih_grants {
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
    }
    gen int_lag0 = exposure if rel == 0
    gen lag0 = 1 if rel == 0
    ds lead* lag* int_lead* int_lag*
    foreach var in `r(varlist)' {
        replace `var' = 0 if mi(`var')
    }
    local leads
    local int_leads
    local lags
    local int_lags
    forval i = 2/`abs_lead' {
        local leads lead`i' `leads'
        local int_leads int_lead`i' `int_leads'
    }
    forval i = 0/`abs_lag' {
        local lags `lags' lag`i'
        local int_lags `int_lags' int_lag`i'
    }
    foreach v in cite_affl_wt ppr_cnt {
        gen ln_`v' = ln(1+`v')
    }
    foreach yvar in cite_affl_wt ppr_cnt ln_cite_affl_wt ln_ppr_cnt affl_wt body_adj_wt avg_num_coathrs num_grants num_nih_grants {
        if "`yvar'" == "ln_spend" local var_name = "Log Spending" 
        if "`yvar'" == "ln_spend" local gap  0.5 
        if "`yvar'" == "cite_affl_wt" local var_name = "Citation Weighted Output" 
        if "`yvar'" == "cite_affl_wt" local gap  1 
        if "`yvar'" == "ppr_cnt" local var_name = "Publication Count" 
        if "`yvar'" == "ppr_cnt" local gap 0.5 
        if "`yvar'" == "avg_coathrs" local var_name = "Average Team Size" 
        if "`yvar'" == "avg_coathrs" local gap 0.5 

        preserve
        mat drop _all 
        sum `yvar' if rel <= -1 & exposure > 0, d
        local pre_mean : dis %4.3f r(mean)
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
          legend(on order(- "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) plotregion(margin(sides))
        graph export ../output/figures/`samp'/es_`yvar'`suf'.pdf, replace
        save ../temp/es_`yvar', replace
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

        // heterogeneity by author & inst characteristics        
        foreach cond in young old r1 r2 above_median below_median {
            sum `yvar' if rel <= -1 & exposure > 0 & `cond' == 1, d
            local pre_mean : dis %4.3f r(mean)
            preserve
            mat drop _all 
            reghdfe `yvar' `int_leads' `int_lags' int_lead1 if `cond' == 1, absorb(`fes') vce(cluster athr_id)
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
            local ymin =  round(r(min),`gap')
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
              legend(on order(- "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) /// 
              yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
            graph export ../output/figures/`samp'/es_`yvar'`suf'_`cond'.pdf, replace
            save ../temp/es_`yvar'`suf'_`cond', replace
            restore
        } 
       
        // hetoregeneity by exposure quartiles
        forval i = 1/4 {
            preserve
            mat drop _all 
            reghdfe `yvar' `int_leads' `int_lags' int_lead1 if q`i' == 1, absorb(`fes') vce(cluster athr_id)
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
            local ymin =  round(r(min),`gap')
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

program combine_es_graphs
    syntax, samp(str)
    foreach yvar in cite_affl_wt ppr_cnt ln_cite_affl_wt ln_ppr_cnt body_adj_wt avg_num_coathrs {
        if "`yvar'" == "cite_affl_wt" local var_name = "Citation Weighted Output" 
        if "`yvar'" == "cite_affl_wt" local gap  1 
        if "`yvar'" == "ppr_cnt" local var_name = "Publication Count" 
        if "`yvar'" == "ppr_cnt" local gap 0.5 
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

program output_tables
    foreach tab in did_impact_cite_affl_wt did_ppr_cnt {
    qui matrix_to_txt, saving("../output/tables/`tab'.txt") matrix(`tab') ///
       title(<tab:`tab'>) format(%20.4f) replace
    }
end
**
main
