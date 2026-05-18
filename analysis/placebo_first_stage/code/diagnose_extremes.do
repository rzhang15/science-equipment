set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main
    build_diagnostics
end

program build_diagnostics
    // Build per-category diagnostics for the 20 most extreme placebo coefficients.
    // Output: ../output/extreme_placebo_diagnostics.csv

    // 1. Collapse placebo coefs to one row per category (mean, sd, n_iters)
    use ../output/did_coefs_placebo, clear
    gcollapse (mean) mean_b = b (sd) sd_b = b (count) n_iters_treated = b, by(category)

    // 2. Tag the 20 categories of interest (top 10 + bottom 10 by mean_b)
    gsort -mean_b
    gen rank_high = _n
    gsort mean_b
    gen rank_low = _n
    gen flagged_top = rank_high <= 10
    gen flagged_bottom = rank_low <= 10
    gen flagged = flagged_top | flagged_bottom

    tempfile coefs
    save `coefs'

    // 3. Compute pre-trend slope and post-trend delta from the AGGREGATE panel
    //    (category × year, weighted across unis). Mirrors match_placebo.R:49-59.
    use ../../../derived/first_stage/make_mkt_panel/output/category_yr_tfidf.dta, clear

    // Pre-trend slope: regression of avg_log_price on year, 2010-2013
    preserve
    keep if year <= 2013
    gen year_c = year - 2012
    statsby pretrend_slope = _b[year_c], by(category) clear: regress avg_log_price year_c
    tempfile slopes
    save `slopes'
    restore

    // Post-2014 delta: mean log_raw_price 2015-2017 minus mean 2011-2013
    preserve
    gen pre_block  = inrange(year, 2011, 2013)
    gen post_block = inrange(year, 2015, 2017)
    keep if pre_block | post_block
    gcollapse (mean) log_raw_price [aw=spend_2013], by(category pre_block post_block)
    gen which = "pre" if pre_block == 1
    replace which = "post" if post_block == 1
    keep category log_raw_price which
    greshape wide log_raw_price, i(category) j(which) string
    gen posttrend_delta = log_raw_pricepost - log_raw_pricepre
    keep category posttrend_delta
    tempfile deltas
    save `deltas'
    restore

    // Category-level metadata: support/precision/recall, total spend, treated, bad_control
    use ../../../derived/first_stage/make_mkt_panel/output/category_yr_tfidf.dta, clear
    gcollapse (firstnm) support precision recall treated tier1 tier2 tier3 spend_2013 ///
              (sum) total_spend = raw_spend total_obs_cnt = obs_cnt, by(category)
    merge 1:1 category using `slopes',  nogen
    merge 1:1 category using `deltas',  nogen

    // 4. Per-category n_unis from the uni panel
    preserve
    use ../../../derived/first_stage/make_mkt_panel/output/uni_category_yr_tfidf.dta, clear
    gcollapse (firstnm) anything = treated, by(category uni_id)
    gcollapse (count) n_unis = anything, by(category)
    tempfile unicount
    save `unicount'
    restore
    merge 1:1 category using `unicount', nogen

    // 5. Bad-control flag from the documentation CSV
    preserve
    import delimited using ../../../derived/first_stage/select_categories/output/bad_control_documentation.csv, clear stringcols(_all) varnames(1)
    keep category bad_control bad_control_reason
    tempfile bc
    save `bc'
    restore
    merge 1:1 category using `bc', nogen keep(1 3)
    replace bad_control = "0" if bad_control == ""

    // 6. Sibling flag: count of OTHER categories sharing same " - " prefix
    gen has_dash = strpos(category, " - ") > 0
    gen prefix = ""
    qui replace prefix = substr(category, 1, strpos(category, " - ") - 1) if has_dash == 1
    bys prefix: gen n_in_prefix = _N if prefix != ""
    gen sibling_within_pool = (n_in_prefix - 1) if prefix != ""
    replace sibling_within_pool = 0 if mi(sibling_within_pool)
    drop has_dash n_in_prefix prefix

    // 7. Merge placebo coefs back
    merge 1:1 category using `coefs', keep(2 3) nogen
    keep if flagged == 1

    // 8. Format and export
    gsort -mean_b
    order category mean_b sd_b n_iters_treated total_spend total_obs_cnt n_unis ///
          support precision recall treated bad_control bad_control_reason ///
          pretrend_slope posttrend_delta sibling_within_pool flagged_top flagged_bottom

    label var mean_b           "Mean placebo DiD coef across iters"
    label var sd_b             "SD of placebo DiD coef across iters"
    label var n_iters_treated  "# placebo iters this cat drew treatment"
    label var total_spend      "Total raw spend across all years/unis"
    label var total_obs_cnt    "Total transaction count"
    label var n_unis           "# distinct universities ever observing cat"
    label var support          "Classifier training support"
    label var precision        "Classifier precision"
    label var recall           "Classifier recall"
    label var treated          "Real-treated indicator (should be 0 for all)"
    label var bad_control      "Already flagged as bad control (CSV)"
    label var pretrend_slope   "Slope of avg_log_price on year, 2010-2013"
    label var posttrend_delta  "Mean log_raw_price 2015-17 minus 2011-13"
    label var sibling_within_pool "# other cats sharing same ' - ' prefix"

    list category mean_b sd_b n_iters_treated support precision recall total_obs_cnt n_unis ///
         pretrend_slope posttrend_delta sibling_within_pool, sep(0) noobs abbrev(40)

    export delimited using ../output/extreme_placebo_diagnostics.csv, replace
end

main
