set more off
clear all
capture log close
set scheme modern
version 17
set maxvar 20000

log using run_age_ngrants.log, replace text

local samp   all_jrnls
local sufs   _r1_r2 _r1_r2_public
local fes    athr_id year
local vce_cl athr_id
local yvars  ppr_cnt cite_affl_wt

cap mkdir "../output/figures/`samp'"
cap mkdir "../output/figures/`samp'/es_ppml"
cap mkdir "../output/tables/`samp'"

global LBL_y_mg "Early-Career Scientists x Multiple NIH Grants at Baseline"
global LBL_y_sg "Early-Career Scientists x Single NIH Grant at Baseline"
global LBL_o_mg "Late-Career Scientists x Multiple NIH Grants at Baseline"
global LBL_o_sg "Late-Career Scientists x Single NIH Grant at Baseline"

* Grant diversification at baseline: max number of NIH projects held
* concurrently in any FY2010-2013 (distinct full_project_num per athr-FY).
* multi = ever >= 2 overlapping awards pre-merger; single = never more than 1.
* Restricted to PIs with at least one FY2010-2013 award: an unmatched PI's
* zero is a failed name match and a matched PI funded only post-2013 was not
* an NIH PI pre-merger, so neither is a single-grant lab. A grant-PI pair can
* appear twice when the same name matches twice in pi_names, hence the dedup.
use athr_id grant_id full_project_num fy using ../external/nih/nih_grants_by_athr_id, clear
duplicates drop athr_id grant_id, force
keep if inrange(fy, 2010, 2013)
bys athr_id fy full_project_num: gen byte proj = _n == 1
gcollapse (sum) n_active = proj, by(athr_id fy) fast
gcollapse (max) max_active = n_active, by(athr_id) fast
save ../temp/nih_pre_ngrants, replace

foreach suf of local sufs {

di as text _n(2) "################ run_age_ngrants: `samp'`suf' ################"

cap confirm file ../temp/es_`samp'`suf'.dta
if _rc {
    di as error "run_age_ngrants: ../temp/es_`samp'`suf'.dta not found -- run add_het_splits for this sample first; skipping."
    continue
}
use ../temp/es_`samp'`suf', clear

cap confirm variable young
if _rc {
    di as error "run_age_ngrants`suf': young not in panel -- rerun add_het_splits; skipping."
    continue
}

cap drop _merge
merge m:1 athr_id using ../temp/nih_pre_ngrants, keep(1 3)
gen byte multi_g = max_active >= 2 if _merge == 3
drop _merge

* 2x2 cells; missing off the pre-funded NIH sample, so every fit below drops
* ineligible PIs rather than pooling them into the base category.
gen byte y_mg = (young == 1 & multi_g == 1) if !mi(young) & !mi(multi_g)
gen byte y_sg = (young == 1 & multi_g == 0) if !mi(young) & !mi(multi_g)
gen byte o_mg = (young == 0 & multi_g == 1) if !mi(young) & !mi(multi_g)
gen byte o_sg = (young == 0 & multi_g == 0) if !mi(young) & !mi(multi_g)

local skip 0
foreach grp in y_mg y_sg o_mg o_sg {
    qui sum `grp'
    if r(N) == 0 | r(max) == 0 {
        di as error "run_age_ngrants`suf': cell `grp' empty -- skipping this sample."
        local skip 1
    }
    cap drop _tag
    egen byte _tag = tag(athr_id) if `grp' == 1
    qui count if _tag == 1
    di as text "run_age_ngrants`suf': cell `grp' PIs = " r(N)
}
cap drop _tag
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

foreach grp in y_mg y_sg o_mg o_sg {
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
postfile `ph' str30 yvar str24 grp str24 split_type ///
    double(post_b post_se p N r2_p n_pis) ///
    using "../temp/age_ngrants_results`suf'", replace

foreach yvar of local yvars {
    local ylab "`yvar'"
    if "`yvar'" == "ppr_cnt"      local ylab "Publications"
    if "`yvar'" == "cite_affl_wt" local ylab "Citation-Weighted Output"
    local gap = cond(regexm("`yvar'", "^cite_affl_wt"), 0.2, 0.1)

    di as text _n "==== pooled DiD PPML 2x2 age x ngrants: `yvar' (`suf') ===="
    * o_sg x post is the omitted base
    cap noi ppmlhdfe `yvar' Z_y_mg Z_y_sg Z_o_mg Z_o_sg ///
                            S_y_mg S_y_sg S_o_mg S_o_sg ///
                            PT_y_mg PT_y_sg PT_o_mg, ///
        absorb(`fes') vce(cluster `vce_cl')
    if _rc {
        di as error "run_age_ngrants`suf': pooled DiD `yvar' failed; skipping."
        continue
    }
    local Nppml  = e(N)
    local r2ppml = e(r2_p)
    foreach grp in y_mg y_sg o_mg o_sg {
        gunique athr_id if e(sample) & `grp' == 1
        local n_pis = r(unique)
        gunique inst_id if e(sample) & `grp' == 1
        local n_insts = r(unique)
        local b  = _b[Z_`grp']
        local se = _se[Z_`grp']
        di as text "PDID `yvar' `grp': b=" %8.4f `b' " se=" %8.4f `se' ///
            "  N=" %9.0f `Nppml' " PIs=`n_pis' Insts=`n_insts'"
        post `ph' ("`yvar'") ("`grp'") ("joint_agengrants") ///
            (`b') (`se') (.) (`Nppml') (`r2ppml') (`n_pis')
    }
    * Multi-vs-single grant within age and young-vs-old within grant tier.
    foreach d in "y_diff_ng Z_y_mg Z_y_sg" "o_diff_ng Z_o_mg Z_o_sg" ///
                 "mg_diff_age Z_y_mg Z_o_mg" "sg_diff_age Z_y_sg Z_o_sg" {
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
        post `ph' ("`yvar'") ("`dname'") ("joint_agengrants_diff") ///
            (`b_diff') (`se_diff') (`p_diff') (`Nppml') (`r2ppml') (.)
    }

    di as text _n "==== event study PPML 2x2 age x ngrants: `yvar' (`suf') ===="
    cap noi ppmlhdfe `yvar' ///
        `leads_y_mg' `lags_y_mg' `leads_y_sg' `lags_y_sg' ///
        `leads_o_mg' `lags_o_mg' `leads_o_sg' `lags_o_sg' ///
        `mleads_y_mg' `mlags_y_mg' `mleads_y_sg' `mlags_y_sg' ///
        `mleads_o_mg' `mlags_o_mg' `mleads_o_sg' `mlags_o_sg' ///
        PT_y_mg PT_y_sg PT_o_mg, ///
        absorb(`fes') vce(cluster `vce_cl')
    if _rc {
        di as error "run_age_ngrants`suf': ES `yvar' failed; skipping plots."
        continue
    }
    foreach grp in y_mg y_sg o_mg o_sg {
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
        graph export ../output/figures/`samp'/es_ppml/es_`yvar'`suf'_`grp'_agengrants.pdf, replace
        restore
    }
}
postclose `ph'

use ../temp/age_ngrants_results`suf', clear
di as text _n "==== age_ngrants_results`suf' ===="
list, sepby(yvar) noobs
export delimited using "../output/tables/`samp'/age_ngrants_results`suf'.txt", replace delim(tab)

}

log close
