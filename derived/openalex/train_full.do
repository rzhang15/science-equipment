set more off
use /n/home02/cxu75/sci_eq/analysis/rf_heterogeneity/temp/es_all_jrnls_r1_r2.dta, clear
cap drop train_yrs
gen train_yrs = min_year - min_year_any
merge m:1 athr_id using /n/home02/cxu75/sci_eq/derived/openalex/athr_age/output/athr_age.dta, keep(1 3) keepusing(first_pub first_last) gen(_ma)
qui count if athr_indicator == 1 & _ma == 1
di as text "PIs not in athr_age: " r(N)
gen earlier_outside = first_pub < min_year_any if !mi(first_pub) & !mi(min_year_any)
gen gap_outside = min_year_any - first_pub
di as text "--- early-career PIs with train_yrs==0: do they have earlier OpenAlex work outside the universe?"
tab earlier_outside if athr_indicator == 1 & young == 1 & train_yrs == 0, missing
qui sum gap_outside if athr_indicator == 1 & young == 1 & train_yrs == 0 & earlier_outside == 1, d
di as text "  years of earlier outside work among those: p25=" r(p25) " p50=" r(p50) " p75=" r(p75)
di as text "--- all early-career PIs: earlier outside work"
tab earlier_outside if athr_indicator == 1 & young == 1, missing
gen train_full = min_year - first_pub
qui sum train_full if athr_indicator == 1 & young == 1, d
di as text "training yrs from full OpenAlex history, early-career: p25=" r(p25) " p50=" r(p50) " p75=" r(p75) " mean=" %5.2f r(mean)
qui count if athr_indicator == 1 & young == 1 & train_full == 0
di as text "  zeros under full history: " r(N)
qui count if athr_indicator == 1 & young == 1 & train_full < 0
di as text "  negative (first_pub after panel min_year, i.e. athr_age vintage/coverage issue): " r(N)

gen post       = year >= 2014
gen Z_it       = exposure      * post
gen Z_share_it = mkt_spend_shr * post
program run_pair
    args g1 g2 tag
    cap drop Z_`g1' Z_`g2' S_`g1' S_`g2' PT_`g1'
    gen Z_`g1' = Z_it * `g1'
    gen Z_`g2' = Z_it * `g2'
    gen S_`g1' = Z_share_it * `g1'
    gen S_`g2' = Z_share_it * `g2'
    gen PT_`g1' = post * `g1'
    ppmlhdfe ppr_cnt Z_`g1' Z_`g2' S_`g1' S_`g2' PT_`g1', absorb(athr_id year) vce(cluster athr_id)
    gunique athr_id if e(sample)
    local npi = r(unique)
    lincom Z_`g1' - Z_`g2'
    di as result "== `tag' (PIs=`npi'): long = " %7.4f _b[Z_`g1'] " (" %6.4f _se[Z_`g1'] ")  short = " %7.4f _b[Z_`g2'] " (" %6.4f _se[Z_`g2'] ")  diff = " %7.4f r(estimate) " (" %6.4f r(se) ") p=" %5.3f r(p)
end
* B: training length from the full OpenAlex history, split at its median
qui sum train_full if athr_indicator == 1 & young == 1 & train_full >= 0, d
local medB = r(p50)
gen byte y_longB  = train_full >  `medB' if young == 1 & train_full >= 0
gen byte y_shortB = train_full <= `medB' if young == 1 & train_full >= 0
di as text "B median = `medB'"
run_pair y_longB y_shortB "B full-history training"
* C: universe training length, dropping zero-training PIs who have earlier work outside the universe
gen byte keepC = young == 1 & !(train_yrs == 0 & earlier_outside == 1)
qui sum train_yrs if athr_indicator == 1 & keepC == 1, d
local medC = r(p50)
gen byte y_longC  = train_yrs >  `medC' if keepC == 1
gen byte y_shortC = train_yrs <= `medC' if keepC == 1
qui count if athr_indicator == 1 & young == 1 & !keepC
di as text "C drops " r(N) " zero-training PIs with earlier outside work; median = `medC'"
run_pair y_longC y_shortC "C drop zeros w/ outside work"
* D: drop ALL zero-training PIs under the full history (true beginners only)
gen byte keepD = young == 1 & train_full > 0 & !mi(train_full)
qui sum train_full if athr_indicator == 1 & keepD == 1, d
local medD = r(p50)
gen byte y_longD  = train_full >  `medD' if keepD == 1
gen byte y_shortD = train_full <= `medD' if keepD == 1
di as text "D median = `medD'"
run_pair y_longD y_shortD "D full-history, zeros dropped"
* continuous on full history
gen Z_y = Z_it * young
gen Z_ytr = Z_it * young * train_full
gen S_y = Z_share_it * young
gen S_ytr = Z_share_it * young * train_full
gen PT_ytr = post * young * train_full
ppmlhdfe ppr_cnt Z_y Z_ytr S_y S_ytr PT_ytr if young == 1 & train_full >= 0, absorb(athr_id year) vce(cluster athr_id)
di as result "== continuous full-history: at 0 = " %7.4f _b[Z_y] " (" %6.4f _se[Z_y] ")  per yr = " %7.4f _b[Z_ytr] " (" %6.4f _se[Z_ytr] ") p=" %5.3f (2*normal(-abs(_b[Z_ytr]/_se[Z_ytr])))
