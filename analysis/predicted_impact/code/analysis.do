/* ---------------------------------------------------------------------------
 analysis/predicted_impact/code/analysis.do

 Event study on predicted-impact tier counts and self-management outcomes.

 Outcomes
 --------
   Tier counts (from derived/openalex/predict_impact):
     n_pred_high            predicted high cite_pct (within field-year)
     n_pred_low             predicted low cite_pct
     n_pred_high_topdecile  predicted high P(topdecile)
     n_pred_low_topdecile   predicted low P(topdecile)
     n_pred_high_top15      predicted high P(top-15 journal)
     n_pred_low_top15       predicted low P(top-15 journal)
     n_real_high            realized high cite_pct (discriminator)
     n_real_low             realized low cite_pct (discriminator)
   Self-management (Phase 3.2 / 3.3):
     n_main_line            paper modal cluster == PI's pre-2013 modal
     n_side_line            otherwise
     n_large_team           team_size in top quartile within field-year
     n_small_team           team_size in bottom quartile
     n_high_junior          junior_share in top quartile
     n_low_junior           junior_share in bottom quartile

 Headline plot
 -------------
 combine_pred_real_plot draws predicted-high vs predicted-low and realized-high
 vs realized-low coefficients side-by-side. If publications fall in
 n_pred_low while n_pred_high is preserved, foresight wins within PI.

 Heterogeneity (Phase 3.1)
 -------------------------
 het_event_study re-runs the event study on median-splits of:
   portfolio_hhi      Herfindahl on paper_modal_cluster over pre-2014 papers
   lab_size_pre       distinct pre-2014 coauthors
   grants_per_pub_pre num_grants pre-2014 sum / pre_ppr_cnt_sum

 Outputs
 -------
   ../output/figures/<samp>/es_<yvar>[<suf>].pdf
   ../output/figures/<samp>/es_pred_vs_real<suf>.pdf
   ../output/tables/<samp>/pdid_<yvar><suf>.txt
   ../temp/es_<samp><suf>.dta                 (built by restrict_samp)
--------------------------------------------------------------------------- */

clear all
program drop _all
set more off

cap mkdir ../output
cap mkdir ../output/figures
cap mkdir ../output/tables
cap mkdir ../temp

global TIER_OUTCOMES n_pred_high n_pred_low                              ///
                     n_pred_high_topdecile n_pred_low_topdecile          ///
                     n_pred_high_top15 n_pred_low_top15                  ///
                     n_real_high n_real_low
global SELFMGMT_OUTCOMES n_main_line n_side_line                         ///
                         n_large_team n_small_team                       ///
                         n_high_junior n_low_junior
global ALL_OUTCOMES $TIER_OUTCOMES $SELFMGMT_OUTCOMES

global SPLITS portfolio_hhi lab_size_pre grants_per_pub_pre

