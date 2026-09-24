set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

* Borusyak-Hull-Jaravel (JEP 2025) exogenous-shifts checklist for the PI exposure design
*   units i   = PIs;  shifts g_k = EB-shrunk log price effect of the merger in product market k
*   shares s_ik = pre-2014 spend share of market k (observed for FOIA PIs, imputed otherwise)
*   z_i = sum_k s_ik g_k = exposure;  S_i = sum_k s_ik = mkt_spend_shr (incomplete shares)
global VERSION "hc"
global SUF     "_all3"
global SAMP    "all_jrnls_r1_r2"
global N_PERM  200

program main
    build_shares
    shift_descriptives
    shift_balance
    share_timing
    unit_balance
    incomplete_share
    shift_controls
    exposure_robust_se
    permutation_inference
    output_tables
end

program build_shares
    use category b se b_eb se_eb lb_eb ub_eb spend_2013 tot_cnt delta_hhi ///
        using ../external/betas/did_coefs_eb_price$SUF, clear
    rename (b se) (b_raw se_raw)
    merge 1:1 category using ../temp/markets, assert(3) nogen
    assert abs(b_eb - g_imp) < 1e-5
    drop g_imp
    sort market_idx
    assert market_idx == _n
    qui count
    global K = r(N)
    save ../temp/shifts, replace

    use athr_id exposure mkt_spend_shr foia_athr using ../external/rf/prepped_samples/es_$SAMP, clear
    bys athr_id: keep if _n == 1
    replace foia_athr = 0 if mi(foia_athr)
    save ../temp/pi_xs, replace

    use athr_id category mkt_spend_shr using ../external/real_exposure/athr_exposure_by_category_${VERSION}${SUF}, clear
    drop if mi(mkt_spend_shr)
    rename mkt_spend_shr s
    gen byte observed = 1
    merge m:1 athr_id using ../temp/pi_xs, keep(3) keepusing(foia_athr) nogen
    keep if foia_athr == 1
    drop foia_athr
    save ../temp/foia_shares, replace

    use ../temp/imputed_shares_long, clear
    rename s_imp s
    gen byte observed = 0
    drop market_idx
    merge m:1 athr_id using ../temp/pi_xs, keep(3) keepusing(foia_athr) nogen
    drop if foia_athr == 1
    drop foia_athr
    append using ../temp/foia_shares
    merge m:1 category using ../temp/shifts, assert(2 3) keep(3) keepusing(market_idx b_eb) nogen
    merge m:1 athr_id using ../temp/pi_xs, assert(3) nogen
    bys athr_id: egen z_chk = total(s * b_eb)
    bys athr_id: egen S_chk = total(s)
    gen dz = abs(z_chk - exposure)
    gen dS = abs(S_chk - mkt_spend_shr)
    sum dz, meanonly
    di as text "build_shares: max |sum_k s_ik g_k - exposure_i| = " %9.2e r(max)
    sum dS, meanonly
    di as text "build_shares: max |sum_k s_ik - S_i|             = " %9.2e r(max)
    qui count if dz > 1e-5 | dS > 1e-5
    if r(N) > 0 di as error "build_shares: shares do not reproduce exposure on " r(N) " PI-market rows"
    qui gunique athr_id
    di as text "build_shares: " r(unique) " PIs, " _N " PI-market rows, K = $K markets"
    keep athr_id category market_idx s observed
    save ../temp/pi_market_shares, replace

    keep athr_id market_idx s
    reshape wide s, i(athr_id) j(market_idx)
    forval k = 1/$K {
        cap gen s`k' = 0
        replace s`k' = 0 if mi(s`k')
    }
    save ../temp/pi_market_shares_wide, replace
end

