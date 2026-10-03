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
        cap mat drop placebo_sd_test
        foreach o in price spend {
            sd_test, outcome(`o')
        }
        output_tables
    }
end

program sd_test
    syntax, outcome(str)

    use ../external/real/did_coefs_`outcome'$suffix, clear
    qui sum b
    local sd_r   = r(sd)
    local n_r    = r(N)
    local mean_r = r(mean)
    if `n_r' < 2 | missing(`sd_r') {
        di as error "Real coefficients must contain at least two valid estimates."
        exit 459
    }
    qui sum se
    local se_r = r(mean)
    keep b
    gen sample = 1
    save ../temp/real_b_`outcome'$suffix, replace

    use ../output/placebo_sd_coefs$suffix, clear
    isid iter cid
    assert !missing(iter, cid)
    // An omitted coefficient (SE = 0) is not a successfully estimated effect.
    gen byte valid_estimate = !missing(b_`outcome', se_`outcome') & se_`outcome' > 0
    gcollapse (sd) sd_b = b_`outcome' (mean) mean_b = b_`outcome' (mean) mean_se = se_`outcome' ///
        (count) n_mkts = b_`outcome' (sum) n_valid = valid_estimate, by(iter)
    // Fail rather than condition the placebo distribution on regression success.
    count if n_mkts != `n_r' | n_valid != `n_r' | missing(sd_b)
    if r(N) > 0 {
        di as error "Incomplete or invalid placebo draws for `outcome'$suffix: " r(N)
        list iter n_mkts n_valid sd_b if n_mkts != `n_r' | n_valid != `n_r' | missing(sd_b), noobs
        exit 459
    }
    if _N == 0 {
        di as error "No placebo draws available."
        exit 459
    }
    save ../output/placebo_sd_iters_`outcome'$suffix, replace

    count
    local n_draws = r(N)
    count if !missing(sd_b) & sd_b >= `sd_r'
    local n_exceed = r(N)
    local p_sd = `n_exceed' / `n_draws'
    // Exact binomial interval describes Monte Carlo uncertainty, including zero hits.
    quietly cii proportions `n_draws' `n_exceed', exact level(95)
    local p_mc_lb = r(lb)
    local p_mc_ub = r(ub)
    qui sum sd_b, d
    local sd_p_mean = r(mean)
    local sd_p_p5   = r(p5)
    local sd_p_p50  = r(p50)
    local sd_p_p95  = r(p95)
    local sd_p_max  = r(max)
    qui sum mean_se
    local se_p = r(mean)
    qui sum n_mkts
    local n_mkts_p = r(mean)

    mat col = (`sd_r' \ `n_r' \ `se_r' \ `n_draws' \ `n_mkts_p' \ `sd_p_mean' \ `sd_p_p5' \ `sd_p_p50' \ `sd_p_p95' \ `sd_p_max' \ `se_p' \ `p_sd' \ `n_exceed' \ `p_mc_lb' \ `p_mc_ub')
    mat rownames col = treated_sd n_treated treated_mean_se n_draws placebo_n_mkts placebo_sd_mean placebo_sd_p5 placebo_sd_p50 placebo_sd_p95 placebo_sd_max placebo_mean_se p_value n_exceed p_mc_lb p_mc_ub
    mat colnames col = `outcome'
    mat placebo_sd_test = nullmat(placebo_sd_test), col

    local sd_r_lab : di %5.3f `sd_r'
    local sd_p_lab : di %5.3f `sd_p_mean'
    local p_lab : di "= " %5.3f `p_sd'
    local p_ci_lab : di "[" %5.3f `p_mc_lb' ", " %5.3f `p_mc_ub' "]"

    local xmax = max(`sd_p_max', `sd_r') * 1.05
    tw histogram sd_b, color(gs10%80) width(0.005) start(0) ///
       xtitle("SD of DiD coefficients across placebo-treated markets (log `outcome')") ///
       ytitle("Density") ///
       xsc(range(0 `xmax')) ///
       xline(`sd_r', lcolor(ebblue) lwidth(medthick)) ///
       legend(on order(- "Treated SD = `sd_r_lab' (N = `n_r')" ///
                         "Placebo SD mean = `sd_p_lab' (draws = `n_draws')" ///
                         "Placebo p `p_lab' (`n_exceed'/`n_draws' exceedances)" ///
                         "95% Monte Carlo CI `p_ci_lab'") ///
              pos(1) ring(0) region(fcolor(none)) size(small))
    graph export ../output/figures/placebo_sd_hist_`outcome'$suffix.pdf, replace

    use ../output/placebo_sd_coefs$suffix, clear
    keep b_`outcome'
    rename b_`outcome' b
    drop if mi(b)
    gen sample = 2
    append using ../temp/real_b_`outcome'$suffix

    qui sum b if sample == 1
    local mean_r_lab : di %6.3f r(mean)
    qui sum b if sample == 2
    local N_p = r(N)
    local mean_p_lab : di %6.3f r(mean)
    local sd_pool_lab : di %6.3f r(sd)

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
    gen lo = min(dens_r, dens_p)

    local modes $exhibit_mode
    if "$exhibit_mode" == "both" local modes presentation paper
    foreach mode in `modes' {
        local figdir ../output/figures
        local stats_note `"- "Placebo SD test p `p_lab' (`n_exceed'/`n_draws' exceedances)" "95% Monte Carlo CI `p_ci_lab'""'
        if "`mode'" == "paper" {
            local figdir ../output/figures/paper
            local stats_note
        }
        tw rarea dens_r lo xgrid, color(ebblue%25) lwidth(none) || ///
           rarea dens_p lo xgrid, color(gs12%50) lwidth(none) || ///
           line dens_r xgrid, color(ebblue%70) lwidth(medthick) || ///
           line dens_p xgrid, color(gs10%80) lwidth(medthick) lpattern(dash) ///
           xtitle("DiD Coefficient (log `outcome')") ///
           ytitle("Density") ///
           xlab(`xmin'(`xstep')`xmax') ///
           xline(0, lcolor(gs6) lpattern(dash)) ///
           xline(`mean_r', lcolor(ebblue) lpattern(solid) lwidth(medthin)) ///
           legend(on order(3 "Actual Treatment Effects (N=`n_r', mean=`mean_r_lab', sd=`sd_r_lab')" ///
                           4 "Placebo Treatment Effects (N=`N_p', mean=`mean_p_lab', sd=`sd_pool_lab')" ///
                           `stats_note') ///
                  pos(7) ring(1) region(fcolor(none)) size(small))
        graph export `figdir'/did_coefs_overlay_kdens_sd_`outcome'$suffix.pdf, replace
    }
end

program output_tables
    foreach tab in placebo_sd_test {
        qui matrix_to_txt, saving("../output/tables/`tab'$suffix.txt") matrix(`tab') ///
            title(<tab:`tab'>) format(%20.4f) replace
    }
end

main
