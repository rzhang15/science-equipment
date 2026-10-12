set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries, loadglob(../external/lib/globals.txt)
adopath ++ "../external/lib/stata"
version 17

program main
    cap mkdir ../output/figures
    cap mkdir ../output/figures/all_jrnls
    foreach suf in _r1_r2 _r1_r2_public _r1 _r1_public {
        exposure_dist, samp(all_jrnls) suf(`suf')
    }
end

program exposure_dist
    syntax, samp(string) [suf(string)]
    use athr_id exposure mkt_spend_shr using ../external/real_exposure/athr_exposure_${EXPOSURE_VERSION}, clear
    rename (exposure mkt_spend_shr) (exposure_all mkt_spend_shr_all)
    append using ../external/prepped_samples/exposure_inputs_`samp'`suf'
    sum exposure_all, d
    local n_obs = r(N)
    local mean : di %4.3f r(mean)
    local sd   : di %4.3f r(sd)
    sum imputed, d
    local n_imp = r(N)
    local imputed_mean : di %4.3f r(mean)
    local imputed_sd   : di %4.3f r(sd)
    sum mkt_spend_shr_all, d
    local mshr_mean : di %4.3f r(mean)
    local mshr_sd   : di %4.3f r(sd)
    sum imputed_mkt_spend_shr, d
    local imshr_mean : di %4.3f r(mean)
    local imshr_sd   : di %4.3f r(sd)
    di as text "exposure_dist `samp'`suf': observed FOIA PIs N=`n_obs' (mean `mean', sd `sd'; share mean `mshr_mean')"
    di as text "  imputed non-FOIA PIs in the panel N=`n_imp'"
    di as text "  \ExpoMeanImputed  = `imputed_mean'"
    di as text "  \ExpoSDImputed    = `imputed_sd'"
    di as text "  \ShareMeanImputed = `imshr_mean'"
    foreach fmode of global FIG_MODES {
        local leg1 legend(on label(1 "FOIA PI observed exposure (mean = `mean', sd = `sd')") label(2 "Imputed exposure (mean = `imputed_mean', sd = `imputed_sd')") pos(7) ring(1) size(small))
        local leg2 legend(on label(1 "FOIA PI observed (mean = `mshr_mean', sd = `mshr_sd')") label(2 "Imputed (mean = `imshr_mean', sd = `imshr_sd')") pos(7) ring(1) size(small))
        local xlab1 xlab(#15)
        local xlab2 xlab(#15)
        if "`fmode'" == "paper" {
            local leg1 legend(on order(1 "Observed, FOIA PIs" 2 "Imputed, non-FOIA PIs") ring(0) position(1) cols(1) region(lcolor(none)) size(small))
            local leg2 `leg1'
            local xlab1 xlab(#15, format(%4.2f))
            local xlab2 xlab(#15, format(%3.1f))
        }
        tw kdensity exposure_all, lcolor(ebblue) || kdensity imputed, lcolor(dkorange) ///
            xtitle("Exposure measure") ytitle("Density") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) `xlab1' `leg1'
        fig_export, path("../output/figures/`samp'/exposure_dist`suf'.pdf") mode(`fmode')
        tw kdensity mkt_spend_shr_all, lcolor(ebblue) || kdensity imputed_mkt_spend_shr, lcolor(dkorange) ///
            xtitle("Treated-market share") ytitle("Density") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) `xlab2' `leg2'
        fig_export, path("../output/figures/`samp'/mkt_spend_shr_dist`suf'.pdf") mode(`fmode')
    }
end

main
