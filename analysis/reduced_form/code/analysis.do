set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main   
    event_study
    *output_tables
end

program event_study
    import delimited ../external/exposure/final_imputed_exposure, clear
    rename exposure imputed
    save ../temp/exposure, replace

    use ../external/samp/athr_panel_full_year_last_all_jrnls,clear 
    bys athr_id: egen min_year = min(year)
    keep if min_year <= 2013
    merge m:1 athr_id using ../temp/exposure, assert(1 2 3) keep(3) nogen
    merge m:1 athr_id using ../external/real_exposure/athr_exposure, assert(1 2 3) keep(1 3) nogen
    replace imputed = exposure if !mi(exposure)
    drop exposure
    rename imputed exposure
    keep if inrange(year, 2009, 2019)
    bys athr_id: gen num_yrs = _N
    gegen athr= group(athr_id)
    /*xtset athr year
    tsfill
    hashsort athr year
    foreach var in athr_id exposure {
        by athr: replace `var' = `var'[_n-1] if mi(`var')    
    }
    foreach var in cite_affl_wt ppr_cnt {
        replace `var' = 0 if mi(`var')    
    }*/
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
    gen ln_cite_affl_wt = ln(1+cite_affl_wt)
    gen ln_ppr_cnt = ln(1+ppr_cnt)
    sum exposure , d 
    local mean : di %4.3f r(mean) 
    local sd: di %4.3f r(sd) 
    local p25: di %4.3f r(p25) 
    local p50: di %4.3f r(p50) 
    local p75: di %4.3f r(p75)
    local max: di %4.3f  r(max) 
    local min: di %4.3f r(min) 
    local fes athr_id year 

    tw kdensity exposure, xtitle("Imputed Exposure Score", size(small)) ytitle("Density", size(small)) ///
        ylab(, labsize(vsmall)) xlab(#15, labsize(vsmall)) ///
        legend(on order(- "Min: `min'" "Q1 = `p25'" "Median = `p50'" "Mean: `mean'" "SD = `sd'" "Q3 = `p75'" "Max = `max'") pos(1) ring(0) size(vsmall))
    graph export ../output/figures/exposure_dist.pdf, replace

    foreach yvar in ln_cite_affl_wt cite_affl_wt ln_ppr_cnt ppr_cnt {
        if "`yvar'" == "ln_cite_affl_wt" local var_name = "Log Citation Weighted Output" 
        if "`yvar'" == "cite_affl_wt" local var_name = "Citation Weighted Output" 
        if "`yvar'" == "ln_ppr_cnt" local var_name = "Log Publication Count" 
        if "`yvar'" == "ppr_cnt" local var_name = "Publication Count" 

        preserve
        gen median = exposure >= `p50'
        bys year: egen avg = mean(`yvar')
        gcollapse (mean) avg `yvar', by(year median)
        tw line avg year , lcolor(ebblue) || line `yvar' year if med == 1, lcolor(lavender) || line `yvar' year if med == 0, lcolor(dkorange) ///
            xtitle("Year", size(small)) ytitle("`var_name'", size(small)) ///
            legend(on order(1 "All Authors" 2 "Top 50% Exposed" 3 "Bottom 50% Exposed") pos(1) ring(0) size(vsmall))
        graph export ../output/figures/trend_`yvar'.pdf, replace
        restore

        preserve
        mat drop _all 
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
        gen lb = b - 1.96*se
        gen rel = -5 if _n == 1
        replace rel = rel[_n-1]+1 if _n > 1
        replace rel = rel + 1 if rel >= -1 
        replace rel = -1 if rel == `abs_lag' + 1
        gen year = rel + 2014
        hashsort rel
        tw rcap ub lb rel if rel != -1 , lcolor(ebblue%70) msize(vsmall) || scatter b rel, mcolor(ebblue) xlab(-5(1)5, labsize(vsmall)) xtitle("Relative Year", size(small)) ytitle("`var_name'", size(small)) ylab(#8, labsize(vsmall)) yline(0, lcolor(gs10) lpattern(solid)) xline(-0.5 , lcolor(gs12) lpattern(dash))  legend(off)
        graph export ../output/figures/es_`yvar'.pdf, replace
        save ../temp/es_`yvar', replace
        restore

        preserve
        mat drop _all 
        reghdfe `yvar' `int_leads' `int_lags' int_lead1 if inrange(exposure , `min', `p25'), absorb(`fes') vce(cluster athr_id)
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
        gen lb = b - 1.96*se
        gen rel = -5 if _n == 1
        replace rel = rel[_n-1]+1 if _n > 1
        replace rel = rel + 1 if rel >= -1 
        replace rel = -1 if rel == `abs_lag' + 1
        gen year = rel + 2014
        hashsort rel
        tw rcap ub lb rel if rel != -1 , lcolor(ebblue%70) msize(vsmall) || scatter b rel, mcolor(ebblue) xlab(-5(1)5, labsize(vsmall)) xtitle("Relative Year", size(small)) ytitle("`var_name'", size(small)) ylab(, labsize(vsmall)) yline(0, lcolor(gs10) lpattern(solid)) xline(-0.5 , lcolor(gs12) lpattern(dash))  legend(off)
        graph export ../output/figures/es_`yvar'_q1.pdf, replace
        save ../temp/es_`yvar'_q1, replace
        restore
        
        preserve
        mat drop _all 
        reghdfe `yvar' `int_leads' `int_lags' int_lead1 if inrange(exposure ,`p25', `p50'), absorb(`fes') vce(cluster athr_id)
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
        gen lb = b - 1.96*se
        gen rel = -5 if _n == 1
        replace rel = rel[_n-1]+1 if _n > 1
        replace rel = rel + 1 if rel >= -1 
        replace rel = -1 if rel == `abs_lag' + 1
        gen year = rel + 2014
        hashsort rel
        tw rcap ub lb rel if rel != -1 , lcolor(ebblue%70) msize(vsmall) || scatter b rel, mcolor(ebblue) xlab(-5(1)5, labsize(vsmall)) xtitle("Relative Year", size(small)) ytitle("`var_name'", size(small)) ylab(, labsize(vsmall)) yline(0, lcolor(gs10) lpattern(solid)) xline(-0.5 , lcolor(gs12) lpattern(dash))  legend(off)
        graph export ../output/figures/es_`yvar'_q2.pdf, replace
        save ../temp/es_`yvar'_q2, replace
        restore
        
        
        preserve
        mat drop _all 
        reghdfe `yvar' `int_leads' `int_lags' int_lead1 if inrange(exposure ,`p50', `p75'), absorb(`fes') vce(cluster athr_id)
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
        gen lb = b - 1.96*se
        gen rel = -5 if _n == 1
        replace rel = rel[_n-1]+1 if _n > 1
        replace rel = rel + 1 if rel >= -1 
        replace rel = -1 if rel == `abs_lag' + 1
        gen year = rel + 2014
        hashsort rel
        tw rcap ub lb rel if rel != -1 , lcolor(ebblue%70) msize(vsmall) || scatter b rel, mcolor(ebblue) xlab(-5(1)5, labsize(vsmall)) xtitle("Relative Year", size(small)) ytitle("`var_name'", size(small)) ylab(, labsize(vsmall)) yline(0, lcolor(gs10) lpattern(solid)) xline(-0.5 , lcolor(gs12) lpattern(dash))  legend(off)
        graph export ../output/figures/es_`yvar'_q3.pdf, replace
        save ../temp/es_`yvar'_q3, replace
        restore
        
        
        preserve
        mat drop _all 
        reghdfe `yvar' `int_leads' `int_lags' int_lead1 if inrange(exposure ,`p75', `max'), absorb(`fes') vce(cluster athr_id)
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
        gen lb = b - 1.96*se
        gen rel = -5 if _n == 1
        replace rel = rel[_n-1]+1 if _n > 1
        replace rel = rel + 1 if rel >= -1 
        replace rel = -1 if rel == `abs_lag' + 1
        gen year = rel + 2014
        hashsort rel
        tw rcap ub lb rel if rel != -1 , lcolor(ebblue%70) msize(vsmall) || scatter b rel, mcolor(ebblue) xlab(-5(1)5, labsize(vsmall)) xtitle("Relative Year", size(small)) ytitle("`var_name'", size(small)) ylab(, labsize(vsmall)) yline(0, lcolor(gs10) lpattern(solid)) xline(-0.5 , lcolor(gs12) lpattern(dash))  legend(off)
        graph export ../output/figures/es_`yvar'_q4.pdf, replace
        save ../temp/es_`yvar'_q4, replace
        restore
        
        preserve
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
           xlab(-5(1)5, labsize(small)) ylab(#8, labsize(vsmall)) ///                         
              yline(0, lcolor(black) lpattern(solid)) ///                                               
              legend(on order(2 "Q1 Exposed (Post Period Avg: `q1_mean')" 4 "Q2 Exposed (Post Period Avg: `q2_mean')" 6 "Q3 Exposed (Post Period Avg: `q3_mean')" 8 "Q4 Exposed (Post Period Avg: `q4_mean')") pos(11) ring(0) size(small) region(fcolor(none))) xtitle("Relative Year", size(small)) ytitle("`var_name'", size(small)) plotregion(margin(sides))
        graph export ../output/figures/es_`yvar'_split.pdf, replace     
        restore
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
