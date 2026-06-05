set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main
    overlay_hist, real_file("../external/real/did_coefs_price") ///
        placebo_file("../external/placebo/did_coefs_placebo") ///
        outcome("price") suf("")
    overlay_hist, real_file("../external/real/did_coefs_spend") ///
        placebo_file("../external/placebo/did_coefs_placebo_spend") ///
        outcome("spend") suf("_spend")
end

program overlay_hist
    syntax, real_file(str) placebo_file(str) outcome(str) [suf(str)]

    // ============================================================
    // Empirical Bayes shrinkage (applied separately to the real
    // cross-section and to each placebo iter). Recipe from
    // analysis/first_stage/code/analysis.do:
    //   b_i ~ N(theta_i, se_i^2), theta_i ~ N(mu, tau^2)
    //   b_eb = w*b + (1-w)*mu_hat, w = tau^2 / (tau^2 + se_i^2)
    //   mu_hat = precision-weighted mean of b within group
    //   tau^2  = max(0, var(b) - mean(se^2)) within group
    // The real sample is one group; each placebo iter is its own group.
    // ============================================================
    use `real_file', clear
    keep b se spend_2013
    gen sample = 1
    gen iter = 0
    tempfile real_raw
    save `real_raw'

    use `placebo_file', clear
    keep b se spend_2013 iter
    gen sample = 2
    append using `real_raw'

    // group key: real = 0, placebo iters = 1..N
    egen grp = group(sample iter)

    gen var_se = se^2
    bys grp: egen mean_var_se = mean(var_se)
    bys grp: egen sample_var  = sd(b)
    replace sample_var = sample_var^2
    gen tau2 = max(0, sample_var - mean_var_se)
    gen prec = 1 / var_se
    bys grp: egen sum_prec    = total(prec)
    bys grp: egen sum_prec_b  = total(prec * b)
    gen mu_hat = sum_prec_b / sum_prec
    gen w_eb = tau2 / (tau2 + var_se)
    gen b_eb = w_eb * b + (1 - w_eb) * mu_hat

    // replace b with the EB-shrunk version for all downstream stats/plots
    replace b = b_eb
    drop b_eb var_se mean_var_se sample_var tau2 prec sum_prec sum_prec_b mu_hat w_eb grp

    // unweighted summaries
    sum b if sample == 1, d
    local N_r        = r(N)
    local mean_r_raw = r(mean)
    local mean_r : di %6.3f r(mean)
    local sd_r   : di %6.3f r(sd)
    sum b if sample == 2, d
    local N_p    = r(N)
    local mean_p : di %6.3f r(mean)
    local sd_p   : di %6.3f r(sd)

    // Two-sample Kolmogorov-Smirnov test on pooled betas.
    // Note: placebo obs are clustered within iter, so this p-value treats
    // all placebo draws as independent and is anti-conservative.
    ksmirnov b, by(sample)
    local ks_d  : di %6.3f r(D)
    local ks_p  : di %5.3f r(p)

    // Fisher randomization-style p-value: test stat = mean of real betas.
    // Build the null distribution of iteration means from the placebo runs
    // (one mean per iter, so within-iter correlation is baked in), then
    // p = share of placebo iter means at least as extreme as the observed mean.
    preserve
        keep if sample == 2
        collapse (mean) iter_mean = b, by(iter)
        local n_iter = _N
        count if iter_mean >= `mean_r_raw'
        local p_one : di %5.3f r(N) / `n_iter'
        count if abs(iter_mean) >= abs(`mean_r_raw')
        local p_two : di %5.3f r(N) / `n_iter'
        sum iter_mean
        local mean_imean : di %6.3f r(mean)
        local sd_imean   : di %6.3f r(sd)
    restore

    tw kdensity b if sample == 1, color(lavender%70) lwidth(medthick) || ///
       kdensity b if sample == 2, color(gs10%80) lwidth(medthick) lpattern(dash) ///
       xtitle("DiD Coefficient (log `outcome')") ///
       ytitle("Density") ///
       xlab(-0.6(0.1)0.6) ///
       xline(0, lcolor(gs6) lpattern(dash)) ///
       xline(`mean_r_raw', lcolor(purple) lpattern(solid) lwidth(medthin)) ///
       legend(on order(1 "Actual Treatment Effects (N=`N_r', mean=`mean_r', sd=`sd_r')" ///
                       2 "Placebo Treatment Effects (N=`N_p', mean=`mean_p', sd=`sd_p')") ///
              pos(7) ring(1) region(fcolor(none)) size(small))
    graph export ../output/figures/did_coefs_overlay_kdens_eb`suf'.pdf, replace

    // Companion figure: histogram of the placebo iteration means with the
    // observed mean overlaid -- this is the actual reference distribution for
    // the RI p-value above.
    preserve
        keep if sample == 2
        collapse (mean) iter_mean = b, by(iter)
        tw histogram iter_mean, color(gs10%80) width(0.005) ///
           xtitle("Mean DiD coefficient within placebo iteration (log `outcome')") ///
           ytitle("Density") ///
           xline(`mean_r_raw', lcolor(purple) lwidth(medthick)) ///
           xline(0, lcolor(gs6) lpattern(dash)) ///
           legend(off) ///
           title("Placebo iteration means (N=`n_iter'); purple = observed mean (`mean_r')", size(small)) ///
           note("One-sided RI p = `p_one'; two-sided RI p = `p_two'; KS D = `ks_d', p = `ks_p'", size(vsmall))
        graph export ../output/figures/placebo_iter_means_ri_eb`suf'.pdf, replace
    restore

end

main
