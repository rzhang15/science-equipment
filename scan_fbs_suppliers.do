set more off
use /n/holylabs/pakes_lab/Lab/sci_eq/derived/first_stage/make_mkt_panel/output/full_item_level_tfidf.dta, clear
keep if category == "us fbs"
collapse (sum) raw_spend (count) obs_cnt = price, by(suppliername)
gsort -raw_spend
gen mkt_shr = raw_spend/`=r(sum)' * 100
egen tot = total(raw_spend)
replace mkt_shr = raw_spend/tot * 100
list suppliername raw_spend obs_cnt mkt_shr, clean noobs
