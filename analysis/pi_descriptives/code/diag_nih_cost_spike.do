clear all
set more off

use ../output/prepped_samples/pi_desc_all_jrnls_r1_r2, clear

gen byte pos = nih_cost_raw > 0 & !mi(nih_cost_raw)
gen double cost_pos = nih_cost_raw if pos
gen double cost_per_grant = nih_cost_raw / n_grants_raw if n_grants_raw > 0

qui sum cost_pos, d
local p99 = r(p99)
gen double cost_w = min(nih_cost_raw, `p99') if !mi(nih_cost_raw)
gen double cost_trim = nih_cost_raw if nih_cost_raw <= `p99'

di "p99 of positive cost = " `p99'

table year, stat(mean nih_cost_raw) stat(mean cost_w) stat(mean cost_trim) ///
    stat(mean pos) stat(mean cost_pos) stat(p50 cost_pos) stat(p90 cost_pos) ///
    stat(mean n_grants_raw) stat(mean cost_per_grant) nformat(%12.0f) nototals

* top-tail share of the total each year
bys year: egen double tot = total(nih_cost_raw)
gsort year -nih_cost_raw
by year: gen rk = _n
by year: gen double top10 = sum(nih_cost_raw)
gen double shr_top10 = top10 / tot if rk == 10
gen double top50 = top10 if rk == 50
table year, stat(max shr_top10) stat(max tot) nformat(%14.4f) nototals

* grant-level: where do the dollars come from
use athr_id year grant_key row_key research total_cost start_year activity ///
    using ../external/nih_panel/nih_grants_by_athr_id, clear
drop if mi(year)
keep if inrange(year, 2010, 2019)
duplicates drop athr_id year row_key, force
keep if research
egen byte tag_res = tag(athr_id year grant_key)
keep if tag_res
gen byte mi_cost = mi(total_cost)
table year, stat(mean total_cost) stat(p50 total_cost) stat(p99 total_cost) ///
    stat(max total_cost) stat(mean mi_cost) stat(count grant_key) nformat(%14.0f) nototals

gen str3 act3 = substr(activity, 1, 3)
gen byte big = total_cost > 2000000 & !mi(total_cost)
table year, stat(mean big) stat(sum total_cost) nformat(%16.0f) nototals
encode act3, gen(act_c)
table act_c year if big, nformat(%9.0f) nototals
