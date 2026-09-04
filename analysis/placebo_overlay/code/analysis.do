set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17
global exhibit_mode both // paper | presentation | both

program main
    foreach s in "" "_all3" {
        global suffix `s'
        overlay_hist, real_file("../external/real/did_coefs_price$suffix") ///
            placebo_file("../external/placebo/did_coefs_placebo$suffix") ///
            outcome("price") suf("")
        overlay_hist, real_file("../external/real/did_coefs_spend$suffix") ///
            placebo_file("../external/placebo/did_coefs_placebo_spend$suffix") ///
            outcome("spend") suf("_spend")
    }
end

program overlay_hist
    syntax, real_file(str) placebo_file(str) outcome(str) [suf(str)]

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

    replace b = b_eb
    drop b_eb var_se mean_var_se sample_var tau2 prec sum_prec sum_prec_b mu_hat w_eb grp

    sum b if sample == 1, d
    local N_r        = r(N)
    local mean_r_raw = r(mean)
    local mean_r : di %6.3f r(mean)
    local sd_r   : di %6.3f r(sd)
    sum b if sample == 2, d
    local N_p    = r(N)
    local mean_p : di %6.3f r(mean)
    local sd_p   : di %6.3f r(sd)

    ksmirnov b, by(sample)
    local ks_d  : di %6.3f r(D)
    if r(p) < 0.001 local ks_p "< 0.001"
    else local ks_p : di "= " %5.3f r(p)

    preserve
        keep if sample == 2
        collapse (mean) iter_mean = b, by(iter)
        local n_iter = _N
        count if iter_mean >= `mean_r_raw'
        if r(N) == 0 local p_one : di "< " %5.3f 1 / `n_iter'
        else local p_one : di "= " %5.3f r(N) / `n_iter'
        count if abs(iter_mean) >= abs(`mean_r_raw')
        if r(N) == 0 local p_two : di "< " %5.3f 1 / `n_iter'
        else local p_two : di "= " %5.3f r(N) / `n_iter'
        sum iter_mean
        local mean_imean : di %6.3f r(mean)
        local sd_imean   : di %6.3f r(sd)
    restore

    preserve
        qui sum b
        local gmin  = r(min)
        local gmax  = r(max)
        local xmin  = floor(`gmin' * 10) / 10
        local xmax  = ceil(`gmax' * 10) / 10
        local xstep = cond(`xmax' - `xmin' > 1.5, 0.2, 0.1)
        local ngrid = 400
        if _N < `ngrid' set obs `ngrid'
        gen xgrid = `gmin' + (`gmax' - `gmin') * (_n - 1) / (`ngrid' - 1) in 1/`ngrid'
        kdensity b if sample == 1, nograph at(xgrid) gen(dens_r)
        kdensity b if sample == 2, nograph at(xgrid) gen(dens_p)

        gen hi_r = dens_r if dens_r >= dens_p
        gen lo_r = dens_p if dens_r >= dens_p
        gen hi_p = dens_p if dens_p >  dens_r
        gen lo_p = dens_r if dens_p >  dens_r

        local modes $exhibit_mode
        if "$exhibit_mode" == "both" local modes presentation paper
        foreach mode in `modes' {
            local figdir ../output/figures
            local stats_note `"- "Randomization Inference p `p_two'; Kolmogorov-Smirnov p `ks_p'""'
            if "`mode'" == "paper" {
                local figdir ../output/figures/paper
                local stats_note
            }
            tw rarea hi_r lo_r xgrid, color(ebblue%25) lwidth(none) || ///
               rarea hi_p lo_p xgrid, color(gs12%50) lwidth(none) || ///
               line dens_r xgrid, color(ebblue%70) lwidth(medthick) || ///
               line dens_p xgrid, color(gs10%80) lwidth(medthick) lpattern(dash) ///
               xtitle("DiD Coefficient (log `outcome')") ///
               ytitle("Density") ///
               xlab(`xmin'(`xstep')`xmax') ///
               xline(0, lcolor(gs6) lpattern(dash)) ///
               xline(`mean_r_raw', lcolor(ebblue) lpattern(solid) lwidth(medthin)) ///
               legend(on order(3 "Actual Treatment Effects (N=`N_r', mean=`mean_r', sd=`sd_r')" ///
                               4 "Placebo Treatment Effects (N=`N_p', mean=`mean_p', sd=`sd_p')" ///
                               `stats_note') ///
                      pos(7) ring(1) region(fcolor(none)) size(small))
            graph export `figdir'/did_coefs_overlay_kdens_eb`suf'$suffix.pdf, replace
        }
    restore

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
           note("One-sided RI p `p_one'; two-sided RI p `p_two'; KS D = `ks_d', p `ks_p'", size(vsmall))
        graph export ../output/figures/placebo_iter_means_ri_eb`suf'$suffix.pdf, replace
    restore

end

main
