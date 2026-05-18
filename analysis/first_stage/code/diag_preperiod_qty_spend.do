set more off
clear all
capture log close
program drop _all
log using diag_preperiod_qty_spend.log, replace

* ------------------------------------------------------------------
* Diagnose positive pre-period coefficients in qty / spend event study
* Suspicion: a specific item or supplier-order shows up only at the
* start of the pre-period in TREATED categories, inflating raw_qty
* / raw_spend in 2010-2012 and pulling -4 / -3 / -2 coefs positive.
* ------------------------------------------------------------------

* === Step 1: Identify treated categories with biggest pre-period bump
use ../external/merged/matched_uni_category_panel, clear
merge m:1 category using ../external/samp/category_hhi_tfidf, assert(1 2 3) keep(3) nogen
drop if delta_hhi <= -2000
gegen uni_mkt = group(uni_id mkt)
bys uni_mkt: egen min_year = min(year)
bys uni_mkt: egen max_year = max(year)
keep if min_year < 2014 & max_year > 2014

preserve
keep if treated == 1
collapse (sum) raw_qty raw_spend obs_cnt [aw=spend_2013], by(category year)
foreach v in raw_qty raw_spend obs_cnt {
    gen log_`v' = ln(`v')
    gen `v'_2013 = `v' if year == 2013
    bys category (`v'_2013): replace `v'_2013 = `v'_2013[_n-1] if mi(`v'_2013)
    gen pct_chg_`v' = (`v' - `v'_2013) / `v'_2013 * 100
}
keep category year pct_chg_* raw_qty raw_spend obs_cnt raw_qty_2013 raw_spend_2013
keep if inlist(year, 2010, 2011, 2012)
gsort -pct_chg_raw_qty year
di " "
di "==== TREATED CATEGORIES sorted by 2010 pct_chg_qty ===="
list category year raw_qty raw_qty_2013 pct_chg_raw_qty raw_spend raw_spend_2013 pct_chg_raw_spend if year == 2010, sep(0) noobs ab(30)
gsort -pct_chg_raw_spend year
di " "
di "==== TREATED CATEGORIES sorted by 2010 pct_chg_spend ===="
list category year raw_qty raw_qty_2013 pct_chg_raw_qty raw_spend raw_spend_2013 pct_chg_raw_spend if year == 2010, sep(0) noobs ab(30)
restore

* === Step 2: For top suspects, look at item-level data
use ../external/samp/full_item_level_tfidf, clear
keep if treated == 1
gen pre_yr = inlist(year, 2010, 2011)
gen mid_yr = inlist(year, 2012, 2013)
gen post_yr = inlist(year, 2015, 2016, 2017, 2018, 2019)
collapse (sum) raw_spend raw_qty obs = obs_cnt, by(category pre_yr mid_yr post_yr)
gen period = "pre" if pre_yr == 1
replace period = "mid" if mid_yr == 1
replace period = "post" if post_yr == 1
drop if mi(period)
drop pre_yr mid_yr post_yr
reshape wide raw_spend raw_qty obs, i(category) j(period) string
gen pct_chg_spend = (raw_spendpre/2 - raw_spendmid/2) / (raw_spendmid/2) * 100
gen pct_chg_qty   = (raw_qtypre/2 - raw_qtymid/2)   / (raw_qtymid/2)   * 100
gsort -pct_chg_spend
list category raw_spendpre raw_spendmid pct_chg_spend pct_chg_qty in 1/15, noobs sep(0) ab(30)
gsort -pct_chg_qty
list category raw_qtypre raw_qtymid pct_chg_qty pct_chg_spend in 1/15, noobs sep(0) ab(30)

* === Step 3: For top-3 suspect categories by pct_chg_spend, dump biggest pre-period items
gsort -pct_chg_spend
keep if _n <= 5
levelsof category, local(top_cats) clean
di "TOP SUSPECT CATEGORIES (by pre-period spend bump):"
foreach c in `top_cats' {
    di "  - `c'"
}

use ../external/samp/full_item_level_tfidf, clear
keep if treated == 1
gen pre_yr = inlist(year, 2010, 2011)
keep if pre_yr == 1
keep category clean_desc raw_price raw_qty raw_spend year suppliername agencyname similarity_score prediction_source
foreach c in `top_cats' {
    preserve
    keep if category == "`c'"
    gsort -raw_spend
    di " "
    di "========================================================"
    di "TOP 20 PRE-PERIOD ITEMS BY SPEND IN: `c'"
    di "========================================================"
    list year suppliername clean_desc raw_qty raw_price raw_spend similarity_score prediction_source in 1/20, noobs sep(0) ab(40)
    restore
}

* === Step 4: For top-3 suspect categories by pct_chg_qty, dump biggest pre-period qty items
use ../external/samp/full_item_level_tfidf, clear
keep if treated == 1
gen pre_yr = inlist(year, 2010, 2011)
gen mid_yr = inlist(year, 2012, 2013)
gen post_yr = inlist(year, 2015, 2016, 2017, 2018, 2019)
collapse (sum) raw_spend raw_qty obs = obs_cnt, by(category pre_yr mid_yr post_yr)
gen period = "pre" if pre_yr == 1
replace period = "mid" if mid_yr == 1
replace period = "post" if post_yr == 1
drop if mi(period)
drop pre_yr mid_yr post_yr
reshape wide raw_spend raw_qty obs, i(category) j(period) string
gen pct_chg_qty = (raw_qtypre/2 - raw_qtymid/2) / (raw_qtymid/2) * 100
gsort -pct_chg_qty
keep if _n <= 5
levelsof category, local(top_qty_cats) clean
di "TOP SUSPECT CATEGORIES (by pre-period QTY bump):"
foreach c in `top_qty_cats' {
    di "  - `c'"
}

use ../external/samp/full_item_level_tfidf, clear
keep if treated == 1
gen pre_yr = inlist(year, 2010, 2011)
keep if pre_yr == 1
foreach c in `top_qty_cats' {
    preserve
    keep if category == "`c'"
    gsort -raw_qty
    di " "
    di "========================================================"
    di "TOP 20 PRE-PERIOD ITEMS BY QTY IN: `c'"
    di "========================================================"
    list year suppliername clean_desc raw_qty raw_price raw_spend similarity_score prediction_source in 1/20, noobs sep(0) ab(40)
    restore
}

log close
