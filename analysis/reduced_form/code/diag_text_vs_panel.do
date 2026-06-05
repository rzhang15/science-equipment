// Hypothesis check: do the 21 dropped FOIAs have pre-2013 rows in the broader
// all_jrnls panel (no r1_r2_public filter)?
set more off
clear all
capture log close
log using diag_text_vs_panel.log, replace

// the 21 dropped at min_year <= 2013 in r1_r2_public panel
local dropped21 ///
    A5010051226 A5029591124 A5039136921 A5057951318 A5060877343 A5064892746 ///
    A5091177547 A5100767723 A5014945614 A5023125790 A5050835243 A5051244336 ///
    A5061970781 A5089103469 A5062698300 A5070177847 A5001952573 A5008234108 ///
    A5029773307 A5108213808 A5089879988

clear
local row = 1
gen str11 athr_id = ""
gen int pre2013_in_all       = .
gen int pre2013_in_r1r2      = .
gen int pre2013_in_r1r2_pub  = .
foreach a of local dropped21 {
    set obs `row'
    replace athr_id = "`a'" in `row'
    local row = `row' + 1
}

// for each panel, count pre-2013 rows per athr_id
foreach v in pre2013_in_all pre2013_in_r1r2 pre2013_in_r1r2_pub {
    if "`v'" == "pre2013_in_all"      local p athr_panel_full_year_last_all_jrnls
    if "`v'" == "pre2013_in_r1r2"     local p athr_panel_full_year_last_all_jrnls_r1_r2
    if "`v'" == "pre2013_in_r1r2_pub" local p athr_panel_full_year_last_all_jrnls_r1_r2_public
    preserve
    use ../external/samp/`p', clear
    keep if year <= 2013
    contract athr_id
    rename _freq cnt_`v'
    save ../temp/diag_tmp_`v', replace
    restore
    merge 1:1 athr_id using ../temp/diag_tmp_`v', keep(1 3) nogen keepusing(cnt_`v')
    replace `v' = cnt_`v' if !mi(cnt_`v')
    replace `v' = 0      if mi(cnt_`v')
    drop cnt_`v'
}

di as result _newline "===== The 21 FOIAs dropped at min_year <= 2013 ====="
di as result "       (pre2013 row counts in successively broader panels)"
di as result "       all = all_jrnls (no inst filter)"
di as result "       r1r2 = + R1/R2 inst filter"
di as result "       r1r2_pub = + public inst filter (= MAIN analysis panel)"
sort athr_id
list, sep(0) noobs

// summary
qui count if pre2013_in_all > 0
di as result _newline "  Of 21:  with pre-2013 rows in all_jrnls (any inst):    " r(N)
qui count if pre2013_in_r1r2 > 0
di as result "          with pre-2013 rows in all_jrnls + R1/R2:        " r(N)
qui count if pre2013_in_r1r2_pub > 0
di as result "          with pre-2013 rows in all_jrnls + R1/R2 public: " r(N) " (should be 0 by construction)"

log close
