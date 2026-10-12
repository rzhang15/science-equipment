set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries, loadglob(../external/lib/globals.txt)
adopath ++ "../external/lib/stata"
version 17
global WEIGHT_MSIM 0
* RUN_ROBUSTNESS : 1 = run the robustness program (slow)
global RUN_ROBUSTNESS 0
global RUN_JOINT_TEST 0

program main
    detect_position_outcomes
    local pubs 0
    if "$RUN_PUBLIC" == "1" local pubs 0 1
    local r1_opts 0
    if "$RUN_R1_ONLY" == "1" local r1_opts 0 1
    cap mkdir "../output/figures/all_jrnls"
    foreach pub of local pubs {
        foreach r1 of local r1_opts {
            di as text _newline "=========================================="
            di as text "  RUNNING sample=all_jrnls PUBLIC=`pub' R1_ONLY=`r1'"
            di as text "=========================================="
            mat drop _all
            placebo_treatment, samp(all_jrnls) r1r2(1) public(`pub') r1_only(`r1')
            trim_top,          samp(all_jrnls) r1r2(1) public(`pub') r1_only(`r1')
            if "$RUN_ROBUSTNESS" == "1" robustness,         samp(all_jrnls) r1r2(1) public(`pub') r1_only(`r1')
            if "$RUN_JOINT_TEST" == "1" joint_outcome_test, samp(all_jrnls) r1r2(1) public(`pub') r1_only(`r1')
            output_tables,     samp(all_jrnls) r1r2(1) public(`pub') r1_only(`r1')
        }
    }
end

program placebo_treatment
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
    local fes athr_id year
    local vce_cl athr_id
    if "$FE_MODE" == "athr_clyr" {
        local fes athr_id i.cluster_30#i.year
    }
    if "$FE_MODE" == "inst_cluster" {
        local fes inst_id cluster_30 year
        local vce_cl inst_id
    }
    if "$FE_MODE" == "inst_cluster_fldyr" {
        local fes inst_id i.cluster_30#i.year
        local vce_cl inst_id
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"

    local outcomes ppr_cnt

    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'
    cap mkdir ../output/figures/`samp'

    foreach placebo_yr in 2011 2012 {
        use ../external/prepped_samples/es_`samp'`suf', clear
        keep if year <= 2013

        gen placebo_post   = year >= `placebo_yr'
        gen Z_placebo      = exposure      * placebo_post
        gen Z_share_placebo = mkt_spend_shr * placebo_post

        foreach yvar of local outcomes {
            local b     = .
            local se    = .
            local b_s   = .
            local se_s  = .
            local N     = .
            local r2_p  = .
            local pre_mean = .
            cap noi ppmlhdfe `yvar' Z_placebo Z_share_placebo, ///
                    absorb(`fes') vce(cluster `vce_cl')
            local rc = _rc
            if `rc' == 0 {
                local b    = _b[Z_placebo]
                local se   = _se[Z_placebo]
                local b_s  = _b[Z_share_placebo]
                local se_s = _se[Z_share_placebo]
                local N    = e(N)
                local r2_p = e(r2_p)
                qui sum `yvar' if year < `placebo_yr' & e(sample)
                local pre_mean = r(mean)
            }
            else di as error "placebo_treatment `yvar' (placebo=`placebo_yr') ppml failed (rc=`rc')"

            local t = cond(`se' > 0 & !mi(`se'), `b' / `se', .)
            di as text "placebo_treatment `samp'`suf' `yvar' (placebo=`placebo_yr'):" ///
                _newline "    ppmlhdfe (+share)  b=" %8.4f `b'   "  se=" %8.4f `se'   "  t=" %6.2f `t' ///
                "  b_share=" %8.4f `b_s' "  se_share=" %8.4f `se_s' ///
                "  pre_mean=" %8.4f `pre_mean' "  N=" %8.0f `N'

            cap mat drop placebo`placebo_yr'_`yvar'
            mat placebo`placebo_yr'_`yvar' = J(7,1,.)
            mat placebo`placebo_yr'_`yvar'[1,1] = `b'
            mat placebo`placebo_yr'_`yvar'[2,1] = `se'
            mat placebo`placebo_yr'_`yvar'[3,1] = `b_s'
            mat placebo`placebo_yr'_`yvar'[4,1] = `se_s'
            mat placebo`placebo_yr'_`yvar'[5,1] = `pre_mean'
            mat placebo`placebo_yr'_`yvar'[6,1] = `N'
            mat placebo`placebo_yr'_`yvar'[7,1] = `r2_p'
            mat rownames placebo`placebo_yr'_`yvar' = b_exp se_exp b_share se_share pre_mean N r2_p
            mat colnames placebo`placebo_yr'_`yvar' = ppmlhdfe_wshr
        }
    }

    foreach placebo_yr in 2011 2012 {
        foreach yvar in ppr_cnt {
            local poisson_name "publications"
            local ppml_ytit "Output-cost elasticity"

            use ../external/prepped_samples/es_`samp'`suf', clear
            cap drop pl_rel pl_int_lead* pl_int_lag* pl_mshr_lead* pl_mshr_lag*
            gen pl_rel = year - `placebo_yr'
            qui sum pl_rel
            local pl_abs_lag  = abs(r(max))
            local pl_abs_lead = abs(r(min))
            forval i = 1/`pl_abs_lead' {
                gen pl_int_lead`i'  = exposure      if pl_rel == -`i'
                gen pl_mshr_lead`i' = mkt_spend_shr if pl_rel == -`i'
            }
            forval i = 0/`pl_abs_lag' {
                gen pl_int_lag`i'  = exposure      if pl_rel == `i'
                gen pl_mshr_lag`i' = mkt_spend_shr if pl_rel == `i'
            }
            ds pl_int_lead* pl_int_lag* pl_mshr_lead* pl_mshr_lag*
            foreach v in `r(varlist)' {
                replace `v' = 0 if mi(`v')
            }
            local pl_int_leads
            local pl_int_lags
            local pl_mshr_leads
            local pl_mshr_lags
            forval i = 2/`pl_abs_lead' {
                local pl_int_leads  pl_int_lead`i'  `pl_int_leads'
                local pl_mshr_leads pl_mshr_lead`i' `pl_mshr_leads'
            }
            forval i = 0/`pl_abs_lag' {
                local pl_int_lags  `pl_int_lags'  pl_int_lag`i'
                local pl_mshr_lags `pl_mshr_lags' pl_mshr_lag`i'
            }

            cap noi ppmlhdfe `yvar' `pl_int_leads' `pl_int_lags' ///
                                    `pl_mshr_leads' `pl_mshr_lags', ///
                    absorb(`fes') vce(cluster `vce_cl')
            local rc = _rc
            if `rc' {
                di as error "placebo ES ppmlhdfe `yvar' yr`placebo_yr' failed (rc=`rc'); skipping."
                continue
            }

            preserve
            cap mat drop es
            foreach var in `pl_int_leads' `pl_int_lags' pl_int_lead1 {
                if "`var'" == "pl_int_lead1" {
                    mat row = 0,0
                }
                else {
                    mat row = _b[`var'], _se[`var']
                }
                mat es = nullmat(es) \ row
            }
            svmat es
            keep es1 es2
            drop if mi(es1)
            rename (es1 es2) (b se)
            gen ub = b + 1.96*se
            gen lb = b - 1.96*se
            gen rel = -`pl_abs_lead' if _n == 1
            replace rel = rel[_n-1]+1 if _n > 1
            replace rel = rel + 1 if rel >= -1
            replace rel = -1 if rel == `pl_abs_lag' + 1
            gen year = rel + `placebo_yr'
            hashsort rel
            sum ub, d
            local ymax = round(r(max), 0.1)
            sum lb, d
            local ymin = round(r(min), 0.1)
            if `ymin' > 0 local ymin = 0
            local ref_yr = `placebo_yr' - 1
            tw rcap ub lb year if year != `ref_yr', lcolor(dkorange%70) msize(vsmall) || ///
              scatter b year, mcolor(dkorange) ///
              , xlab(2010(1)2019) xtitle("Year (placebo treatment at `placebo_yr')") ///
                ytitle("`ppml_ytit'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                ylab(`ymin'(0.1)`ymax') yline(0, lcolor(gs10) lpattern(solid)) ///
                xline(2014, lpattern(dash) lcolor(gs10)) ///
                title("Placebo ES: treatment shifted to `placebo_yr' (real: 2014)", size(small)) ///
                legend(off) plotregion(margin(sides))
            fig_export, path("../output/figures/`samp'/placebo_es_`yvar'_yr`placebo_yr'`suf'.pdf")
            save ../temp/placebo_es_`yvar'_yr`placebo_yr'`suf', replace
            restore
        }
    }
end

program trim_top
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
    local fes athr_id year
    local vce_cl athr_id
    if "$FE_MODE" == "athr_clyr" {
        local fes athr_id i.cluster_30#i.year
    }
    if "$FE_MODE" == "inst_cluster" {
        local fes inst_id cluster_30 year
        local vce_cl inst_id
    }
    if "$FE_MODE" == "inst_cluster_fldyr" {
        local fes inst_id i.cluster_30#i.year
        local vce_cl inst_id
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"

    local outcomes ppr_cnt
    local trims 0 1 5 10 25

    cap mkdir ../output/tables/`samp'
    cap mkdir ../output/figures/`samp'

    foreach trim of local trims {
        use ../external/prepped_samples/es_`samp'`suf', clear
        qui gunique athr_id
        local n_pre = r(unique)
        if `trim' > 0 {
            bys athr_id: gen _one = _n == 1
            local p = 100 - `trim'
            qui _pctile pre_ppr_cnt_sum if _one == 1, p(`p')
            local cut = r(r1)
            drop if pre_ppr_cnt_sum > `cut'
            drop _one
            qui gunique athr_id
            local n_post = r(unique)
            di as text "trim_top `samp'`suf' trim=`trim'%: cut=" %7.2f `cut' ///
                "  PIs dropped " (`n_pre' - `n_post') " / `n_pre' (kept " %7.4f (`n_post' / `n_pre') ")"
        }
        else {
            local n_post = `n_pre'
            di as text "trim_top `samp'`suf' trim=0: full sample, N PIs = `n_post'"
        }

        gen post       = year >= 2014
        gen Z_it       = exposure      * post
        gen Z_share_it = mkt_spend_shr * post

        foreach yvar of local outcomes {
            local lb = .
            local lse = .
            local lN = .
            local l_pmn = .
            cap noi reghdfe `yvar' Z_it Z_share_it, absorb(`fes') vce(cluster `vce_cl')
            if _rc == 0 {
                local lb  = _b[Z_it]
                local lse = _se[Z_it]
                local lN  = e(N)
                qui sum `yvar' if year < 2014 & e(sample)
                local l_pmn = r(mean)
            }

            local pb = .
            local pse = .
            local pN = .
            local p_pmn = .
            cap noi ppmlhdfe `yvar' Z_it Z_share_it, absorb(`fes') vce(cluster `vce_cl')
            if _rc == 0 {
                local pb  = _b[Z_it]
                local pse = _se[Z_it]
                local pN  = e(N)
                qui sum `yvar' if year < 2014 & e(sample)
                local p_pmn = r(mean)
            }

            di as text "  trim=`trim'% `yvar': reghdfe b=" %8.4f `lb' "  se=" %8.4f `lse' ///
                "    ppml b=" %8.4f `pb' "  se=" %8.4f `pse' "    pre_mean=" %7.4f `l_pmn'

            cap mat drop trim`trim'_`yvar'
            mat trim`trim'_`yvar' = J(5,2,.)
            mat trim`trim'_`yvar'[1,1] = `lb'
            mat trim`trim'_`yvar'[2,1] = `lse'
            mat trim`trim'_`yvar'[3,1] = `l_pmn'
            mat trim`trim'_`yvar'[4,1] = `lN'
            mat trim`trim'_`yvar'[5,1] = `n_post'
            mat trim`trim'_`yvar'[1,2] = `pb'
            mat trim`trim'_`yvar'[2,2] = `pse'
            mat trim`trim'_`yvar'[3,2] = `p_pmn'
            mat trim`trim'_`yvar'[4,2] = `pN'
            mat trim`trim'_`yvar'[5,2] = `n_post'
            mat rownames trim`trim'_`yvar' = b se pre_mean N n_PIs
            mat colnames trim`trim'_`yvar' = reghdfe ppmlhdfe
        }
    }

    foreach yvar in ppr_cnt {
        local var_name "Publication count"
        local poisson_name "publications"
        local ppml_ytit "Output-cost elasticity"

        preserve
        clear
        set obs 5
        gen trim = .
        gen b  = .
        gen se = .
        local i = 1
        foreach t of local trims {
            replace trim = `t' in `i'
            cap confirm matrix trim`t'_`yvar'
            if !_rc {
                replace b  = trim`t'_`yvar'[1,1] in `i'
                replace se = trim`t'_`yvar'[2,1] in `i'
            }
            local ++i
        }
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        tw rcap ub lb trim, lcolor(ebblue%70) msize(small) || ///
           scatter b trim, mcolor(ebblue) msize(medium) ///
           , xlab(0 "Full sample" 1 "Drop top 1%" 5 "5%" 10 "10%" 25 "25%", labsize(small)) ///
             xtitle("Top-pre-pub PIs dropped") ///
             ytitle("pdid {&beta}: `var_name'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
             yline(0, lcolor(gs10) lpattern(solid)) ///
             title("Trim-top sensitivity: `var_name'", size(small)) ///
             legend(off) plotregion(margin(sides))
        fig_export, path("../output/figures/`samp'/trim_top_`yvar'`suf'.pdf")
        restore

        preserve
        clear
        set obs 5
        gen trim = .
        gen b  = .
        gen se = .
        local i = 1
        foreach t of local trims {
            replace trim = `t' in `i'
            cap confirm matrix trim`t'_`yvar'
            if !_rc {
                replace b  = trim`t'_`yvar'[1,2] in `i'
                replace se = trim`t'_`yvar'[2,2] in `i'
            }
            local ++i
        }
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        tw rcap ub lb trim, lcolor(dkorange%70) msize(small) || ///
           scatter b trim, mcolor(dkorange) msize(medium) ///
           , xlab(0 "Full sample" 1 "Drop top 1%" 5 "5%" 10 "10%" 25 "25%", labsize(small)) ///
             xtitle("Top-pre-pub PIs dropped") ///
             ytitle("`ppml_ytit'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
             yline(0, lcolor(gs10) lpattern(solid)) ///
             title("Trim-top sensitivity (ppml): `var_name'", size(small)) ///
             legend(off) plotregion(margin(sides))
        fig_export, path("../output/figures/`samp'/trim_top_ppml_`yvar'`suf'.pdf")
        restore
    }
end

program joint_outcome_test
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"
    use ../external/prepped_samples/es_`samp'`suf', clear

    foreach v in cite_affl_wt ppr_cnt {
        cap gen ln_`v' = ln(1+`v')
    }

    gen post = year >= 2014
    gen Z_it = exposure * post
    gen Z_share_it = mkt_spend_shr * post

    qui sum ppr_cnt      if year < 2014
    local mean_ppr = r(mean)
    qui sum cite_affl_wt if year < 2014
    local mean_cite = r(mean)

    keep athr_id year Z_it Z_share_it ppr_cnt cite_affl_wt ln_ppr_cnt ln_cite_affl_wt

    preserve
        gen outcome = 1
        gen y_raw = cite_affl_wt
        gen y_ln  = ln_cite_affl_wt
        gen y_nrm = cite_affl_wt / `mean_cite'
        keep athr_id year Z_it Z_share_it outcome y_raw y_ln y_nrm
        save ../temp/stack_cite_`samp'`suf', replace
    restore
    gen outcome = 0
    gen y_raw = ppr_cnt
    gen y_ln  = ln_ppr_cnt
    gen y_nrm = ppr_cnt / `mean_ppr'
    keep athr_id year Z_it Z_share_it outcome y_raw y_ln y_nrm
    append using ../temp/stack_cite_`samp'`suf'

    egen athr_outcome = group(athr_id outcome)
    egen year_outcome = group(year outcome)
    gen Z_it_cite = Z_it * (outcome == 1)
    gen Z_share_it_cite = Z_share_it * (outcome == 1)

    cap mat drop joint_`samp'`suf'
    mat joint_`samp'`suf' = J(8,3,.)
    mat rownames joint_`samp'`suf' = b_ppr se_ppr b_cite se_cite b_diff se_diff Wald_F p_value
    mat colnames joint_`samp'`suf' = log norm_levels ppml

    reghdfe y_ln Z_it Z_it_cite Z_share_it Z_share_it_cite, absorb(athr_outcome year_outcome) vce(cluster athr_id)
    local b_ppr_ln  = _b[Z_it]
    local se_ppr_ln = _se[Z_it]
    local b_diff_ln = _b[Z_it_cite]
    local se_diff_ln = _se[Z_it_cite]
    qui lincom Z_it + Z_it_cite
    local b_cite_ln  = r(estimate)
    local se_cite_ln = r(se)
    qui test Z_it_cite
    local F_ln = r(F)
    local p_ln = r(p)
    mat joint_`samp'`suf'[1,1] = `b_ppr_ln'
    mat joint_`samp'`suf'[2,1] = `se_ppr_ln'
    mat joint_`samp'`suf'[3,1] = `b_cite_ln'
    mat joint_`samp'`suf'[4,1] = `se_cite_ln'
    mat joint_`samp'`suf'[5,1] = `b_diff_ln'
    mat joint_`samp'`suf'[6,1] = `se_diff_ln'
    mat joint_`samp'`suf'[7,1] = `F_ln'
    mat joint_`samp'`suf'[8,1] = `p_ln'

    reghdfe y_nrm Z_it Z_it_cite Z_share_it Z_share_it_cite, absorb(athr_outcome year_outcome) vce(cluster athr_id)
    local b_ppr_nr  = _b[Z_it]
    local se_ppr_nr = _se[Z_it]
    local b_diff_nr = _b[Z_it_cite]
    local se_diff_nr = _se[Z_it_cite]
    qui lincom Z_it + Z_it_cite
    local b_cite_nr  = r(estimate)
    local se_cite_nr = r(se)
    qui test Z_it_cite
    local F_nr = r(F)
    local p_nr = r(p)
    mat joint_`samp'`suf'[1,2] = `b_ppr_nr'
    mat joint_`samp'`suf'[2,2] = `se_ppr_nr'
    mat joint_`samp'`suf'[3,2] = `b_cite_nr'
    mat joint_`samp'`suf'[4,2] = `se_cite_nr'
    mat joint_`samp'`suf'[5,2] = `b_diff_nr'
    mat joint_`samp'`suf'[6,2] = `se_diff_nr'
    mat joint_`samp'`suf'[7,2] = `F_nr'
    mat joint_`samp'`suf'[8,2] = `p_nr'

    local b_ppr_pp = .
    local se_ppr_pp = .
    local b_cite_pp = .
    local se_cite_pp = .
    local b_diff_pp = .
    local se_diff_pp = .
    local F_pp = .
    local p_pp = .
    cap noi ppmlhdfe y_raw Z_it Z_it_cite Z_share_it Z_share_it_cite, absorb(athr_outcome year_outcome) vce(cluster athr_id)
    local rc = _rc
    if `rc' == 0 {
        local b_ppr_pp  = _b[Z_it]
        local se_ppr_pp = _se[Z_it]
        local b_diff_pp = _b[Z_it_cite]
        local se_diff_pp = _se[Z_it_cite]
        qui lincom Z_it + Z_it_cite
        local b_cite_pp  = r(estimate)
        local se_cite_pp = r(se)
        qui test Z_it_cite
        local F_pp = r(F)
        local p_pp = r(p)
    }
    else di as error "joint_outcome_test ppml failed (rc=`rc'); ppml column left missing."
    mat joint_`samp'`suf'[1,3] = `b_ppr_pp'
    mat joint_`samp'`suf'[2,3] = `se_ppr_pp'
    mat joint_`samp'`suf'[3,3] = `b_cite_pp'
    mat joint_`samp'`suf'[4,3] = `se_cite_pp'
    mat joint_`samp'`suf'[5,3] = `b_diff_pp'
    mat joint_`samp'`suf'[6,3] = `se_diff_pp'
    mat joint_`samp'`suf'[7,3] = `F_pp'
    mat joint_`samp'`suf'[8,3] = `p_pp'

    di as text "joint outcome test `samp'`suf':  H0 beta_ppr = beta_cite (same H0 in three flavors)"
    di as text "  --- log      : β_ln_ppr    = " %9.4f `b_ppr_ln'  "  β_ln_cite    = " %9.4f `b_cite_ln'  "  diff = " %9.4f `b_diff_ln'  "  F = " %9.4f `F_ln'  "  p = " %9.4f `p_ln'
    di as text "  --- norm lvl : β_ppr/mean  = " %9.4f `b_ppr_nr'  "  β_cite/mean  = " %9.4f `b_cite_nr'  "  diff = " %9.4f `b_diff_nr'  "  F = " %9.4f `F_nr'  "  p = " %9.4f `p_nr'
    di as text "  --- ppml     : β_ppr (sel) = " %9.4f `b_ppr_pp'  "  β_cite (sel) = " %9.4f `b_cite_pp'  "  diff = " %9.4f `b_diff_pp'  "  F = " %9.4f `F_pp'  "  p = " %9.4f `p_pp'

    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'
    qui matrix_to_txt, saving("../output/tables/`samp'/joint_outcome_test`suf'.txt") ///
        matrix(joint_`samp'`suf') title(<tab:joint_outcome_test`suf'>) format(%20.4f) replace
end

program robustness
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
    local fes athr_id year
    local vce_cl athr_id
    if "$FE_MODE" == "athr_clyr" {
        local fes athr_id i.cluster_30#i.year
    }
    if "$FE_MODE" == "inst_cluster" {
        local fes inst_id cluster_30 year
        local vce_cl inst_id
    }
    if "$FE_MODE" == "inst_cluster_fldyr" {
        local fes inst_id i.cluster_30#i.year
        local vce_cl inst_id
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"
    cap mkdir "../output/figures/`samp'/robustness"
    cap mkdir "../output/tables"
    cap mkdir "../output/tables/`samp'"
    cap mkdir "../output/tables/`samp'/robustness"

    local outcomes ppr_cnt cite_affl_wt ppr_cnt_any cite_affl_wt_any ///
                   ppr_cnt_notlast cite_affl_wt_notlast

    foreach yvar of local outcomes {
        if "`yvar'" == "ppr_cnt"              local var_name "Publication count"
        if "`yvar'" == "cite_affl_wt"         local var_name "Citation weighted output"
        if "`yvar'" == "ppr_cnt_any"          local var_name "Publication count (any position)"
        if "`yvar'" == "cite_affl_wt_any"     local var_name "Citation weighted output (any position)"
        if "`yvar'" == "ppr_cnt_notlast"      local var_name "Publication count (non-last author)"
        if "`yvar'" == "cite_affl_wt_notlast" local var_name "Citation weighted output (non-last author)"
        local poisson_name "`var_name'"
        if "`yvar'" == "ppr_cnt"              local poisson_name "publications"
        if "`yvar'" == "cite_affl_wt"         local poisson_name "citation-weighted output"
        if "`yvar'" == "ppr_cnt_any"          local poisson_name "publications (any position)"
        if "`yvar'" == "cite_affl_wt_any"     local poisson_name "citation-weighted output (any position)"
        if "`yvar'" == "ppr_cnt_notlast"      local poisson_name "publications (non-last author)"
        if "`yvar'" == "cite_affl_wt_notlast" local poisson_name "citation-weighted output (non-last author)"
        local ppml_ytit "Output-cost elasticity"
        if regexm("`yvar'", "^ppr_cnt")      local gap 0.5
        if regexm("`yvar'", "^cite_affl_wt") local gap 1
        if regexm("`yvar'", "^ppr_cnt")      & "`samp'" == "top_jrnls" local gap 2
        if regexm("`yvar'", "^cite_affl_wt") & "`samp'" == "top_jrnls" local gap 2

        foreach spec in ageCtrl noattrit fldyr {
            if "`spec'" == "ageCtrl"  local title "Age x year controls"
            if "`spec'" == "noattrit" local title "PIs with last real pub year >= 2019"
            if "`spec'" == "fldyr"    local title "Author + field x year FE"
            local spec_fes `fes'
            if "`spec'" == "fldyr"    local spec_fes athr_id i.cluster_30#i.year

            use ../external/prepped_samples/es_`samp'`suf', clear
            cap drop rel int_lead* int_lag* mshr_lead* mshr_lag*
            gen rel = year - 2014
            qui sum rel
            local abs_lag  = abs(r(max))
            local abs_lead = abs(r(min))
            forval i = 1/`abs_lead' {
                gen int_lead`i'  = exposure      if rel == -`i'
                gen mshr_lead`i' = mkt_spend_shr if rel == -`i'
            }
            forval i = 1/`abs_lag' {
                gen int_lag`i'  = exposure      if rel == `i'
                gen mshr_lag`i' = mkt_spend_shr if rel == `i'
            }
            gen int_lag0  = exposure      if rel == 0
            gen mshr_lag0 = mkt_spend_shr if rel == 0
            ds int_lead* int_lag* mshr_lead* mshr_lag*
            foreach var in `r(varlist)' {
                replace `var' = 0 if mi(`var')
            }
            if "`spec'" == "noattrit" {
                keep if max_year >= 2019
            }
            qui sum rel
            local abs_lag  = abs(r(max))
            local abs_lead = abs(r(min))
            local int_leads
            local int_lags
            local mshr_leads
            local mshr_lags
            forval i = 2/`abs_lead' {
                local int_leads int_lead`i' `int_leads'
                local mshr_leads mshr_lead`i' `mshr_leads'
            }
            forval i = 0/`abs_lag' {
                local int_lags `int_lags' int_lag`i'
                local mshr_lags `mshr_lags' mshr_lag`i'
            }
            local addctrl
            if "`spec'" == "ageCtrl" local addctrl c.age_2014#i.year

            local ests ppmlhdfe
            if "`yvar'" == "ppr_cnt" local ests reghdfe ppmlhdfe

            foreach est of local ests {
            local esuf ""
            if "`est'" == "ppmlhdfe" local esuf "_ppml"
            cap noi `est' `yvar' `int_leads' `int_lags' `mshr_leads' `mshr_lags' `addctrl', ///
                    absorb(`spec_fes') vce(cluster `vce_cl')
            local rc = _rc
            if `rc' {
                di as error "robustness `samp'`suf' `yvar' `spec' `est' failed (rc=`rc'); skipping."
                continue
            }
            gunique athr_id if e(sample)
            local n_pi = r(unique)

            preserve
            cap mat drop es
            foreach var in `int_leads' `int_lags' int_lead1 {
                if "`var'" == "int_lead1" {
                    mat row = 0,0
                }
                else {
                    cap mat row = _b[`var'], _se[`var']
                    if _rc mat row = ., .
                }
                mat es = nullmat(es) \ row
            }
            svmat es
            keep es1 es2
            drop if mi(es1)
            rename (es1 es2) (b se)
            gen ub = b + 1.96*se
            gen lb = b - 1.96*se
            gen rel = -`abs_lead' if _n == 1
            replace rel = rel[_n-1]+1 if _n > 1
            replace rel = rel + 1 if rel >= -1
            replace rel = -1 if rel == `abs_lag' + 1
            gen year = rel + 2014
            hashsort rel
            save ../temp/robust_es_main_`yvar'`esuf'_`spec'_`samp'`suf', replace
            local ytit "`var_name'"
            local ylabopt ""
            if "`est'" == "ppmlhdfe" {
                local ytit "`ppml_ytit'"
                local ylabopt "ylab(#6)"
            }
            else {
                sum ub, d
                local ymax = round(r(max),`gap')
                sum lb, d
                local ymin = round(r(min),`gap')
                if `ymin' > 0 local ymin = 0
                local ylabopt "ylab(`ymin'(`gap')`ymax')"
            }
            cap graph drop _all
            cap noi tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
              scatter b year, mcolor(ebblue) ///
              , xlab(2010(1)2019) xtitle("Year") ytitle("`ytit'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                `ylabopt' yline(0, lcolor(gs10) lpattern(solid)) ///
                title("Main ES: `title' (N PIs = `n_pi')", size(small)) ///
                legend(off) plotregion(margin(sides))
            cap noi fig_export, path("../output/figures/`samp'/robustness/es_`yvar'_main`esuf'_`spec'`suf'.pdf")
            restore
            }
        }
    }

end

program output_tables
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
    local wsuf ""
    if "$WEIGHT_MSIM" == "1" local wsuf "_msimwt"
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"
    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'
    local position_outcomes ""
    if "$POSITION_OUTCOMES_AVAIL" == "1" {
        local position_outcomes n_middle_ppr avg_position avg_team_size_last avg_team_size_notlast
    }
    local outcomes cite_affl_wt ppr_cnt ln_ppr_cnt ///
                   cite_affl_wt_any ppr_cnt_any ///
                   cite_affl_wt_notlast ppr_cnt_notlast ///
                   avg_num_coathrs n_grants nih_total_cost ///
                   `position_outcomes'
    foreach prog in placebo2011 placebo2012 trim0 trim1 trim5 trim10 trim25 {
        foreach yvar of local outcomes {
            cap confirm matrix `prog'_`yvar'
            if !_rc {
                qui matrix_to_txt, saving("../output/tables/`samp'/`prog'_`yvar'`suf'`wsuf'.txt") ///
                    matrix(`prog'_`yvar') title(<tab:`prog'_`yvar'`suf'`wsuf'>) format(%20.4f) replace
            }
        }
    }

end

main
