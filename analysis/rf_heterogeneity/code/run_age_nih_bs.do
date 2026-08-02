set more off
clear all
capture log close
set scheme modern
version 17
set maxvar 20000

log using run_age_nih_bs.log, replace text

local samp   all_jrnls
local suf    _r1_r2
local fes    athr_id year
local vce_cl athr_id
local yvars  n_grants nih_total_cost
local pairs  `" "young old" "young_nih old_nih" "'

use ../temp/es_`samp'`suf', clear
gen post       = year >= 2014
gen Z_it       = exposure      * post
gen Z_share_it = mkt_spend_shr * post

cap mkdir "../output/figures/`samp'/ppml_pdid_het_bs"

foreach yvar of local yvars {
    local bs_lbl "`yvar'"
    if "`yvar'" == "n_grants"       local bs_lbl "Active NIH Research Grants"
    if "`yvar'" == "nih_total_cost" local bs_lbl "NIH Award Dollars"

    foreach pair of local pairs {
        local g1 : word 1 of `pair'
        local g2 : word 2 of `pair'

        foreach v in Z_`g1' Z_`g2' S_`g1' S_`g2' PT_`g1' _mu _z_work _dvar _fwlw _y_r _Z_r {
            cap drop `v'
        }
        gen Z_`g1'  = Z_it       * `g1'
        gen Z_`g2'  = Z_it       * `g2'
        gen S_`g1'  = Z_share_it * `g1'
        gen S_`g2'  = Z_share_it * `g2'
        gen PT_`g1' = post       * `g1'

        di as text _n "==== pdid binscatter fit: `yvar' `g1' vs `g2' ===="
        cap noi ppmlhdfe `yvar' Z_`g1' Z_`g2' S_`g1' S_`g2' PT_`g1', ///
            absorb(`fes') vce(cluster `vce_cl') d(_dvar)
        if _rc {
            di as error "run_age_nih_bs: `yvar' `g1'/`g2' joint fit failed; skipping."
            continue
        }
        local b_`g1'  = _b[Z_`g1']
        local se_`g1' = _se[Z_`g1']
        local b_`g2'  = _b[Z_`g2']
        local se_`g2' = _se[Z_`g2']

        predict double _mu, mu
        gen double _z_work = ln(_mu) + (`yvar' - _mu)/_mu if !mi(_mu) & _mu > 0
        gen double _fwlw   = _mu                          if !mi(_mu) & _mu > 0

        foreach grp in `g1' `g2' {
            local other = cond("`grp'" == "`g1'", "`g2'", "`g1'")
            foreach v in _y_r _Z_r {
                cap drop `v'
            }
            cap noi qui reghdfe _z_work Z_`other' S_`g1' S_`g2' PT_`g1' if !mi(_fwlw) [pw=_fwlw], ///
                absorb(`fes') residuals(_y_r)
            if _rc == 0 cap noi qui reghdfe Z_`grp' Z_`other' S_`g1' S_`g2' PT_`g1' if !mi(_fwlw) [pw=_fwlw], ///
                absorb(`fes') residuals(_Z_r)
            if _rc {
                di as error "run_age_nih_bs FWL `grp' failed; skipping plot."
                continue
            }
            gunique athr_id if `grp' == 1 & !mi(_y_r) & !mi(_Z_r)
            local n_pis = r(unique)
            gunique inst_id if `grp' == 1 & !mi(_y_r) & !mi(_Z_r)
            local n_insts = r(unique)
            local b_str  : dis %7.3f `b_`grp''
            local se_str : dis %7.3f `se_`grp''
            di as text "BS `yvar' `grp': beta=`b_str' se=`se_str' PIs=`n_pis' Insts=`n_insts'"
            binscatter _y_r _Z_r [aw=_fwlw] if `grp' == 1 & !mi(_y_r) & !mi(_Z_r), n(30) ///
                xtitle("Exposure x Post") ///
                ytitle("{&Delta} Log Expected `bs_lbl'") ///
                xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                msymbol(O) mcolor(ebblue) ///
                note("Num. PIs: `n_pis'   Num. Insts: `n_insts'" "{&beta} = `b_str' (SE: `se_str')", ///
                     size(small) pos(7) ring(1) justification(left)) ///
                plotregion(margin(sides))
            graph export ///
                ../output/figures/`samp'/ppml_pdid_het_bs/ppml_pdid_`yvar'_`grp'_agenih`suf'.pdf, replace
        }
    }
}

log close
