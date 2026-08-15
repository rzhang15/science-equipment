set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

global WEIGHT_MSIM 1

program main
    fit_and_predict, samp(all_jrnls) suf(_r1_r2)
end

program fit_and_predict
    syntax, samp(string) suf(string)
    local wt ""
    local wsuf ""
    if "$WEIGHT_MSIM" == "1" {
        local wt "[pw=max_sim]"
        local wsuf "_msimwt"
    }

    use ../output/prepped_samples/es_`samp'`suf', clear
    gen post = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post

    ppmlhdfe ppr_cnt Z_it Z_share_it `wt', absorb(athr_id year) vce(cluster athr_id) d
    local b   = _b[Z_it]
    local se  = _se[Z_it]
    local blo = `b' - 1.96*`se'
    local bhi = `b' + 1.96*`se'

    predict double mu, mu
    keep if e(sample)

    gen double mu_cf     = mu * exp(-`b'   * Z_it)
    gen double mu_cf_lo  = mu * exp(-`bhi' * Z_it)
    gen double mu_cf_hi  = mu * exp(-`blo' * Z_it)
    gen double loss      = mu_cf    - mu
    gen double loss_lo   = mu_cf_lo - mu
    gen double loss_hi   = mu_cf_hi - mu

    gen double wloss    = loss    * max_sim
    gen double wmu      = mu      * max_sim
    gen double wmu_cf   = mu_cf   * max_sim

    qui sum ppr_cnt
    local tot_actual = r(sum)
    qui sum mu
    local tot_mu = r(sum)
    di as text _newline "fit check: sum(ppr_cnt)=" %12.1f `tot_actual' "  sum(mu)=" %12.1f `tot_mu'
    di as text "beta_exposure = " %7.4f `b' "  (SE " %7.4f `se' ")"

    save ../temp/output_loss_athr_yr`suf'`wsuf', replace

    preserve
        collapse (sum) mu mu_cf loss loss_lo loss_hi wmu wmu_cf wloss ///
                 (count) n_athr = mu, by(year)
        gen double pct_loss = 100 * loss / mu_cf
        list year n_athr mu mu_cf loss loss_lo loss_hi pct_loss if year >= 2014, ///
            sep(0) noobs abbrev(12)

        qui sum loss if year >= 2014
        local tot_loss = r(sum)
        local n_post   = r(N)
        qui sum loss_lo if year >= 2014
        local tot_lo = r(sum)
        qui sum loss_hi if year >= 2014
        local tot_hi = r(sum)
        qui sum mu_cf if year >= 2014
        local tot_cf = r(sum)
        qui sum wloss if year >= 2014
        local tot_wloss = r(sum)

        di as text _newline "TOTAL post-2014 papers lost = " %12.1f `tot_loss' ///
            "  [95% CI " %10.1f `tot_lo' ", " %10.1f `tot_hi' "]"
        di as text "  = " %8.2f 100*`tot_loss'/`tot_cf' "% of counterfactual output"
        di as text "PER YEAR (avg over `n_post' post years) = " %10.1f `tot_loss'/`n_post'
        di as text "max_sim-weighted total = " %12.1f `tot_wloss'

        keep year n_athr mu mu_cf loss loss_lo loss_hi pct_loss
        order year n_athr mu_cf mu loss loss_lo loss_hi pct_loss
        mkmat year n_athr mu_cf mu loss loss_lo loss_hi pct_loss, matrix(output_loss_by_year)
        mat colnames output_loss_by_year = year n_athr pred_cf pred_actual loss loss_lo loss_hi pct_loss
        cap mkdir ../output/tables
        cap mkdir ../output/tables/`samp'
        qui matrix_to_txt, saving("../output/tables/`samp'/output_loss_by_year`suf'`wsuf'.txt") ///
            matrix(output_loss_by_year) title(<tab:output_loss_by_year`suf'`wsuf'>) ///
            format(%20.4f) replace
    restore

    collapse (sum) mu mu_cf loss (max) exposure mkt_spend_shr max_sim ///
        (firstnm) cluster_30 if year >= 2014, by(athr_id)
    gen double pct_loss = 100 * loss / mu_cf
    sum loss, d
    save ../temp/output_loss_by_athr`suf'`wsuf', replace

    collapse (mean) avg_exposure = exposure avg_loss = loss ///
             (sum) tot_loss = loss tot_cf = mu_cf ///
             (count) n_athr = mu_cf, by(cluster_30)
    gen double pct_loss = 100 * tot_loss / tot_cf
    list cluster_30 n_athr avg_exposure avg_loss pct_loss, sep(0) noobs abbrev(12)
    mkmat cluster_30 n_athr avg_exposure avg_loss tot_loss pct_loss, ///
        matrix(output_loss_by_cluster)
    mat colnames output_loss_by_cluster = cluster n_athr avg_exposure avg_loss tot_loss pct_loss
    qui matrix_to_txt, saving("../output/tables/`samp'/output_loss_by_cluster`suf'`wsuf'.txt") ///
        matrix(output_loss_by_cluster) title(<tab:output_loss_by_cluster`suf'`wsuf'>) ///
        format(%20.4f) replace
end

main
