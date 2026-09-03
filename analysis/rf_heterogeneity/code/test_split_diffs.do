set more off
clear all
capture log close
program drop _all
set scheme modern
version 17
log using test_split_diffs.log, replace

* Group-difference test for every split on the main het coefplot, off the
* joint pooled-DiD PPML that event_study_het fits (split_type med_pi).
* Reads the panel analysis.do already wrote to ../temp/, so no rebuild.

local fes athr_id year
local vce_cl athr_id
local pairs `" "young old" "r1 r2" "high_pre_ppr low_pre_ppr" "high_nihd low_nihd" "big_msa small_msa" "hiw_tfnd low_tfnd" "hiw_lsf low_lsf" "hiw_endow low_endow" "'

foreach suf in _r1_r2 {
    cap confirm file "../temp/es_all_jrnls`suf'.dta"
    if _rc {
        di as error "../temp/es_all_jrnls`suf'.dta missing -- run analysis.do first."
        continue
    }
    local dummies
    foreach pair of local pairs {
        local dummies `dummies' `pair'
    }
    use athr_id year ppr_cnt exposure mkt_spend_shr `dummies' ///
        using ../temp/es_all_jrnls`suf', clear

    gen post       = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post

    cap matrix drop SPLITS
    local split_rows
    foreach pair of local pairs {
        local g1 : word 1 of `pair'
        local g2 : word 2 of `pair'
        cap drop Z_`g1' Z_`g2' S_`g1' S_`g2' PT_`g1'
        gen Z_`g1'  = Z_it       * `g1'
        gen Z_`g2'  = Z_it       * `g2'
        gen S_`g1'  = Z_share_it * `g1'
        gen S_`g2'  = Z_share_it * `g2'
        gen PT_`g1' = post * `g1'

        cap noi ppmlhdfe ppr_cnt Z_`g1' Z_`g2' S_`g1' S_`g2' PT_`g1', ///
            absorb(`fes') vce(cluster `vce_cl')
        if _rc {
            di as error "test_split_diffs`suf' `g1'/`g2': ppml failed (rc=" _rc "); skipping."
            continue
        }
        local b1   = _b[Z_`g1']
        local se1  = _se[Z_`g1']
        local b2   = _b[Z_`g2']
        local se2  = _se[Z_`g2']
        local Nfit = e(N)
        lincom Z_`g1' - Z_`g2'
        local b_diff  = r(estimate)
        local se_diff = r(se)
        local p_diff  = r(p)

        di as result _n "== all_jrnls`suf' ppr_cnt `g1' vs `g2' (N=`Nfit') =="
        di as text "  `g1': b=" %8.4f `b1' " (se=" %7.4f `se1' ")"
        di as text "  `g2': b=" %8.4f `b2' " (se=" %7.4f `se2' ")"
        di as text "  diff, joint VCE:  b=" %8.4f `b_diff' " se=" %7.4f `se_diff' " p=" %6.4f `p_diff'

        matrix SPLITS = nullmat(SPLITS) \ ///
            (`b1', `se1', `b2', `se2', `b_diff', `se_diff', `p_diff', `Nfit')
        local split_rows `split_rows' `g1'
    }

    if "`split_rows'" != "" {
        matrix colnames SPLITS = b_g1 se_g1 b_g2 se_g2 b_diff se_diff p_diff N
        matrix rownames SPLITS = `split_rows'
        di as result _n "== all_jrnls`suf' ppr_cnt: g1 - g2 summary across coefplot splits (rows = g1) =="
        matlist SPLITS, format(%9.4f) lines(oneline)
    }
}

log close