program main
    gather_external_data
    foreach samp in all_jrnls {
        cap mkdir ../output/figures/`samp'
        cap mkdir ../output/tables/`samp'
        foreach r1r2 in 0 1 {
            foreach public in 0 1 {
                if (`r1r2' == 0 & `public' == 1) continue
                restrict_samp, samp(`samp') r1r2(`r1r2') public(`public')
                event_study,  samp(`samp') r1r2(`r1r2') public(`public')
                pooled_did,   samp(`samp') r1r2(`r1r2') public(`public')
                output_tables, samp(`samp') r1r2(`r1r2') public(`public')
                combine_pred_real_plot, samp(`samp') r1r2(`r1r2') public(`public')

                /* Phase 3.1: PI heterogeneity */
                foreach s of global SPLITS {
                    foreach half in high low {
                        het_event_study, samp(`samp') r1r2(`r1r2') public(`public') ///
                                         split(`s') half(`half')
                    }
                }
            }
        }
    }
end

/* ---------------------------------------------------------------------------
 gather_external_data
 Build the per-PI exposure file and the PI-year grant count file consumed by
 restrict_samp. Mirrors analysis/reduced_form/code/analysis.do.
--------------------------------------------------------------------------- */
program gather_external_data
    import delimited ../external/exposure/final_imputed_exposure_restricted, clear
    rename exposure imputed
    rename mkt_spend_shr imputed_mkt_spend_shr
    save ../temp/exposure, replace

    use ../external/grants/pi_grants_clean, clear
    bys athr_id year: gen num_grants = _N
    contract athr_id year num_grants
    drop _freq
    save ../temp/athr_yr_grnt_cnt, replace
end

/* ---------------------------------------------------------------------------
 restrict_samp
 Build the analysis panel for this samp/suf. Reuses the columns the
 reduced-form sample already has (exposure, mkt_spend_shr, etc.) and adds the
 Phase 3.1 het flags.
--------------------------------------------------------------------------- */
program restrict_samp
    syntax, samp(string) [r1r2(int 0) public(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"

    use ../external/samp/athr_panel_full_year_last_`samp'`suf', clear

    keep if inrange(year, 2010, 2019)
    bys athr_id: egen __min_year = min(year)
    keep if __min_year <= 2010
    drop __min_year

    merge m:1 athr_id using ../temp/exposure, assert(1 2 3) keep(3) nogen
    merge m:1 athr_id using ../external/real_exposure/athr_exposure, assert(1 2 3) keep(1 3) nogen

    replace exposure = imputed if mi(exposure)
    replace mkt_spend_shr = imputed_mkt_spend_shr if mi(mkt_spend_shr)
    drop if exposure <= 0 | mi(exposure)
    drop if mkt_spend_shr <= 0 | mi(mkt_spend_shr)

    /* Fill new tier-count columns with zero outside the years we scored */
    foreach v of global ALL_OUTCOMES {
        cap confirm variable `v'
        if !_rc replace `v' = 0 if mi(`v')
    }

    /* num_grants from analysis-level upstream (mirrors reduced_form). */
    cap merge 1:1 athr_id year using ../temp/athr_yr_grnt_cnt, keep(1 3) assert(1 2 3) nogen
    cap replace num_grants = 0 if mi(num_grants)

    /* Pre-period publication and grant sums (PI-level, time-invariant). */
    gen __pre_ppr  = ppr_cnt    if year < 2014
    bys athr_id: egen pre_ppr_cnt_sum = sum(__pre_ppr)
    drop __pre_ppr
    gen __pre_g = num_grants if year < 2014
    bys athr_id: egen pre_grants_sum = sum(__pre_g)
    drop __pre_g

    /* Phase 3.1 het flags. */
    cap confirm variable portfolio_hhi
    if !_rc {
        sum portfolio_hhi if !mi(portfolio_hhi), d
        gen high_portfolio_hhi = portfolio_hhi >= r(p50) if !mi(portfolio_hhi)
        gen low_portfolio_hhi  = portfolio_hhi <  r(p50) if !mi(portfolio_hhi)
    }
    cap confirm variable lab_size_pre
    if !_rc {
        sum lab_size_pre if !mi(lab_size_pre), d
        gen high_lab_size_pre = lab_size_pre >= r(p50) if !mi(lab_size_pre)
        gen low_lab_size_pre  = lab_size_pre <  r(p50) if !mi(lab_size_pre)
    }
    gen grants_per_pub_pre = pre_grants_sum / pre_ppr_cnt_sum if pre_ppr_cnt_sum > 0
    sum grants_per_pub_pre if !mi(grants_per_pub_pre), d
    gen high_grants_per_pub_pre = grants_per_pub_pre >= r(p50) if !mi(grants_per_pub_pre)
    gen low_grants_per_pub_pre  = grants_per_pub_pre <  r(p50) if !mi(grants_per_pub_pre)

    save ../temp/es_`samp'`suf', replace
end

/* ---------------------------------------------------------------------------
 event_study
 Standard event study spec with cluster-robust SEs at the PI level. Outcomes:
 every tier-count + self-management column we built. Outputs both the saved
 coefficient panel and a per-outcome plot.
--------------------------------------------------------------------------- */
program event_study
    syntax, samp(string) [r1r2(int 0) public(int 0)]
    local fes athr_id year
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"

    use ../temp/es_`samp'`suf', clear
    gen rel = year - 2014
    qui sum rel
    local abs_lag  = abs(r(max))
    local abs_lead = abs(r(min))

    forval i = 1/`abs_lead' {
        gen int_lead`i' = exposure      if rel == -`i'
        gen mshr_lead`i' = mkt_spend_shr if rel == -`i'
    }
    forval i = 0/`abs_lag' {
        gen int_lag`i'  = exposure      if rel == `i'
        gen mshr_lag`i' = mkt_spend_shr if rel == `i'
    }
    ds int_lead* int_lag* mshr_lead* mshr_lag*
    foreach v in `r(varlist)' {
        replace `v' = 0 if mi(`v')
    }
    local int_leads
    local int_lags
    local mshr_leads
    local mshr_lags
    forval i = 2/`abs_lead' {
        local int_leads  int_lead`i'  `int_leads'
        local mshr_leads mshr_lead`i' `mshr_leads'
    }
    forval i = 0/`abs_lag' {
        local int_lags  `int_lags'  int_lag`i'
        local mshr_lags `mshr_lags' mshr_lag`i'
    }

    foreach yvar of global ALL_OUTCOMES {
        cap confirm variable `yvar'
        if _rc continue
        preserve
        mat drop _all
        sum `yvar' if rel <= -1 & exposure > 0, d
        local pre_mean : di %6.3f r(mean)
        qui reghdfe `yvar' `int_leads' `int_lags' int_lead1 ///
                          `mshr_leads' `mshr_lags' mshr_lead1, ///
                          absorb(`fes') vce(cluster athr_id)
        foreach var in `int_leads' `int_lags' int_lead1 {
            mat row = _b[`var'], _se[`var']
            if "`var'" == "int_lead1" mat row = 0,0
            mat es = nullmat(es) \ row
        }
        svmat es
        keep es1 es2
        drop if mi(es1)
        rename (es1 es2) (b se)
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        gen rel = .
        replace rel = -`abs_lead' if _n == 1
        replace rel = rel[_n-1] + 1 if _n > 1
        replace rel = rel + 1 if rel >= -1
        replace rel = -1 if rel == `abs_lag' + 1
        gen year = rel + 2014
        sort rel
        save ../temp/es_`yvar'_`samp'`suf', replace
        plot_one, yvar(`yvar') samp(`samp') suf(`suf') pre_mean(`pre_mean')
        restore
    }
end

program plot_one
    syntax, yvar(string) samp(string) pre_mean(string) [suf(string)]
    sum ub, d
    local ymax = r(max)
    sum lb, d
    local ymin = r(min)
    local gap  = max(0.1, round((`ymax'-`ymin')/10, 0.1))

    cap graph drop _all
    tw (rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall)) ///
       (scatter b year if year != 2013, mcolor(ebblue)), ///
       xlab(2010(1)2019) xtitle("Year") ytitle("`yvar'") ///
       yline(0, lcolor(gs10) lpattern(solid)) ///
       xline(2014, lcolor(gs10) lpattern(dash)) ///
       title("`yvar' -- `samp'`suf' (pre-mean=`pre_mean')", size(small)) ///
       legend(off) plotregion(margin(sides))
    graph export ../output/figures/`samp'/es_`yvar'`suf'.pdf, replace
