set more off
set scheme modern
cap log close _all
log using mr_diag.log, replace text

* ============================================================
* Mean-reversion diagnostics for the high/low baseline-productivity split.
* high_pre_ppr = 1{ sum(ppr_cnt, 2010-2013) >= median }, i.e. split on the
* outcome's own pre-window. Tests whether the HP/LP contrast is reversion.
* ============================================================

* ---------- A. Saved ES coefficients: differential pre-trend ----------
di as text _n(2) "=== A. Event-study coefficients (exposure x rel-year), by baseline group ==="
foreach g in high_pre_ppr low_pre_ppr {
    use ../temp/es_ppr_cnt_r1_r2_`g'_ppml_mshrctrl, clear
    di as text _n "--- `g' ---"
    list year b se lb ub, noobs sep(0) abbrev(12)
    qui sum b if year <= 2012
    di as text "  mean pre-2013 lead coef = " %7.4f r(mean) "   (N=" r(N) ")"
}

* ---------- load panel ----------
use ../temp/es_all_jrnls_r1_r2, clear
qui sum year
di as text _n "panel years: " r(min) " - " r(max)

gen post       = year >= 2014
gen Z_it       = exposure      * post
gen Z_share_it = mkt_spend_shr * post

* ---------- B. Raw group trajectories: is there visible reversion? ----------
di as text _n(2) "=== B. Mean ppr_cnt by year x baseline group (raw) ==="
table year high_pre_ppr, stat(mean ppr_cnt) nformat(%7.3f)

di as text _n "=== B2. Same, normalized to each group's 2013 level ==="
preserve
    collapse (mean) m = ppr_cnt, by(year high_pre_ppr)
    bys high_pre_ppr (year): gen base = m[_n-1] if year == 2014
    bys high_pre_ppr: egen b13 = max(cond(year == 2013, m, .))
    gen idx = m / b13
    list year high_pre_ppr m idx, noobs sepby(year) abbrev(12)
restore

* ---------- C. Direct reversion test: post change on pre level ----------
di as text _n(2) "=== C. Within-PI reversion: post-period mean vs pre-period mean ==="
preserve
    bys athr_id: egen pre_m  = mean(cond(year <  2014, ppr_cnt, .))
    bys athr_id: egen post_m = mean(cond(year >= 2014, ppr_cnt, .))
    bys athr_id: keep if _n == 1
    gen d = post_m - pre_m
    di as text "-- change (post-pre) by baseline group --"
    table high_pre_ppr, stat(mean d) stat(mean pre_m) stat(mean post_m) stat(n d) nformat(%8.3f)
    di as text _n "-- regression of change on pre level (slope<0 = reversion) --"
    reg d pre_m, robust
    di as text _n "-- same in logs --"
    gen ld = ln(1+post_m) - ln(1+pre_m)
    gen lpre = ln(1+pre_m)
    reg ld lpre, robust
restore

* ---------- D. THE TEST: group x post  vs  group x year FE ----------
di as text _n(2) "=== D. Pooled DiD PPML: group x post (current) vs group x year FE ==="
gen Z_hp = Z_it * high_pre_ppr
gen Z_lp = Z_it * low_pre_ppr
gen S_hp = Z_share_it * high_pre_ppr
gen S_lp = Z_share_it * low_pre_ppr
gen PT_hp = post * high_pre_ppr

di as text _n "--- D1. current spec: absorb(athr_id year) + PT_hp ---"
ppmlhdfe ppr_cnt Z_hp Z_lp S_hp S_lp PT_hp, absorb(athr_id year) vce(cluster athr_id)
local d1_hp = _b[Z_hp]
local d1_lp = _b[Z_lp]
local d1_hpse = _se[Z_hp]
local d1_lpse = _se[Z_lp]
lincom Z_hp - Z_lp
local d1_diff = r(estimate)
local d1_diffse = r(se)
local d1_diffp = r(p)

di as text _n "--- D2. group x year FE: absorb(athr_id i.high_pre_ppr#i.year) ---"
ppmlhdfe ppr_cnt Z_hp Z_lp S_hp S_lp, absorb(athr_id i.high_pre_ppr#i.year) vce(cluster athr_id)
local d2_hp = _b[Z_hp]
local d2_lp = _b[Z_lp]
local d2_hpse = _se[Z_hp]
local d2_lpse = _se[Z_lp]
lincom Z_hp - Z_lp
local d2_diff = r(estimate)
local d2_diffse = r(se)
local d2_diffp = r(p)

di as text _n(2) "=== D. SUMMARY ==="
di as text "spec                     beta_HP (se)        beta_LP (se)        HP-LP (se) [p]"
di as text "D1 grp x post      " %8.4f `d1_hp' " (" %6.4f `d1_hpse' ")   " ///
   %8.4f `d1_lp' " (" %6.4f `d1_lpse' ")   " %8.4f `d1_diff' " (" %6.4f `d1_diffse' ") [" %5.3f `d1_diffp' "]"
di as text "D2 grp x year FE   " %8.4f `d2_hp' " (" %6.4f `d2_hpse' ")   " ///
   %8.4f `d2_lp' " (" %6.4f `d2_lpse' ")   " %8.4f `d2_diff' " (" %6.4f `d2_diffse' ") [" %5.3f `d2_diffp' "]"

log close
