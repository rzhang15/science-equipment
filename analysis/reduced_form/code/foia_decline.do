set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

* Publication decline for the FOIA PIs that survive into es_all_jrnls_r1_r2.
*
* ATTRITION_CUT drops PIs whose LAST last-author paper ever is before that year.
* max_year runs past the 2010-2019 estimation window (out to 2025), so the gate
* uses post-window information and does not select on the in-window outcome.
* 0 = keep everyone.
* FOIA PIs carry observed (non-imputed) exposure, so this is invariant to the
* EXPOSURE_FILTER the prepped sample was built under. The full-sample beta
* reported alongside is NOT: it needs a real (non-placebo) prepped sample.

global ATTRITION_CUT 2020

program main
    build_panels
    attrition_sensitivity
    estimate_betas
    author_level_decline
    decline_scatter
end

program build_panels
    use ../output/prepped_samples/es_all_jrnls_r1_r2, clear
    gen post = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post
    save ../temp/foia_decline_full_all, replace
    apply_attrition
    save ../temp/foia_decline_full, replace

    use ../temp/foia_decline_full_all, clear
    keep if foia_athr == 1
    save ../temp/foia_decline_panel_all, replace
    apply_attrition
    save ../temp/foia_decline_panel, replace
end

program apply_attrition
    if $ATTRITION_CUT <= 0 exit
    qui gunique athr_id
    local n0 = r(unique)
    drop if max_year < $ATTRITION_CUT
    qui gunique athr_id
    di as text "attrition gate (max_year >= $ATTRITION_CUT): kept " r(unique) " of `n0' PIs"
end

