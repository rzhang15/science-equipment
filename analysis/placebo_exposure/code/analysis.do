set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries

global PRES_SCALE 1.2

cap program drop fig_export
program fig_export
    syntax, path(string) [mode(string) xsize(real 6) ysize(real 4)]
    local p : subinstr local path "/paper/" "/", all
    local p : subinstr local p "/pres/" "/", all
    local k = strpos("`p'", "figures/")
    if `k' > 0 {
        local base = substr("`p'", 1, `k' + 7)
        local rest = substr("`p'", `k' + 8, .)
    }
    else {
        local slash = strrpos("`p'", "/")
        local base = substr("`p'", 1, `slash')
        local rest = substr("`p'", `slash' + 1, .)
    }
    local tscale = cond(`xsize' >= `ysize', (2/3) * `xsize' / min(`xsize', `ysize'), 1)
    if "`mode'" == "presentation" local mode pres
    foreach m in paper pres {
        if "`mode'" != "" & "`mode'" != "`m'" continue
        local dir "`base'`m'"
        cap mkdir "`dir'"
        local sub "`rest'"
        while strpos("`sub'", "/") > 0 {
            local seg = substr("`sub'", 1, strpos("`sub'", "/") - 1)
            local dir "`dir'/`seg'"
            cap mkdir "`dir'"
            local sub = substr("`sub'", strpos("`sub'", "/") + 1, .)
        }
        local s = cond("`m'" == "pres", `tscale' * $PRES_SCALE, `tscale')
        graph display, scale(`s')
        graph export "`base'`m'/`rest'", replace
    }
end
version 17

global EXPOSURE_VERSION "hc_all3"
global EXPOSURE_FILTER  "_cf_k3"
global SAMP "all_jrnls"
global SUF  "_r1_r2"
global YVAR "ppr_cnt"
global PLACEBO_ES 0
global PLACEBO_CAREER 1
global PLACEBO_MODES "base transplant"

program main
    foreach m in $PLACEBO_MODES {
        local mode = cond("`m'" == "base", "", "_`m'")
        global MODE `mode'
        global TAG "`mode'$SUF"
        mat drop _all
        prep_placebo
        qui sum iter
        local n_iter = r(max)
        forvalues i = 0/`n_iter' {
            di as text "===== placebo exposure$MODE iter `i' / `n_iter' ====="
            run_spec, iter(`i')
        }
        collect_results
        output_tables
        plots
    }
end

program prep_placebo
    import delimited "../external/exposure/placebo_shift_share_${EXPOSURE_VERSION}${EXPOSURE_FILTER}${MODE}.csv", clear varnames(1)
    cap tostring athr_id, replace
    rename exposure_ss exposure
    rename sum_imputed_shares mkt_spend_shr
    save ../temp/placebo_exposure, replace
end

program run_spec
    syntax, iter(int)
    use ../external/rf/prepped_samples/es_${SAMP}${SUF}, clear
    gen real_exposure = exposure
    gen real_share = mkt_spend_shr
    if `iter' > 0 {
        drop exposure mkt_spend_shr foia_athr
        preserve
        use ../temp/placebo_exposure, clear
        keep if iter == `iter'
        drop iter
        save ../temp/placebo_iter, replace
        restore
        merge m:1 athr_id using ../temp/placebo_iter, keep(3) nogen
    }
    drop if mi(exposure) | mi(mkt_spend_shr) | mkt_spend_shr <= 0
    cap drop athr_indicator
    bys athr_id: gen athr_indicator = _n == 1

    qui sum exposure if athr_indicator == 1
    local mean_exp = r(mean)
    local sd_exp = r(sd)
    qui sum mkt_spend_shr if athr_indicator == 1
    local mean_shr = r(mean)
    local sd_shr = r(sd)
    qui corr exposure real_exposure if athr_indicator == 1
    local corr_real = r(rho)
    qui corr mkt_spend_shr real_share if athr_indicator == 1
    local corr_shr = r(rho)

    gen post = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post
    foreach l in b se bs ses N n_athrs {
        local `l' = .
    }
    cap noi ppmlhdfe $YVAR Z_it Z_share_it, absorb(athr_id year) vce(cluster athr_id)
    if _rc == 0 {
        local b   = _b[Z_it]
        local se  = _se[Z_it]
        local bs  = _b[Z_share_it]
        local ses = _se[Z_share_it]
        local N   = e(N)
        local n_athrs = e(N_clust)
    }
    else di as error "run_spec iter `iter' pooled ppml failed (rc=`_rc')"
    mat placebo_exposure_coefs = nullmat(placebo_exposure_coefs) \ ///
        (`iter', `b', `se', `bs', `ses', `N', `n_athrs', `mean_exp', `sd_exp', `mean_shr', `sd_shr', `corr_real', `corr_shr')

    if "$PLACEBO_ES" == "1" run_es, iter(`iter')
    if "$PLACEBO_CAREER" == "1" run_career, iter(`iter')
end

program run_es
    syntax, iter(int)
    gen rel = year - 2014
    qui sum rel
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
        local int_leads int_lead`i' `int_leads'
        local mshr_leads mshr_lead`i' `mshr_leads'
    }
    forval i = 0/`abs_lag' {
        local int_lags `int_lags' int_lag`i'
        local mshr_lags `mshr_lags' mshr_lag`i'
    }
    cap noi ppmlhdfe $YVAR `int_leads' `int_lags' `mshr_leads' `mshr_lags', absorb(athr_id year) vce(cluster athr_id)
    if _rc != 0 {
        di as error "run_es iter `iter' event-study ppml failed (rc=`_rc')"
        exit
    }
    forval i = `abs_lead'(-1)2 {
        mat placebo_exposure_es = nullmat(placebo_exposure_es) \ (`iter', -`i', _b[int_lead`i'], _se[int_lead`i'])
    }
    mat placebo_exposure_es = nullmat(placebo_exposure_es) \ (`iter', -1, 0, 0)
    forval i = 0/`abs_lag' {
        mat placebo_exposure_es = nullmat(placebo_exposure_es) \ (`iter', `i', _b[int_lag`i'], _se[int_lag`i'])
    }
end

program run_career
    syntax, iter(int)
    qui sum min_year if athr_indicator == 1, d
    local med = r(p50)
    gen young = min_year >  `med' if !mi(min_year)
    gen old   = min_year <= `med' if !mi(min_year)
    gen Z_young  = Z_it * young
    gen Z_old    = Z_it * old
    gen S_young  = Z_share_it * young
    gen S_old    = Z_share_it * old
    gen PT_young = post * young
    cap noi ppmlhdfe $YVAR Z_young Z_old S_young S_old PT_young, absorb(athr_id year) vce(cluster athr_id)
    if _rc != 0 {
        di as error "run_career iter `iter' career ppml failed (rc=`_rc')"
        exit
    }
    qui lincom Z_young - Z_old
    mat placebo_exposure_career = nullmat(placebo_exposure_career) \ ///
        (`iter', _b[Z_young], _se[Z_young], _b[Z_old], _se[Z_old], r(estimate), r(se), e(N))
end

program collect_results
    clear
    svmat placebo_exposure_coefs
    rename (placebo_exposure_coefs1 placebo_exposure_coefs2 placebo_exposure_coefs3 placebo_exposure_coefs4 ///
            placebo_exposure_coefs5 placebo_exposure_coefs6 placebo_exposure_coefs7 placebo_exposure_coefs8 ///
            placebo_exposure_coefs9 placebo_exposure_coefs10 placebo_exposure_coefs11 placebo_exposure_coefs12 ///
            placebo_exposure_coefs13) ///
           (iter b se b_share se_share N n_athrs mean_exp sd_exp mean_shr sd_shr corr_real corr_shr)
    gen t = b / se
    gen se_t = 1
    gen b_std = b * sd_exp
    gen se_b_std = se * sd_exp
    gen sig5 = abs(t) >= 1.96 if !mi(t)
    save ../output/placebo_exposure_coefs${TAG}, replace

    cap mat drop placebo_exposure_summary
    foreach v in b t b_std {
        qui sum `v' if iter == 0
        local real = r(mean)
        qui sum `v' if iter > 0, d
        local n_plc = r(N)
        local mean_plc = r(mean)
        local sd_plc = r(sd)
        local p5 = r(p5)
        local p95 = r(p95)
        local minv = r(min)
        local maxv = r(max)
        qui count if iter > 0 & `v' <= `real'
        local n_left = r(N)
        qui count if iter > 0 & abs(`v') >= abs(`real')
        local n_abs = r(N)
        mat placebo_exposure_summary = nullmat(placebo_exposure_summary), ///
            (`real' \ `mean_plc' \ `sd_plc' \ `p5' \ `p95' \ `minv' \ `maxv' \ `n_left' \ `n_abs' \ `n_left'/`n_plc' \ `n_abs'/`n_plc' \ `n_plc')
    }
    mat rownames placebo_exposure_summary = real placebo_mean placebo_sd placebo_p5 placebo_p95 placebo_min placebo_max ///
        n_at_or_below n_abs_at_or_above p_one_sided p_two_sided n_placebo
    mat colnames placebo_exposure_summary = b t b_std

    qui sum se if iter == 0
    local real_se = r(mean)
    qui sum se if iter > 0
    local mean_plc_se = r(mean)
    qui sum b if iter > 0
    local sd_plc_b = r(sd)
    qui sum sig5 if iter > 0
    local share_sig5 = r(mean)
    local n_sig5 = r(sum)
    qui sum b_share if iter > 0
    local mean_bshare = r(mean)
    local sd_bshare = r(sd)
    qui sum b_share if iter == 0
    local real_bshare = r(mean)
    foreach v in mean_exp sd_exp mean_shr sd_shr N n_athrs {
        qui sum `v' if iter == 0
        local real_`v' = r(mean)
        qui sum `v' if iter > 0
        local plc_`v' = r(mean)
    }
    qui sum corr_real if iter > 0, d
    local corr_mean = r(mean)
    local corr_min = r(min)
    local corr_max = r(max)
    qui sum corr_shr if iter > 0
    local corr_shr_mean = r(mean)
    mat placebo_exposure_diag = (`real_se' \ `mean_plc_se' \ `sd_plc_b' \ `sd_plc_b'/`mean_plc_se' \ `sd_plc_b'/`real_se' \ `n_sig5' \ `share_sig5' \ ///
        `real_bshare' \ `mean_bshare' \ `sd_bshare' \ ///
        `real_mean_exp' \ `plc_mean_exp' \ `real_sd_exp' \ `plc_sd_exp' \ `plc_sd_exp'/`real_sd_exp' \ ///
        `real_mean_shr' \ `plc_mean_shr' \ `real_sd_shr' \ `plc_sd_shr' \ ///
        `corr_mean' \ `corr_min' \ `corr_max' \ `corr_shr_mean' \ ///
        `real_N' \ `plc_N' \ `real_n_athrs' \ `plc_n_athrs')
    mat rownames placebo_exposure_diag = real_se placebo_mean_se placebo_sd_b ratio_sd_b_to_placebo_se ratio_sd_b_to_real_se ///
        n_placebo_sig5 share_placebo_sig5 real_b_share placebo_mean_b_share placebo_sd_b_share ///
        real_exposure_mean placebo_exposure_mean real_exposure_sd placebo_exposure_sd ratio_exposure_sd ///
        real_share_mean placebo_share_mean real_share_sd placebo_share_sd ///
        corr_placebo_real_exposure_mean corr_min corr_max corr_placebo_real_share_mean ///
        real_N placebo_mean_N real_n_pis placebo_mean_n_pis
    mat colnames placebo_exposure_diag = ${YVAR}${TAG}

    if "$PLACEBO_ES" == "1" {
        clear
        svmat placebo_exposure_es
        rename (placebo_exposure_es1 placebo_exposure_es2 placebo_exposure_es3 placebo_exposure_es4) (iter rel b se)
        save ../output/placebo_exposure_es${TAG}, replace
        preserve
        keep if iter == 0
        rename (b se) (b_real se_real)
        drop iter
        save ../temp/es_real, replace
        restore
        keep if iter > 0
        gcollapse (mean) b_plc = b se_plc = se (sd) sd_plc = b (p5) p5_plc = b (p95) p95_plc = b (count) n_plc = b, by(rel)
        merge 1:1 rel using ../temp/es_real, nogen
        order rel b_real se_real b_plc se_plc sd_plc p5_plc p95_plc n_plc
        save ../output/placebo_exposure_es_path${TAG}, replace
        mkmat rel b_real se_real b_plc se_plc sd_plc p5_plc p95_plc n_plc, matrix(placebo_exposure_es_path)
        mat colnames placebo_exposure_es_path = rel b_real se_real b_placebo_mean se_placebo_mean sd_placebo p5_placebo p95_placebo n_placebo
    }

    if "$PLACEBO_CAREER" == "1" {
        clear
        svmat placebo_exposure_career
        rename (placebo_exposure_career1 placebo_exposure_career2 placebo_exposure_career3 placebo_exposure_career4 ///
                placebo_exposure_career5 placebo_exposure_career6 placebo_exposure_career7 placebo_exposure_career8) ///
               (iter b_early se_early b_late se_late gap se_gap N)
        gen se_b_early = se_early
        gen se_b_late = se_late
        gen t_early = b_early / se_early
        gen t_late = b_late / se_late
        gen t_gap = gap / se_gap
        foreach v in t_early t_late t_gap {
            gen se_`v' = 1
        }
        save ../output/placebo_exposure_career${TAG}, replace
        cap mat drop placebo_exposure_career_summary
        foreach v in b_early b_late gap t_early t_late t_gap {
            qui sum `v' if iter == 0
            local real = r(mean)
            qui count if iter > 0 & `v' <= `real'
            local n_left = r(N)
            qui count if iter > 0 & abs(`v') >= abs(`real')
            local n_abs = r(N)
            qui sum `v' if iter > 0, d
            local n_plc = r(N)
            mat placebo_exposure_career_summary = nullmat(placebo_exposure_career_summary), ///
                (`real' \ r(mean) \ r(sd) \ r(p5) \ r(p95) \ `n_left'/`n_plc' \ `n_abs'/`n_plc' \ `n_plc')
        }
        mat rownames placebo_exposure_career_summary = real placebo_mean placebo_sd placebo_p5 placebo_p95 p_one_sided p_two_sided n_placebo
        mat colnames placebo_exposure_career_summary = b_early b_late b_early_minus_late t_early t_late t_early_minus_late
    }
end

program output_tables
    mat colnames placebo_exposure_coefs = iter b se b_share se_share N n_athrs mean_exp sd_exp mean_shr sd_shr corr_real corr_shr
    local mats placebo_exposure_coefs placebo_exposure_summary placebo_exposure_diag
    if "$PLACEBO_ES" == "1" local mats `mats' placebo_exposure_es_path
    if "$PLACEBO_CAREER" == "1" local mats `mats' placebo_exposure_career_summary
    foreach m of local mats {
        qui matrix_to_txt, saving("../output/tables/`m'${TAG}.txt") ///
            matrix(`m') title(<tab:`m'${TAG}>) format(%20.4f) replace
    }
end

program plots
    foreach v in b t b_std {
        if "`v'" == "b"     local xlab "Coefficient, placebo exposure measures"
        if "`v'" == "t"     local xlab "T-statistic, placebo exposure measures"
        if "`v'" == "b_std" local xlab "Effect of 1 SD exposure, placebo exposure measures"
        overlay_fig, var(`v') xlab("`xlab'")
    }
    rank_fig
    if "$PLACEBO_ES" == "1" es_fig
    if "$PLACEBO_CAREER" == "1" {
        overlay_fig, var(gap) xlab("Early-career minus late-career coefficient, placebo exposure measures") ///
            file(placebo_exposure_career${TAG}) fname(career_gap)
        overlay_fig, var(t_gap) xlab("Early-career minus late-career t-statistic, placebo exposure measures") ///
            file(placebo_exposure_career${TAG}) fname(career_gap_t)
    }
end

program overlay_fig
    syntax, var(str) xlab(str) [file(str) fname(str)]
    if "`file'" == "" local file placebo_exposure_coefs${TAG}
    if "`fname'" == "" local fname `var'
    use ../output/`file', clear
    local se_var = cond("`var'" == "b", "se", "se_`var'")
    qui sum `var' if iter == 0
    local real = r(mean)
    local real_lab : di %6.3f `real'
    qui sum `se_var' if iter == 0
    local real_se_lab : di %6.3f r(mean)
    local actual_lab "Actual Estimate = `real_lab' (clustered se = `real_se_lab')"
    if substr("`var'", 1, 1) == "t" {
        local real_lab : di %5.2f `real'
        local actual_lab "Actual t-statistic = `real_lab'"
    }
    keep if iter > 0
    qui sum `var', d
    local n_p = r(N)
    local mean_p : di %6.3f r(mean)
    local sd_p   : di %6.3f r(sd)
    qui count if `var' <= `real'
    if r(N) == 0 local p_one : di "< " %5.3f 1 / `n_p'
    else local p_one : di "= " %5.3f r(N) / `n_p'
    qui count if abs(`var') >= abs(`real')
    if r(N) == 0 local p_two : di "< " %5.3f 1 / `n_p'
    else local p_two : di "= " %5.3f r(N) / `n_p'

    qui sum `var'
    local gmin = min(r(min), `real')
    local gmax = max(r(max), `real')
    local xmin  = floor(`gmin' * 10) / 10
    local xmax  = ceil(`gmax' * 10) / 10
    local xstep = cond(`xmax' - `xmin' > 1.5, 0.5, 0.1)
    if "`var'" == "b_std" local xstep = 0.01
    local ngrid = 400
    if _N < `ngrid' set obs `ngrid'
    gen xgrid = `xmin' + (`xmax' - `xmin') * (_n - 1) / (`ngrid' - 1) in 1/`ngrid'
    kdensity `var', nograph at(xgrid) gen(dens_p)
    gen zero = 0

    foreach mode in presentation paper {
        local figdir ../output/figures
        local stats_note `"- "Randomization Inference p `p_one'""'
        if "`mode'" == "paper" {
            local stats_note
        }
        tw rarea dens_p zero xgrid, color(gs12%50) lwidth(none) || ///
           line dens_p xgrid, color(gs10%80) lwidth(medthick) lpattern(dash) ///
           xtitle("`xlab'") ytitle("Density") ///
           xlab(`xmin'(`xstep')`xmax') ///
           xline(0, lcolor(gs6) lpattern(dash)) ///
           xline(`real', lcolor(ebblue) lpattern(solid) lwidth(medthick)) ///
           legend(on order(- "`actual_lab'" ///
                           2 "Placebo estimates (N=`n_p', mean=`mean_p', sd=`sd_p')" ///
                           `stats_note') ///
                  pos(7) ring(1) region(fcolor(none)) size(small))
        fig_export, path("`figdir'/placebo_exposure_overlay_`fname'${TAG}.pdf") mode(`mode')
    }
end

program rank_fig
    use ../output/placebo_exposure_coefs${TAG}, clear
    qui sum b if iter == 0
    local real = r(mean)
    keep if iter > 0
    hashsort b
    gen rank = _n
    gen lb = b - 1.96 * se
    gen ub = b + 1.96 * se
    tw rcap ub lb rank, msize(vsmall) lcolor(gs10) || ///
       scatter b rank, msize(small) mcolor(gs6) ///
       yline(`real', lcolor(ebblue) lwidth(medthick)) yline(0, lcolor(gs6) lpattern(dash)) ///
       xtitle("Placebo draw (ranked)") ytitle("Exposure coefficient (${YVAR})") legend(off)
    fig_export, path("../output/figures/placebo_exposure_rank${TAG}.pdf")
end

program es_fig
    use ../output/placebo_exposure_es_path${TAG}, clear
    gen lb_real = b_real - 1.96 * se_real
    gen ub_real = b_real + 1.96 * se_real
    qui sum rel
    local rmin = r(min)
    local rmax = r(max)
    foreach mode in presentation paper {
        local figdir ../output/figures
        tw rarea p95_plc p5_plc rel, color(gs12%50) lwidth(none) || ///
           line b_plc rel, lcolor(dkorange) lpattern(dash) lwidth(medthick) || ///
           rcap ub_real lb_real rel, lcolor(ebblue) || ///
           connected b_real rel, lcolor(ebblue) mcolor(ebblue) msymbol(O) ///
           xline(-0.5, lcolor(gs6) lpattern(dash)) yline(0, lcolor(gs6) lpattern(dash)) ///
           xlab(`rmin'(1)`rmax') xtitle("Years relative to 2014") ytitle("Exposure coefficient (${YVAR})") ///
           legend(on order(4 "Actual" 2 "Placebo mean" 1 "Placebo 5th-95th percentile") pos(7) ring(1) region(fcolor(none)) size(small))
        fig_export, path("`figdir'/placebo_exposure_es_path${TAG}.pdf") mode(`mode')
    }
end

main
