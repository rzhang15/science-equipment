set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main
    overlay_hist
end

program overlay_hist
    use ../external/real/did_coefs, clear
    keep b spend_2013
    gen sample = 1
    append using ../external/placebo/did_coefs_placebo, keep(b spend_2013)
    replace sample = 2 if mi(sample)

    // unweighted summaries
    sum b if sample == 1, d
    local N_r    = r(N)
    local mean_r : di %6.3f r(mean)
    local sd_r   : di %6.3f r(sd)
    sum b if sample == 2, d
    local N_p    = r(N)
    local mean_p : di %6.3f r(mean)
    local sd_p   : di %6.3f r(sd)

    tw kdensity b if sample == 1, color(lavender%70) lwidth(medthick) || ///
       kdensity b if sample == 2, color(orange%70) lwidth(medthick) ///
       xtitle("DiD Coefficient", size(small)) ///
       ytitle("Density", size(small)) ///
       xlab(, labsize(small)) ylab(, labsize(small)) ///
       xline(0, lcolor(gs6) lpattern(dash)) ///
       title("Unweighted", size(small)) ///
       legend(on order(1 "Real (N=`N_r', mean=`mean_r', sd=`sd_r')" ///
                       2 "Placebo (N=`N_p', mean=`mean_p', sd=`sd_p')") ///
              pos(1) ring(0) region(fcolor(none)) size(small))
    graph export ../output/figures/did_coefs_overlay_kdens_uw.pdf, replace

    // spend-weighted summaries
    sum b [aw=spend_2013] if sample == 1
    local mean_rw : di %6.3f r(mean)
    local sd_rw   : di %6.3f r(sd)
    sum b [aw=spend_2013] if sample == 2
    local mean_pw : di %6.3f r(mean)
    local sd_pw   : di %6.3f r(sd)

    tw kdensity b [aw=spend_2013] if sample == 1, color(lavender%70) lwidth(medthick) || ///
       kdensity b [aw=spend_2013] if sample == 2, color(orange%70) lwidth(medthick) ///
       xtitle("DiD Coefficient", size(small)) ///
       ytitle("Density (spend-weighted)", size(small)) ///
       xlab(, labsize(small)) ylab(, labsize(small)) ///
       xline(0, lcolor(gs6) lpattern(dash)) ///
       title("Spend-weighted", size(small)) ///
       legend(on order(1 "Real (mean=`mean_rw', sd=`sd_rw')" ///
                       2 "Placebo (mean=`mean_pw', sd=`sd_pw')") ///
              pos(1) ring(0) region(fcolor(none)) size(small))
    graph export ../output/figures/did_coefs_overlay_kdens_sw.pdf, replace
end

main
