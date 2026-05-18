set more off
clear all
capture log close
program drop _all
log using diag_preperiod_qty_spend3.log, replace

* ------------------------------------------------------------------
* Third pass: drill into us fbs (and nitrocellulose) item-level data
* to find the specific items / suppliers driving the 2010-2011
* qty / spend bump.
* ------------------------------------------------------------------

local susp_cats `" "us fbs" "nitrocellulose blotting membranes" "column-based dna plasmid miniprep" "nucleic acid gel stains" "phosphate-buffered saline (pbs) buffer" "'

use ../external/samp/full_item_level_tfidf, clear
keep if treated == 1

foreach c of local susp_cats {
    preserve
    keep if category == "`c'"
    di " "
    di "=================================================================="
    di "CATEGORY: `c'"
    di "=================================================================="

    * (a) qty distribution by year
    di "  -- (a) Year-level summary --"
    tabstat raw_qty raw_spend , by(year) stat(sum N) format(%12.1f)
    di " "

    * (b) supplier-level shares by year (top 10)
    di "  -- (b) Supplier x year qty totals --"
    preserve
    collapse (sum) raw_qty raw_spend obs = obs_cnt, by(suppliername year)
    keep if inlist(year, 2010, 2011, 2013, 2017)
    reshape wide raw_qty raw_spend obs, i(suppliername) j(year)
    gen total = raw_qty2010 + raw_qty2011 + raw_qty2013 + raw_qty2017
    gsort -raw_qty2010
    list suppliername raw_qty2010 raw_qty2011 raw_qty2013 raw_qty2017 in 1/15, noobs sep(0) ab(30)
    restore

    * (c) top 20 by raw_spend in 2010-2011
    di " "
    di "  -- (c) Top 20 items by spend in 2010-2011 --"
    preserve
    keep if inlist(year, 2010, 2011)
    gsort -raw_spend
    list year suppliername agencyname clean_desc raw_qty raw_price raw_spend similarity_score in 1/20, noobs sep(0) ab(40)
    restore

    * (d) top 20 by raw_qty in 2010-2011
    di " "
    di "  -- (d) Top 20 items by qty in 2010-2011 --"
    preserve
    keep if inlist(year, 2010, 2011)
    gsort -raw_qty
    list year suppliername agencyname clean_desc raw_qty raw_price raw_spend similarity_score in 1/20, noobs sep(0) ab(40)
    restore

    * (e) drop the single biggest qty observation in 2010 and check the impact on 2010-vs-2013 mean log_qty
    di " "
    di "  -- (e) Effect of dropping top-N pre-period qty obs on mean log_qty[2010] - mean log_qty[2013] --"
    preserve
    gen ln_q = ln(raw_qty)
    foreach n of numlist 0 1 5 10 20 50 100 {
        qui {
            * make a copy where we drop top-N items by raw_qty in pre period
            preserve
            gsort year -raw_qty
            bys year: gen rk = _n
            drop if inlist(year, 2010, 2011) & rk <= `n'
            sum ln_q if year == 2013
            local m2013 = r(mean)
            sum ln_q if year == 2010
            local d2010 = r(mean) - `m2013'
            sum ln_q if year == 2011
            local d2011 = r(mean) - `m2013'
            restore
        }
        di as txt "    n_dropped = " %3.0f `n' "   d_log_qty[2010] = " %7.4f `d2010' "   d_log_qty[2011] = " %7.4f `d2011'
    }
    restore

    restore
}

log close