program shift_descriptives
    use ../temp/pi_market_shares, clear
    qui gunique athr_id
    local N = r(unique)
    gcollapse (sum) s_k=s (count) n_pis=s, by(category)
    replace s_k = s_k / `N'
    merge 1:1 category using ../temp/shifts, assert(2 3) nogen
    replace s_k = 0 if mi(s_k)
    replace n_pis = 0 if mi(n_pis)
    egen tot_s = total(s_k)
    gen w_k = s_k / tot_s
    drop tot_s
    gsort -w_k
    gen rank_w = _n
    gen cum_w = sum(w_k)
    egen hhi_w = total(w_k^2)

    qui sum b_eb
    local mean_g = r(mean)
    local sd_g   = r(sd)
    local min_g  = r(min)
    local max_g  = r(max)
    qui sum b_eb [aw=w_k]
    local wmean_g = r(mean)
    local wsd_g   = r(sd)
    qui sum b_raw
    local mean_b = r(mean)
    local sd_b   = r(sd)
    qui sum b_raw [aw=w_k]
    local wmean_b = r(mean)
    local wsd_b   = r(sd)
    local eff_k = 1 / hhi_w[1]
    local top5  = cum_w[5]
    local top10 = cum_w[10]
    qui count if n_pis > 0
    local k_used = r(N)

    mat shift_desc = J(15, 1, .)
    mat shift_desc[1,1]  = $K
    mat shift_desc[2,1]  = `k_used'
    mat shift_desc[3,1]  = `eff_k'
    mat shift_desc[4,1]  = `mean_g'
    mat shift_desc[5,1]  = `sd_g'
    mat shift_desc[6,1]  = `min_g'
    mat shift_desc[7,1]  = `max_g'
    mat shift_desc[8,1]  = `wmean_g'
    mat shift_desc[9,1]  = `wsd_g'
    mat shift_desc[10,1] = `mean_b'
    mat shift_desc[11,1] = `sd_b'
    mat shift_desc[12,1] = `wmean_b'
    mat shift_desc[13,1] = `wsd_b'
    mat shift_desc[14,1] = `top5'
    mat shift_desc[15,1] = `top10'
    mat rownames shift_desc = K K_with_positive_share effective_K mean_g sd_g min_g max_g ///
        wmean_g wsd_g mean_b_raw sd_b_raw wmean_b_raw wsd_b_raw top5_weight_share top10_weight_share
    mat colnames shift_desc = value
    mat list shift_desc, format(%12.4f)

    save ../temp/shift_level, replace
    export delimited category b_eb se_eb b_raw se_raw s_k w_k cum_w n_pis rotemberg_wt n_foia_pis ///
        using ../output/tables/shift_importance.csv, replace

    gsort b_eb
    gen rank_g = _n
    tw (rcap ub_eb lb_eb rank_g, lcolor(lavender%70) msize(vsmall)) ///
       (scatter b_eb rank_g [aw=w_k], mcolor(ebblue%70) msymbol(circle)), ///
        xtitle("Product market, ranked by shift") ytitle("Shift g{sub:k} (log price effect)") ///
        yline(0, lcolor(gs10) lpattern(dash)) legend(off) ///
        note("Marker size proportional to importance weight s{sub:k} = mean{sub:i} s{sub:ik}", size(vsmall))
    graph export ../output/figures/shifts_by_rank.pdf, replace

    tw (kdensity b_eb, lcolor(ebblue)) (kdensity b_eb [aw=w_k], lcolor(dkorange)), ///
        xtitle("Shift g{sub:k}") ytitle("Density") ///
        legend(on order(1 "Unweighted" 2 "Importance-weighted (s{sub:k})") pos(1) ring(0) size(small))
    graph export ../output/figures/shifts_density.pdf, replace
end

program shift_balance
    use category year avg_log_price spend_2013 obs_2013 using ../external/mkt/category_yr_tfidf$SUF, clear
    replace category = "acrylamide-bis solution" if category == "acrylamide/bis solution"
    replace category = "dmem-f-12" if category == "dmem/f-12"
    keep if inrange(year, 2010, 2013)
    bys category: egen ybar = mean(year)
    bys category: egen pbar = mean(avg_log_price)
    gen num = (year - ybar) * (avg_log_price - pbar)
    gen den = (year - ybar)^2
    gen p2013 = avg_log_price if year == 2013
    gcollapse (sum) num den (mean) p2013 spend_2013 obs_2013, by(category)
    gen pre_trend = num / den
    gen log_spend_2013 = log(spend_2013)
    gen log_obs_2013 = log(obs_2013)
    keep category pre_trend p2013 log_spend_2013 log_obs_2013
    save ../temp/shift_covariates, replace

    use ../temp/shift_level, clear
    merge 1:1 category using ../temp/shift_covariates, keep(1 3)
    qui count if _merge == 1
    if r(N) > 0 di as error "shift_balance: " r(N) " shifts lack category covariates"
    drop _merge
    save ../temp/shift_level, replace

    local covs pre_trend p2013 log_spend_2013 log_obs_2013
    local ncov : word count `covs'
    mat shift_bal = J(`ncov', 6, .)
    local r = 1
    foreach v of local covs {
        egen z_`v' = std(`v')
        qui reg b_eb z_`v' [aw=w_k], r
        mat shift_bal[`r',1] = _b[z_`v']
        mat shift_bal[`r',2] = _se[z_`v']
        mat shift_bal[`r',3] = 2 * ttail(e(df_r), abs(_b[z_`v'] / _se[z_`v']))
        qui reg b_eb z_`v', r
        mat shift_bal[`r',4] = _b[z_`v']
        mat shift_bal[`r',5] = _se[z_`v']
        mat shift_bal[`r',6] = 2 * ttail(e(df_r), abs(_b[z_`v'] / _se[z_`v']))
        local ++r
    }
    mat rownames shift_bal = `covs'
    mat colnames shift_bal = b_wt se_wt p_wt b_unwt se_unwt p_unwt
    mat list shift_bal, format(%12.4f)

    qui reg b_eb z_* [aw=w_k], r
    qui testparm z_*
    mat shift_bal_joint = J(3, 2, .)
    mat shift_bal_joint[1,1] = r(F)
    mat shift_bal_joint[2,1] = r(p)
    mat shift_bal_joint[3,1] = e(N)
    qui reg b_eb z_*, r
    qui testparm z_*
    mat shift_bal_joint[1,2] = r(F)
    mat shift_bal_joint[2,2] = r(p)
    mat shift_bal_joint[3,2] = e(N)
    mat rownames shift_bal_joint = F p N
    mat colnames shift_bal_joint = weighted unweighted
    mat list shift_bal_joint, format(%12.4f)

    tw (scatter b_eb pre_trend [aw=w_k], mcolor(ebblue%60) msymbol(circle)) ///
       (lfit b_eb pre_trend [aw=w_k], lcolor(dkorange)), ///
        xtitle("Pre-period log price trend, 2010-2013 (per year)") ytitle("Shift g{sub:k}") legend(off)
    graph export ../output/figures/shift_balance_pretrend.pdf, replace
end

program share_timing
    use ../external/real_exposure/athr_category_spend$SUF, clear
    keep if keep == 1
    replace category = "acrylamide-bis solution" if category == "acrylamide/bis solution"
    replace category = "dmem-f-12" if category == "dmem/f-12"
    gen post = year >= 2014
    gcollapse (sum) spend, by(athr_id category post)
    bys athr_id post: egen tot = total(spend)
    gen s = spend / tot
    bys athr_id: egen has_pre  = max(post == 0)
    bys athr_id: egen has_post = max(post == 1)
    keep if has_pre == 1 & has_post == 1
    merge m:1 category using ../temp/shifts, keep(3) keepusing(b_eb) nogen
    keep athr_id category post s b_eb has_pre has_post
    reshape wide s, i(athr_id category) j(post)
    replace s0 = 0 if mi(s0)
    replace s1 = 0 if mi(s1)
    gen ds = s1 - s0
    qui gunique athr_id
    local n_pis = r(unique)

    mat share_timing = J(3, 3, .)
    reghdfe ds b_eb, absorb(athr_id) vce(cluster category)
    mat share_timing[1,1] = _b[b_eb]
    mat share_timing[2,1] = _se[b_eb]
    mat share_timing[3,1] = e(N)
    reghdfe ds b_eb s0, absorb(athr_id) vce(cluster category)
    mat share_timing[1,2] = _b[b_eb]
    mat share_timing[2,2] = _se[b_eb]
    mat share_timing[3,2] = e(N)
    gcollapse (mean) ds s0 s1, by(category b_eb)
    reg ds b_eb, r
    mat share_timing[1,3] = _b[b_eb]
    mat share_timing[2,3] = _se[b_eb]
    mat share_timing[3,3] = e(N)
    mat rownames share_timing = b_g se_g N
    mat colnames share_timing = pi_fe pi_fe_ctrl_s0 market_level
    mat list share_timing, format(%12.4f)
    di as text "share_timing: post-minus-pre share change regressed on g_k, `n_pis' FOIA PIs with spend in both periods"

    tw (scatter ds b_eb, mcolor(ebblue%70)) (lfit ds b_eb, lcolor(dkorange)), ///
        xtitle("Shift g{sub:k}") ytitle("Mean change in spend share, post minus pre") ///
        yline(0, lcolor(gs10) lpattern(dash)) legend(off)
    graph export ../output/figures/share_change_vs_shift.pdf, replace
