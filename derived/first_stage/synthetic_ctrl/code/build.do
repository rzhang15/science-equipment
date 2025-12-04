set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17


program main
 synthetic_ctrl
end


program synthetic_ctrl
    use "../external/samp/category_yr_tfidf.dta", clear
    preserve
    keep if year <= 2013
    gen coef_log_price = .
    gen coef_log_spend = .
    levelsof mkt, local(markets)
    foreach m in `markets' {
        reg avg_log_price year [aw=spend_2013] if mkt == `m'
        replace coef_log_price = _b[year] if mkt == `m'
        reg avg_log_spend year [w=spend_2013] if mkt == `m'
        replace coef_log_spend = _b[year] if mkt == `m'
    }
    gcontract mkt coef_log_price coef_log_spend
    drop _freq
    save ../temp/lin_time_trends, replace
    restore
    merge m:1 mkt using ../temp/lin_time_trends, assert(1 3) keep(3) nogen
    tsset mkt year
    glevelsof mkt if treated == 1, local(trt_mkts)
    foreach m in `trt_mkts' {
        preserve
        keep if treated == 0 | mkt == `m'
        gen posttreat = treated * year >=2014
        synth_runner avg_log_price coef_log_spend, d(posttreat) gen_vars trends
        effect_graphs, scaled 
        graph export ../output/figures/synth_price_`m'.pdf, replace
        restore
    }    
end

main