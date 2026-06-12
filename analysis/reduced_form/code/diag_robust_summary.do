set more off
clear all
capture log close
log using ../temp/diag_robust_summary.log, replace text

local samp all_jrnls
local suf  _r1_r2_public

program summ_es
    syntax, fpath(string) tag(string)
    use "`fpath'", clear
    qui sum rel
    if r(N) == 0 {
        di as text "`tag': (empty)"
        exit
    }
    qui sum b if rel < -1
    local pre_max_b = r(max)
    local pre_min_b = r(min)
    local pre_mean_b = r(mean)
    qui sum b if rel >= 0 & rel <= 5
    local post_mean_b = r(mean)
    qui sum se if rel >= 0 & rel <= 5
    local post_mean_se = r(mean)
    qui count if rel >= 0 & (lb > 0 | ub < 0)
    local n_post_signif = r(N)
    qui count if rel < -1 & (lb > 0 | ub < 0)
    local n_pre_signif = r(N)
    di as text "`tag': pre_mean=" %5.3f `pre_mean_b' " pre_minmax=[" %5.3f `pre_min_b' "," %5.3f `pre_max_b' "] post_mean=" %5.3f `post_mean_b' " post_mean_se=" %5.3f `post_mean_se' " n_pre_signif=`n_pre_signif' n_post_signif=`n_post_signif'"
end

di as text "================ MAIN ES (no heterogeneity) ================"
foreach yvar in ppr_cnt cite_affl_wt {
    di as text "---- `yvar' ----"
    foreach spec in base ageCtrl noattrit unbal clusterYrFE {
        cap noi summ_es, fpath(../temp/robust_es_main_`yvar'_`spec'_`samp'`suf'.dta) tag("main_`spec'")
        if _rc cap noi summ_es, fpath(../temp/robust_es_main_`spec'_`yvar'_`samp'`suf'.dta) tag("main_`spec'")
    }
}

di as text "================ AGE-CONTROL HETEROGENEITY (high/low pre_ppr, high/low grants) ================"
foreach yvar in ppr_cnt cite_affl_wt {
    di as text "---- `yvar' ----"
    foreach grp in high_pre_ppr low_pre_ppr high_grants low_grants {
        cap noi summ_es, fpath(../temp/robust_es_main_`yvar'_ageCtrl_`samp'`suf'.dta) tag("ageCtrl_`grp'_skip")
    }
}

di as text "================ GROUP-ABSORBED ES (within-group exposure only) ================"
foreach yvar in ppr_cnt cite_affl_wt {
    di as text "---- `yvar' ----"
    foreach grp in high_pre_ppr low_pre_ppr high_grants low_grants above_median below_median young old {
        cap noi summ_es, fpath(../temp/robust_es_grpabsorb_`grp'_`samp'`suf'.dta) tag("grpAbsorb_`grp'")
    }
}

di as text "================ UNBALANCED PANEL ES ================"
foreach yvar in ppr_cnt cite_affl_wt {
    di as text "---- `yvar' ----"
    foreach grp in high_pre_ppr low_pre_ppr high_grants low_grants {
        cap noi summ_es, fpath(../temp/robust_es_unbal_`grp'_`yvar'_`samp'`suf'.dta) tag("unbal_`grp'")
    }
}

di as text "================ FIELD-CLUSTER ES (top-10 FOIA-containing clusters) ================"
foreach yvar in ppr_cnt cite_affl_wt {
    di as text "---- `yvar' ----"
    foreach c in 0 6 14 36 43 45 49 55 62 68 {
        cap noi summ_es, fpath(../temp/robust_es_clusterTop_`c'_`yvar'_`samp'`suf'.dta) tag("clusterTop_`c'")
    }
}

di as text "================ CLUSTER-YEAR-FE MAIN ES ================"
foreach yvar in ppr_cnt cite_affl_wt {
    cap noi summ_es, fpath(../temp/robust_es_main_clusterYrFE_`yvar'_`samp'`suf'.dta) tag("`yvar'_clusterYrFE")
}

log close
