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
    raw_plots
    did
    event_study
end

program raw_plots
    use ../external/samp/mkt_yr, clear
    bys mkt: gen num_year = _N 
    keep if num_year == 9
    glevelsof mkt if treated == 1, local(categories)
    foreach var in avg_log_price log_tot_qty log_tot_spend  {
        gen trt_`var' = `var' if treated == 1
        gen ctrl_`var' = `var' if treated == 0
    }
    foreach c in `categories' {
        preserve
        qui keep if mkt == `c'  | treated == 0
        glevelsof prdct_ctgry if treated == 1, local(name)
        collapse (mean) avg_log_price log_tot_qty log_tot_spend, by(year treated)
        foreach var in avg_log_price log_tot_qty log_tot_spend  {
            gen trt_`var' = `var' if treated == 1
            gen ctrl_`var' = `var' if treated == 0
        }
        foreach var in avg_log_price log_tot_qty log_tot_spend  {
            if "`var'" == "avg_log_price" local yname "Avg. Log Price"
            if "`var'" == "log_tot_qty" local yname "Log Total Qty"
            if "`var'" == "log_tot_spend" local yname "Log Total spend"
            // normalize to 2013 
            qui sum trt_`var' if year == 2013 
            qui replace trt_`var' = trt_`var' - r(mean)
            qui sum ctrl_`var' if year == 2013 
            qui replace ctrl_`var' = ctrl_`var' - r(mean)
            qui tw connected trt_`var' year , lcolor(lavender) mcolor(lavender) || connected ctrl_`var' year , lcolor(dkorange%40) mcolor(dkorange%40) legend(on label(1 "Treated `var'") label(2 "Control `var'") ring(1) pos(6) rows(1) size(vsmall)) ytitle("`yname'", size(small)) ylabel(#6, labsize(small)) xlabel(2011(1)2019, labsize(small)) xtitle("Year", size(small)) title(`name', size(small))  tline(2014.5, lpattern(shortdash) lcolor(gs4%80))
            qui graph export "../output/figures/`var'_trends_mkt`c'.pdf", replace
        }
        restore
    }
end
program did
    use ../external/samp/mkt_yr, clear
    bys mkt: gen num_year = _N 
    keep if num_year == 9
    gen post = 0 
    replace post = 1 if year >= 2015
    gen posttreat = treated * post
    glevelsof mkt if treated == 1, local(mkts)
	foreach m in `mkts' {
		gen m_`m' = mkt == `m' 
        gen posttreat_`m'  = posttreat * m_`m'
        gen post_`m'  = post * m_`m'
        gen treat_`m'  = treated * m_`m'
        foreach var in avg_log_price {
            di "`m'"
            reghdfe `var' post treated posttreat if mkt == `m' | treated == 0, vce(robust)  noabsorb
        }
    }
end

program event_study
    use ../external/samp/mkt_yr, clear
    bys mkt: gen num_year = _N 
    keep if num_year == 9
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
    glevelsof mkt if treated == 1, local(mkts)
	foreach m in `mkts' {
        glevelsof prdct_ctgry if mkt == `m', local(name)
        foreach yvar in avg_log_price log_tot_qty log_tot_spend {
            if "`yvar'" == "avg_log_price" local yname "Avg. Log Price"
            if "`yvar'" == "log_tot_qty" local yname "Log Total Qty"
            if "`yvar'" == "log_tot_spend" local yname "Log Total spend"
            preserve
            mat drop _all 
            keep if mkt == `m' | treated == 0
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
            save ../output/es_`yvar'_mkt`m', replace
            tw rcap ub lb rel if rel != -1 , lcolor(gs7) msize(vsmall) || scatter b rel , mcolor(ebblue) xlab(-4(1)4, labsize(vsmall)) xtitle("Relative Year", size(small)) ytitle("`yname'", size(small)) title(`name', size(small)) yline(0, lcolor(gs10) lpattern(solid)) xline(-0.5, lcolor(purple%50) lpattern(dash)) legend(on order(- "Treatment Level Avg. in t = -1: `trt_mean'" "Control Level Avg. in t = -1: `ctrl_mean'") pos(6) rows(2))
            graph export "../output/figures/es_`yvar'_mkt`m'.pdf", replace
            restore
        }
    }
end
**
main
