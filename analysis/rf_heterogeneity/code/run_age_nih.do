set more off
clear all
capture log close
set scheme modern
version 17
set maxvar 20000

log using run_age_nih.log, replace text

local samp   all_jrnls
local sufs   _r1_r2 _r1_r2_public
local fes    athr_id year
local vce_cl athr_id
local yvars  n_grants nih_total_cost
local pairs `" "young old" "young_nih old_nih" "'

cap mkdir "../output/figures/`samp'"
cap mkdir "../output/figures/`samp'/es_ppml"
cap mkdir "../output/tables/`samp'"

global LBL_young     "Early-Career Scientists"
global LBL_old       "Late-Career Scientists"
global LBL_young_nih "Early-Career Scientists (NIH-Matched PIs)"
global LBL_old_nih   "Late-Career Scientists (NIH-Matched PIs)"

foreach suf of local sufs {

di as text _n(2) "################ run_age_nih: `samp'`suf' ################"

cap confirm file ../temp/es_`samp'`suf'.dta
if _rc {
    di as error "run_age_nih: ../temp/es_`samp'`suf'.dta not found -- run add_het_splits for this sample first; skipping."
    continue
}
use ../temp/es_`samp'`suf', clear

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

local skip 0
foreach pair of local pairs {
    foreach grp of local pair {
        cap confirm variable `grp'
        if _rc {
            di as error "run_age_nih `suf': `grp' not in panel -- skipping this sample."
            local skip 1
            continue, break
        }
        qui sum `grp'
        if r(N) == 0 | r(min) == r(max) {
            di as error "run_age_nih `suf': `grp' degenerate -- skipping this sample."
            local skip 1
            continue, break
        }
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
    if `skip' continue, break
}
if `skip' continue

tempname ph
postfile `ph' str30 yvar str24 grp str12 split_type ///
    double(post_b post_se N r2_p n_pis) ///
    using "../temp/age_nih_results`suf'", replace

foreach yvar of local yvars {
    local ylab "`yvar'"
    if "`yvar'" == "n_grants"       local ylab "Active NIH Research Grants"
    if "`yvar'" == "nih_total_cost" local ylab "NIH Award Dollars"
    local gap = cond("`yvar'" == "nih_total_cost", 0.4, 0.1)

    foreach pair of local pairs {
        local g1 : word 1 of `pair'
        local g2 : word 2 of `pair'
        local st = cond("`g1'" == "young", "med_pi", "med_pi_nih")

        di as text _n "==== pooled DiD PPML: `yvar' `g1' vs `g2' (`suf') ===="
        cap noi ppmlhdfe `yvar' Z_`g1' Z_`g2' S_`g1' S_`g2' PT_`g1', ///
            absorb(`fes') vce(cluster `vce_cl')
        if _rc {
            di as error "run_age_nih`suf': pooled DiD `yvar' `g1'/`g2' failed; skipping."
            continue
        }
        local Nppml  = e(N)
        local r2ppml = e(r2_p)
        foreach grp in `g1' `g2' {
            gunique athr_id if e(sample) & `grp' == 1
            local n_pis = r(unique)
            gunique inst_id if e(sample) & `grp' == 1
            local n_insts = r(unique)
            local b  = _b[Z_`grp']
            local se = _se[Z_`grp']
            di as text "PDID `yvar' `grp': b=" %8.4f `b' " se=" %8.4f `se' ///
                "  N=" %9.0f `Nppml' " PIs=`n_pis' Insts=`n_insts'"
            post `ph' ("`yvar'") ("`grp'") ("`st'") ///
                (`b') (`se') (`Nppml') (`r2ppml') (`n_pis')
        }
        cap noi lincom Z_`g1' - Z_`g2'
        if !_rc di as text "DIFF `yvar' `g1'-`g2': b=" %8.4f r(estimate) ///
            " se=" %8.4f r(se) " p=" %6.4f r(p)

        di as text _n "==== event study PPML: `yvar' `g1' vs `g2' (`suf') ===="
        cap noi ppmlhdfe `yvar' `leads_`g1'' `lags_`g1'' `leads_`g2'' `lags_`g2'' ///
            `mleads_`g1'' `mlags_`g1'' `mleads_`g2'' `mlags_`g2'' PT_`g1', ///
            absorb(`fes') vce(cluster `vce_cl')
        if _rc {
            di as error "run_age_nih`suf': ES `yvar' `g1'/`g2' failed; skipping plots."
            continue
        }
        foreach grp in `g1' `g2' {
            local grp_label = "${LBL_`grp'}"
            gunique athr_id if e(sample) & `grp' == 1
            local num_athrs = r(unique)
            gunique inst_id if e(sample) & `grp' == 1
            local num_insts = r(unique)
            sum `yvar' if rel <= -1 & e(sample) & `grp' == 1, d
            local pre_mean : dis %6.3f r(mean)
            if "`yvar'" == "nih_total_cost" ///
                local pre_mean = string(r(mean), "%12.0fc")
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
               subtitle("`grp_label' -- `ylab'", pos(11) size(small)) ///
               legend(on order(- "Num. PIs: `num_athrs'" "Num. Insts: `num_insts'" "Pre-Period Avg : `pre_mean'") ///
                      pos(7) ring(1) rows(3) bmargin(zero) size(small)) ///
               yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
            graph export ../output/figures/`samp'/es_ppml/es_`yvar'`suf'_`grp'_agenih.pdf, replace
            restore
        }
    }
}
postclose `ph'

use ../temp/age_nih_results`suf', clear
di as text _n "==== age_nih_results`suf' ===="
list, sepby(yvar) noobs
export delimited using "../output/tables/`samp'/age_nih_results`suf'.txt", replace delim(tab)

}

log close
