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

* Match analysis/reduced_form/code/analysis.do preamble so plot styling
* (scheme modern + preliminaries defaults) is identical.
set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

cap mkdir ../output
cap mkdir ../output/figures
cap mkdir ../output/tables
cap mkdir ../temp

* ============================================================
*  Match the switches in analysis/reduced_form/code/analysis.do
*  so the sample construction here is identical to the reduced
*  form. See that file's header comment for switch semantics.
*  Update in lockstep with reduced_form if you change one.
* ============================================================
global EXPOSURE_VERSION "hc"
global EXPOSURE_FILTER  "_cf"

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
    /* Match analysis/reduced_form/code/analysis.do: only the R1+R2+public panel
     is run. The base all_jrnls panel does not carry the `type' column
     (R1/R2/other), which restrict_samp needs to build r1/r2 flags. The r1_r2
     panel would work here too but reduced_form treats r1_r2_public as canonical
     so we stay in lockstep. */
    gather_external_data
    foreach samp in all_jrnls {
        cap mkdir ../output/figures/`samp'
        cap mkdir ../output/tables/`samp'
        restrict_samp, samp(`samp') r1r2(1) public(1)
        event_study,  samp(`samp') r1r2(1) public(1)
        pooled_did,   samp(`samp') r1r2(1) public(1)
        ppml_specs,   samp(`samp') r1r2(1) public(1)
        output_tables, samp(`samp') r1r2(1) public(1)
        combine_pred_real_plot, samp(`samp') r1r2(1) public(1)

        /* Phase 3.1: PI heterogeneity */
        foreach s of global SPLITS {
            foreach half in high low {
                het_event_study, samp(`samp') r1r2(1) public(1) ///
                                 split(`s') half(`half')
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
    * Mirrors analysis/reduced_form/code/analysis.do: same shift_share source,
    * same variable renames. Switches keyed off $EXPOSURE_VERSION/$EXPOSURE_FILTER.
    import delimited ../external/exposure/final_imputed_shift_share_${EXPOSURE_VERSION}${EXPOSURE_FILTER}, clear
    rename exposure_ss imputed
    rename sum_imputed_shares imputed_mkt_spend_shr
    save ../temp/exposure, replace

    use ../external/grants/pi_grants_clean, clear
    bys athr_id year: gen num_grants = _N
    contract athr_id year num_grants
    drop _freq
    save ../temp/athr_yr_grnt_cnt, replace

    * author -> us_cluster_fields 30-cluster assignment (kept for parity with
    * reduced_form; predicted_impact currently uses author FEs but the file is
    * cheap to build and future specs may want it).
    cap confirm file ../temp/athr_cluster30.dta
    if _rc {
        import delimited ../external/cluster/author_static_clusters_30.csv, clear varnames(1)
        cap tostring athr_id, replace
        rename cluster_label cluster_30
        save ../temp/athr_cluster30, replace
    }
end

/* ---------------------------------------------------------------------------
 restrict_samp
 Build the analysis panel for this samp/suf. Reuses the columns the
 reduced-form sample already has (exposure, mkt_spend_shr, etc.) and adds the
 Phase 3.1 het flags.
--------------------------------------------------------------------------- */
program restrict_samp
    /* Sample construction mirrors analysis/reduced_form/code/analysis.do's
     restrict_samp so the two analyses run on the identical panel. Any
     departures below are called out inline with "PREDICT_IMPACT:" comments
     and only add predict_impact-specific columns; the sample-filtering
     logic stays identical.
    */
    syntax, samp(string) [, r1r2(int 0) public(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"

    use ../external/samp/athr_panel_full_year_last_`samp'`suf', clear
    bys athr_id: egen max_year = max(year)
    bys athr_id: egen min_year = min(year)
    keep if min_year <= 2011
    keep if inrange(year, 2010, 2019)

    merge m:1 athr_id using ../temp/exposure, assert(1 2 3) keep(3) nogen
    merge m:1 athr_id using ../external/real_exposure/athr_exposure_${EXPOSURE_VERSION}, assert(1 2 3) keep(1 3) nogen
    merge m:1 athr_id using ../temp/athr_cluster30, keep(1 3) nogen

    gen foia_athr = 1 if !mi(exposure)
    bys athr_id : gen athr_indicator = _n == 1

    * Percentiles from imputed distribution -- same reference used in reduced_form
    * so exposure quartiles are on identical cuts.
    sum imputed if athr_indicator == 1, d
    local imputed_p25: di %4.3f r(p25)
    local imputed_p50: di %4.3f r(p50)
    local imputed_p75: di %4.3f r(p75)

    * Prefer observed exposure/mkt_spend_shr; fall back to imputed. Matches
    * reduced_form.
    replace imputed = exposure if !mi(exposure)
    replace imputed_mkt_spend_shr = mkt_spend_shr if !mi(mkt_spend_shr)
    drop exposure
    rename imputed exposure
    drop mkt_spend_shr
    rename imputed_mkt_spend_shr mkt_spend_shr
    drop if mi(exposure)
    drop if mi(mkt_spend_shr)
    drop if exposure == 0 | mkt_spend_shr == 0

    gen q1     = exposure <  `imputed_p25'
    gen q2     = inrange(exposure, `imputed_p25', `imputed_p50')
    gen q3     = inrange(exposure, `imputed_p50', `imputed_p75')
    gen q4     = exposure >= `imputed_p75'
    gen median = exposure >= `imputed_p50'

    bys athr_id: gen num_yrs = _N if year < 2014
    bys athr_id inst_id: gen plc_cntr = _n == 1
    bys athr_id : egen num_place = total(plc_cntr)
    drop if num_yrs <= 2
    keep if num_place == 1

    * PREDICT_IMPACT: capture the static self-mgmt columns before the tsfill
    * blows them away. Same trick reduced_form uses for exposure/q1..q4/type.
    local static_extras
    foreach v in portfolio_hhi lab_size_pre {
        cap confirm variable `v'
        if !_rc local static_extras `static_extras' `v'
    }

    gegen athr = group(athr_id)
    preserve
    contract athr num_place athr_id exposure q1 q2 q3 q4 median inst_id inst ///
             msa_comb msa_c_world min_year type mkt_spend_shr cluster_30      ///
             `static_extras'
    drop _freq
    save ../temp/athr_xw, replace
    restore
    xtset athr year
    tsfill, full
    drop athr_id exposure q1 q2 q3 q4 median inst_id inst msa_comb msa_c_world ///
         min_year type mkt_spend_shr cluster_30 `static_extras'
    merge m:1 athr using ../temp/athr_xw, assert(3) keep(3) nogen

    foreach var in ppr_cnt cite_affl_wt affl_wt {
        replace `var' = 0 if mi(`var')
    }

    * PREDICT_IMPACT: same zero-fill for tier / self-management outcomes. These
    * are missing (a) on tsfill rows because they only exist on real panel
    * years, and (b) on years/PIs the scoring step didn't reach.
    foreach v of global ALL_OUTCOMES {
        cap confirm variable `v'
        if !_rc replace `v' = 0 if mi(`v')
    }

    bys athr_id: egen tot_pprs = total(ppr_cnt)
    gen pre_ppr_cnt = ppr_cnt if year < 2014
    bys athr_id: egen pre_ppr_cnt_sum = sum(pre_ppr_cnt)
    bys athr_id: egen pre_ppr_cnt_avg = mean(pre_ppr_cnt)
    sum pre_ppr_cnt_avg, d
    drop if pre_ppr_cnt_avg < 0.1
    sum pre_ppr_cnt_sum, d
    drop if pre_ppr_cnt_sum < 5
    gen high_pre_ppr = pre_ppr_cnt_sum >= r(p50)
    gen low_pre_ppr  = pre_ppr_cnt_sum <  r(p50)
    gen age      = 2026 - min_year + 30
    gen age_2014 = 2014 - min_year + 30
    sum age_2014, d
    local med = r(p50)
    gen young = age_2014 <  `med'
    gen old   = age_2014 >= `med'
    gen r1 = type == "r1"
    gen r2 = type == "r2"

    merge 1:1 athr_id year using ../external/coathrs/avg_coathrs, keep(1 3) assert(1 2 3) nogen
    replace avg_num_coathrs = 0 if mi(avg_num_coathrs)
    merge 1:1 athr_id year using ../temp/athr_yr_grnt_cnt, keep(1 3) assert(1 2 3) nogen
    replace num_grants = 0 if mi(num_grants)

    gen pre_grants_cnt = num_grants if year < 2014
    bys athr_id: egen pre_grants_sum = total(pre_grants_cnt)
    drop pre_grants_cnt
    qui sum pre_grants_sum if athr_indicator == 1, d
    local g_cut = r(p50)
    if `g_cut' <= 0 local g_cut = 0.5
    gen high_grants = pre_grants_sum >= `g_cut'
    gen low_grants  = pre_grants_sum <  `g_cut'

    * Winsorize cite_affl_wt / affl_wt at pooled p99 to cap mega-cite outliers.
    * Matches reduced_form.
    foreach v in cite_affl_wt affl_wt {
        qui sum `v', d
        local p99_`v' = r(p99)
        replace `v' = `p99_`v'' if `v' > `p99_`v'' & !mi(`v')
    }

    assert !mi(athr_id)
    assert !mi(exposure)
    assert !mi(mkt_spend_shr)

    * PREDICT_IMPACT-specific splits (portfolio_hhi, lab_size_pre,
    * grants_per_pub_pre) — same median-split idiom, on the reduced-form
    * sample above.
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
        * Compute pre-mean and PI count BEFORE preserve so the locals persist
        * across the reshape-into-coefficient-table below (mirrors reduced_form).
        sum `yvar' if rel <= -1 & exposure > 0, d
        local pre_mean : di %6.3f r(mean)
        gunique athr_id
        local n_athrs = r(unique)
        preserve
        mat drop _all
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
        plot_one, yvar(`yvar') samp(`samp') suf(`suf') pre_mean(`pre_mean') n_athrs(`n_athrs')
        restore

        * PPML event study: tier / self-mgmt outcomes are non-negative counts,
        * so ppmlhdfe is a natural fit alongside the linear reghdfe above.
        * Coefficients are semielasticities (percent change in E[y] per unit
        * exposure). Mirrors the reghdfe spec above (same regressor list, same
        * FEs, same clustering) so the two are directly comparable.
        preserve
        mat drop _all
        cap noi ppmlhdfe `yvar' `int_leads' `int_lags' int_lead1 ///
                          `mshr_leads' `mshr_lags' mshr_lead1, ///
                          absorb(`fes') vce(cluster athr_id)
        if _rc {
            di as error "event_study ppmlhdfe `yvar'`suf' failed (rc=`_rc'); skipping."
            restore
            continue
        }
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
        save ../temp/es_`yvar'_`samp'`suf'_ppml, replace
        plot_one, yvar(`yvar') samp(`samp') suf(`suf'_ppml) pre_mean(`pre_mean') n_athrs(`n_athrs')
        restore
    }
end

program plot_one
    /* Event-study point plot in the same visual grammar as
     analysis/reduced_form/code/analysis.do:
       - rcap + scatter in ebblue
       - grey translucent shaded band at 2013.75-2014.25 marking the
         treatment discontinuity (via scatteri recast(area))
       - yline at 0
       - legend with num-PIs / pre-period-avg annotations at pos(7) ring(1)
     n_athrs is optional; the caller can compute gunique athr_id before
     preserve and pass it in. Falls back to "" if omitted.
    */
    syntax, yvar(string) samp(string) pre_mean(string) [suf(string) n_athrs(string)]
    local ytit "`yvar'"
    if strpos("`suf'", "_ppml") local ytit "Output-Cost Elasticity"
    sum ub, d
    local ymax = r(max)
    sum lb, d
    local ymin = r(min)
    local range = `ymax' - `ymin'
    local gap = max(0.1, round(`range'/10, 0.1))
    * Round ymax up and ymin down to nearest `gap' so ylab hits are clean.
    local ymax = ceil(`ymax' / `gap') * `gap'
    local ymin = floor(`ymin' / `gap') * `gap'

    local legend_extra ""
    if "`n_athrs'" != "" local legend_extra `"order(- "Num. PIs: `n_athrs'" "Pre-Period Avg : `pre_mean'")"'
    else                 local legend_extra `"order(- "Pre-Period Avg : `pre_mean'")"'

    cap graph drop _all
    tw rcap ub lb year if year != 2013 , lcolor(ebblue%70) msize(vsmall) || ///
      scatter b year, mcolor(ebblue) || ///
      scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
      xlab(2010(1)2019) xtitle("Year") ///
      ytitle("`ytit'") ylab(`ymin'(`gap')`ymax') ///
      yline(0, lcolor(gs10) lpattern(solid)) ///
      legend(on `legend_extra' pos(7) ring(1) rows(2) bmargin(zero) size(small)) plotregion(margin(sides))
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

        sum ub_hi, d
        local hi_max = r(max)
        sum ub_lo, d
        local lo_max = r(max)
        local ymax = max(`hi_max', `lo_max')
        sum lb_hi, d
        local hi_min = r(min)
        sum lb_lo, d
        local lo_min = r(min)
        local ymin = min(`hi_min', `lo_min')
        local gap = max(0.1, round((`ymax'-`ymin')/10, 0.1))
        local ymax = ceil(`ymax' / `gap') * `gap'
        local ymin = floor(`ymin' / `gap') * `gap'

        cap graph drop _all
        tw rcap ub_hi lb_hi yr_hi if year != 2013 , lcolor(dkemerald%70) msize(vsmall) || ///
          scatter b_hi yr_hi if year != 2013, mcolor(dkemerald) || ///
          rcap ub_lo lb_lo yr_lo if year != 2013, lcolor(cranberry%70) msize(vsmall) || ///
          scatter b_lo yr_lo if year != 2013, mcolor(cranberry) || ///
          scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
          xlab(2010(1)2019) xtitle("Year") ///
          ytitle("Coefficient") ylab(`ymin'(`gap')`ymax') ///
          yline(0, lcolor(gs10) lpattern(solid)) ///
          legend(on order(2 "high tier" 4 "low tier") pos(7) ring(1) size(small) bmargin(zero)) plotregion(margin(sides))
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

    sum ub_pred, d
    local p_max = r(max)
    sum ub_real, d
    local r_max = r(max)
    local ymax = max(`p_max', `r_max')
    sum lb_pred, d
    local p_min = r(min)
    sum lb_real, d
    local r_min = r(min)
    local ymin = min(`p_min', `r_min')
    local gap = max(0.1, round((`ymax'-`ymin')/10, 0.1))
    local ymax = ceil(`ymax' / `gap') * `gap'
    local ymin = floor(`ymin' / `gap') * `gap'

    cap graph drop _all
    tw rcap ub_pred lb_pred yr_p if year != 2013 , lcolor(navy%70) msize(vsmall) || ///
      scatter b_pred yr_p if year != 2013, mcolor(navy) || ///
      rcap ub_real lb_real yr_r if year != 2013, lcolor(maroon%70) msize(vsmall) || ///
      scatter b_real yr_r if year != 2013, mcolor(maroon) || ///
      scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
      xlab(2010(1)2019) xtitle("Year") ///
      ytitle("Coefficient (n_low)") ylab(`ymin'(`gap')`ymax') ///
      yline(0, lcolor(gs10) lpattern(solid)) ///
      legend(on order(2 "predicted low" 4 "realized low") pos(7) ring(1) size(small) bmargin(zero)) plotregion(margin(sides))
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
 ppml_specs
 Poisson (ppmlhdfe) analog of pooled_did. Same base + with_share pattern,
 same FE/cluster, so coefficients are directly comparable to their reghdfe
 counterparts. Mirrors analysis/reduced_form/code/analysis.do:ppml_specs.
 Matrix ppml_pdid_<yvar> has rows [b_x, se_x, b_share, se_share, pre_mean,
 N, r2_p] and cols [base, with_share].
--------------------------------------------------------------------------- */
program ppml_specs
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

        local b_b = .
        local b_se = .
        local b_N = .
        local b_r2 = .
        local s_bx = .
        local s_sex = .
        local s_bs = .
        local s_ses = .
        local s_N = .
        local s_r2 = .
        cap noi ppmlhdfe `yvar' Z_it, absorb(`fes') vce(cluster athr_id)
        if _rc == 0 {
            local b_b  = _b[Z_it]
            local b_se = _se[Z_it]
            local b_N  = e(N)
            local b_r2 = e(r2_p)
        }
        else di as error "ppml_specs `yvar'`suf' base failed (rc=`_rc')"
        cap noi ppmlhdfe `yvar' Z_it Z_share_it, absorb(`fes') vce(cluster athr_id)
        if _rc == 0 {
            local s_bx  = _b[Z_it]
            local s_sex = _se[Z_it]
            local s_bs  = _b[Z_share_it]
            local s_ses = _se[Z_share_it]
            local s_N   = e(N)
            local s_r2  = e(r2_p)
        }
        else di as error "ppml_specs `yvar'`suf' +share failed (rc=`_rc')"

        di as text "ppml_specs `samp'`suf' `yvar': base b=" %7.4f `b_b' ///
            " se=" %7.4f `b_se' "  with_share b=" %7.4f `s_bx' " se=" %7.4f `s_sex'

        cap mat drop ppml_pdid_`yvar'
        mat ppml_pdid_`yvar' = J(7, 2, .)
        mat ppml_pdid_`yvar'[1,1] = `b_b'
        mat ppml_pdid_`yvar'[2,1] = `b_se'
        mat ppml_pdid_`yvar'[5,1] = `pre_mean'
        mat ppml_pdid_`yvar'[6,1] = `b_N'
        mat ppml_pdid_`yvar'[7,1] = `b_r2'
        mat ppml_pdid_`yvar'[1,2] = `s_bx'
        mat ppml_pdid_`yvar'[2,2] = `s_sex'
        mat ppml_pdid_`yvar'[3,2] = `s_bs'
        mat ppml_pdid_`yvar'[4,2] = `s_ses'
        mat ppml_pdid_`yvar'[5,2] = `pre_mean'
        mat ppml_pdid_`yvar'[6,2] = `s_N'
        mat ppml_pdid_`yvar'[7,2] = `s_r2'
        mat rownames ppml_pdid_`yvar' = b_exposure se_exposure b_share se_share pre_mean N r2_p
        mat colnames ppml_pdid_`yvar' = base with_share
    }
end

/* ---------------------------------------------------------------------------
 output_tables
 Dump each pdid_<yvar> and ppml_pdid_<yvar> matrix to txt.
--------------------------------------------------------------------------- */
program output_tables
    syntax, samp(string) [r1r2(int 0) public(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local suf "_r1_r2_public"
    foreach prog in pdid ppml_pdid {
        foreach yvar of global ALL_OUTCOMES {
            cap confirm matrix `prog'_`yvar'
            if !_rc {
                qui matrix_to_txt, saving("../output/tables/`samp'/`prog'_`yvar'`suf'.txt") ///
                    matrix(`prog'_`yvar') title(<tab:`prog'_`yvar'`suf'>) format(%20.4f) replace
            }
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
        qui sum `yvar' if rel <= -1 & exposure > 0, d
        local pre_mean : di %6.3f r(mean)
        gunique athr_id
        local n_athrs = r(unique)
        preserve
        mat drop _all
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
        plot_one, yvar(`yvar') samp(`samp') suf(`suf') pre_mean(`pre_mean') n_athrs(`n_athrs')
        restore
    }
end

main
