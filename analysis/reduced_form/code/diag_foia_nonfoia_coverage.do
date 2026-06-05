// Parallel coverage funnel for FOIA vs non-FOIA PIs through restrict_samp,
// mirroring the CURRENT code path (lines 83-85 commented out).
// all_jrnls / r1r2=1 / public=1.

set more off
clear all
capture log close
log using diag_foia_nonfoia_coverage.log, replace

// Pre-build a sticky FOIA flag from athr_exposure.dta (211 PIs).
use ../external/real_exposure/athr_exposure, clear
keep athr_id
gen byte foia_flag = 1
save ../temp/diag_foia_flag, replace
gunique athr_id
di as result "===== FOIA pool (athr_exposure): " r(unique) " ====="

// ---------- start of restrict_samp ----------
use ../external/samp/athr_panel_full_year_last_all_jrnls_r1_r2_public, clear
merge m:1 athr_id using ../temp/diag_foia_flag, keep(1 3) nogen
replace foia_flag = 0 if mi(foia_flag)

gunique athr_id
di as result "STEP 0 (raw panel): " r(unique) " unique PIs"
gunique athr_id if foia_flag
di as result "          FOIA: " r(unique)
gunique athr_id if !foia_flag
di as result "      non-FOIA: " r(unique)

// line 70-72: tot_pprs >= 10
bys athr_id: egen tot_pprs = total(ppr_cnt)
keep if tot_pprs >= 10
drop tot_pprs
gunique athr_id if foia_flag
di as result "STEP 1 (tot_pprs >= 10):       FOIA: " r(unique)
gunique athr_id if !foia_flag
di as result "                           non-FOIA: " r(unique)

// line 73-74: max_year >= 2014
bys athr_id: egen max_year = max(year)
keep if max_year >= 2014
gunique athr_id if foia_flag
di as result "STEP 2 (max_year >= 2014):     FOIA: " r(unique)
gunique athr_id if !foia_flag
di as result "                           non-FOIA: " r(unique)

// line 75: year in [2010, 2019]
keep if inrange(year, 2010, 2019)
gunique athr_id if foia_flag
di as result "STEP 3 (year in [2010,2019]):  FOIA: " r(unique)
gunique athr_id if !foia_flag
di as result "                           non-FOIA: " r(unique)

// line 76-77: min_year < 2013
bys athr_id: egen min_year = min(year)
keep if min_year < 2013
gunique athr_id if foia_flag
di as result "STEP 4 (min_year < 2013):      FOIA: " r(unique)
gunique athr_id if !foia_flag
di as result "                           non-FOIA: " r(unique)

// line 78: merge imputed (keep(3) drops PIs without imputed value)
preserve
import delimited ../external/exposure/final_imputed_exposure_restricted, clear
rename (exposure mkt_spend_shr) (imputed imputed_mkt_spend_shr)
keep athr_id imputed imputed_mkt_spend_shr
save ../temp/diag_imp, replace
restore
merge m:1 athr_id using ../temp/diag_imp, keep(3) nogen
gunique athr_id if foia_flag
di as result "STEP 5 (merge imputed keep(3)): FOIA: " r(unique)
gunique athr_id if !foia_flag
di as result "                            non-FOIA: " r(unique)

// line 79: merge FOIA observed exposure
merge m:1 athr_id using ../external/real_exposure/athr_exposure, keep(1 3) nogen
gen foia_athr = 1 if !mi(exposure)
replace imputed = exposure if !mi(exposure)
replace imputed_mkt_spend_shr = mkt_spend_shr if !mi(mkt_spend_shr)
// lines 83-85 commented out in current code (no drops here)

// line 106-107: drop exposure (observed), rename imputed → exposure
drop exposure
rename imputed exposure

// line 113-116: num_yrs > 1
bys athr_id: gen num_yrs = _N
keep if num_yrs > 1
gunique athr_id if foia_flag
di as result "STEP 6 (num_yrs > 1):          FOIA: " r(unique)
gunique athr_id if !foia_flag
di as result "                           non-FOIA: " r(unique)

// line 114-117: num_place == 1
bys athr_id inst_id: gen plc_cntr = _n == 1
bys athr_id: egen num_place = total(plc_cntr)
keep if num_place == 1
gunique athr_id if foia_flag
di as result "STEP 7 (num_place == 1):       FOIA: " r(unique)
gunique athr_id if !foia_flag
di as result "                           non-FOIA: " r(unique)

// line 118: drop if exposure <= 0  (after rename: exposure = imputed, with FOIA observed overlaid)
drop if exposure <= 0
gunique athr_id if foia_flag
di as result "STEP 8 (drop if exposure<=0):  FOIA: " r(unique)
gunique athr_id if !foia_flag
di as result "                           non-FOIA: " r(unique)

// tsfill (lines 119-128) + recomputed tot_pprs >= 5 (line 129-130)
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
di as result "STEP 9 (tsfill + tot_pprs2>=5): FOIA: " r(unique)
gunique athr_id if !foia_flag
di as result "                            non-FOIA: " r(unique)

di as result _newline "===== DONE ====="

// sanity: should match the actual saved analysis dataset
preserve
use ../temp/es_all_jrnls_r1_r2_public, clear
gunique athr_id
di as result "Saved dataset total athr_id: " r(unique)
gunique athr_id if foia_athr == 1
di as result "  FOIA: " r(unique)
gunique athr_id if foia_athr != 1
di as result "  non-FOIA: " r(unique) "  (note: !=1 includes tsfill rows where foia_athr is missing)"
restore

log close
