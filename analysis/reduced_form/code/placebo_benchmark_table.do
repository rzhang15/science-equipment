set more off
clear all
capture log close
set scheme modern
version 17

local samp all_jrnls
local suf  _r1_r2

import delimited ../temp/exposure_pl.csv, clear varnames(1) stringcols(1)
save ../temp/exposure_pl, replace

use ../output/prepped_samples/es_`samp'`suf', clear
merge m:1 athr_id using ../temp/exposure_pl, keep(1 3) nogen
assert !mi(exposure_pl)
gen post  = year >= 2014
gen Zs_it = mkt_spend_shr * post

reg exposure_pl exposure mkt_spend_shr
local proj_b  = _b[exposure]
local proj_s  = _b[mkt_spend_shr]
local proj_r2 = e(r2)

mat plb = J(13, 2, .)
local c = 0
foreach x in exposure exposure_pl {
    local ++c
    gen Z_it = `x' * post
    ppmlhdfe ppr_cnt Z_it Zs_it, absorb(athr_id year) vce(cluster athr_id) d
    local b = _b[Z_it]
    mat plb[1, `c']  = `b'
    mat plb[2, `c']  = _se[Z_it]
    mat plb[3, `c']  = _b[Zs_it]
    mat plb[4, `c']  = _se[Zs_it]
    mat plb[10, `c'] = e(N)
    qui sum `x' if e(sample)
    mat plb[5, `c'] = r(mean)
    mat plb[6, `c'] = 100 * (1 - exp(`b' * r(mean)))
    predict double mu, mu
    gen double mu_cf = mu * exp(-`b' * Z_it) if e(sample) & post
    gen double loss  = mu_cf - mu
    qui sum loss
    local tot_loss = r(sum)
    mat plb[7, `c'] = `tot_loss'
    qui sum mu_cf
    mat plb[8, `c'] = 100 * `tot_loss' / r(sum)
    qui sum ppr_cnt if year < 2014 & e(sample)
    mat plb[9, `c'] = r(mean)
    drop Z_it mu mu_cf loss
}
mat plb[11, 2] = `proj_b'
mat plb[12, 2] = `proj_s'
mat plb[13, 2] = `proj_r2'
mat rownames plb = b_exposure se_exposure b_share se_share avg_exposure decline_pct ///
                   papers_lost pct_cf_lost pre_mean N proj_slope_exposure proj_slope_share proj_r2
mat colnames plb = baseline placebo_bench
mat list plb, format(%9.4f)

cap mkdir ../output/tables/`samp'/robustness
matrix_to_txt, saving("../output/tables/`samp'/robustness/placebo_benchmark`suf'.txt") ///
    matrix(plb) title(<tab:placebo_benchmark`suf'>) format(%20.4f) replace
