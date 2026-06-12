set more off
clear all
capture log close
log using ../temp/diag_meanrev.log, replace text

local samp all_jrnls
local suf  _r1_r2_public
local fes  athr_id year

program summ_grp
    syntax, hi(string) lo(string) tag(string)
    foreach grp in `hi' `lo' {
        local b_post = 0
        local n_post = 0
        local b_pre  = 0
        local n_pre  = 0
        forval k = 0/5 {
            local b = _b[int_lag`k'_`grp']
            local b_post = `b_post' + `b'
            local n_post = `n_post' + 1
        }
        forval k = 2/4 {
            local b = _b[int_lead`k'_`grp']
            local b_pre = `b_pre' + `b'
            local n_pre = `n_pre' + 1
        }
        local post_mean = `b_post' / `n_post'
        local pre_mean = `b_pre' / `n_pre'
        di as text "`tag' `grp': pre_mean=" %6.3f `pre_mean' " post_mean=" %6.3f `post_mean'
    }
end

foreach yvar in ppr_cnt cite_affl_wt {
    di as text "============================================"
    di as text "==== `yvar' ===="
    di as text "============================================"

    foreach pair in "high_pre_ppr low_pre_ppr" "high_grants low_grants" {
        local hi : word 1 of `pair'
        local lo : word 2 of `pair'

        di as text "---- heterogeneous ES (base specification): `hi' vs `lo' ----"
        use ../temp/es_`samp'`suf', clear
        cap drop rel int_lead* int_lag*
        gen rel = year - 2014
        qui sum rel
        local abs_lag  = abs(r(max))
        local abs_lead = abs(r(min))
        forval i = 1/`abs_lead' {
            gen int_lead`i' = exposure if rel == -`i'
        }
        forval i = 1/`abs_lag' {
            gen int_lag`i'  = exposure if rel == `i'
        }
        gen int_lag0 = exposure if rel == 0
        ds int_lead* int_lag*
        foreach var in `r(varlist)' {
            replace `var' = 0 if mi(`var')
        }
        foreach grp in `hi' `lo' {
            forval i = 1/`abs_lead' {
                gen int_lead`i'_`grp' = int_lead`i' * `grp'
            }
            forval i = 0/`abs_lag' {
                gen int_lag`i'_`grp' = int_lag`i' * `grp'
            }
        }
        local leads_hi
        local lags_hi
        local leads_lo
        local lags_lo
        forval i = 2/`abs_lead' {
            local leads_hi `leads_hi' int_lead`i'_`hi'
            local leads_lo `leads_lo' int_lead`i'_`lo'
        }
        forval i = 0/`abs_lag' {
            local lags_hi `lags_hi' int_lag`i'_`hi'
            local lags_lo `lags_lo' int_lag`i'_`lo'
        }
        cap noi reghdfe `yvar' `leads_hi' `lags_hi' `leads_lo' `lags_lo' ///
                int_lead1_`hi' int_lead1_`lo', absorb(`fes') vce(cluster athr_id)
        summ_grp, hi(`hi') lo(`lo') tag("HET")

        di as text "---- group-absorbed ES (within-group exposure only): `hi' vs `lo' ----"
        forval i = 2/`abs_lead' {
            cap drop g1rel_lead`i'
            gen g1rel_lead`i' = (rel == -`i') * `hi'
        }
        forval i = 0/`abs_lag' {
            cap drop g1rel_lag`i'
            gen g1rel_lag`i'  = (rel == `i')  * `hi'
        }
        local g1rel_leads
        local g1rel_lags
        forval i = 2/`abs_lead' {
            local g1rel_leads `g1rel_leads' g1rel_lead`i'
        }
        forval i = 0/`abs_lag' {
            local g1rel_lags `g1rel_lags' g1rel_lag`i'
        }
        cap noi reghdfe `yvar' `leads_hi' `lags_hi' `leads_lo' `lags_lo' ///
                int_lead1_`hi' int_lead1_`lo' `g1rel_leads' `g1rel_lags', ///
                absorb(`fes') vce(cluster athr_id)
        summ_grp, hi(`hi') lo(`lo') tag("ABS")

        // also print the absorbed-trend (g1's common trend relative to g2)
        local b_post = 0
        forval k = 0/5 {
            local b_post = `b_post' + _b[g1rel_lag`k']
        }
        local b_pre = 0
        forval k = 2/4 {
            local b_pre = `b_pre' + _b[g1rel_lead`k']
        }
        local post_mean = `b_post' / 6
        local pre_mean  = `b_pre' / 3
        di as text "    --> absorbed common trend (`hi' minus `lo'): pre_mean=" %6.3f `pre_mean' " post_mean=" %6.3f `post_mean'
    }
}

log close
