set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main
    foreach s in "" "_all3" {
        merge_matched, suffix(`s')
    }
end

program merge_matched
    syntax, [suffix(string)]
    import delimited ../external/matched/match_pairs`suffix'.csv, clear varn(1) 
    rename treated_market category
    save ../output/matched_pairs`suffix', replace
    preserve
    gcontract category
    drop _freq
    save ../output/matched_mkts`suffix', replace
    restore
    gcontract control_market 
    drop _freq
    rename control_market category
    save ../output/matched_controls`suffix', replace

    use ../external/samp/category_yr_tfidf`suffix', clear
    merge m:1 category using ../output/matched_mkts`suffix', assert(1 3) keep(1 3)
    drop if treated == 1 & _merge == 1
    drop _merge
    merge m:1 category using ../output/matched_controls`suffix', assert(1 3) keep(1 3)
    drop if treated == 0 & _merge == 1 
    drop _merge
    merge m:1 category using ../external/samp/category_hhi_tfidf`suffix', assert(2 3) keep(3) nogen
    foreach var in avg_log_price log_raw_price log_raw_qty log_raw_spend {
        gen trt_`var' = `var' if treated == 1
        gen ctrl_`var' = `var' if treated == 0
    }
    save ../output/matched_category_panel`suffix' , replace
    gcontract  category spend_2013
    drop _freq
    save ../output/spend_xw`suffix', replace

    use ../external/samp/category_yr_tfidf`suffix', clear
    keep if treated == 1
    glevelsof category, local(treated_cats)
    foreach c in `treated_cats' {
        preserve
        keep if category == "`c'"
        save "../temp/cat_`c'`suffix'", replace
        use ../output/matched_pairs`suffix', clear
        keep if category == "`c'"
        contract control_market
        drop _freq
        rename control_market category
        merge 1:m category using ../external/samp/category_yr_tfidf`suffix', assert(2 3) keep(3) nogen
        append using "../temp/cat_`c'`suffix'"
        gen experiment = "`c'"
        save "../output/cat_`c'`suffix'", replace
        restore
    }
    clear
    foreach c in `treated_cats' {
        cap append using "../output/cat_`c'`suffix'", force        
    }
    save ../output/stacked_matched_category_panel`suffix', replace
    
    use ../external/samp/uni_category_yr_tfidf`suffix', clear
    merge m:1 category using ../output/matched_mkts`suffix', assert(1  3) keep(1 3)
    drop if treated == 1 & _merge == 1
    drop _merge
    merge m:1 category using ../output/matched_controls`suffix', assert(1 3) keep(1 3)
    drop if treated == 0 & _merge == 1 
    drop _merge
    merge m:1 category using ../external/samp/category_hhi_tfidf`suffix', assert(2 3) keep(3) nogen
    foreach var in avg_log_price log_raw_price log_raw_qty log_raw_spend {
        gen trt_`var' = `var' if treated == 1
        gen ctrl_`var' = `var' if treated == 0
    }
    save ../output/matched_uni_category_panel`suffix' , replace

    use ../external/samp/uni_category_yr_tfidf`suffix', clear
    keep if treated == 1
    glevelsof category, local(treated_cats)
    foreach c in `treated_cats' {
        preserve
        keep if category == "`c'"
        save "../temp/uni_cat_`c'`suffix'", replace               
        use ../output/matched_pairs`suffix', clear
        keep if category == "`c'"
        contract control_market
        drop _freq          
        rename control_market category
        merge 1:m category using ../external/samp/uni_category_yr_tfidf`suffix', assert(2 3) keep(3) nogen
        append using "../temp/uni_cat_`c'`suffix'"
        gen experiment = "`c'"
        save "../output/uni_cat_`c'`suffix'", replace
        restore 
    }
    clear
    foreach c in `treated_cats' {
        append using "../output/uni_cat_`c'`suffix'", force
    }
    save ../output/stacked_matched_uni_category_panel`suffix', replace
end
main
