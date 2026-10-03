set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

global EXPOSURE_VERSION "hc_all3"
global EXPOSURE_FILTER  "_cf_k3"
global SAMP "all_jrnls"
global SUF  "_r1_r2"
global YVAR "ppr_cnt"

program main
    prep_placebo
    run_spec, iter(0)
    qui sum iter
    local n_iter = r(max)
    forvalues i = 1/`n_iter' {
        di as text "===== placebo exposure iter `i' / `n_iter' ====="
        run_spec, iter(`i')
    }
    collect_results
    output_tables
    plots
end

program prep_placebo
    import delimited "../external/exposure/placebo_shift_share_${EXPOSURE_VERSION}${EXPOSURE_FILTER}.csv", clear varnames(1)
    cap tostring athr_id, replace
    rename exposure_ss exposure
    rename sum_imputed_shares mkt_spend_shr
    save ../temp/placebo_exposure, replace
end

program run_spec
    syntax, iter(int)
    use ../external/rf/prepped_samples/es_${SAMP}${SUF}, clear
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
    gen post = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post
    local b = .
    local se = .
    local bs = .
    local ses = .
    local N = .
    local n_athrs = .
    cap noi ppmlhdfe $YVAR Z_it Z_share_it, absorb(athr_id year) vce(cluster athr_id)
    if _rc == 0 {
        local b   = _b[Z_it]
        local se  = _se[Z_it]
        local bs  = _b[Z_share_it]
        local ses = _se[Z_share_it]
        local N   = e(N)
        local n_athrs = e(N_clust)
    }
    else di as error "run_spec iter `iter' ppml failed (rc=`_rc')"
    mat placebo_exposure_coefs = nullmat(placebo_exposure_coefs) \ (`iter', `b', `se', `bs', `ses', `N', `n_athrs')
    use ../temp/placebo_exposure, clear
end

program collect_results
    clear
    svmat placebo_exposure_coefs
    rename (placebo_exposure_coefs1 placebo_exposure_coefs2 placebo_exposure_coefs3 placebo_exposure_coefs4 placebo_exposure_coefs5 placebo_exposure_coefs6 placebo_exposure_coefs7) ///
           (iter b se b_share se_share N n_athrs)
    save ../output/placebo_exposure_coefs, replace

    qui sum b if iter == 0
    local b_real = r(mean)
    qui sum b if iter > 0, d
    local n_plc = r(N)
    local mean_plc = r(mean)
    local sd_plc = r(sd)
    qui count if iter > 0 & abs(b) >= abs(`b_real')
    local p_two = r(N) / `n_plc'
    qui count if iter > 0 & b <= `b_real'
    local p_one = r(N) / `n_plc'
    mat placebo_exposure_summary = (`b_real' \ `mean_plc' \ `sd_plc' \ `p_two' \ `p_one' \ `n_plc')
    mat rownames placebo_exposure_summary = b_real placebo_mean placebo_sd p_abs p_left n_placebo
    mat colnames placebo_exposure_summary = ${YVAR}${SUF}
end

program output_tables
    mat colnames placebo_exposure_coefs = iter b se b_share se_share N n_athrs
    foreach m in placebo_exposure_coefs placebo_exposure_summary {
        qui matrix_to_txt, saving("../output/tables/`m'${SUF}.txt") ///
            matrix(`m') title(<tab:`m'${SUF}>) format(%20.4f) replace
    }
end

program plots
    use ../output/placebo_exposure_coefs, clear
    qui sum b if iter == 0
    local b_real = r(mean)
    local b_real_lab : di %5.3f `b_real'
    keep if iter > 0
    qui sum b, d
    local n = r(N)
    local mean : di %5.3f r(mean)
    local sd   : di %5.3f r(sd)
    qui count if abs(b) >= abs(`b_real')
    local p : di %4.2f r(N) / `n'

    tw hist b, freq bin(25) color(ebblue%60) ///
        xline(`b_real', lcolor(dkorange) lwidth(medthick)) ///
        xline(0, lcolor(gs6) lpattern(dash)) ///
        xtitle("Placebo exposure coefficient (${YVAR})") ytitle("# of placebo draws") ///
        legend(on order(- "Actual = `b_real_lab'" "Placebo mean = `mean'" "Placebo sd = `sd'" "P(|b| {&ge} |actual|) = `p'") ///
               pos(1) ring(0) region(fcolor(none)) size(small))
    graph export ../output/figures/placebo_exposure_hist${SUF}.pdf, replace

    tw kdensity b, color(ebblue) ///
        xline(`b_real', lcolor(dkorange) lwidth(medthick)) ///
        xline(0, lcolor(gs6) lpattern(dash)) ///
        xtitle("Placebo exposure coefficient (${YVAR})") ytitle("Density") ///
        legend(on order(- "Actual = `b_real_lab'" "Placebo mean = `mean'" "Placebo sd = `sd'" "P(|b| {&ge} |actual|) = `p'") ///
               pos(1) ring(0) region(fcolor(none)) size(small))
    graph export ../output/figures/placebo_exposure_kdens${SUF}.pdf, replace

    hashsort b
    gen rank = _n
    gen lb = b - 1.96 * se
    gen ub = b + 1.96 * se
    tw rcap ub lb rank, msize(vsmall) lcolor(gs10) || ///
       scatter b rank, msize(small) mcolor(ebblue) ///
       yline(`b_real', lcolor(dkorange) lwidth(medthick)) yline(0, lcolor(gs6) lpattern(dash)) ///
       xtitle("Placebo draw (ranked)") ytitle("Placebo exposure coefficient (${YVAR})") legend(off)
    graph export ../output/figures/placebo_exposure_rank${SUF}.pdf, replace
end

main
