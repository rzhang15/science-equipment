// (A) compare the 211 in athr_exposure vs the 204 in foia_author_text_final
import delimited ../external/exposure/foia_author_text_final.csv, clear varnames(1)
keep athr_id
duplicates drop athr_id, force
gen in_text204 = 1
save ../temp/diag_text204, replace

use ../external/real_exposure/athr_exposure, clear
keep athr_id exposure
merge 1:1 athr_id using ../temp/diag_text204
di as result "===== 211 (athr_exposure) vs 204 (text corpus) ====="
tab _merge
di as result "_merge==3: in BOTH"
di as result "_merge==1: in athr_exposure but NOT in text corpus (these are the '+7' candidates)"
di as result "_merge==2: in text corpus but NOT in athr_exposure"

// list the ones in athr_exposure but not in text
preserve
keep if _merge == 1
gunique athr_id
di as result "  athr_exposure-only count: " r(unique)
list athr_id exposure, sep(0)
restore

// list the ones in text but not in athr_exposure
preserve
count if _merge == 2
di as result "  text-only count: " r(N)
restore

// (B) for the 12 PIs lost at min_year < 2013: what are their actual first pub years?
//     these were FOIA-eligible (in athr_exposure with exposure>0) and made it through
//     tot_pprs>=10 and max_year>=2014 but min_year >= 2013
use ../external/real_exposure/athr_exposure, clear
keep if exposure > 0
keep athr_id
save ../temp/diag_foia_eligible_166, replace

use ../external/samp/athr_panel_full_year_last_all_jrnls_r1_r2_public, clear
merge m:1 athr_id using ../temp/diag_foia_eligible_166, keep(3) nogen
bys athr_id: egen tot_pprs = total(ppr_cnt)
keep if tot_pprs >= 10
bys athr_id: egen max_year = max(year)
keep if max_year >= 2014
keep if inrange(year, 2010, 2019)
bys athr_id: egen min_year = min(year)

preserve
keep if min_year >= 2013
contract athr_id min_year
di as result "===== 12 FOIA PIs dropped by min_year >= 2013 ====="
gunique athr_id
di as result "  count: " r(unique)
list, sep(0) clean
restore

// for those 12, what was their FULL panel min_year (before [2010,2019] restriction)?
preserve
use ../external/samp/athr_panel_full_year_last_all_jrnls_r1_r2_public, clear
merge m:1 athr_id using ../temp/diag_foia_eligible_166, keep(3) nogen
bys athr_id: egen tot_pprs_full = total(ppr_cnt)
bys athr_id: egen max_year_full = max(year)
bys athr_id: egen min_year_full = min(year)
keep athr_id tot_pprs_full max_year_full min_year_full
duplicates drop athr_id, force
save ../temp/diag_foia_full_years, replace
restore

merge m:1 athr_id using ../temp/diag_foia_full_years, keep(1 3) nogen keepusing(min_year_full max_year_full tot_pprs_full)
keep if min_year >= 2013
contract athr_id min_year min_year_full max_year_full tot_pprs_full
di as result "===== 12 dropped PIs: their FULL-panel year ranges ====="
list, sep(0) clean
