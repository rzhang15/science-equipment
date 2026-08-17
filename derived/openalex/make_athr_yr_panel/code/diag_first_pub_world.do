* One-off diagnostic: true first-publication year (any author position, any
* country) for the RF-sample PIs, from the full world corpus (~88GB scan).
* Run by hand: /n/sw/stata-17/stata-mp -b do diag_first_pub_world.do
set more off
clear all

use athr_id min_year min_year_any athr_indicator using ///
    "/n/home02/cxu75/sci_eq/analysis/rf_heterogeneity/temp/es_all_jrnls_r1_r2.dta", clear
keep if athr_indicator == 1
contract athr_id min_year min_year_any
drop _freq
save ../temp/diag_rf_pis, replace

use athr_id year using ../external/openalex/cleaned_all_jrnls, clear
merge m:1 athr_id using ../temp/diag_rf_pis, keep(3) nogen keepusing(athr_id)
gcollapse (min) first_any_world=year, by(athr_id)
save ../temp/diag_first_any_world, replace

use athr_id year using ../external/sub_athrs/last/cleaned_all_jrnls, clear
merge m:1 athr_id using ../temp/diag_rf_pis, keep(3) nogen keepusing(athr_id)
gcollapse (min) first_last_world=year, by(athr_id)
save ../temp/diag_first_last_world, replace

use ../temp/diag_rf_pis, clear
merge 1:1 athr_id using ../temp/diag_first_any_world, keep(1 3) nogen
merge 1:1 athr_id using ../temp/diag_first_last_world, keep(1 3) nogen
gen trunc_yrs = min_year_any - first_any_world
gen gap_world = first_last_world - first_any_world

di as text _n "=== Left-truncation: current min_year_any minus world first-any year ==="
tabstat trunc_yrs, stats(n mean sd p10 p25 p50 p75 p90 p95 p99) col(stat) format(%9.1f)
count if trunc_yrs > 0

di as text _n "=== DIST: world first-any year ==="
tabstat first_any_world, stats(n mean sd p5 p10 p25 p50 p75 p90 p95) col(stat) format(%9.1f)
di as text _n "=== DIST: world first-last-author year ==="
tabstat first_last_world, stats(n mean sd p5 p10 p25 p50 p75 p90 p95) col(stat) format(%9.1f)

di as text _n "=== GAP: world first-last minus world first-any ==="
tabstat gap_world, stats(n mean sd p10 p25 p50 p75 p90 p95) col(stat) format(%9.1f)
count if gap_world == 0

save ../temp/diag_first_pub_world, replace
