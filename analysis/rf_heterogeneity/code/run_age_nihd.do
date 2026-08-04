set more off
clear all
capture log close
set scheme modern
version 17
set maxvar 20000

log using run_age_nihd.log, replace text

local samp   all_jrnls
local sufs   _r1_r2 _r1_r2_public
local fes    athr_id year
local vce_cl athr_id
local yvars  ppr_cnt cite_affl_wt

cap mkdir "../output/figures/`samp'"
cap mkdir "../output/figures/`samp'/es_ppml"
cap mkdir "../output/figures/`samp'/coefplot_evavg"
cap mkdir "../output/tables/`samp'"

global LBL_y_hn "Early-Career Scientists x More NIH Funding at Baseline"
global LBL_y_ln "Early-Career Scientists x Less NIH Funding at Baseline"
global LBL_o_hn "Late-Career Scientists x More NIH Funding at Baseline"
global LBL_o_ln "Late-Career Scientists x Less NIH Funding at Baseline"

foreach suf of local sufs {

di as text _n(2) "################ run_age_nihd: `samp'`suf' ################"

cap confirm file ../temp/es_`samp'`suf'.dta
if _rc {
    di as error "run_age_nihd: ../temp/es_`samp'`suf'.dta not found -- run add_het_splits for this sample first; skipping."
    continue
}
use ../temp/es_`samp'`suf', clear

local skip 0
foreach v in young high_nihd {
    cap confirm variable `v'
    if _rc {
        di as error "run_age_nihd`suf': `v' not in panel -- rerun add_het_splits; skipping."
        local skip 1
    }
}
if `skip' continue

* 2x2 cells; missing off the NIH-matched sample, so every fit below drops
* unmatched PIs rather than pooling them into the base category.
gen byte y_hn = (young == 1 & high_nihd == 1) if !mi(young) & !mi(high_nihd)
gen byte y_ln = (young == 1 & high_nihd == 0) if !mi(young) & !mi(high_nihd)
gen byte o_hn = (young == 0 & high_nihd == 1) if !mi(young) & !mi(high_nihd)
gen byte o_ln = (young == 0 & high_nihd == 0) if !mi(young) & !mi(high_nihd)

foreach grp in y_hn y_ln o_hn o_ln {
    qui sum `grp'
    if r(N) == 0 | r(max) == 0 {
        di as error "run_age_nihd`suf': cell `grp' empty -- skipping this sample."
        local skip 1
    }
}
if `skip' continue

gen rel = year - 2014
qui sum rel, d
local abs_lag  = abs(r(max))
local abs_lead = abs(r(min))

forval i = 1/`abs_lead' {
    gen int_lead`i'  = exposure      if rel == -`i'
    gen mshr_lead`i' = mkt_spend_shr if rel == -`i'
}
forval i = 0/`abs_lag' {
    gen int_lag`i'  = exposure      if rel == `i'
    gen mshr_lag`i' = mkt_spend_shr if rel == `i'
}
ds int_lead* int_lag* mshr_lead* mshr_lag*
foreach var in `r(varlist)' {
    replace `var' = 0 if mi(`var')
}
local int_leads
local mshr_leads
local int_lags
local mshr_lags
forval i = 2/`abs_lead' {
    local int_leads  int_lead`i'  `int_leads'
    local mshr_leads mshr_lead`i' `mshr_leads'
}
forval i = 0/`abs_lag' {
    local int_lags  `int_lags'  int_lag`i'
    local mshr_lags `mshr_lags' mshr_lag`i'
}

gen post       = year >= 2014
gen Z_it       = exposure      * post
gen Z_share_it = mkt_spend_shr * post

foreach grp in y_hn y_ln o_hn o_ln {
    * cleared per suffix: these accumulate, and stale terms from the
    * previous sample would enter the next sample's ES spec.
    local leads_`grp'
    local lags_`grp'
    local mleads_`grp'
    local mlags_`grp'
    foreach v of local int_leads {
        gen `v'_`grp' = `v' * `grp'
        local leads_`grp' `leads_`grp'' `v'_`grp'
    }
    foreach v of local int_lags {
        gen `v'_`grp' = `v' * `grp'
        local lags_`grp' `lags_`grp'' `v'_`grp'
    }
    foreach v of local mshr_leads {
        gen `v'_`grp' = `v' * `grp'
        local mleads_`grp' `mleads_`grp'' `v'_`grp'
    }
    foreach v of local mshr_lags {
        gen `v'_`grp' = `v' * `grp'
        local mlags_`grp' `mlags_`grp'' `v'_`grp'
    }
    gen int_lead1_`grp' = int_lead1 * `grp'
    gen Z_`grp'  = Z_it       * `grp'
    gen S_`grp'  = Z_share_it * `grp'
    gen PT_`grp' = post       * `grp'
}

tempname ph
postfile `ph' str30 yvar str24 grp str18 split_type ///
    double(post_b post_se p N r2_p n_pis) ///
    using "../temp/age_nihd_results`suf'", replace

