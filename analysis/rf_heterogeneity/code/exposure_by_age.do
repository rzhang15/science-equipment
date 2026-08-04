set more off
clear all
capture log close
set scheme modern
version 17
set maxvar 20000

log using exposure_by_age.log, replace text

local samp all_jrnls
local suf  _r1_r2

use ../temp/es_`samp'`suf', clear

cap drop athr_indicator
bys athr_id : gen athr_indicator = _n == 1

qui sum age_2014 if athr_indicator == 1, d
di as text _n "es_`samp'`suf': age_2014 median (young/old cutoff) = " %6.2f r(p50)

di as text _n "==== PI-level exposure, full analysis sample ===="
foreach g in young old {
    qui sum exposure if athr_indicator == 1 & `g' == 1, d
    di as text "  `g': N=" %6.0f r(N) "  mean=" %9.5f r(mean) ///
        "  sd=" %9.5f r(sd) "  p25=" %9.5f r(p25) ///
        "  p50=" %9.5f r(p50) "  p75=" %9.5f r(p75)
}

di as text _n "==== PI-level exposure, NIH-matched PIs ===="
cap confirm variable young_nih
if !_rc {
    foreach g in young_nih old_nih {
        qui sum exposure if athr_indicator == 1 & `g' == 1, d
        di as text "  `g': N=" %6.0f r(N) "  mean=" %9.5f r(mean) ///
            "  sd=" %9.5f r(sd) "  p25=" %9.5f r(p25) ///
            "  p50=" %9.5f r(p50) "  p75=" %9.5f r(p75)
    }
}
else di as error "  young_nih/old_nih not in panel"

di as text _n "==== PI-level exposure, observed FOIA exposure only ===="
foreach g in young old {
    qui count if athr_indicator == 1 & `g' == 1 & foia_athr == 1
    if r(N) == 0 {
        di as text "  `g' (FOIA): no PIs"
        continue
    }
    qui sum exposure if athr_indicator == 1 & `g' == 1 & foia_athr == 1, d
    di as text "  `g' (FOIA): N=" %6.0f r(N) "  mean=" %9.5f r(mean) ///
        "  sd=" %9.5f r(sd) "  p25=" %9.5f r(p25) ///
        "  p50=" %9.5f r(p50) "  p75=" %9.5f r(p75)
}

di as text _n "==== Difference test (PI level, clustered on institution) ===="
egen long inst_num = group(inst_id)
cap noi reg exposure young if athr_indicator == 1, vce(cluster inst_num)

log close