program attrition_sensitivity
    foreach c in 0 2020 2021 2022 {
        use ../temp/foia_decline_panel_all, clear
        if `c' > 0 drop if max_year < `c'
        qui gunique athr_id
        local n = r(unique)
        cap noi qui ppmlhdfe ppr_cnt Z_it Z_share_it, absorb(athr_id year) vce(cluster athr_id)
        if _rc {
            di as error "attrition_sensitivity cut=`c' failed"
            continue
        }
        di as text "cut=`c'  N PIs=" %4.0f `n' "  b=" %8.4f _b[Z_it] ///
            "  se=" %7.4f _se[Z_it] "  t=" %6.2f _b[Z_it]/_se[Z_it]
    }
end

program estimate_betas
    mat foia_decline = J(6,2,.)

    use ../temp/foia_decline_panel, clear
    ppmlhdfe ppr_cnt Z_it Z_share_it, absorb(athr_id year) vce(cluster athr_id)
    scalar b_foia = _b[Z_it]
    mat foia_decline[1,1] = _b[Z_it]
    mat foia_decline[2,1] = _se[Z_it]
    mat foia_decline[3,1] = _b[Z_share_it]
    mat foia_decline[4,1] = _se[Z_share_it]
    qui sum ppr_cnt if year < 2014 & e(sample)
    mat foia_decline[5,1] = r(mean)
    qui gunique athr_id
    mat foia_decline[6,1] = r(unique)

    use ../temp/foia_decline_full, clear
    ppmlhdfe ppr_cnt Z_it Z_share_it, absorb(athr_id year) vce(cluster athr_id)
    scalar b_full = _b[Z_it]
    mat foia_decline[1,2] = _b[Z_it]
    mat foia_decline[2,2] = _se[Z_it]
    mat foia_decline[3,2] = _b[Z_share_it]
    mat foia_decline[4,2] = _se[Z_share_it]
    qui sum ppr_cnt if year < 2014 & e(sample)
    mat foia_decline[5,2] = r(mean)
    qui gunique athr_id
    mat foia_decline[6,2] = r(unique)

    mat rownames foia_decline = b_exposure se_exposure b_share se_share pre_mean n_pis
    mat colnames foia_decline = foia_only full_samp
    cap mkdir ../output/tables
    qui matrix_to_txt, saving("../output/tables/foia_decline_betas.txt") ///
        matrix(foia_decline) title(<tab:foia_decline_betas>) format(%20.6f) replace

    di as text _newline "beta(FOIA-only) = " %7.4f b_foia "   beta(full samp) = " %7.4f b_full
end

program author_level_decline
    use ../temp/foia_decline_panel, clear
    gen _pre  = ppr_cnt if year <  2014
    gen _post = ppr_cnt if year >= 2014
    bys athr_id: egen pre_mean  = mean(_pre)
    bys athr_id: egen post_mean = mean(_post)

    qui sum _pre
    local agg_pre = r(mean)
    qui sum _post
    local agg_post = r(mean)
    local agg_ratio = `agg_post' / `agg_pre'
    di as text "FOIA sample pooled pre mean = " %5.3f `agg_pre' ///
        "  post mean = " %5.3f `agg_post' "  ratio = " %5.3f `agg_ratio'

    gen double realized_ratio = post_mean / pre_mean if pre_mean > 0
    gen double realized_pct     = 100 * (realized_ratio - 1)
    gen double realized_pct_adj = 100 * (realized_ratio / `agg_ratio' - 1)
    gen double pred_chg = b_foia * exposure
    gen double pred_pct = 100 * (exp(b_foia * exposure) - 1)

    gsort athr_id -athr_name
    by athr_id: replace athr_name = athr_name[1]
    by athr_id: keep if _n == 1
    gisid athr_id

    gen byte declined_raw = realized_pct < 0     if !mi(realized_pct)
    gen byte declined_adj = realized_pct_adj < 0 if !mi(realized_pct_adj)
    gen byte pred_decline = pred_pct < 0         if !mi(pred_pct)

    keep athr_name inst athr_id age_2014 cluster_30 exposure mkt_spend_shr ///
         pre_mean post_mean realized_pct realized_pct_adj ///
         pred_chg pred_pct declined_raw declined_adj pred_decline
    order athr_name inst athr_id age_2014 cluster_30 exposure mkt_spend_shr ///
          pre_mean post_mean realized_pct realized_pct_adj pred_pct ///
          declined_raw declined_adj pred_decline

    gsort -exposure
    save ../temp/foia_ppr_decline, replace
    export delimited using ../output/foia_ppr_decline.csv, replace

    count
    di as text _newline "=== FOIA PIs: " r(N)
    count if pred_decline == 1
    di as text "predicted decline (b x exposure < 0): " r(N)
    count if declined_raw == 1
    di as text "realized raw decline (post < pre): " r(N)
    count if declined_adj == 1
    di as text "realized decline vs FOIA-sample trend: " r(N)
    tab pred_decline declined_adj, row

    qui corr pred_pct realized_pct_adj
    di as text "corr(predicted, realized-adjusted) = " %6.3f r(rho)

    di as text _newline "=== 15 largest predicted declines ==="
    gsort pred_pct
    list athr_name inst exposure pred_pct realized_pct realized_pct_adj in 1/15, ///
        noobs abbrev(22) sep(0)

    di as text _newline "=== 15 largest realized declines (trend-adjusted) ==="
    gsort realized_pct_adj
    list athr_name inst exposure pred_pct realized_pct realized_pct_adj in 1/15, ///
        noobs abbrev(22) sep(0)
end

program decline_scatter
    cap mkdir ../output/figures/all_jrnls
    use ../temp/foia_ppr_decline, clear
    local bstr : di %6.3f b_foia
    twoway (scatter realized_pct_adj exposure, mcolor(ebblue%60) msymbol(O)) ///
           (function 100*(exp(b_foia*x)-1), range(exposure) lcolor(dkorange) lwidth(medthick)), ///
        xtitle("Observed exposure") ///
        ytitle("Realized {&Delta} papers vs FOIA trend (%)") ///
        legend(order(1 "FOIA PI" 2 "PPML fit") pos(6) rows(1)) ///
        note("{&beta} = `bstr' (FOIA-only PPML, author + year FE)", size(small) pos(7) ring(1) justification(left))
    graph export ../output/figures/all_jrnls/foia_decline_scatter.pdf, replace
end

main