end

program build_pi_xs
    use ../external/rf/prepped_samples/es_$SAMP, clear
    gen pre   = year < 2014
    gen post  = year >= 2014
    gen early = inrange(year, 2010, 2011)
    gen late  = inrange(year, 2012, 2013)
    foreach v in ppr_cnt cite_affl_wt ppr_cnt_any {
        gen `v'_pre   = `v' if pre
        gen `v'_post  = `v' if post
        gen `v'_early = `v' if early
        gen `v'_late  = `v' if late
    }
    gen team_pre = avg_team_size_last if pre
    replace foia_athr = 0 if mi(foia_athr)
    gcollapse (mean) *_pre *_post *_early *_late team_pre ///
              (first) exposure mkt_spend_shr age_2014 public nih_athr foia_athr, by(athr_id)
    foreach v in ppr_cnt cite_affl_wt {
        gen `v'_dy       = `v'_post - `v'_pre
        gen `v'_pretrend = `v'_late - `v'_early
    }
    rename (exposure mkt_spend_shr) (z S)
    qui sum z
    gen z_sd = z / r(sd)
    save ../temp/pi_xs_full, replace
end

program shift_level_reg
    syntax varlist(min=2 max=2)
    gettoken yvar xvar : varlist
    ssaggregate `yvar' `xvar', n(category) s(s) l(athr_id) sfilename(../temp/pi_market_shares) ///
        controls("S") addmissing
    merge m:1 category using ../temp/shifts, keep(1 3) keepusing(b_eb) nogen
    replace b_eb = 0 if category == ""
    ivregress 2sls `yvar' (`xvar' = b_eb) [aw=s_n], vce(robust)