end

/* ---------------------------------------------------------------------------
 combine_pred_real_plot
 Side-by-side: predicted-high vs predicted-low coefficients, realized-high vs
 realized-low coefficients. The headline figure for the foresight claim.
--------------------------------------------------------------------------- */
program combine_pred_real_plot
    syntax, samp(string) [r1r2(int 0) public(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"

    foreach pair in pred real {
        if "`pair'" == "pred" {
            local hi n_pred_high
            local lo n_pred_low
            local title "Predicted tiers"
        }
        else {
            local hi n_real_high
            local lo n_real_low
            local title "Realized tiers"
        }
        cap confirm file ../temp/es_`hi'_`samp'`suf'.dta
        if _rc continue
        cap confirm file ../temp/es_`lo'_`samp'`suf'.dta
        if _rc continue

        use ../temp/es_`hi'_`samp'`suf', clear
        rename (b se ub lb) (b_hi se_hi ub_hi lb_hi)
        merge 1:1 rel using ../temp/es_`lo'_`samp'`suf', nogen
        rename (b se ub lb) (b_lo se_lo ub_lo lb_lo)

        gen yr_hi = year + 0.1
        gen yr_lo = year - 0.1

        cap graph drop _all
        tw (rcap ub_hi lb_hi yr_hi if year != 2013, lcolor(dkemerald%70) msize(vsmall)) ///
           (scatter b_hi yr_hi if year != 2013, mcolor(dkemerald)) ///
           (rcap ub_lo lb_lo yr_lo if year != 2013, lcolor(cranberry%70) msize(vsmall)) ///
           (scatter b_lo yr_lo if year != 2013, mcolor(cranberry)), ///
           xlab(2010(1)2019) xtitle("Year") ytitle("Coefficient") ///
           yline(0, lcolor(gs10) lpattern(solid)) ///
           xline(2014, lcolor(gs10) lpattern(dash)) ///
           title("`title' -- `samp'`suf'", size(small)) ///
           legend(on order(2 "high tier" 4 "low tier") pos(7) ring(0) size(small)) ///
           plotregion(margin(sides))
        graph export ../output/figures/`samp'/es_`pair'_`samp'`suf'.pdf, replace
    }

    /* Combined pred+real overlay for n_pred_low vs n_real_low: the
       discriminator plot. */
    cap confirm file ../temp/es_n_pred_low_`samp'`suf'.dta
    if _rc exit 0
    cap confirm file ../temp/es_n_real_low_`samp'`suf'.dta
    if _rc exit 0
    use ../temp/es_n_pred_low_`samp'`suf', clear
    rename (b se ub lb) (b_pred se_pred ub_pred lb_pred)
    merge 1:1 rel using ../temp/es_n_real_low_`samp'`suf', nogen
    rename (b se ub lb) (b_real se_real ub_real lb_real)
    gen yr_p = year + 0.1
    gen yr_r = year - 0.1
    cap graph drop _all
    tw (rcap ub_pred lb_pred yr_p if year != 2013, lcolor(navy%70) msize(vsmall)) ///
       (scatter b_pred yr_p if year != 2013, mcolor(navy)) ///
       (rcap ub_real lb_real yr_r if year != 2013, lcolor(maroon%70) msize(vsmall)) ///
       (scatter b_real yr_r if year != 2013, mcolor(maroon)), ///
       xlab(2010(1)2019) xtitle("Year") ytitle("Coefficient (n_low)") ///
       yline(0, lcolor(gs10) lpattern(solid)) ///
       xline(2014, lcolor(gs10) lpattern(dash)) ///
       title("predicted-low vs realized-low -- `samp'`suf'", size(small)) ///
       legend(on order(2 "predicted low" 4 "realized low") pos(7) ring(0) size(small)) ///
       plotregion(margin(sides))
    graph export ../output/figures/`samp'/es_pred_vs_real`suf'.pdf, replace
end

/* ---------------------------------------------------------------------------
 pooled_did
 Headline pooled DiD on each outcome. Stores pdid_<yvar> matrix in memory for
 output_tables to dump.
--------------------------------------------------------------------------- */
program pooled_did
    syntax, samp(string) [r1r2(int 0) public(int 0)]
    local fes athr_id year
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"

    use ../temp/es_`samp'`suf', clear
    gen post       = year >= 2014
    gen Z_it       = exposure       * post
    gen Z_share_it = mkt_spend_shr  * post

    foreach yvar of global ALL_OUTCOMES {
        cap confirm variable `yvar'
        if _rc continue
        qui sum `yvar' if year < 2014, d
        local pre_mean = r(mean)

        qui reghdfe `yvar' Z_it, absorb(`fes') vce(cluster athr_id)
        local b_b   = _b[Z_it]
        local b_se  = _se[Z_it]
        local b_N   = e(N)
        local b_r2  = e(r2)

        qui reghdfe `yvar' Z_it Z_share_it, absorb(`fes') vce(cluster athr_id)
        local s_bx  = _b[Z_it]
        local s_sex = _se[Z_it]
        local s_bs  = _b[Z_share_it]
        local s_ses = _se[Z_share_it]
        local s_N   = e(N)
        local s_r2  = e(r2)

        di as text "pooled_did `samp'`suf' `yvar': base b=" %7.4f `b_b' ///
            " se=" %7.4f `b_se' "  with_share b=" %7.4f `s_bx' " se=" %7.4f `s_sex'

        cap mat drop pdid_`yvar'
        mat pdid_`yvar' = J(7, 2, .)
        mat pdid_`yvar'[1,1] = `b_b'
        mat pdid_`yvar'[2,1] = `b_se'
        mat pdid_`yvar'[5,1] = `pre_mean'
        mat pdid_`yvar'[6,1] = `b_N'
        mat pdid_`yvar'[7,1] = `b_r2'
        mat pdid_`yvar'[1,2] = `s_bx'
        mat pdid_`yvar'[2,2] = `s_sex'
        mat pdid_`yvar'[3,2] = `s_bs'
        mat pdid_`yvar'[4,2] = `s_ses'
        mat pdid_`yvar'[5,2] = `pre_mean'
        mat pdid_`yvar'[6,2] = `s_N'
        mat pdid_`yvar'[7,2] = `s_r2'
        mat rownames pdid_`yvar' = b_exposure se_exposure b_share se_share pre_mean N r2
        mat colnames pdid_`yvar' = base with_share
    }
end

/* ---------------------------------------------------------------------------
 output_tables
 Dump each pdid_<yvar> matrix to txt.
--------------------------------------------------------------------------- */
program output_tables
    syntax, samp(string) [r1r2(int 0) public(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"
    foreach yvar of global ALL_OUTCOMES {
        cap confirm matrix pdid_`yvar'
        if !_rc {
            qui matrix_to_txt, saving("../output/tables/`samp'/pdid_`yvar'`suf'.txt") ///
                matrix(pdid_`yvar') title(<tab:pdid_`yvar'`suf'>) format(%20.4f) replace
        }
    }
end

/* ---------------------------------------------------------------------------
 het_event_study
 Phase 3.1: re-run the event study restricted to the half indicated by
 `half'_`split' flag (e.g., high_portfolio_hhi). Suf gains a "_`split'_`half'"
 tag so output filenames are distinct.
--------------------------------------------------------------------------- */
program het_event_study
    syntax, samp(string) split(string) half(string) [r1r2(int 0) public(int 0)]
    local fes athr_id year
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"
    local hsuf "`suf'_`half'_`split'"

    use ../temp/es_`samp'`suf', clear
    cap confirm variable `half'_`split'
    if _rc {
        di as error "het_event_study: missing flag `half'_`split' on `samp'`suf'"
        exit 0
    }
    keep if `half'_`split' == 1

    save ../temp/es_`samp'`hsuf', replace
    event_study_inline, samp(`samp') suf(`hsuf')
end

/* Stripped-down event study that takes a fully-formed suffix (used by
   het_event_study so it doesn't need to re-derive suf from r1r2/public). */
program event_study_inline
    syntax, samp(string) [suf(string)]
    local fes athr_id year

    use ../temp/es_`samp'`suf', clear
    gen rel = year - 2014
    qui sum rel
    local abs_lag  = abs(r(max))
    local abs_lead = abs(r(min))

    forval i = 1/`abs_lead' {
        gen int_lead`i' = exposure      if rel == -`i'
        gen mshr_lead`i' = mkt_spend_shr if rel == -`i'
    }
    forval i = 0/`abs_lag' {
        gen int_lag`i'  = exposure      if rel == `i'
        gen mshr_lag`i' = mkt_spend_shr if rel == `i'
    }
    ds int_lead* int_lag* mshr_lead* mshr_lag*
    foreach v in `r(varlist)' {
        replace `v' = 0 if mi(`v')
    }
    local int_leads
    local int_lags
    local mshr_leads
    local mshr_lags
    forval i = 2/`abs_lead' {
        local int_leads  int_lead`i'  `int_leads'
        local mshr_leads mshr_lead`i' `mshr_leads'
    }
    forval i = 0/`abs_lag' {
        local int_lags  `int_lags'  int_lag`i'
        local mshr_lags `mshr_lags' mshr_lag`i'
    }

    foreach yvar in n_pred_high n_pred_low n_real_high n_real_low {
        cap confirm variable `yvar'
        if _rc continue
        preserve
        mat drop _all
        qui sum `yvar' if rel <= -1 & exposure > 0, d
        local pre_mean : di %6.3f r(mean)
        qui reghdfe `yvar' `int_leads' `int_lags' int_lead1 ///
                          `mshr_leads' `mshr_lags' mshr_lead1, ///
                          absorb(`fes') vce(cluster athr_id)
        foreach var in `int_leads' `int_lags' int_lead1 {
            mat row = _b[`var'], _se[`var']
            if "`var'" == "int_lead1" mat row = 0,0
            mat es = nullmat(es) \ row
        }
        svmat es
        keep es1 es2
        drop if mi(es1)
        rename (es1 es2) (b se)
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        gen rel = .
        replace rel = -`abs_lead' if _n == 1
        replace rel = rel[_n-1] + 1 if _n > 1
        replace rel = rel + 1 if rel >= -1
        replace rel = -1 if rel == `abs_lag' + 1
        gen year = rel + 2014
        sort rel
        save ../temp/es_`yvar'_`samp'`suf', replace
        plot_one, yvar(`yvar') samp(`samp') suf(`suf') pre_mean(`pre_mean')
        restore
    }
end

main
