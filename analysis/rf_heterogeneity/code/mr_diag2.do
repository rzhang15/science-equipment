set more off
set scheme modern
cap log close _all
log using mr_diag2.log, replace text

use ../temp/es_all_jrnls_r1_r2, clear
gen post       = year >= 2014
gen Z_it       = exposure      * post
gen Z_share_it = mkt_spend_shr * post

* ---------- E1. Is exposure correlated with baseline level WITHIN group? ----------
di as text _n(2) "=== E1. Exposure vs pre-period level, within baseline group ==="
preserve
    bys athr_id: keep if _n == 1
    di as text "-- corr(exposure, pre_ppr_cnt_sum) overall and within group --"
    corr exposure pre_ppr_cnt_sum
    foreach g in 0 1 {
        di as text _n "  high_pre_ppr == `g':"
        corr exposure pre_ppr_cnt_sum if high_pre_ppr == `g'
    }
    di as text _n "-- mean exposure by group --"
    table high_pre_ppr, stat(mean exposure) stat(sd exposure) stat(n exposure) nformat(%8.4f)
restore

* ---------- E2. Split-half reliability of the HP/LP classification ----------
di as text _n(2) "=== E2. Split-half reliability: HP defined on even vs odd pre-years ==="
preserve
    gen pe = ppr_cnt if inlist(year, 2010, 2012)
    gen po = ppr_cnt if inlist(year, 2011, 2013)
    bys athr_id: egen se_ = total(pe)
    bys athr_id: egen so_ = total(po)
    bys athr_id: keep if _n == 1
    qui sum se_, d
    gen byte hp_e = se_ >= r(p50)
    qui sum so_, d
    gen byte hp_o = so_ >= r(p50)
    di as text "-- agreement between even-year and odd-year classification --"
    tab hp_e hp_o, row
    qui corr hp_e hp_o
    di as text "  corr(hp_even, hp_odd) = " %6.4f r(rho)
restore

* ---------- E3. Clean split: define on 2010-2011, estimate on 2012-2019 ----------
di as text _n(2) "=== E3. Split defined on 2010-2011 only; estimation window 2012-2019 ==="
preserve
    gen p1011 = ppr_cnt if inlist(year, 2010, 2011)
    bys athr_id: egen pre_early = total(p1011)
    bys athr_id: gen _one = _n == 1
    qui sum pre_early if _one == 1, d
    local cut = r(p50)
    gen byte hp2 = pre_early >= `cut'
    gen byte lp2 = pre_early <  `cut'
    di as text "  cut = `cut';  N PIs hi/lo:"
    qui count if _one == 1 & hp2 == 1
    di as text "    hp2 = " r(N)
    qui count if _one == 1 & lp2 == 1
    di as text "    lp2 = " r(N)

    keep if year >= 2012
    gen Z_hp2 = Z_it * hp2
    gen Z_lp2 = Z_it * lp2
    gen S_hp2 = Z_share_it * hp2
    gen S_lp2 = Z_share_it * lp2
    gen PT_hp2 = post * hp2

    di as text _n "--- E3a. grp x post ---"
    ppmlhdfe ppr_cnt Z_hp2 Z_lp2 S_hp2 S_lp2 PT_hp2, absorb(athr_id year) vce(cluster athr_id)
    local e3_hp = _b[Z_hp2]
    local e3_lp = _b[Z_lp2]
    local e3_hpse = _se[Z_hp2]
    local e3_lpse = _se[Z_lp2]
    lincom Z_hp2 - Z_lp2
    local e3_d = r(estimate)
    local e3_dse = r(se)
    local e3_dp = r(p)

    di as text _n(2) "=== E3 SUMMARY (clean split, 2010-11 defined, 2012-19 est) ==="
    di as text "  beta_HP = " %8.4f `e3_hp' " (" %6.4f `e3_hpse' ")"
    di as text "  beta_LP = " %8.4f `e3_lp' " (" %6.4f `e3_lpse' ")"
    di as text "  HP-LP   = " %8.4f `e3_d' " (" %6.4f `e3_dse' ")  p=" %5.3f `e3_dp'
restore

* ---------- E4. Same 2012-2019 window, ORIGINAL split, for apples-to-apples ----------
di as text _n(2) "=== E4. Original 2010-13 split, same 2012-2019 window ==="
preserve
    keep if year >= 2012
    gen Z_hp = Z_it * high_pre_ppr
    gen Z_lp = Z_it * low_pre_ppr
    gen S_hp = Z_share_it * high_pre_ppr
    gen S_lp = Z_share_it * low_pre_ppr
    gen PT_hp = post * high_pre_ppr
    ppmlhdfe ppr_cnt Z_hp Z_lp S_hp S_lp PT_hp, absorb(athr_id year) vce(cluster athr_id)
    local e4_hp = _b[Z_hp]
    local e4_lp = _b[Z_lp]
    local e4_hpse = _se[Z_hp]
    local e4_lpse = _se[Z_lp]
    lincom Z_hp - Z_lp
    di as text _n(2) "=== E4 SUMMARY (original split, 2012-19 window) ==="
    di as text "  beta_HP = " %8.4f `e4_hp' " (" %6.4f `e4_hpse' ")"
    di as text "  beta_LP = " %8.4f `e4_lp' " (" %6.4f `e4_lpse' ")"
    di as text "  HP-LP   = " %8.4f r(estimate) " (" %6.4f r(se) ")  p=" %5.3f r(p)
restore

log close
