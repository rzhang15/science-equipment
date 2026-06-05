// (A) Why 207 -> 194? Walk the gap.
// (B) Why 21 dropped at min_year <= 2013? List them with full pub-year ranges.

set more off
clear all
capture log close
log using diag_207_to_panel.log, replace

// ---------- (A) 207 imputation FOIAs vs 194 panel FOIAs ----------
import delimited ../external/exposure/final_imputed_exposure_restricted.csv, clear
keep athr_id
gen byte in_imp = 1
duplicates drop athr_id, force
save ../temp/diag_imp_ids, replace

use ../external/real_exposure/athr_exposure, clear
keep athr_id exposure
merge 1:1 athr_id using ../temp/diag_imp_ids, keep(1 3) nogen
gen byte foia_in_imp = (in_imp == 1)
drop in_imp
keep if foia_in_imp == 1   // = 207
gunique athr_id
di as result _newline "===== 207 FOIA PIs in imputation pool ====="
di as result "  unique: " r(unique)

// presence in each panel (short var names)
local i = 0
foreach p in athr_panel_full_year_last_all_jrnls               ///
             athr_panel_full_year_last_all_jrnls_r1_r2         ///
             athr_panel_full_year_last_all_jrnls_r1_r2_public {
    local i = `i' + 1
    preserve
    use ../external/samp/`p', clear
    contract athr_id
    gen byte p`i' = 1
    keep athr_id p`i'
    save ../temp/diag_panel_p`i', replace
    restore
    merge 1:1 athr_id using ../temp/diag_panel_p`i', keep(1 3) nogen
    replace p`i' = 0 if mi(p`i')
}
label var p1 "in all_jrnls"
label var p2 "in all_jrnls_r1_r2"
label var p3 "in all_jrnls_r1_r2_public (MAIN)"

qui count if p3 == 1
di as result _newline "  Of 207 imputation FOIAs, in MAIN panel: " r(N)
qui count if p3 == 0
di as result "  Missing from MAIN panel:                " r(N) " <-- the 207 -> 194 gap"

di as result _newline "  === Breakdown of the 13 missing ==="
gen any_panel = p1 | p2 | p3
qui count if p3 == 0 & !any_panel
di as result "  (i)  In NO panel at all (true OpenAlex/journal gaps): " r(N)
list athr_id exposure if p3 == 0 & !any_panel, sep(0) noobs

qui count if p3 == 0 & any_panel
di as result _newline "  (ii) In some other panel, excluded by R1/R2/public filter: " r(N)
list athr_id exposure p1 p2 p3 if p3 == 0 & any_panel, sep(0) noobs

// ---------- (B) drop at min_year <= 2013 (current code) ----------
use ../external/samp/athr_panel_full_year_last_all_jrnls_r1_r2_public, clear
merge m:1 athr_id using ../temp/diag_imp_ids, keep(3) nogen
merge m:1 athr_id using ../external/real_exposure/athr_exposure, keep(3) keepusing(exposure) nogen
// FOIA-only here (foia_athr is everyone matched on athr_exposure)
bys athr_id: egen max_year = max(year)
keep if max_year >= 2014
keep if inrange(year, 2010, 2019)
bys athr_id: egen min_year = min(year)
preserve
keep if min_year > 2013
gunique athr_id
di as result _newline "===== FOIA PIs dropped at min_year <= 2013 ====="
di as result "  unique dropped: " r(unique)
contract athr_id min_year exposure
restore

// also pull each PI's FULL pub-year range (pre any [2010,2019] restriction)
preserve
use ../external/samp/athr_panel_full_year_last_all_jrnls_r1_r2_public, clear
merge m:1 athr_id using ../temp/diag_imp_ids, keep(3) nogen
bys athr_id: egen min_year_full = min(year)
bys athr_id: egen max_year_full = max(year)
bys athr_id: egen tot_pprs_full = total(ppr_cnt)
keep athr_id min_year_full max_year_full tot_pprs_full
duplicates drop athr_id, force
save ../temp/diag_full_yrs, replace
restore

merge m:1 athr_id using ../temp/diag_full_yrs, keep(1 3) nogen
keep if min_year > 2013
contract athr_id min_year min_year_full max_year_full tot_pprs_full
di as result _newline "  FOIA PIs dropped at min_year <= 2013, with FULL panel year range:"
list athr_id min_year min_year_full max_year_full tot_pprs_full, sep(0) noobs

log close
