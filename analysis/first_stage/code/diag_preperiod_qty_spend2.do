set more off
clear all
capture log close
program drop _all
log using diag_preperiod_qty_spend2.log, replace

* ------------------------------------------------------------------
* Second pass: contribution-weighted analysis.
* Goal: identify TREATED categories whose 2010-2012 raw_qty/raw_spend
* is large enough (after weight = spend_2013) to drive the +0.16 ES
* coefficient at rel=-4 and rel=-3 for the event study.
* Then drill into specific items in those categories.
* ------------------------------------------------------------------

use ../external/merged/matched_uni_category_panel, clear
merge m:1 category using ../external/samp/category_hhi_tfidf, assert(1 2 3) keep(3) nogen
drop if delta_hhi <= -2000
gegen uni_mkt = group(uni_id mkt)
bys uni_mkt: egen min_year = min(year)
bys uni_mkt: egen max_year = max(year)
keep if min_year < 2014 & max_year > 2014

* === Step 1: For TREATED vs CONTROL, compute weighted mean log_raw_qty / log_raw_spend by year
preserve
collapse (mean) log_raw_qty log_raw_spend [aw=spend_2013], by(year treated)
gen treated_lbl = "trt" if treated == 1
replace treated_lbl = "ctl" if treated == 0
keep year treated_lbl log_raw_qty log_raw_spend
reshape wide log_raw_qty log_raw_spend, i(year) j(treated_lbl) string
gen diff_qty = log_raw_qtytrt - log_raw_qtyctl
gen diff_spend = log_raw_spendtrt - log_raw_spendctl
sum diff_qty if year == 2013
qui replace diff_qty = diff_qty - r(mean)
sum diff_spend if year == 2013
qui replace diff_spend = diff_spend - r(mean)
list year diff_qty diff_spend, sep(0) noobs
restore

* === Step 2: For each treated category, compute the difference
*     (mean log_raw_qty in 2010 - mean log_raw_qty in 2013) * weight
*     where weight = spend_2013 / sum(spend_2013) among treated.
* Same for control. Then trt minus ctrl contribution to coef.
preserve
keep if inlist(year, 2010, 2011, 2012, 2013)
collapse (mean) log_raw_qty log_raw_spend (firstnm) spend_2013 treated, by(category year)
reshape wide log_raw_qty log_raw_spend, i(category treated) j(year)
gen d_log_qty_10 = log_raw_qty2010 - log_raw_qty2013
gen d_log_qty_11 = log_raw_qty2011 - log_raw_qty2013
gen d_log_qty_12 = log_raw_qty2012 - log_raw_qty2013
gen d_log_spend_10 = log_raw_spend2010 - log_raw_spend2013
gen d_log_spend_11 = log_raw_spend2011 - log_raw_spend2013
gen d_log_spend_12 = log_raw_spend2012 - log_raw_spend2013

* normalize weights within treated/control
bys treated: egen tot_wt = total(spend_2013)
gen wt = spend_2013 / tot_wt
foreach v in d_log_qty_10 d_log_qty_11 d_log_qty_12 d_log_spend_10 d_log_spend_11 d_log_spend_12 {
    gen contrib_`v' = wt * `v'
}
* weighted sum by treated status
tempfile snap
save `snap', replace
collapse (sum) contrib_*, by(treated)
list, noobs ab(30)
use `snap', clear

* show top categories contributing to pre-period 2010 difference: contrib_d_log_qty_10 (treated) and (control)
keep if treated == 1
gsort -contrib_d_log_qty_10
di " "
di "==== TREATED cats contributing MOST POSITIVELY to qty[2010] - qty[2013] (weighted) ===="
list category spend_2013 d_log_qty_10 contrib_d_log_qty_10 d_log_spend_10 contrib_d_log_spend_10 in 1/15, noobs sep(0) ab(30)
gsort contrib_d_log_qty_10
di " "
di "==== TREATED cats contributing MOST NEGATIVELY to qty[2010] - qty[2013] (weighted) ===="
list category spend_2013 d_log_qty_10 contrib_d_log_qty_10 d_log_spend_10 contrib_d_log_spend_10 in 1/15, noobs sep(0) ab(30)

gsort -contrib_d_log_spend_10
di " "
di "==== TREATED cats contributing MOST POSITIVELY to spend[2010] - spend[2013] (weighted) ===="
list category spend_2013 d_log_spend_10 contrib_d_log_spend_10 d_log_qty_10 contrib_d_log_qty_10 in 1/15, noobs sep(0) ab(30)

restore

* === Step 3: Same exercise but for control
preserve
keep if inlist(year, 2010, 2011, 2012, 2013)
collapse (mean) log_raw_qty log_raw_spend (firstnm) spend_2013 treated, by(category year)
reshape wide log_raw_qty log_raw_spend, i(category treated) j(year)
gen d_log_qty_10 = log_raw_qty2010 - log_raw_qty2013
gen d_log_spend_10 = log_raw_spend2010 - log_raw_spend2013
keep if treated == 0
bys treated: egen tot_wt = total(spend_2013)
gen wt = spend_2013 / tot_wt
gen contrib_qty = wt * d_log_qty_10
gen contrib_spend = wt * d_log_spend_10
gsort contrib_qty
di " "
di "==== CONTROL cats contributing MOST NEGATIVELY to qty[2010] - qty[2013] (weighted) ===="
list category spend_2013 d_log_qty_10 contrib_qty d_log_spend_10 contrib_spend in 1/15, noobs sep(0) ab(30)
gsort -contrib_qty
di " "
di "==== CONTROL cats contributing MOST POSITIVELY to qty[2010] - qty[2013] (weighted) ===="
list category spend_2013 d_log_qty_10 contrib_qty d_log_spend_10 contrib_spend in 1/15, noobs sep(0) ab(30)
restore

log close
