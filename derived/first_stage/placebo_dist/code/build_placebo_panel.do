set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main
    build_pairs_xw
    build_category_panel
    build_uni_category_panel
end

program build_pairs_xw
    // pairs xw built from placebo match output
    import delimited ../output/placebo_match_pairs.csv, clear varn(1)
    rename treated_market category
    save ../output/placebo_matched_pairs, replace

    preserve
    gcontract category
    drop _freq
    save ../output/placebo_matched_mkts, replace
    restore

    gcontract control_market
    drop _freq
    rename control_market category
    save ../output/placebo_matched_controls, replace
end

program build_category_panel
    use ../external/samp/category_yr_tfidf, clear
    // drop the real treated -- placebo pool is original controls only
    drop if treated == 1
    // assign placebo treated flag from match output
    drop treated
    merge m:1 category using ../output/placebo_matched_mkts
    gen placebo_treated = (_merge == 3)
    drop _merge
    merge m:1 category using ../output/placebo_matched_controls, keep(1 3)
    gen placebo_control = (_merge == 3)
    drop _merge
    keep if placebo_treated == 1 | placebo_control == 1
    rename placebo_treated treated
    drop placebo_control
    foreach var in avg_log_price log_raw_price log_raw_qty log_raw_spend {
        gen trt_`var' = `var' if treated == 1
        gen ctrl_`var' = `var' if treated == 0
    }
    save ../output/placebo_matched_category_panel, replace
end

program build_uni_category_panel
    use ../external/samp/uni_category_yr_tfidf, clear
    drop if treated == 1
    drop treated
    merge m:1 category using ../output/placebo_matched_mkts
    gen placebo_treated = (_merge == 3)
    drop _merge
    merge m:1 category using ../output/placebo_matched_controls, keep(1 3)
    gen placebo_control = (_merge == 3)
    drop _merge
    keep if placebo_treated == 1 | placebo_control == 1
    rename placebo_treated treated
    drop placebo_control
    foreach var in avg_log_price log_raw_price log_raw_qty log_raw_spend {
        gen trt_`var' = `var' if treated == 1
        gen ctrl_`var' = `var' if treated == 0
    }
    save ../output/placebo_matched_uni_category_panel, replace
end

main
