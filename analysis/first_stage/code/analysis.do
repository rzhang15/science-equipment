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
end

program raw_plots
    use ../output/mkt_yr, clear
    drop if year >= 2020
    drop if mi(merged_price)
    bys mkt: gen tot_yrs = _N 
    keep if tot_yrs >= 7  
    glevelsof prdct_ctgry, local(categories)
    foreach c in `categories' {
        preserve
        keep if prdct_ctgry == "`c'" 
        qui sum mkt
        local suf = r(mean)
        hashsort mkt year
        foreach var in price qty spend raw_price raw_qty raw_spend {
            // normalize to 2013 
            qui sum merged_`var' if year == 2013
            replace merged_`var' = merged_`var' - r(mean)
            qui sum rival_`var' if year == 2013
            replace rival_`var' = rival_`var' - r(mean)
            qui sum `var' if year == 2013
            replace `var' = `var' - r(mean)
            tw connected merged_`var' year, lcolor(lavender) mcolor(lavender) || connected rival_`var' year, lcolor(dkorange%40) mcolor(dkorange%40) || connected `var' year, lcolor(ebblue%50) mcolor(ebblue%50) legend(on label(1 "Merged entity `var'") label(2 "Rival `var'") label(3 "Overall `var'") ring(1) pos(6) rows(1) size(vsmall)) ytitle("Log `var'", size(small)) ylabel(#6, labsize(small)) xlabel(2011(2)2024, labsize(small)) xtitle("Year", size(small)) title("`c'", size(small))  tline(2014, lpattern(shortdash) lcolor(gs4%80))
            graph export "../output/figures/`var'_trends_mkt`suf'.pdf", replace
        }
        restore
    }
end

**
main
