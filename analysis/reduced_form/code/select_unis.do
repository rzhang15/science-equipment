* Selects the 50 largest R1s and 10 largest R2s in the RF analysis sample.
set more off
clear all
capture log close
version 17

use athr_id year inst_id inst type using ../external/samp/athr_panel_full_year_last_all_jrnls_r1_r2, clear
bys athr_id: egen max_year = max(year)
bys athr_id: egen min_year = min(year)
keep if min_year <= 2013 & max_year >= 2015 & inrange(year, 2010, 2019)
gcontract inst_id inst type
drop if inst == "Harvard University"
drop if _freq < 20
isid inst_id

count if type == "r1"
assert r(N) >= 45
count if type == "r2"
assert r(N) >=5 

gen neg_freq = -_freq
bys type (neg_freq inst_id): gen rank = _n
keep if (type == "r1" & rank <= 45) | (type == "r2" & rank <= 5)
drop neg_freq rank

sort type inst
list type inst _freq, noobs clean
export delimited inst_id inst type _freq using ../output/largest_50_unis.csv, replace
