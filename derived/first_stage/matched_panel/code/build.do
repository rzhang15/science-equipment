set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main   
   merge_matched
end

program merge_matched
    // get xw of matched mkts
    import delimited ../external/matched/match_pairs.csv, clear varn(1) 
    rename treated_market category
    save ../output/matched_pairs, replace
    preserve
    gcontract category
    drop _freq
    save ../output/matched_mkts, replace
    restore
    gcontract control_market 
    drop _freq
    rename control_market category
    save ../output/matched_controls, replace

    // create matched mkt-year panel
    use ../external/samp/category_yr_tfidf, clear
    merge m:1 category using ../output/matched_mkts, assert(1 3) keep(1 3)
    drop if treated == 1 & _merge == 1
    drop _merge
    merge m:1 category using ../output/matched_controls, assert(1 3) keep(1 3)
    drop if treated == 0 & _merge == 1 
    drop _merge
    merge m:1 category using ../external/samp/category_hhi_tfidf, assert(2 3) keep(3) nogen
    foreach var in avg_log_price avg_log_qty avg_log_spend  {
        gen trt_`var' = `var' if treated == 1
        gen ctrl_`var' = `var' if treated == 0
    }
    save ../output/matched_category_panel , replace
    gcontract  category spend_2013
    drop _freq
    save ../output/spend_xw, replace
    
    // create matched uni-mkt-year panel
    use ../external/samp/uni_category_yr_tfidf, clear
    merge m:1 category using ../output/matched_mkts, assert(1  3) keep(1 3)
    drop if treated == 1 & _merge == 1
    drop _merge
    merge m:1 category using ../output/matched_controls, assert(1 3) keep(1 3)
    drop if treated == 0 & _merge == 1 
    drop _merge
    merge m:1 category using ../external/samp/category_hhi_tfidf, assert(2 3) keep(3) nogen
    foreach var in avg_log_price avg_log_qty avg_log_spend  {
        gen trt_`var' = `var' if treated == 1
        gen ctrl_`var' = `var' if treated == 0
    }
    save ../output/matched_uni_category_panel , replace
end
main
