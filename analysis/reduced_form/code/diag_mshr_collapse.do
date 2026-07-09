// Why do the exposure event-study coefs collapse toward zero in 2016+ when
// mshr_lag/mshr_lead controls are added? Answer: are we losing identifying
// variation (collinearity) or absorbing something substantive?
set more off
clear all
capture log close
program drop _all
preliminaries
version 17

log using ../output/diag_mshr_collapse.log, replace text

use ../temp/es_all_jrnls_r1_r2_public, clear

//------------------------------------------------------------------
// 1. PI-level collinearity between exposure and mkt_spend_shr
//------------------------------------------------------------------
preserve
    bys athr_id: keep if _n == 1
    di as text _newline "=== PI-LEVEL DISTRIBUTIONS (1 row per PI) ==="
    sum exposure mkt_spend_shr, d
    di as text _newline "=== CORR + REG: exposure ~ mkt_spend_shr ==="
    corr exposure mkt_spend_shr
    reg exposure mkt_spend_shr
    di as text "  R^2 = " %6.4f e(r2) "   slope = " %6.4f _b[mkt_spend_shr]
    // How much of exposure IS mkt_spend_shr times a constant?
    predict exp_hat, xb
    predict exp_res, resid
    sum exp_hat exp_res
    di as text _newline "  → residual sd (share of exposure orthogonal to mkt_spend_shr) = " %6.4f r(sd)
    di as text "  → fitted   sd (share of exposure explained by mkt_spend_shr) = " %6.4f `=r(sd)'
restore

//------------------------------------------------------------------
// 2. Build event-time interactions (mirror event_study exactly)
//------------------------------------------------------------------
gen rel = year - 2014
qui sum rel
local abs_lead = abs(r(min))
local abs_lag  = abs(r(max))
forval i = 1/`abs_lead' {
    gen int_lead`i'  = exposure       * (rel == -`i')
    gen mshr_lead`i' = mkt_spend_shr  * (rel == -`i')
}
forval i = 0/`abs_lag' {
    gen int_lag`i'  = exposure       * (rel == `i')
    gen mshr_lag`i' = mkt_spend_shr  * (rel == `i')
}
local int_leads
local mshr_leads
forval i = 2/`abs_lead' {
    local int_leads  int_lead`i'  `int_leads'
    local mshr_leads mshr_lead`i' `mshr_leads'
}
local int_lags
local mshr_lags
forval i = 0/`abs_lag' {
    local int_lags  `int_lags'  int_lag`i'
    local mshr_lags `mshr_lags' mshr_lag`i'
}

//------------------------------------------------------------------
// 3. Per-year collinearity of int_lag_k and mshr_lag_k over the panel
//------------------------------------------------------------------
di as text _newline "=== PER-YEAR CORR(int_lag_k, mshr_lag_k) OVER FULL PANEL ==="
forval i = 0/`abs_lag' {
    qui corr int_lag`i' mshr_lag`i'
    di as text "  rel=`i' (year=`=`i'+2014'):  corr = " %6.4f r(rho)
}

//------------------------------------------------------------------
// 4. Coefficient sensitivity per year: base vs +mshr controls
//------------------------------------------------------------------
foreach yvar in cite_affl_wt ppr_cnt {
    di as text _newline "=== `yvar': PER-YEAR SENSITIVITY TO ADDING mshr CONTROLS ==="

    qui reghdfe `yvar' `int_leads' `int_lags' int_lead1, ///
                absorb(athr_id year) vce(cluster athr_id)
    forval i = 0/`abs_lag' {
        local b_base_`i'  = _b[int_lag`i']
        local se_base_`i' = _se[int_lag`i']
    }
    // partial R^2 numerator (SSE_base)
    local sse_base = e(rss)

    qui reghdfe `yvar' `int_leads' `int_lags' int_lead1 ///
                       `mshr_leads' `mshr_lags' mshr_lead1, ///
                absorb(athr_id year) vce(cluster athr_id)
    forval i = 0/`abs_lag' {
        local b_ctrl_`i'  = _b[int_lag`i']
        local se_ctrl_`i' = _se[int_lag`i']
        local mb_`i'      = _b[mshr_lag`i']
        local mse_`i'     = _se[mshr_lag`i']
    }

    di as text " rel  yr    b_base    se_base    b_ctrl    se_ctrl   Δb/base     mshr_b    mshr_se   se_ratio"
    forval i = 0/`abs_lag' {
        local yr = `i' + 2014
        local delta_pct = ((`b_ctrl_`i'' - `b_base_`i'') / `b_base_`i'') * 100
        local se_ratio  = `se_ctrl_`i'' / `se_base_`i''
        di as text " " %2.0f `i' "  " %4.0f `yr' ///
            "  " %8.4f `b_base_`i''  "  " %8.4f `se_base_`i'' ///
            "  " %8.4f `b_ctrl_`i''  "  " %8.4f `se_ctrl_`i'' ///
            "  " %7.1f `delta_pct' " %" ///
            "  " %8.4f `mb_`i''      "  " %8.4f `mse_`i'' ///
            "  " %5.2f `se_ratio' "x"
    }
}

