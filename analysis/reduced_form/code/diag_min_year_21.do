// List the 21 FOIAs dropped at min_year <= 2013 with details
set more off
clear all
capture log close
log using diag_min_year_21.log, replace

use ../external/samp/athr_panel_full_year_last_all_jrnls_r1_r2_public, clear
merge m:1 athr_id using ../external/real_exposure/athr_exposure, keep(3) keepusing(exposure) nogen
bys athr_id: egen max_year = max(year)
keep if max_year >= 2014

// pre-window full year range
preserve
bys athr_id: egen min_full = min(year)
bys athr_id: egen max_full = max(year)
bys athr_id: egen tot_full = total(ppr_cnt)
keep athr_id min_full max_full tot_full
duplicates drop athr_id, force
save ../temp/diag_full_window, replace
restore

keep if inrange(year, 2010, 2019)
bys athr_id: egen min_year = min(year)
keep if min_year > 2013   // these are the 21 dropped
contract athr_id min_year exposure
merge 1:1 athr_id using ../temp/diag_full_window, keep(1 3) nogen keepusing(min_full max_full tot_full)
gen byte zero_or_neg_exp = exposure <= 0
sort min_year athr_id
di as result _newline "===== 21 FOIA PIs dropped at min_year <= 2013 ====="
di as result "  (min_year = first panel year within [2010,2019])"
di as result "  (min_full = first panel year EVER, no window restriction)"
list athr_id min_year min_full max_full tot_full exposure, sep(0) noobs ab(12)

di as result _newline "  ===== summary by first panel-year =====:"
tab min_year
log close