foreach yvar of local yvars {
    local ylab "`yvar'"
    if "`yvar'" == "ppr_cnt"      local ylab "Publications"
    if "`yvar'" == "cite_affl_wt" local ylab "Citation-Weighted Output"
    local gap = cond(regexm("`yvar'", "^cite_affl_wt"), 0.2, 0.1)

    di as text _n "==== pooled DiD PPML 2x2 age x nihd: `yvar' (`suf') ===="
    * [H11] o_ln x post is the omitted base
    cap noi ppmlhdfe `yvar' Z_y_hn Z_y_ln Z_o_hn Z_o_ln ///
                            S_y_hn S_y_ln S_o_hn S_o_ln ///
                            PT_y_hn PT_y_ln PT_o_hn, ///
        absorb(`fes') vce(cluster `vce_cl')
    if _rc {
        di as error "run_age_nihd`suf': pooled DiD `yvar' failed; skipping."
        continue
    }
    local Nppml  = e(N)
    local r2ppml = e(r2_p)
    foreach grp in y_hn y_ln o_hn o_ln {
        gunique athr_id if e(sample) & `grp' == 1
        local n_pis = r(unique)
        gunique inst_id if e(sample) & `grp' == 1
        local n_insts = r(unique)
        local b  = _b[Z_`grp']
        local se = _se[Z_`grp']
        di as text "PDID `yvar' `grp': b=" %8.4f `b' " se=" %8.4f `se' ///
            "  N=" %9.0f `Nppml' " PIs=`n_pis' Insts=`n_insts'"
        post `ph' ("`yvar'") ("`grp'") ("joint_agenih") ///
            (`b') (`se') (.) (`Nppml') (`r2ppml') (`n_pis')
    }
    * Hi-vs-lo NIH funding within age and young-vs-old within funding tier.
    foreach d in "y_diff_nihd Z_y_hn Z_y_ln" "o_diff_nihd Z_o_hn Z_o_ln" ///
                 "hi_diff_age Z_y_hn Z_o_hn" "lo_diff_age Z_y_ln Z_o_ln" {
        local dname : word 1 of `d'
        local d1    : word 2 of `d'
        local d2    : word 3 of `d'
        cap noi lincom `d1' - `d2'
        if _rc continue
        local b_diff  = r(estimate)
        local se_diff = r(se)
        local p_diff  = r(p)
        di as text "DIFF `yvar' `dname': b=" %8.4f `b_diff' ///
            " se=" %8.4f `se_diff' " p=" %6.4f `p_diff'
        post `ph' ("`yvar'") ("`dname'") ("joint_agenih_diff") ///
            (`b_diff') (`se_diff') (`p_diff') (`Nppml') (`r2ppml') (.)
    }

    di as text _n "==== event study PPML 2x2 age x nihd: `yvar' (`suf') ===="
    cap noi ppmlhdfe `yvar' ///
        `leads_y_hn' `lags_y_hn' `leads_y_ln' `lags_y_ln' ///
        `leads_o_hn' `lags_o_hn' `leads_o_ln' `lags_o_ln' ///
        `mleads_y_hn' `mlags_y_hn' `mleads_y_ln' `mlags_y_ln' ///
        `mleads_o_hn' `mlags_o_hn' `mleads_o_ln' `mlags_o_ln' ///
        PT_y_hn PT_y_ln PT_o_hn, ///
        absorb(`fes') vce(cluster `vce_cl')
    if _rc {
        di as error "run_age_nihd`suf': ES `yvar' failed; skipping plots."
        continue
    }
    foreach grp in y_hn y_ln o_hn o_ln {
        local grp_label = "${LBL_`grp'}"
        gunique athr_id if e(sample) & `grp' == 1
        local num_athrs = r(unique)
        gunique inst_id if e(sample) & `grp' == 1
        local num_insts = r(unique)
        sum `yvar' if rel <= -1 & e(sample) & `grp' == 1, d
        local pre_mean : dis %6.3f r(mean)
        preserve
        cap mat drop es
        foreach var in `leads_`grp'' `lags_`grp'' int_lead1_`grp' {
            if "`var'" == "int_lead1_`grp'" mat row = 0,0
            else mat row = _b[`var'], _se[`var']
            mat es = nullmat(es) \ row
        }
        svmat es
        keep es1 es2
        drop if mi(es1)
        rename (es1 es2) (b se)
        gen ub = b + 1.96*se
        qui sum ub
        local ymax = round(r(max), `gap')
        gen lb = b - 1.96*se
        qui sum lb
        local ymin = round(r(min), `gap')
        if `ymin' > 0 local ymin = 0
        gen rel = -`abs_lead' if _n == 1
        replace rel = rel[_n-1]+1 if _n > 1
        replace rel = rel + 1 if rel >= -1
        replace rel = -1 if rel == `abs_lag' + 1
        gen year = rel + 2014
        hashsort rel
        tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
           scatter b year, mcolor(ebblue) || ///
        scatteri `ymax' 2013.75 `ymax' 2014.25, bcolor(gs12%30) recast(area) base(`ymin') ///
           xlab(2010(1)2019, labsize(small)) xtitle("Year") ///
           ytitle("{&Delta} Log Expected `ylab'") ylab(`ymin'(`gap')`ymax') ///
           subtitle("`grp_label'", pos(11) size(small)) ///
           legend(on order(- "Num. PIs: `num_athrs'" "Num. Insts: `num_insts'" "Pre-Period Avg : `pre_mean'") ///
                  pos(7) ring(1) rows(3) bmargin(zero) size(small)) ///
           yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
        graph export ../output/figures/`samp'/es_ppml/es_`yvar'`suf'_`grp'_agenihd.pdf, replace
        restore
    }
}
postclose `ph'

use ../temp/age_nihd_results`suf', clear
di as text _n "==== age_nihd_results`suf' ===="
list, sepby(yvar) noobs
export delimited using "../output/tables/`samp'/age_nihd_results`suf'.txt", replace delim(tab)

}

do plot_age_nihd.do

log close