//------------------------------------------------------------------
// 5. Frisch-Waugh partial-R^2 of int_lag2 (year 2016)
//     What fraction of within-athr, within-year variation in int_lag2 is
//     already spanned by mshr_lag2 (and the other regressors)?
//------------------------------------------------------------------
di as text _newline "=== FRISCH-WAUGH: variance in int_lag2 orthogonal to full spec ==="

// (a) residualize int_lag2 on FE alone
qui reghdfe int_lag2, absorb(athr_id year) residuals(_r_fe_only)
qui sum _r_fe_only
local sd_fe_only = r(sd)

// (b) residualize int_lag2 on FE + mshr_lag2
qui reghdfe int_lag2 mshr_lag2, absorb(athr_id year) residuals(_r_plus_mshr)
qui sum _r_plus_mshr
local sd_plus_mshr = r(sd)

// (c) residualize int_lag2 on FE + all other year interactions in the base spec
local others
foreach v of local int_leads {
    local others `others' `v'
}
foreach v of local int_lags {
    if "`v'" != "int_lag2" local others `others' `v'
}
local others `others' int_lead1
qui reghdfe int_lag2 `others', absorb(athr_id year) residuals(_r_base)
qui sum _r_base
local sd_base = r(sd)

// (d) residualize int_lag2 on FE + all other year interactions + all mshr interactions
local others_full `others' `mshr_leads' `mshr_lags' mshr_lead1
qui reghdfe int_lag2 `others_full', absorb(athr_id year) residuals(_r_ctrl)
qui sum _r_ctrl
local sd_ctrl = r(sd)

di as text "  sd of int_lag2 after netting out ..."
di as text "    (a) FE only                              : " %8.4f `sd_fe_only'
di as text "    (b) FE + mshr_lag2                       : " %8.4f `sd_plus_mshr'  ///
    "   (retained variance = " %5.1f (100*`sd_plus_mshr'^2/`sd_fe_only'^2) "%)"
di as text "    (c) FE + all other exposure×year         : " %8.4f `sd_base'       ///
    "   (retained variance = " %5.1f (100*`sd_base'^2/`sd_fe_only'^2) "%)"
di as text "    (d) FE + all other exposure×year + mshr×year: " %8.4f `sd_ctrl'    ///
    "   (retained variance = " %5.1f (100*`sd_ctrl'^2/`sd_fe_only'^2) "%)"
di as text "  → (d)/(c) = fraction of int_lag2 identifying variation that survives adding mshr controls"
di as text "     = " %5.1f (100*`sd_ctrl'^2/`sd_base'^2) "%"

//------------------------------------------------------------------
// 6. Alternative parameterization: is per-share exposure orthogonal?
//     Define avg_g = exposure / mkt_spend_shr. Under BHJ this is the
//     "average shock experienced per unit of covered spending" and is
//     mechanically less correlated with the coverage sum than raw exposure.
//------------------------------------------------------------------
gen avg_g = exposure / mkt_spend_shr if mkt_spend_shr > 0
preserve
    bys athr_id: keep if _n == 1
    di as text _newline "=== PI-LEVEL corr WITH avg_g = exposure/mkt_spend_shr ==="
    corr avg_g mkt_spend_shr
    di as text "  → if this is much smaller than corr(exposure, mkt_spend_shr), avg_g is a cleaner exposure measure"
restore

forval i = 1/`abs_lead' {
    gen avg_g_lead`i' = avg_g * (rel == -`i')
    replace avg_g_lead`i' = 0 if mi(avg_g_lead`i')
}
forval i = 0/`abs_lag' {
    gen avg_g_lag`i' = avg_g * (rel == `i')
    replace avg_g_lag`i' = 0 if mi(avg_g_lag`i')
}
local avg_g_leads
forval i = 2/`abs_lead' {
    local avg_g_leads avg_g_lead`i' `avg_g_leads'
}
local avg_g_lags
forval i = 0/`abs_lag' {
    local avg_g_lags `avg_g_lags' avg_g_lag`i'
}

di as text _newline "=== ALTERNATIVE ES: avg_g = exposure/mkt_spend_shr, + mshr controls ==="
foreach yvar in cite_affl_wt ppr_cnt {
    di as text _newline "--- `yvar' ---"
    qui reghdfe `yvar' `avg_g_leads' `avg_g_lags' avg_g_lead1 ///
                       `mshr_leads' `mshr_lags' mshr_lead1, ///
                absorb(athr_id year) vce(cluster athr_id)
    di as text " rel  yr    b_avg_g    se_avg_g"
    forval i = 0/`abs_lag' {
        local yr = `i' + 2014
        di as text " " %2.0f `i' "  " %4.0f `yr' "  " ///
            %8.4f _b[avg_g_lag`i'] "  " %8.4f _se[avg_g_lag`i']
    }
}

log close
