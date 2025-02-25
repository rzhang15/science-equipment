set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 18
set maxvar 120000, perm 
global dropbox_dir "~/dropbox (harvard university)/scientific equipment"

program main   
    foreach m in mkt broad_mkt {
        qui raw_plots, classification(`m')
        did, classification(`m')
        qui event_study, classification(`m')
    }
end

program raw_plots
    syntax, classification(str)
    use ../external/samp/`classification'_yr, clear
    gen has_trt_2013 = year == 2013  & !mi(merged_avg_log_price)
    gen has_ctrl_2013 = year == 2013  & !mi(rival_avg_log_price)
    bys `classification': egen has_2013 = max(has_trt_2013*has_ctrl_2013)
    keep if has_2013 == 1
    glevelsof `classification', local(categories)
    foreach c in `categories' {
        preserve
        qui keep if `classification' == `c' 
        if "`classification'" == "mkt" { 
            glevelsof prdct_ctgry , local(name)
        }
        if "`classification'" == "broad_mkt" { 
            glevelsof broad_ctgry , local(name)
        }
        qui hashsort `classification' year
        foreach var in avg_log_price log_tot_qty log_tot_spend  {
            if "`var'" == "avg_log_price" local yname "Avg. Log Price"
            if "`var'" == "log_tot_qty" local yname "Log Total Qty"
            if "`var'" == "log_tot_spend" local yname "Log Total spend"
            // normalize to 2013 
            qui sum merged_`var' if year == 2013
            qui replace merged_`var' = merged_`var' - r(mean)
            qui sum rival_`var' if year == 2013
            qui replace rival_`var' = rival_`var' - r(mean)
            qui sum `var' if year == 2013
            qui replace `var' = `var' - r(mean)
            qui tw connected merged_`var' year, lcolor(lavender) mcolor(lavender) || connected rival_`var' year, lcolor(dkorange%40) mcolor(dkorange%40) legend(on label(1 "Merged entity `var'") label(2 "Rival `var'") ring(1) pos(6) rows(1) size(vsmall)) ytitle("`yname'", size(small)) ylabel(#6, labsize(small)) xlabel(2011(1)2019, labsize(small)) xtitle("Year", size(small)) title(`name', size(small))  tline(2014.5, lpattern(shortdash) lcolor(gs4%80))
            qui graph export "../output/figures/`var'_trends_`classification'`c'.pdf", replace
        }
        restore
    }
end
program did
    syntax, classification(str)
    use ../external/samp/sku_`classification'_yr, clear
    gen post = 0 
    replace post = 1 if year >= 2015
    gen posttreat = treated * post
    glevelsof `classification', local(mkts)
	foreach m in `mkts' {
		gen m_`m' = `classification' == `m' 
        gen posttreat_`m'  = posttreat * m_`m'
        gen post_`m'  = post * m_`m'
        gen treat_`m'  = treated * m_`m'
        foreach var in avg_log_price {
            di "`m'"
            reghdfe `var' post treated posttreat if `classification' == `m', vce(robust)  noabsorb
        }
    }
end

program event_study
    syntax, classification(str)
    use ../external/samp/sku_`classification'_yr, clear
    gen rel = year - 2015
    forval i = 1/4 {
        gen lag`i' = 1 if rel == `i'
        gen lead`i' = 1 if rel == -`i'
    }
    gen lag0 = 1 if rel ==  0
    ds lead* lag*
    foreach var in `r(varlist)' {
        replace `var' = 0 if mi(`var')
    }
    local leads 
    local lags
    forval i = 2/4 {
        local leads lead`i' `leads'
    }
    forval i = 0/4 {
        local lags `lags' lag`i'
    }
    glevelsof `classification', local(mkts)
	foreach m in `mkts' {
        if "`classification'" == "mkt" { 
            glevelsof prdct_ctgry if `classification' == `m', local(name)
        }
        if "`classification'" == "broad_mkt" { 
            glevelsof broad_ctgry if `classification' == `m', local(name)
        }
        foreach yvar in avg_log_price log_tot_qty log_tot_spend {
            if "`yvar'" == "avg_log_price" local yname "Avg. Log Price"
            if "`yvar'" == "log_tot_qty" local yname "Log Total Qty"
            if "`yvar'" == "log_tot_spend" local yname "Log Total spend"
            preserve
            mat drop _all 
            keep if `classification' == `m'
            qui sum `yvar' if treated == 1 & rel == -1 
            local trt_mean : dis %4.3f r(mean)
            qui sum `yvar' if treated == 0 & rel == -1 
            local ctrl_mean : dis %4.3f r(mean)
            reghdfe  `yvar' `leads' `lags' lead1, vce(robust) noabsorb
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
            gen ub = b + 1.96*se
            gen lb = b - 1.96*se
            gen rel = -4 if _n == 1
            replace rel = rel[_n-1]+1 if _n > 1
            replace rel = rel + 1 if rel >= -1
            replace rel = -1 if rel == 4 + 1
            save ../output/es_`yvar'_`classification'`m', replace
            tw rcap ub lb rel if rel != -1 , lcolor(gs7) msize(vsmall) || scatter b rel , mcolor(ebblue) xlab(-4(1)4, labsize(vsmall)) xtitle("Relative Year", size(small)) ytitle("`yname'", size(small)) title(`name', size(small)) yline(0, lcolor(gs10) lpattern(solid)) xline(-0.5, lcolor(purple%50) lpattern(dash)) legend(on order(- "Treatment Level Avg. in t = -1: `trt_mean'" "Control Level Avg. in t = -1: `ctrl_mean'") pos(6) rows(2))
            graph export "../output/figures/es_`yvar'_`classification'`m'.pdf", replace
            restore
        }
    }
end
**
main
