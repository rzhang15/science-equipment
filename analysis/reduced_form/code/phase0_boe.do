/* ---------------------------------------------------------------------------
 phase0_boe.do
 Phase 0: back-of-envelope test of constant returns to scale at the project
 level.

 For each suf in {"", "_r1_r2", "_r1_r2_public"} that has both the all_jrnls
 and top_jrnls panel built:
   1. Run with-shares pooled DID for ppr_cnt + cite_affl_wt on all_jrnls and
      ppr_cnt on top_jrnls.
   2. Compute and stash:
        p_top_pre          = pre-2014 mean top-15 pubs / pre-2014 mean all pubs
        cite_per_pub_pre   = pre-2014 mean citations / pre-2014 mean all pubs
        impl_p_top         = beta_pub_top  / beta_pub_all   (Wald num)
        impl_cite          = beta_cite_all / beta_pub_all   (Wald num)
        delta-method SE and 95% CI on each ratio
        z-stat against H0: impl_p_top == p_top_pre
        z-stat against H0: impl_cite  == cite_per_pub_pre

 Both nulls hold jointly under constant returns to scale at the project level:
 if cutting the budget by Δ%% scales every project's output by Δ%%, the marginal
 cut paper has the average top-pub probability and average citation rate. So
 rejecting either ratio rejects CRS at the project level.

 Inputs:   ../temp/es_<samp><suf>.dta   (built by restrict_samp in analysis.do)
 Outputs:  ../output/tables/boe<suf>.txt
--------------------------------------------------------------------------- */

clear all
program drop _all
set more off

cap mkdir ../output
cap mkdir ../output/tables

