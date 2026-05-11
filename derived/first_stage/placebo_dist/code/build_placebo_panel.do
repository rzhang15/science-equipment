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
    // pairs xw built from placebo match output (now keyed on iter)
    import delimited ../output/placebo_match_pairs.csv, clear varn(1)
    rename treated_market category
    save ../output/placebo_matched_pairs, replace

    preserve
    gcontract iter category
    drop _freq
    save ../output/placebo_matched_mkts, replace
    restore

    gcontract iter control_market
    drop _freq
    rename control_market category
    save ../output/placebo_matched_controls, replace
end

program build_category_panel
    use ../output/placebo_matched_mkts, clear
    qui sum iter
    local n_iter = r(max)

    tempfile stacked mkts_i ctrls_i
    forvalues i = 1/`n_iter' {
        di "===== build_category_panel iter `i' / `n_iter' ====="
        use ../output/placebo_matched_mkts, clear
        keep if iter == `i'
        keep category
        save `mkts_i', replace

        use ../output/placebo_matched_controls, clear
        keep if iter == `i'
        keep category
        duplicates drop category, force
        save `ctrls_i', replace

        use ../external/samp/category_yr_tfidf, clear
        drop if treated == 1
        drop treated
        merge m:1 category using `mkts_i'
        gen placebo_treated = (_merge == 3)
        drop _merge
        merge m:1 category using `ctrls_i', keep(1 3)
        gen placebo_control = (_merge == 3)
        drop _merge
        keep if placebo_treated == 1 | placebo_control == 1
        rename placebo_treated treated
        drop placebo_control
        foreach var in avg_log_price log_raw_price log_raw_qty log_raw_spend {
            gen trt_`var'  = `var' if treated == 1
            gen ctrl_`var' = `var' if treated == 0
        }
        gen iter = `i'
        if `i' > 1 append using `stacked'
        save `stacked', replace
    }
    use `stacked', clear
    save ../output/placebo_matched_category_panel, replace
end

program build_uni_category_panel
    use ../output/placebo_matched_mkts, clear
    qui sum iter
    local n_iter = r(max)

    tempfile stacked mkts_i ctrls_i
    forvalues i = 1/`n_iter' {
        di "===== build_uni_category_panel iter `i' / `n_iter' ====="
        use ../output/placebo_matched_mkts, clear
        keep if iter == `i'
        keep category
        save `mkts_i', replace

        use ../output/placebo_matched_controls, clear
        keep if iter == `i'
        keep category
        duplicates drop category, force
        save `ctrls_i', replace

        use ../external/samp/uni_category_yr_tfidf, clear
        drop if treated == 1
        drop treated
        merge m:1 category using `mkts_i'
        gen placebo_treated = (_merge == 3)
        drop _merge
        merge m:1 category using `ctrls_i', keep(1 3)
        gen placebo_control = (_merge == 3)
        drop _merge
        keep if placebo_treated == 1 | placebo_control == 1
        rename placebo_treated treated
        drop placebo_control
        foreach var in avg_log_price log_raw_price log_raw_qty log_raw_spend {
            gen trt_`var'  = `var' if treated == 1
            gen ctrl_`var' = `var' if treated == 0
        }
        gen iter = `i'
        if `i' > 1 append using `stacked'
        save `stacked', replace
    }
    use `stacked', clear
    save ../output/placebo_matched_uni_category_panel, replace
end

main
