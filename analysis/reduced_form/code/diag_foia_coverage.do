// diagnostic: walk restrict_samp and count FOIA authors at each step
// runs for samp=all_jrnls, r1r2=1, public=1 (same as main analysis call)

set more off
clear all
capture log close
log using diag_foia_coverage.log, replace

local samp all_jrnls
local suf  _r1_r2_public

// ground truth: how many FOIA authors are in athr_exposure to begin with?
use ../external/real_exposure/athr_exposure, clear
gunique athr_id
di as result "STEP 0 (athr_exposure file, all rows): " r(unique) " unique athr_id"
count if mi(athr_id)
di as result "  ... of which missing athr_id: " r(N)
count if exposure <= 0
di as result "  ... of which exposure <= 0: " r(N)
count if exposure > 0 & !mi(exposure) & !mi(athr_id)
di as result "  ... eligible (athr_id ok and exposure > 0): " r(N)
preserve
keep if !mi(athr_id) & exposure > 0
gunique athr_id
local foia_eligible = r(unique)
di as result "  ==> eligible unique athr_ids: `foia_eligible'"
save ../temp/diag_foia_eligible, replace
restore

// also pull the imputed exposure file for comparison
import delimited ../external/exposure/final_imputed_exposure_restricted, clear
rename exposure imputed
rename mkt_spend_shr imputed_mkt_spend_shr
save ../temp/diag_imputed, replace
gunique athr_id
di as result "STEP 0b (imputed exposure file): " r(unique) " unique athr_id"

// now mimic restrict_samp step by step
use ../external/samp/athr_panel_full_year_last_`samp'`suf', clear
di as result _newline "STEP 1 (raw panel `samp'`suf'):"
gunique athr_id
di as result "  panel unique athr_id: " r(unique)
preserve
    merge m:1 athr_id using ../temp/diag_foia_eligible, keep(2 3) keepusing(exposure)
    gunique athr_id if _merge == 3
    di as result "  FOIA-eligible athrs PRESENT in raw panel: " r(unique)
    gunique athr_id if _merge == 2
    di as result "  FOIA-eligible athrs MISSING from raw panel: " r(unique)
    // list the missing ones
    keep if _merge == 2
    duplicates drop athr_id, force
    list athr_id, sep(0) abb(20)
restore

// step: tot_pprs >= 10
use ../external/samp/athr_panel_full_year_last_`samp'`suf', clear
bys athr_id: egen tot_pprs = total(ppr_cnt)
keep if tot_pprs >= 10
drop tot_pprs
merge m:1 athr_id using ../temp/diag_foia_eligible, keep(3) keepusing(exposure) nogen
gunique athr_id
di as result "STEP 2 (after tot_pprs >= 10): FOIA athrs surviving: " r(unique)

// step: max_year >= 2014
bys athr_id: egen max_year = max(year)
keep if max_year >= 2014
gunique athr_id
di as result "STEP 3 (after max_year >= 2014): FOIA athrs surviving: " r(unique)

// step: inrange(year, 2010, 2019)
keep if inrange(year, 2010, 2019)
gunique athr_id
di as result "STEP 4 (after year in [2010,2019]): FOIA athrs surviving: " r(unique)

// step: min_year < 2013
bys athr_id: egen min_year = min(year)
keep if min_year < 2013
gunique athr_id
di as result "STEP 5 (after min_year < 2013, i.e. published before 2013): FOIA athrs surviving: " r(unique)

// step: merge imputed (already merged above, but track)
merge m:1 athr_id using ../temp/diag_imputed, keep(1 3) nogen
gunique athr_id
di as result "STEP 6 (after merge imputed exposure): FOIA athrs: " r(unique)

// step: replace imputed with FOIA-observed where avail (no-op for athr count)
gen foia_athr = 1 if !mi(exposure)
replace imputed = exposure if !mi(exposure)
gunique athr_id if foia_athr == 1
di as result "STEP 7 (gen foia_athr flag): FOIA athrs flagged: " r(unique)

// step: drop if exposure <= 0  / imputed <= 0
drop if exposure <= 0
gunique athr_id if foia_athr == 1
di as result "STEP 8a (drop if FOIA exposure <= 0): FOIA athrs: " r(unique)
drop if imputed <= 0
gunique athr_id if foia_athr == 1
di as result "STEP 8b (drop if imputed <= 0):       FOIA athrs: " r(unique)

// step: keep if foia_athr == 1  (downstream filters are applied to FOIA only)
keep if foia_athr == 1
gunique athr_id
di as result "STEP 9 (keep if foia_athr==1): " r(unique)

// step: num_yrs > 1
bys athr_id: gen num_yrs = _N
gunique athr_id if num_yrs > 1
di as result "STEP 10 (would keep if num_yrs > 1):     " r(unique)
gunique athr_id if num_yrs == 1
di as result "  ... DROPPED b/c num_yrs == 1:           " r(unique)
keep if num_yrs > 1

// step: num_place == 1
bys athr_id inst_id: gen plc_cntr = _n == 1
bys athr_id: egen num_place = total(plc_cntr)
gunique athr_id if num_place == 1
di as result "STEP 11 (would keep if num_place == 1):  " r(unique)
gunique athr_id if num_place > 1
di as result "  ... DROPPED b/c num_place > 1:          " r(unique)
keep if num_place == 1

// step: drop if exposure <= 0 (redundant guard)
drop if exposure <= 0
gunique athr_id
di as result "STEP 12 (drop if exposure <= 0 again):   " r(unique)

// step: tsfill then num_yrs>1 check is moot; recompute tot_pprs and apply >=5 filter
gegen athr = group(athr_id)
xtset athr year
tsfill
hashsort athr year
foreach var in athr_id exposure min_year inst_id {
    by athr: replace `var' = `var'[_n-1] if mi(`var')
}
foreach var in ppr_cnt {
    replace `var' = 0 if mi(`var')
}
bys athr_id: egen tot_pprs2 = total(ppr_cnt)
gunique athr_id if tot_pprs2 >= 5
di as result "STEP 13 (after tsfill + keep if tot_pprs2 >= 5): " r(unique)
gunique athr_id if tot_pprs2 < 5
di as result "  ... DROPPED b/c tot_pprs2 < 5:                  " r(unique)

di as result _newline "DONE."

log close