program boe_one_suf
    syntax, r1r2(int) public(int)
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"
    local fes athr_id year

    /* require both panels for this suf */
    local missing = 0
    foreach samp in all_jrnls top_jrnls {
        cap confirm file ../temp/es_`samp'`suf'.dta
        if _rc local missing = 1
    }
    if `missing' {
        di as text "phase0_boe: panels for suf=`suf' not built -- skipping"
        di as text "    (run analysis.do main, which calls restrict_samp for that suf)"
        exit 0
    }

    /* drop any stale scalars from a prior suf */
    foreach s in pm_all_ppr_cnt pm_all_cite_affl_wt pm_top_ppr_cnt           ///
                 b_all_ppr_cnt  se_all_ppr_cnt                               ///
                 b_all_cite_affl_wt se_all_cite_affl_wt                      ///
                 b_top_ppr_cnt  se_top_ppr_cnt                               ///
                 p_top_pre cite_per_pub_pre                                  ///
                 impl_p_top se_impl_p_top lo_p_top hi_p_top z_p_top          ///
                 impl_cite  se_impl_cite  lo_cite  hi_cite  z_cite {
        cap scalar drop `s'
    }

    /* ----- all_jrnls: ppr_cnt + cite_affl_wt ----- */
    use ../temp/es_all_jrnls`suf', clear
    gen post       = year >= 2014
    gen Z_it       = exposure       * post
    gen Z_share_it = mkt_spend_shr  * post

    foreach yvar in ppr_cnt cite_affl_wt {
        qui sum `yvar' if year < 2014
        scalar pm_all_`yvar'  = r(mean)
        qui reghdfe `yvar' Z_it Z_share_it, absorb(`fes') vce(cluster athr_id)
        scalar b_all_`yvar'   = _b[Z_it]
        scalar se_all_`yvar'  = _se[Z_it]
    }

    /* ----- top_jrnls: ppr_cnt ----- */
    use ../temp/es_top_jrnls`suf', clear
    gen post       = year >= 2014
    gen Z_it       = exposure       * post
    gen Z_share_it = mkt_spend_shr  * post

    qui sum ppr_cnt if year < 2014
    scalar pm_top_ppr_cnt  = r(mean)
    qui reghdfe ppr_cnt Z_it Z_share_it, absorb(`fes') vce(cluster athr_id)
    scalar b_top_ppr_cnt   = _b[Z_it]
    scalar se_top_ppr_cnt  = _se[Z_it]

    /* ----- ratios + CRS-null z-stats ----- */
    scalar p_top_pre        = pm_top_ppr_cnt / pm_all_ppr_cnt
    scalar cite_per_pub_pre = pm_all_cite_affl_wt / pm_all_ppr_cnt

    scalar impl_p_top = b_top_ppr_cnt      / b_all_ppr_cnt
    scalar impl_cite  = b_all_cite_affl_wt / b_all_ppr_cnt

    /* delta-method SE on the ratio of two cluster-robust coefficients.
       Cov(b_num,b_den) is treated as zero -- conservative because the two
       regressions are run on different samples (all_jrnls vs top_jrnls for
       impl_p_top) or different outcomes on the same sample (impl_cite, where
       the omitted Cov is bounded by the SEs but small in practice).
       Replace with bootstrap if a referee pushes. */
    scalar se_impl_p_top = abs(impl_p_top) * sqrt(                            ///
        (se_top_ppr_cnt/b_top_ppr_cnt)^2 + (se_all_ppr_cnt/b_all_ppr_cnt)^2 )
    scalar se_impl_cite  = abs(impl_cite)  * sqrt(                            ///
        (se_all_cite_affl_wt/b_all_cite_affl_wt)^2 +                          ///
        (se_all_ppr_cnt     /b_all_ppr_cnt     )^2 )

    scalar z_p_top = (impl_p_top - p_top_pre)        / se_impl_p_top
    scalar z_cite  = (impl_cite  - cite_per_pub_pre) / se_impl_cite

    scalar lo_p_top = impl_p_top - 1.96 * se_impl_p_top
    scalar hi_p_top = impl_p_top + 1.96 * se_impl_p_top
    scalar lo_cite  = impl_cite  - 1.96 * se_impl_cite
    scalar hi_cite  = impl_cite  + 1.96 * se_impl_cite

    /* ----- pack into matrix and write txt ----- */
    cap mat drop boe
    mat boe = J(21,1,.)
    mat boe[ 1,1] = pm_all_ppr_cnt
    mat boe[ 2,1] = pm_top_ppr_cnt
    mat boe[ 3,1] = pm_all_cite_affl_wt
    mat boe[ 4,1] = p_top_pre
    mat boe[ 5,1] = cite_per_pub_pre
    mat boe[ 6,1] = b_all_ppr_cnt
    mat boe[ 7,1] = se_all_ppr_cnt
    mat boe[ 8,1] = b_top_ppr_cnt
    mat boe[ 9,1] = se_top_ppr_cnt
    mat boe[10,1] = b_all_cite_affl_wt
    mat boe[11,1] = se_all_cite_affl_wt
    mat boe[12,1] = impl_p_top
    mat boe[13,1] = se_impl_p_top
    mat boe[14,1] = lo_p_top
    mat boe[15,1] = hi_p_top
    mat boe[16,1] = z_p_top
    mat boe[17,1] = impl_cite
    mat boe[18,1] = se_impl_cite
    mat boe[19,1] = lo_cite
    mat boe[20,1] = hi_cite
    mat boe[21,1] = z_cite

    mat rownames boe =                                                        ///
        pre_mean_pub_all  pre_mean_pub_top  pre_mean_cite_all                 ///
        p_top_pre         cite_per_pub_pre                                    ///
        b_pub_all  se_pub_all  b_pub_top  se_pub_top                          ///
        b_cite_all se_cite_all                                                ///
        impl_p_top_marginal se_impl_p_top ci_lo_p_top ci_hi_p_top             ///
        z_vs_crs_p_top                                                        ///
        impl_cite_marginal  se_impl_cite  ci_lo_cite  ci_hi_cite              ///
        z_vs_crs_cite
    mat colnames boe = value

    qui matrix_to_txt, saving("../output/tables/boe`suf'.txt")                ///
        matrix(boe) title(<tab:boe`suf'>) format(%20.4f) replace

    /* ----- log to console ----- */
    di as text _newline "===== Phase 0 BOE  suf='`suf'' ====="
    di as text "  pre_mean_pub_all              = " %10.4f scalar(pm_all_ppr_cnt)
    di as text "  pre_mean_pub_top              = " %10.4f scalar(pm_top_ppr_cnt)
    di as text "  pre_mean_cite_all             = " %10.4f scalar(pm_all_cite_affl_wt)
    di as text "  p_top_pre (CRS null for top)  = " %10.4f scalar(p_top_pre)
    di as text "  cite_per_pub_pre (CRS null)   = " %10.4f scalar(cite_per_pub_pre)
    di as text ""
    di as text "  beta pub (all_jrnls)          = " %10.4f scalar(b_all_ppr_cnt)      ///
        "  (se " %7.4f scalar(se_all_ppr_cnt) ")"
    di as text "  beta pub (top_jrnls)          = " %10.4f scalar(b_top_ppr_cnt)      ///
        "  (se " %7.4f scalar(se_top_ppr_cnt) ")"
    di as text "  beta cite (all_jrnls)         = " %10.4f scalar(b_all_cite_affl_wt) ///
        "  (se " %7.4f scalar(se_all_cite_affl_wt) ")"
    di as text ""
    di as text "  implied P(top | dropped pub)  = " %10.4f scalar(impl_p_top)         ///
        "   95%% CI [" %7.4f scalar(lo_p_top) ", " %7.4f scalar(hi_p_top) "]"
    di as text "    z vs CRS null               = " %10.4f scalar(z_p_top)
    di as text "  implied cite per dropped pub  = " %10.4f scalar(impl_cite)          ///
        "   95%% CI [" %7.4f scalar(lo_cite)  ", " %7.4f scalar(hi_cite)  "]"
    di as text "    z vs CRS null               = " %10.4f scalar(z_cite)
end

program main
    boe_one_suf, r1r2(0) public(0)
    boe_one_suf, r1r2(1) public(0)
    boe_one_suf, r1r2(1) public(1)
end

main
