set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

global WEIGHT_MSIM 0

program main
    predict_decline, samp(all_jrnls) suf(_r1_r2)
end

program predict_decline
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

    ppmlhdfe ppr_cnt Z_it Z_share_it `wt', absorb(athr_id year) vce(cluster athr_id)
    local b = _b[Z_it]
    keep if e(sample)

    gen double pred_chg     = `b' * exposure
    gen double pred_pct_chg = 100 * (exp(`b' * exposure) - 1)

    keep athr_id athr_name inst age_2014 cluster_30 exposure pred_chg pred_pct_chg
    // tsfill rows carry blank athr_name; backfill within author before deduping
    gsort athr_id -athr_name
    by athr_id: replace athr_name = athr_name[1]
    by athr_id: keep if _n == 1
    gisid athr_id

    order athr_name inst athr_id age_2014 cluster_30 exposure pred_chg pred_pct_chg
    gsort -exposure
    save ../temp/pred_decline_by_athr`suf'`wsuf', replace
    export delimited using ../output/pred_decline_by_athr`suf'`wsuf'.csv, replace

    sum pred_chg, d
    di as text "N authors = " _N "  beta = " %7.4f `b'
end

main
