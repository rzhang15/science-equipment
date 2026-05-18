set more off
clear all
capture log close
program drop _all
log using diag_preperiod_qty_spend4.log, replace

* ------------------------------------------------------------------
* Drill into us fbs item-level data
* ------------------------------------------------------------------

local susp_cats `" "us fbs" "nitrocellulose blotting membranes" "column-based dna plasmid miniprep" "nucleic acid gel stains" "phosphate-buffered saline (pbs) buffer" "'

foreach c of local susp_cats {
    di " "
    di "=================================================================="
    di "CATEGORY: `c'"
    di "=================================================================="

    * (a) year-level summary
    use ../external/samp/full_item_level_tfidf, clear
    keep if treated == 1 & category == "`c'"
    di "  -- (a) Year-level summary --"
    tabstat raw_qty raw_spend , by(year) stat(sum mean N) format(%12.2f)

    * (b) supplier x year qty totals - top 15 by 2010 qty
    use ../external/samp/full_item_level_tfidf, clear
    keep if treated == 1 & category == "`c'"
    keep if inlist(year, 2010, 2011, 2013, 2017)
    collapse (sum) raw_qty raw_spend (count) n_obs = raw_qty, by(suppliername year)
    reshape wide raw_qty raw_spend n_obs, i(suppliername) j(year)
    foreach v of varlist raw_qty* raw_spend* n_obs* {
        replace `v' = 0 if mi(`v')
    }
    gsort -raw_qty2010
    di " "
    di "  -- (b) Top suppliers by 2010 qty (qty / spend / N obs by year) --"
    list suppliername raw_qty2010 raw_qty2011 raw_qty2013 raw_qty2017 ///
        n_obs2010 n_obs2011 n_obs2013 n_obs2017 in 1/12, noobs sep(0) ab(15)

    * (c) top 20 items by spend in 2010-2011
    use ../external/samp/full_item_level_tfidf, clear
    keep if treated == 1 & category == "`c'"
    keep if inlist(year, 2010, 2011)
    gsort -raw_spend
    di " "
    di "  -- (c) Top 20 items by spend in 2010-2011 --"
    list year suppliername agencyname clean_desc raw_qty raw_price raw_spend similarity_score in 1/20, noobs sep(0) ab(40)

    * (d) top 20 items by qty in 2010-2011
    use ../external/samp/full_item_level_tfidf, clear
    keep if treated == 1 & category == "`c'"
    keep if inlist(year, 2010, 2011)
    gsort -raw_qty
    di " "
    di "  -- (d) Top 20 items by qty in 2010-2011 --"
    list year suppliername agencyname clean_desc raw_qty raw_price raw_spend similarity_score in 1/20, noobs sep(0) ab(40)

    * (e) drop top-N obs by raw_qty in 2010-2011 and measure impact on mean log_qty[2010] - mean log_qty[2013]
    di " "
    di "  -- (e) Drop top-N pre items, recompute mean(log_qty[2010]) - mean(log_qty[2013]) --"
    foreach n of numlist 0 1 5 10 20 50 100 {
        use ../external/samp/full_item_level_tfidf, clear
        qui keep if treated == 1 & category == "`c'"
        qui gen ln_q = ln(raw_qty)
        qui gsort year -raw_qty
        qui bys year: gen rk = _n
        qui drop if inlist(year, 2010, 2011) & rk <= `n'
        qui sum ln_q if year == 2013
        local m2013 = r(mean)
        qui sum ln_q if year == 2010
        local d2010 = r(mean) - `m2013'
        qui sum ln_q if year == 2011
        local d2011 = r(mean) - `m2013'
        di as txt "    n_dropped = " %3.0f `n' "   d_log_qty[2010] = " %7.4f `d2010' "   d_log_qty[2011] = " %7.4f `d2011'
    }
}

log close