end

program unit_balance
    build_pi_xs
    local chars ppr_cnt_pre cite_affl_wt_pre ppr_cnt_any_pre team_pre age_2014 public nih_athr foia_athr ///
                ppr_cnt_pretrend cite_affl_wt_pretrend
    local nch : word count `chars'
    mat unit_bal = J(`nch', 7, .)
    local r = 1
    foreach v of local chars {
        use ../temp/pi_xs_full, clear
        keep athr_id z_sd S `v'
        drop if mi(`v')
        qui sum `v'
        mat unit_bal[`r',1] = r(mean)
        qui reg `v' z_sd S, r
        mat unit_bal[`r',2] = _b[z_sd]
        mat unit_bal[`r',3] = _se[z_sd]
        mat unit_bal[`r',4] = 2 * ttail(e(df_r), abs(_b[z_sd] / _se[z_sd]))
        mat unit_bal[`r',7] = e(N)
        shift_level_reg `v' z_sd
        mat unit_bal[`r',5] = _se[z_sd]
        mat unit_bal[`r',6] = 2 * normal(-abs(_b[z_sd] / _se[z_sd]))
        di as text "unit_balance `v': unit-level b=" %8.4f unit_bal[`r',2] "  shift-level b=" %8.4f _b[z_sd]
        local ++r
    }
    mat rownames unit_bal = `chars'
    mat colnames unit_bal = mean b_per_sd_z se_robust p_robust se_exposure_robust p_exposure_robust N
    mat list unit_bal, format(%12.4f)
end

program run_ppml, rclass
    syntax varlist(min=2), absorb(string) [cl(string)]
    gettoken yvar rhs : varlist
    gettoken x1 rest : rhs
    gettoken x2 : rest
    local vce vce(robust)
    if "`cl'" != "" local vce vce(cluster `cl')
    cap noi ppmlhdfe `yvar' `rhs', absorb(`absorb') `vce'
    local rc = _rc
    if `rc' {
        di as error "run_ppml: ppmlhdfe `yvar' `rhs' failed (rc=`rc')"
        return scalar b   = .
        return scalar se  = .
        return scalar b2  = .
        return scalar se2 = .
        return scalar N   = .
        exit
    }
    return scalar b  = _b[`x1']
    return scalar se = _se[`x1']
    return scalar N  = e(N)
    return scalar b2  = .
    return scalar se2 = .
    if "`x2'" != "" {
        return scalar b2  = _b[`x2']
        return scalar se2 = _se[`x2']
    }
end

program incomplete_share
    use ../external/rf/prepped_samples/es_$SAMP, clear
    gen post       = year >= 2014
    gen Z_it       = exposure * post
    gen Z_share_it = mkt_spend_shr * post
    gen Znorm_it   = exposure / mkt_spend_shr * post
    foreach yvar in ppr_cnt cite_affl_wt {
        mat inc_share_`yvar' = J(5, 4, .)
        local c = 1
        foreach rhs in "Z_it" "Z_it Z_share_it" "Znorm_it" "Znorm_it Z_share_it" {
            run_ppml `yvar' `rhs', absorb(athr_id year) cl(athr_id)
            mat inc_share_`yvar'[1,`c'] = r(b)
            mat inc_share_`yvar'[2,`c'] = r(se)
            mat inc_share_`yvar'[3,`c'] = r(b2)
            mat inc_share_`yvar'[4,`c'] = r(se2)
            mat inc_share_`yvar'[5,`c'] = r(N)
            local ++c
        }
        mat rownames inc_share_`yvar' = b_exposure se_exposure b_share se_share N
        mat colnames inc_share_`yvar' = z_only z_plus_S z_normalized z_normalized_plus_S
        mat list inc_share_`yvar', format(%12.4f)
    }
end

program shift_controls
    use ../temp/pi_market_shares, clear
    merge m:1 category using ../temp/shift_level, assert(2 3) keep(3) ///
        keepusing(pre_trend p2013 log_spend_2013 log_obs_2013) nogen
    local qs pre_trend p2013 log_spend_2013 log_obs_2013
    foreach q of local qs {
        qui count if mi(`q')
        if r(N) > 0 di as error "shift_controls: `q' missing on " r(N) " PI-market rows (dropped from aggregate)"
        gen sq_`q' = s * `q'
        replace sq_`q' = 0 if mi(sq_`q')
    }
    gcollapse (sum) sq_*, by(athr_id)
    rename sq_* q_*
    save ../temp/pi_shift_controls, replace

    use ../external/rf/prepped_samples/es_$SAMP, clear
    merge m:1 athr_id using ../temp/pi_shift_controls, assert(3) nogen
    gen post       = year >= 2014
    gen Z_it       = exposure * post
    gen Z_share_it = mkt_spend_shr * post
    local all_q ""
    foreach q of local qs {
        gen Q_`q'_it = q_`q' * post
        local all_q `all_q' Q_`q'_it
    }
    foreach yvar in ppr_cnt cite_affl_wt {
        mat shift_ctrl_`yvar' = J(3, 6, .)
        local c = 1
        foreach extra in "" "Q_pre_trend_it" "Q_p2013_it" "Q_log_spend_2013_it" "Q_log_obs_2013_it" "`all_q'" {
            run_ppml `yvar' Z_it Z_share_it `extra', absorb(athr_id year) cl(athr_id)
            mat shift_ctrl_`yvar'[1,`c'] = r(b)
            mat shift_ctrl_`yvar'[2,`c'] = r(se)
            mat shift_ctrl_`yvar'[3,`c'] = r(N)
            local ++c
        }
        mat rownames shift_ctrl_`yvar' = b_exposure se_exposure N
        mat colnames shift_ctrl_`yvar' = base pre_trend price_level_2013 log_spend_2013 log_obs_2013 all
        mat list shift_ctrl_`yvar', format(%12.4f)
    }
end

program exposure_robust_se
    foreach yvar in ppr_cnt cite_affl_wt {
        use ../external/rf/prepped_samples/es_$SAMP, clear
        gen post       = year >= 2014
        gen Z_it       = exposure * post
        gen Z_share_it = mkt_spend_shr * post
        mat expo_se_`yvar' = J(3, 4, .)
        reghdfe `yvar' Z_it Z_share_it, absorb(athr_id year) vce(cluster athr_id)
        mat expo_se_`yvar'[1,1] = _b[Z_it]
        mat expo_se_`yvar'[2,1] = _se[Z_it]
        mat expo_se_`yvar'[3,1] = e(N)
        local b_panel = _b[Z_it]
        reghdfe `yvar' Z_it Z_share_it, absorb(athr_id year) vce(robust)
        mat expo_se_`yvar'[1,2] = _b[Z_it]
        mat expo_se_`yvar'[2,2] = _se[Z_it]
        mat expo_se_`yvar'[3,2] = e(N)

        use ../temp/pi_xs_full, clear
        keep athr_id z S `yvar'_dy
        reg `yvar'_dy z S, r
        mat expo_se_`yvar'[1,3] = _b[z]
        mat expo_se_`yvar'[2,3] = _se[z]
        mat expo_se_`yvar'[3,3] = e(N)
        di as text "exposure_robust_se `yvar': panel FE b=" %9.5f `b_panel' ///
            "  long-difference b=" %9.5f _b[z] "  reldif=" %9.2e reldif(_b[z], `b_panel')

        shift_level_reg `yvar'_dy z
        mat expo_se_`yvar'[1,4] = _b[z]
        mat expo_se_`yvar'[2,4] = _se[z]
        mat expo_se_`yvar'[3,4] = e(N)
        mat rownames expo_se_`yvar' = b_exposure se N
        mat colnames expo_se_`yvar' = panel_cluster_pi panel_robust long_diff_robust shift_level_robust
        mat list expo_se_`yvar', format(%12.5f)
        save ../temp/shift_agg_`yvar', replace

        tw (scatter `yvar'_dy b_eb if category != "" [aw=s_n], mcolor(ebblue%60) msymbol(circle)) ///
           (lfit `yvar'_dy b_eb if category != "" [aw=s_n], lcolor(dkorange)), ///
            xtitle("Shift g{sub:k}") ytitle("Exposure-weighted change in `yvar' (residualized on S{sub:i})") ///
            legend(off) note("Marker size proportional to s{sub:k}; missing-industry observation omitted from plot", size(vsmall))
        graph export ../output/figures/shift_level_rf_`yvar'.pdf, replace
    }
end

program permutation_inference
    use athr_id year ppr_cnt cite_affl_wt exposure mkt_spend_shr using ../external/rf/prepped_samples/es_$SAMP, clear
    gen post       = year >= 2014
    gen Z_it       = exposure * post
    gen Z_share_it = mkt_spend_shr * post
    merge m:1 athr_id using ../temp/pi_market_shares_wide, assert(3) nogen
    save ../temp/perm_panel, replace

    use market_idx b_eb using ../temp/shifts, clear
    sort market_idx
    mkmat b_eb, matrix(G)

    foreach yvar in ppr_cnt cite_affl_wt {
        use ../temp/perm_panel, clear
        ppmlhdfe `yvar' Z_it Z_share_it, absorb(athr_id year) vce(cluster athr_id)
        local b_hat  = _b[Z_it]
        local se_hat = _se[Z_it]

        set seed 8975
        cap postutil clear
        postfile perm_h int(draw) double(b) using ../temp/perm_`yvar', replace
        forval d = 1/$N_PERM {
            use market_idx using ../temp/shifts, clear
            gen u = runiform()
            sort u
            gen g_perm = G[_n, 1]
            sort market_idx
            forval k = 1/$K {
                local gp`k' = g_perm[`k']
            }
            use ../temp/perm_panel, clear
            gen z_perm = 0
            forval k = 1/$K {
                replace z_perm = z_perm + s`k' * `gp`k''
            }
            gen Zp_it = z_perm * post
            cap qui ppmlhdfe `yvar' Zp_it Z_share_it, absorb(athr_id year)
            if !_rc post perm_h (`d') (_b[Zp_it])
            if mod(`d', 25) == 0 di as text "permutation_inference `yvar': draw `d' of $N_PERM"
        }
        postclose perm_h

        use ../temp/perm_`yvar', clear
        gen byte extreme = abs(b) >= abs(`b_hat')
        qui sum extreme
        local p_perm = r(mean)
        qui sum b
        mat perm_`yvar' = J(6, 1, .)
        mat perm_`yvar'[1,1] = `b_hat'
        mat perm_`yvar'[2,1] = `se_hat'
        mat perm_`yvar'[3,1] = r(sd)
        mat perm_`yvar'[4,1] = r(mean)
        mat perm_`yvar'[5,1] = `p_perm'
        mat perm_`yvar'[6,1] = r(N)
        mat rownames perm_`yvar' = b_hat se_cluster_pi sd_perm mean_perm p_perm n_draws
        mat colnames perm_`yvar' = value
        mat list perm_`yvar', format(%12.5f)

        hist b, color(ebblue%70) lcolor(white) xline(`b_hat', lcolor(dkorange) lpattern(dash) lwidth(medthick)) ///
            xtitle("PPML coefficient on permuted exposure x post") ytitle("Density") ///
            note("Shifts g{sub:k} permuted across the $K markets, shares held fixed; dashed line = actual estimate", size(vsmall))
        graph export ../output/figures/perm_`yvar'.pdf, replace
    }
end

program output_tables
    local mats shift_desc shift_bal shift_bal_joint share_timing unit_bal ///
               inc_share_ppr_cnt inc_share_cite_affl_wt ///
               shift_ctrl_ppr_cnt shift_ctrl_cite_affl_wt ///
               expo_se_ppr_cnt expo_se_cite_affl_wt ///
               perm_ppr_cnt perm_cite_affl_wt
    foreach m of local mats {
        cap confirm matrix `m'
        if _rc {
            di as error "output_tables: matrix `m' not found"
            continue
        }
        matrix_to_txt, saving("../output/tables/`m'.txt") matrix(`m') ///
            title(<tab:`m'>) format(%20.5f) replace
    }
end

main
