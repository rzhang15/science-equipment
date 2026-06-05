// Post-change author sample analysis.
// Walks the CURRENT restrict_samp (lifetime tot_pprs>=10 commented out, min_year<=2013)
// and reports FOIA vs non-FOIA counts at each step.

set more off
clear all
capture log close
log using diag_postchange.log, replace

// ---------- FOIA flag ----------
use ../external/real_exposure/athr_exposure, clear
keep athr_id
gen byte foia_flag = 1
save ../temp/diag_pc_foia, replace

// ---------- imputed pool ----------
import delimited ../external/exposure/final_imputed_exposure_restricted, clear
rename (exposure mkt_spend_shr) (imputed imputed_mkt_spend_shr)
keep athr_id imputed imputed_mkt_spend_shr
save ../temp/diag_pc_imp, replace

// ---------- mirror current restrict_samp ----------
use ../external/samp/athr_panel_full_year_last_all_jrnls_r1_r2_public, clear
merge m:1 athr_id using ../temp/diag_pc_foia, keep(1 3) nogen
replace foia_flag = 0 if mi(foia_flag)

di as result _newline "===== POST-CHANGE author sample funnel (all_jrnls_r1_r2_public) ====="
gunique athr_id
di as result _newline "STEP 0 (raw panel): " r(unique) " PIs"
gunique athr_id if foia_flag
di as result "    FOIA:     " r(unique)
gunique athr_id if !foia_flag
di as result "    non-FOIA: " r(unique)

// line 70-72: tot_pprs >= 10  <-- NOW COMMENTED OUT, so skip
bys athr_id: egen tot_pprs = total(ppr_cnt)
drop tot_pprs

// line 73-74: max_year >= 2014
bys athr_id: egen max_year = max(year)
keep if max_year >= 2014
gunique athr_id if foia_flag
di as result _newline "STEP 1 (max_year >= 2014):    FOIA: " r(unique)
gunique athr_id if !foia_flag
di as result "                             non-FOIA: " r(unique)

// line 75: year in [2010, 2019]
keep if inrange(year, 2010, 2019)
gunique athr_id if foia_flag
di as result _newline "STEP 2 (year in [2010,2019]): FOIA: " r(unique)
gunique athr_id if !foia_flag
di as result "                             non-FOIA: " r(unique)

// line 76-77: min_year <= 2013  (changed from <)
bys athr_id: egen min_year = min(year)
keep if min_year <= 2013
gunique athr_id if foia_flag
di as result _newline "STEP 3 (min_year <= 2013):    FOIA: " r(unique)
gunique athr_id if !foia_flag
di as result "                             non-FOIA: " r(unique)

// line 78: merge imputed keep(3)
merge m:1 athr_id using ../temp/diag_pc_imp, keep(3) nogen
gunique athr_id if foia_flag
di as result _newline "STEP 4 (merge imputed):       FOIA: " r(unique)
gunique athr_id if !foia_flag
di as result "                             non-FOIA: " r(unique)

// line 79: merge FOIA observed
merge m:1 athr_id using ../external/real_exposure/athr_exposure, keep(1 3) nogen
gen foia_athr = 1 if !mi(exposure)
replace imputed = exposure if !mi(exposure)
replace imputed_mkt_spend_shr = mkt_spend_shr if !mi(mkt_spend_shr)
// lines 83-85 commented out

drop exposure
rename imputed exposure

// line 113-116: num_yrs > 1
bys athr_id: gen num_yrs = _N
keep if num_yrs > 1
gunique athr_id if foia_flag
di as result _newline "STEP 5 (num_yrs > 1):         FOIA: " r(unique)
gunique athr_id if !foia_flag
di as result "                             non-FOIA: " r(unique)

// line 114-117: num_place == 1
bys athr_id inst_id: gen plc_cntr = _n == 1
bys athr_id: egen num_place = total(plc_cntr)
keep if num_place == 1
gunique athr_id if foia_flag
di as result _newline "STEP 6 (num_place == 1):      FOIA: " r(unique)
gunique athr_id if !foia_flag
di as result "                             non-FOIA: " r(unique)

// line 118: drop if exposure <= 0 -- REMOVED in current code

// tsfill + tot_pprs >= 5
gegen athr = group(athr_id)
xtset athr year
tsfill
hashsort athr year
foreach var in athr_id exposure foia_flag min_year inst_id {
    bys athr (year): replace `var' = `var'[_n-1] if mi(`var')
}
replace ppr_cnt = 0 if mi(ppr_cnt)
bys athr_id: egen tot_pprs2 = total(ppr_cnt)
keep if tot_pprs2 >= 5
gunique athr_id if foia_flag
di as result _newline "STEP 8 (tsfill + tot_pprs2>=5): FOIA: " r(unique)
gunique athr_id if !foia_flag
di as result "                              non-FOIA: " r(unique)

di as result _newline "===== DONE ====="

// sanity check against the actual saved analysis dataset
preserve
use ../temp/es_all_jrnls_r1_r2_public, clear
gunique athr_id
di as result _newline "Saved es_all_jrnls_r1_r2_public total athr_id: " r(unique)
gunique athr_id if foia_athr == 1
di as result "  with foia_athr==1: " r(unique)
restore

log close
