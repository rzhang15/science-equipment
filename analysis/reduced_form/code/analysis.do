set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17
set maxvar 120000, perm 
global dropbox_dir "~/dropbox (harvard university)/scientific equipment"

program main   
    event_study
    *output_tables
end

program event_study
    use ../external/samp/athr_panel_full_year,clear 
    gen trt = exposure == 2
    gen post = year >= 2014
    gen posttreat = post*trt
    gen lr = inrange(year, 2019,2023) 
    gen sr = inrange(year, 2014,2018)
    gen posttreatlr = lr * posttreat
    gen posttreatsr = sr * posttreat
    gen rel = year - 2014 if trt == 1 
    forval i = 1/14 {
        gen lag`i' = 1 if rel == `i'
        gen lead`i' = 1 if rel == -`i'
    }
    drop lag10 lag11 lag12 lag13 lag14 
    gen lag0 = 1 if rel ==  0
    ds lead* lag*
    foreach var in `r(varlist)' {
        replace `var' = 0 if mi(`var')
    }
    local leads 
    local lags
    forval i = 2/14 {
        local leads lead`i' `leads'
    }
    forval i = 0/9 {
        local lags `lags' lag`i'
    }
    foreach yvar in cite_affl_wt affl_wt impact_cite_affl_wt ppr_cnt {
        preserve
        mat drop _all 
        reghdfe `yvar' posttreatlr posttreatsr , absorb(athr_id year)  cluster(athr_id)
        mat did_`yvar' = (_b[posttreatlr] , _se[posttreatlr]) \ (_b[posttreatsr], _se[posttreatsr]) \ (_cons, .)

        qui sum `yvar' if trt == 1 & rel == -1 
        local trt_mean : dis %4.3f r(mean)
        qui sum `yvar' if trt == 0 & year == 2013 
        local ctrl_mean : dis %4.3f r(mean)
        reghdfe  `yvar' `leads' `lags' lead1, cluster(athr_id) absorb(year athr_id)
        foreach var in `leads' `lags' lead1 {
            mat row  = _b[`var'], _se[`var']
            if "`var'" == "lead1" {
                mat row = 0,0
            }
            mat es = nullmat(es) \ row
        }
        svmat es
        keep es1 es2
        rename (es1 es2) (b se)
        drop if mi(b)
        gen id = _n 
        gen tot = _N
        drop if b == 0 & id != tot
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        gen rel = -14 if _n == 1
        replace rel = rel[_n-1]+1 if _n > 1
        replace rel = rel + 1 if rel >= -1
        replace rel = -1 if rel == 9 + 1
        save ../output/es_`yvar', replace
        tw rcap ub lb rel if rel != -1 , lcolor(gs7) msize(vsmall) || scatter b rel , mcolor(ebblue) ylab(#10, labsize(vsmall)) xlab(-14(1)9, labsize(vsmall)) ytitle("Effective Publications", size(small)) xtitle("Relative Year", size(small)) ytitle("`yname'", size(small)) yline(0, lcolor(gs10) lpattern(solid)) xline(-0.5, lcolor(purple%50) lpattern(dash)) legend(on order(- "Treated Level Avg. in t = -1: `trt_mean'" "Control Level Avg. in t = -1: `ctrl_mean'") pos(6) rows(2))
        graph export "../output/figures/es_`yvar'.pdf", replace
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
