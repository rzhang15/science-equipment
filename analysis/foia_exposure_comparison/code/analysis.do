set more off
clear all
capture log close
program drop _all
version 17

program main
    prepare_sample
    compare_exposure
end

program prepare_sample
    use ../external/validation/validation_pi, clear
    keep athr_id exposure exposure_loo mkt_spend_shr mkt_spend_shr_loo
    rename exposure exposure_validation
    rename mkt_spend_shr share_validation
    isid athr_id
    save ../temp/loo, replace

    use athr_id year ppr_cnt exposure mkt_spend_shr foia_athr inst min_year ///
        cluster_30 using ../external/rf/prepped_samples/es_all_jrnls_r1_r2, clear
    keep if foia_athr == 1
    isid athr_id year
    merge m:1 athr_id using ../temp/loo, keep(1 3)
    assert _merge == 3
    drop _merge
    assert abs(exposure - exposure_validation) < 1e-6
    assert abs(mkt_spend_shr - share_validation) < 1e-6
    assert !mi(exposure, exposure_loo, mkt_spend_shr, mkt_spend_shr_loo, ppr_cnt)
    gen byte post = year >= 2014
    gen double Z_observed = exposure * post
    gen double Z_loo = exposure_loo * post
    gen double S_observed = mkt_spend_shr * post
    gen double S_loo = mkt_spend_shr_loo * post
    save ../temp/paired_panel, replace
    preserve
        bys athr_id (year): keep if _n == 1
        save ../output/paired_pi, replace
        export delimited using ../output/paired_pi.csv, replace
        corr exposure exposure_loo
        corr mkt_spend_shr mkt_spend_shr_loo
    restore
end

program compare_exposure
    tempname result
    postfile `result' str28 specification double coefficient se ci_lo ci_hi ///
        b_share se_share long N_rows N_pis using ../output/comparison, replace
    * These three comparisons are fixed before inspecting their results.
    * The middle specification changes only exposure, holding the share control fixed.
    foreach spec in observed loo_exposure_only loo_exposure_and_share {
        use ../temp/paired_panel, clear
        local z Z_observed
        local s S_observed
        if "`spec'" != "observed" local z Z_loo
        if "`spec'" == "loo_exposure_and_share" local s S_loo
        ppmlhdfe ppr_cnt `z' `s', absorb(athr_id year) vce(cluster athr_id)
        local b = _b[`z']
        local se = _se[`z']
        local bs = _b[`s']
        local ses = _se[`s']
        local N = e(N)
        gen byte included = e(sample)
        egen byte pi_tag = tag(athr_id) if included
        qui count if pi_tag == 1
        local N_pi = r(N)
        estimates save ../output/`spec', replace
        post `result' ("`spec'") (`b') (`se') ///
            (`b' - invnormal(.975)*`se') (`b' + invnormal(.975)*`se') ///
            (`bs') (`ses') (`N') (`N_pi')
    }
    postclose `result'
    use ../output/comparison, clear
    assert N_rows == N_rows[1]
    assert N_pis == N_pis[1]
    gen double p_normal = 2*normal(-abs(coefficient/se))
    save ../output/comparison, replace
    export delimited using ../output/comparison.csv, replace
    list, noobs abbreviate(28)
end

main
