// Goal: identify the 17 FOIA PIs missing from the all_jrnls_r1_r2_public panel.

use ../external/real_exposure/athr_exposure, clear
keep athr_id exposure
save ../temp/diag_a211, replace

// Pull a "present" flag from each candidate panel, using short var names.
local i = 0
foreach p in athr_panel_full_year_last_all_jrnls               ///
             athr_panel_full_year_last_all_jrnls_r1_r2         ///
             athr_panel_full_year_last_all_jrnls_r1_r2_public  ///
             athr_panel_full_year_last_top_jrnls               ///
             athr_panel_full_year_last_top_jrnls_r1_r2_public {
    local i = `i' + 1
    preserve
    use ../external/samp/`p', clear
    contract athr_id
    gen byte p`i' = 1
    keep athr_id p`i'
    save ../temp/diag_p`i', replace
    restore
}

use ../temp/diag_a211, clear
forval i = 1/5 {
    merge 1:1 athr_id using ../temp/diag_p`i', keep(1 3) nogen
    replace p`i' = 0 if mi(p`i')
}
label var p1 "all_jrnls"
label var p2 "all_jrnls_r1_r2"
label var p3 "all_jrnls_r1_r2_public  (main analysis panel)"
label var p4 "top_jrnls"
label var p5 "top_jrnls_r1_r2_public"

di as result _newline "===== FOIA presence across panels (211 total) ====="
forval i = 1/5 {
    qui count if p`i' == 1
    di as result "  p`i' (`:var label p`i''): present = " r(N) "/211"
}

di as result _newline "===== 17 FOIAs missing from main panel (p3 = all_jrnls_r1_r2_public) ====="
keep if p3 == 0
gunique athr_id
di as result "  unique: " r(unique)
list athr_id exposure p1 p2 p3 p4 p5, sep(0) noobs

// Of these 17: how many are in NO panel at all?
gen any_present = p1 | p2 | p3 | p4 | p5
di as result _newline "  ... in NO panel at all (true OpenAlex gaps):"
list athr_id exposure if !any_present, sep(0) noobs

di as result _newline "  ... in at least one OTHER panel but excluded by r1_r2_public:"
list athr_id exposure p1 p2 p3 p4 p5 if any_present, sep(0) noobs

// Cross-check upstream: is there ANY pre-2013-publishing filter in the chain?
// build.do for exposure_msr merges with list_of_athrs. Let's see what list_of_athrs is.
preserve
use ../external/real_exposure/foia_athrs, clear
gunique athr_id
di as result _newline "foia_athrs.dta (merged FOIA-to-OpenAlex): " r(unique)
restore
