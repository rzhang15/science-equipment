set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries, loadglob(../external/lib/globals.txt)

adopath ++ "../external/lib/stata"
version 17

* QUICK_TOPJRNL    : 1 = top_jrnls sample, ppr_cnt only, single pass
* HISIM_PCT        : 0 = off; N = use the es_all_jrnls_hisimN samples
* RUN_PUBLIC       : 1 = also run the _public sample
* RUN_ROBUSTNESS   : 1 = run the robustness program (slow)
* RUN_R1_ONLY      : 1 = also run the R1-only passes
global WEIGHT_MSIM 0
global QUICK_TOPJRNL 0
global HISIM_PCT 0
global RUN_PUBLIC 1
global RUN_ROBUSTNESS 0
global RUN_R1_ONLY 1

program detect_position_outcomes
    cap use n_first_ppr in 1 using ../external/prepped_samples/es_all_jrnls_r1_r2, clear
    global POSITION_OUTCOMES_AVAIL = cond(_rc == 0, 1, 0)
end

program main
    detect_position_outcomes
    if "$QUICK_TOPJRNL" == "1" {
        cap mkdir "../output/figures/top_jrnls"
        global WEIGHT_MSIM 0
        di as text _newline "=========================================="
        di as text "  RUNNING sample=top_jrnls ppr_cnt only (QUICK_TOPJRNL)"
        di as text "=========================================="
        mat drop _all
        event_study,       samp(top_jrnls) r1r2(1) public(0)
        pooled_did,        samp(top_jrnls) r1r2(1) public(0)
        ppml_specs,        samp(top_jrnls) r1r2(1) public(0)
        placebo_treatment, samp(top_jrnls) r1r2(1) public(0)
        trim_top,          samp(top_jrnls) r1r2(1) public(0)
        robustness,        samp(top_jrnls) r1r2(1) public(0)
        output_tables,     samp(top_jrnls) r1r2(1) public(0)
        exit
    }
    if "$HISIM_PCT" != "0" {
        local hs all_jrnls_hisim$HISIM_PCT
        cap mkdir "../output/figures/all_jrnls"
        cap mkdir "../output/figures/`hs'"
        foreach wmode in 0 1 {
            global WEIGHT_MSIM `wmode'
            di as text _newline "=========================================="
            di as text "  RUNNING sample=`hs' WEIGHT_MSIM=`wmode' PUBLIC=0"
            di as text "=========================================="
            mat drop _all
            event_study,   samp(`hs') r1r2(1) public(0)
            pooled_did,    samp(`hs') r1r2(1) public(0)
            ppml_specs,    samp(`hs') r1r2(1) public(0)
            output_tables, samp(`hs') r1r2(1) public(0)
        }
        global WEIGHT_MSIM 0
        exit
    }
    local pubs 0
    if "$RUN_PUBLIC" == "1" local pubs 0 1
    foreach pub of local pubs {
        foreach s in all_jrnls {
            cap mkdir "../output/figures/`s'"
            foreach wmode in 0 1 {
                global WEIGHT_MSIM `wmode'
                di as text _newline "=========================================="
                di as text "  RUNNING sample=`s' WEIGHT_MSIM=`wmode' PUBLIC=`pub'"
                di as text "=========================================="
                mat drop _all
                event_study, samp(`s') r1r2(1) public(`pub')
                pooled_did, samp(`s') r1r2(1) public(`pub')
                ppml_specs, samp(`s') r1r2(1) public(`pub')
                exit_analysis, samp(`s') r1r2(1) public(`pub')
                if `wmode' == 0 {
                    placebo_treatment, samp(`s') r1r2(1) public(`pub')
                    trim_top, samp(`s') r1r2(1) public(`pub')
                    if "$RUN_ROBUSTNESS" == "1" robustness, samp(`s') r1r2(1) public(`pub')
                }
                output_tables, samp(`s') r1r2(1) public(`pub')
            }
            global WEIGHT_MSIM 0
        }
       * joint_outcome_test, samp(all_jrnls) r1r2(1) public(`pub')

        if "$RUN_R1_ONLY" != "1" continue
        foreach wmode in 0 1 {
            global WEIGHT_MSIM `wmode'
            di as text _newline "=========================================="
            di as text "  RUNNING sample=all_jrnls WEIGHT_MSIM=`wmode' PUBLIC=`pub' (R1-only)"
            di as text "=========================================="
            mat drop _all
            event_study, samp(all_jrnls) r1r2(1) public(`pub') r1_only(1)
            pooled_did,  samp(all_jrnls) r1r2(1) public(`pub') r1_only(1)
            ppml_specs,  samp(all_jrnls) r1r2(1) public(`pub') r1_only(1)
            exit_analysis, samp(all_jrnls) r1r2(1) public(`pub') r1_only(1)
            if `wmode' == 0 {
                placebo_treatment, samp(all_jrnls) r1r2(1) public(`pub') r1_only(1)
                trim_top,          samp(all_jrnls) r1r2(1) public(`pub') r1_only(1)
                if "$RUN_ROBUSTNESS" == "1" robustness, samp(all_jrnls) r1r2(1) public(`pub') r1_only(1)
            }
            output_tables, samp(all_jrnls) r1r2(1) public(`pub') r1_only(1)
        }
        global WEIGHT_MSIM 0
    }
end



program event_study
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
    local fes athr_id year
    local vce_cl athr_id
    if "$FE_MODE" == "athr_clyr" {
        local fes athr_id i.cluster_30#i.year
    }
    if "$FE_MODE" == "inst_cluster" {
        local fes inst_id cluster_30 year
        local vce_cl inst_id
    }
    if "$FE_MODE" == "inst_cluster_fldyr" {
        local fes inst_id i.cluster_30#i.year
        local vce_cl inst_id
    }
    local wt ""
    local wsuf ""
    if "$WEIGHT_MSIM" == "1" {
        local wt "[pw=max_sim]"
        local wsuf "_msimwt"
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"
    use ../external/prepped_samples/es_`samp'`suf', clear

    gen rel = year - 2014
    qui sum rel, d
    local abs_lag  = abs(r(max))
    local abs_lead = abs(r(min))
    forval i = 1/`abs_lead' {
        gen int_lead`i'  = exposure      if rel == -`i'
        gen mshr_lead`i' = mkt_spend_shr if rel == -`i'
    }
    forval i = 0/`abs_lag' {
        gen int_lag`i'  = exposure      if rel == `i'
        gen mshr_lag`i' = mkt_spend_shr if rel == `i'
    }
    ds int_lead* int_lag* mshr_lead* mshr_lag*
    foreach var in `r(varlist)' {
        replace `var' = 0 if mi(`var')
    }
    local int_leads
    local mshr_leads
    local int_lags
    local mshr_lags
    forval i = 2/`abs_lead' {
        local int_leads int_lead`i' `int_leads'
        local mshr_leads mshr_lead`i' `mshr_leads'
    }
    forval i = 0/`abs_lag' {
        local int_lags `int_lags' int_lag`i'
        local mshr_lags `mshr_lags' mshr_lag`i'
    }
    foreach v in ppr_cnt cite_affl_wt ppr_cnt_any cite_affl_wt_any ///
                 ppr_cnt_notlast cite_affl_wt_notlast {
        gen ln_`v' = ln(1+`v')
    }

    local position_outcomes ""
    if "$POSITION_OUTCOMES_AVAIL" == "1" {
        local position_outcomes n_middle_ppr avg_position avg_team_size_last avg_team_size_notlast
    }

    local outcomes ppr_cnt cite_affl_wt ln_ppr_cnt ppr_cnt_any cite_affl_wt_any ///
                   ppr_cnt_notlast cite_affl_wt_notlast avg_num_coathrs n_grants nih_total_cost ///
                   `position_outcomes'
    if "$QUICK_TOPJRNL" == "1" local outcomes ppr_cnt ln_ppr_cnt

    foreach yvar of local outcomes {
        if "`yvar'" == "cite_affl_wt" local var_name = "Citation weighted output"
        if "`yvar'" == "cite_affl_wt" local gap  1
        if "`yvar'" == "ppr_cnt" local var_name = "Publication count"
        if "`yvar'" == "ppr_cnt" local gap 0.5
        if "`yvar'" == "ln_ppr_cnt"      local var_name = "Log publication counts"
        if "`yvar'" == "ln_ppr_cnt"      local gap 0.1
        if "`yvar'" == "ppr_cnt"      & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "cite_affl_wt" & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "ppr_cnt_any"         local var_name = "Publication count (any position)"
        if "`yvar'" == "ppr_cnt_any"         local gap 0.5
        if "`yvar'" == "cite_affl_wt_any"    local var_name = "Citation weighted output (any position)"
        if "`yvar'" == "cite_affl_wt_any"    local gap 1
        if "`yvar'" == "ppr_cnt_any"         & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "cite_affl_wt_any"    & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "ppr_cnt_notlast"         local var_name = "Publication count (non-last author)"
        if "`yvar'" == "ppr_cnt_notlast"         local gap 0.5
        if "`yvar'" == "cite_affl_wt_notlast"    local var_name = "Citation weighted output (non-last author)"
        if "`yvar'" == "cite_affl_wt_notlast"    local gap 1
        if "`yvar'" == "ppr_cnt_notlast"         & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "cite_affl_wt_notlast"    & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "avg_num_coathrs"   local var_name = "Average team size"
        if "`yvar'" == "avg_num_coathrs"   local gap 0.5
        if "`yvar'" == "n_grants"          local var_name = "# active NIH research grants"
        if "`yvar'" == "n_grants"          local gap 0.5
        if "`yvar'" == "nih_total_cost"    local var_name = "NIH award amount ($)"
        if "`yvar'" == "nih_total_cost"    local gap 50000
        if "`yvar'" == "n_first_ppr"           local var_name = "# first-author papers"
        if "`yvar'" == "n_first_ppr"           local gap 0.5
        if "`yvar'" == "n_middle_ppr"          local var_name = "# middle-author papers"
        if "`yvar'" == "n_middle_ppr"          local gap 0.5
        if "`yvar'" == "n_last_ppr"            local var_name = "# last-author papers"
        if "`yvar'" == "n_last_ppr"            local gap 0.5
        if "`yvar'" == "avg_position"          local var_name = "Avg author position (1=first, n=last)"
        if "`yvar'" == "avg_position"          local gap 0.5
        if "`yvar'" == "avg_position_rat"      local var_name = "Avg author position / team size (0-1)"
        if "`yvar'" == "avg_position_rat"      local gap 0.05
        if "`yvar'" == "avg_team_size_last"    local var_name = "Team size (papers where PI is last)"
        if "`yvar'" == "avg_team_size_last"    local gap 0.5
        if "`yvar'" == "avg_team_size_notlast" local var_name = "Team size (papers where PI is not last)"
        if "`yvar'" == "avg_team_size_notlast" local gap 0.5
        local poisson_name "`var_name'"
        if "`yvar'" == "ppr_cnt"              local poisson_name "publications"
        if "`yvar'" == "cite_affl_wt"         local poisson_name "citation-weighted output"
        if "`yvar'" == "ppr_cnt_any"          local poisson_name "publications (any position)"
        if "`yvar'" == "cite_affl_wt_any"     local poisson_name "citation-weighted output (any position)"
        if "`yvar'" == "ppr_cnt_notlast"      local poisson_name "publications (non-last author)"
        if "`yvar'" == "cite_affl_wt_notlast" local poisson_name "citation-weighted output (non-last author)"
        if "`yvar'" == "avg_num_coathrs"      local poisson_name "coauthors"
        if "`yvar'" == "n_grants"             local poisson_name "active NIH research grants"
        if "`yvar'" == "nih_total_cost"       local poisson_name "NIH award dollars"
        local ppml_ytit "Output-cost elasticity"
        if inlist("`yvar'", "n_grants", "n_new_grants", "nih_total_cost") ///
            local ppml_ytit "{&Delta} log expected `poisson_name'"

        local ppml_ok = !regexm("`yvar'", "^ln_") & (!regexm("`yvar'", "^avg_") | "`yvar'" == "avg_num_coathrs")
        local ols_ok  = inlist("`yvar'", "ppr_cnt", "ln_ppr_cnt") | !`ppml_ok'

        if `ols_ok' {
        preserve
        cap mat drop es
        cap noi reghdfe `yvar' `int_leads' `int_lags' `mshr_leads' `mshr_lags' `wt', ///
                       absorb(`fes') vce(cluster `vce_cl')
        local rc = _rc
        if `rc' {
            di as error "event_study `samp'`suf' `yvar' mshrctrl failed (rc=`rc'); skipping mshrctrl plot."
            restore
        }
        else {
        gunique athr_id if e(sample)
        local num_athrs = r(unique)
        gunique inst_id if e(sample)
        local num_insts = r(unique)
        sum `yvar' if rel <= -1 & e(sample), d
        local pre_mean : dis %4.3f r(mean)
        foreach var in `int_leads' `int_lags' int_lead1 {
            if "`var'" == "int_lead1" {
                mat row = 0,0
            }
            else {
                mat row = _b[`var'], _se[`var']
            }
            mat es = nullmat(es) \ row
        }
        svmat es
        keep es1 es2
        drop if mi(es1)
        rename (es1 es2) (b se)
        gen ub = b + 1.96*se
        sum ub, d
        local ymax = round(r(max),`gap')
        gen lb = b - 1.96*se
        sum lb, d
        local ymin = round(r(min),`gap')
        if `ymin' > 0 local ymin = 0
        if inlist("`yvar'", "ln_ppr_cnt", "ln_cite_affl_wt") local ymin = -1
        gen rel = -`abs_lead' if _n == 1
        replace rel = rel[_n-1]+1 if _n > 1
        replace rel = rel + 1 if rel >= -1
        replace rel = -1 if rel == `abs_lag' + 1
        gen year = rel + 2014
        hashsort rel
        local stats_leg `"legend(on order(- "Num. PIs: `num_athrs'" "Num. institutions: `num_insts'" "Pre-period avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small))"'
        local fdir ../output/figures/`samp'
        foreach fmode of global FIG_MODES {
            if "`fmode'" == "paper" {
                local stats_leg legend(off)
                cap mkdir "`fdir'"
            }
            tw rcap ub lb year if year != 2013 , lcolor(ebblue%70) msize(vsmall) || ///
              scatter b year, mcolor(ebblue) || ///
              scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
              xlab(2010(1)2019) xtitle("Year") ///
              ytitle("`var_name'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ylab(`ymin'(`gap')`ymax') ///
              yline(0, lcolor(gs10) lpattern(solid)) ///
              `stats_leg' plotregion(margin(sides))
            fig_export, path("`fdir'/es_`yvar'`suf'_mshrctrl`wsuf'.pdf") mode(`fmode')
        }
        save ../temp/es_`yvar'`suf'_mshrctrl`wsuf', replace
        restore
        }
        }

        if `ppml_ok' {
            preserve
            cap mat drop es
            cap noi ppmlhdfe `yvar' `int_leads' `int_lags' ///
                                   `mshr_leads' `mshr_lags' `wt', ///
                    absorb(`fes') vce(cluster `vce_cl')
            local rc = _rc
            if `rc' {
                di as error "ppmlhdfe `yvar' mshrctrl failed (rc=`rc'); skipping plot."
                restore
            }
            else {
            gunique athr_id if e(sample)
            local num_athrs = r(unique)
            gunique inst_id if e(sample)
            local num_insts = r(unique)
            sum `yvar' if rel <= -1 & e(sample), d
            local pre_mean : dis %4.3f r(mean)
            foreach var in `int_leads' `int_lags' int_lead1 {
                if "`var'" == "int_lead1" {
                    mat row = 0,0
                }
                else {
                    mat row = _b[`var'], _se[`var']
                }
                mat es = nullmat(es) \ row
            }
            svmat es
            keep es1 es2
            drop if mi(es1)
            rename (es1 es2) (b se)
            local pgap 0.1
            if inlist("`yvar'", "n_grants", "nih_total_cost") {
                local pgap 0.4
            }
            gen ub = b + 1.96*se
            gen lb = b - 1.96*se
            local ymax = 1.2
            local ymin = -2.2
            local pgap 0.2
            gen rel = -`abs_lead' if _n == 1
            replace rel = rel[_n-1]+1 if _n > 1
            replace rel = rel + 1 if rel >= -1
            replace rel = -1 if rel == `abs_lag' + 1
            gen year = rel + 2014
            hashsort rel
            local stats_leg `"legend(on order(- "Num. PIs: `num_athrs'" "Num. institutions: `num_insts'" "Pre-period avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small))"'
            local fdir ../output/figures/`samp'
            foreach fmode of global FIG_MODES {
                if "`fmode'" == "paper" {
                    local stats_leg legend(off)
                    cap mkdir "`fdir'"
                }
                local ylab_m ylab(`ymin'(`pgap')`ymax') ytick(`ymin'(0.2)`ymax')
                local ysc_r
                if "`fmode'" == "paper" {
                    local ylab_m ylab(-2(0.5)1, format(%3.1f))
                    local ysc_r r(`ymin' `ymax')
                }
                tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
                  scatter b year, mcolor(ebblue) || ///
                  scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                  xlab(2010(1)2019) xtitle("Year") ///
                  ytitle("`ppml_ytit'") ysc(titlegap($FIG_YTITLEGAP) outergap(0) `ysc_r') `ylab_m' ///
                  yline(0, lcolor(gs10) lpattern(solid)) ///
                  `stats_leg' plotregion(margin(sides))
                fig_export, path("`fdir'/es_`yvar'`suf'_ppml_mshrctrl`wsuf'.pdf") mode(`fmode')
            }
            save ../temp/es_`yvar'`suf'_ppml_mshrctrl`wsuf', replace
            restore
            }
        }

        if "`yvar'" == "ppr_cnt" {
            preserve
            keep if foia_athr == 1
            cap mat drop es
            cap noi ppmlhdfe `yvar' `int_leads' `int_lags' ///
                                   `mshr_leads' `mshr_lags' `wt', ///
                    absorb(`fes') vce(cluster `vce_cl')
            local rc = _rc
            if `rc' {
                di as error "ppmlhdfe `yvar' foia-only mshrctrl failed (rc=`rc'); skipping plot."
                restore
            }
            else {
            gunique athr_id if e(sample)
            local num_athrs = r(unique)
            gunique inst_id if e(sample)
            local num_insts = r(unique)
            sum `yvar' if rel <= -1 & e(sample), d
            local pre_mean : dis %4.3f r(mean)
            foreach var in `int_leads' `int_lags' int_lead1 {
                if "`var'" == "int_lead1" {
                    mat row = 0,0
                }
                else {
                    cap mat row = _b[`var'], _se[`var']
                    if _rc mat row = ., .
                }
                mat es = nullmat(es) \ row
            }
            svmat es
            keep es1 es2
            drop if mi(es1)
            rename (es1 es2) (b se)
            gen ub = b + 1.96*se
            sum ub, d
            local ymax = r(max)
            gen lb = b - 1.96*se
            sum lb, d
            local ymin = min(r(min), 0)
            gen rel = -`abs_lead' if _n == 1
            replace rel = rel[_n-1]+1 if _n > 1
            replace rel = rel + 1 if rel >= -1
            replace rel = -1 if rel == `abs_lag' + 1
            gen year = rel + 2014
            hashsort rel
            local stats_leg `"legend(on order(- "Num. PIs: `num_athrs'" "Num. institutions: `num_insts'" "Pre-period avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small))"'
            local es_title title("FOIA PIs only (observed exposure)", size(small))
            local fdir ../output/figures/`samp'
            foreach fmode of global FIG_MODES {
                if "`fmode'" == "paper" {
                    local stats_leg legend(off)
                    local es_title
                    cap mkdir "`fdir'"
                }
                tw rcap ub lb year if year != 2013, lcolor(dkorange%70) msize(vsmall) || ///
                  scatter b year, mcolor(dkorange) || ///
                  scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                  xlab(2010(1)2019) xtitle("Year") ///
                  ytitle("`ppml_ytit'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ylab(#6) ///
                  yline(0, lcolor(gs10) lpattern(solid)) ///
                  `es_title' ///
                  `stats_leg' plotregion(margin(sides))
                fig_export, path("`fdir'/es_`yvar'`suf'_ppml_mshrctrl_foia`wsuf'.pdf") mode(`fmode')
            }
            save ../temp/es_`yvar'`suf'_ppml_mshrctrl_foia`wsuf', replace
            restore
            }
        }

        if inlist("`yvar'", "ppr_cnt", "cite_affl_wt") {
            preserve
            keep if nih_athr == 1
            cap mat drop es
            cap noi ppmlhdfe `yvar' `int_leads' `int_lags' ///
                                   `mshr_leads' `mshr_lags' `wt', ///
                    absorb(`fes') vce(cluster `vce_cl')
            local rc = _rc
            if `rc' {
                di as error "ppmlhdfe `yvar' nih-only mshrctrl failed (rc=`rc'); skipping plot."
                restore
            }
            else {
            gunique athr_id if e(sample)
            local num_athrs = r(unique)
            gunique inst_id if e(sample)
            local num_insts = r(unique)
            sum `yvar' if rel <= -1 & e(sample), d
            local pre_mean : dis %4.3f r(mean)
            foreach var in `int_leads' `int_lags' int_lead1 {
                if "`var'" == "int_lead1" {
                    mat row = 0,0
                }
                else {
                    cap mat row = _b[`var'], _se[`var']
                    if _rc mat row = ., .
                }
                mat es = nullmat(es) \ row
            }
            svmat es
            keep es1 es2
            drop if mi(es1)
            rename (es1 es2) (b se)
            gen ub = b + 1.96*se
            sum ub, d
            local ymax = r(max)
            gen lb = b - 1.96*se
            sum lb, d
            local ymin = min(r(min), 0)
            gen rel = -`abs_lead' if _n == 1
            replace rel = rel[_n-1]+1 if _n > 1
            replace rel = rel + 1 if rel >= -1
            replace rel = -1 if rel == `abs_lag' + 1
            gen year = rel + 2014
            hashsort rel
            local stats_leg `"legend(on order(- "Num. PIs: `num_athrs'" "Num. institutions: `num_insts'" "Pre-period avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small))"'
            local es_title title("NIH-matched PIs only", size(small))
            local fdir ../output/figures/`samp'
            foreach fmode of global FIG_MODES {
                if "`fmode'" == "paper" {
                    local stats_leg legend(off)
                    local es_title
                    cap mkdir "`fdir'"
                }
                tw rcap ub lb year if year != 2013, lcolor(lavender%70) msize(vsmall) || ///
                  scatter b year, mcolor(lavender) || ///
                  scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                  xlab(2010(1)2019) xtitle("Year") ///
                  ytitle("`ppml_ytit'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ylab(#6) ///
                  yline(0, lcolor(gs10) lpattern(solid)) ///
                  `es_title' ///
                  `stats_leg' plotregion(margin(sides))
                fig_export, path("`fdir'/es_`yvar'`suf'_ppml_mshrctrl_nih`wsuf'.pdf") mode(`fmode')
            }
            save ../temp/es_`yvar'`suf'_ppml_mshrctrl_nih`wsuf', replace
            restore
            }
        }
    }
end

program pooled_did
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
    local fes athr_id year
    local vce_cl athr_id
    if "$FE_MODE" == "athr_clyr" {
        local fes athr_id i.cluster_30#i.year
    }
    if "$FE_MODE" == "inst_cluster" {
        local fes inst_id cluster_30 year
        local vce_cl inst_id
    }
    if "$FE_MODE" == "inst_cluster_fldyr" {
        local fes inst_id i.cluster_30#i.year
        local vce_cl inst_id
    }
    local wt ""
    local wsuf ""
    if "$WEIGHT_MSIM" == "1" {
        // ppmlhdfe rejects aw, binscatter rejects pw
        local wt "[pw=max_sim]"
        local wt_bin "[aw=max_sim]"
        local wsuf "_msimwt"
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"
    use ../external/prepped_samples/es_`samp'`suf', clear

    foreach v in cite_affl_wt ppr_cnt cite_affl_wt_any ppr_cnt_any ///
                 cite_affl_wt_notlast ppr_cnt_notlast {
        cap gen ln_`v' = ln(1+`v')
    }

    gen post       = year >= 2014
    gen Z_it       = exposure              * post
    gen Z_share_it = mkt_spend_shr * post

    local position_outcomes ""
    if "$POSITION_OUTCOMES_AVAIL" == "1" {
        local position_outcomes n_middle_ppr avg_position avg_team_size_last avg_team_size_notlast
    }
    local outcomes cite_affl_wt ppr_cnt ln_ppr_cnt ///
                   cite_affl_wt_any ppr_cnt_any cite_affl_wt_notlast ppr_cnt_notlast  ///
                   avg_num_coathrs n_grants nih_total_cost ///
                   `position_outcomes'
    if "$QUICK_TOPJRNL" == "1" local outcomes ppr_cnt ln_ppr_cnt

    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'

    cap mat drop results
    local kept_outcomes
    local ppml_covered cite_affl_wt cite_affl_wt_any ppr_cnt_any ///
                       cite_affl_wt_notlast ppr_cnt_notlast ///
                       avg_num_coathrs n_grants nih_total_cost n_middle_ppr
    foreach yvar of local outcomes {
        if `: list yvar in ppml_covered' continue

        local b_b = .
        local b_se = .
        local b_N = .
        local b_r2 = .
        local b_pmn = .

        local s_bx = .
        local s_sex = .
        local s_bs = .
        local s_ses = .
        local s_N = .
        local s_r2 = .

        if "`yvar'" == "ppr_cnt" {
            cap noi qui reghdfe `yvar' Z_it `wt', absorb(`fes') vce(cluster `vce_cl')
            local rc = _rc
            if `rc' == 0 {
                local b_b  = _b[Z_it]
                local b_se = _se[Z_it]
                local b_N  = e(N)
                local b_r2 = e(r2)
                qui sum `yvar' if year < 2014 & e(sample)
                local b_pmn = r(mean)
            }
            else di as error "pooled_did `samp'`suf' `yvar' base failed (rc=`rc')."
        }

        cap noi qui reghdfe `yvar' Z_it Z_share_it `wt', absorb(`fes') vce(cluster `vce_cl')
        local rc = _rc
        if `rc' {
            di as error "pooled_did `samp'`suf' `yvar' +share failed (rc=`rc'); skipping outcome."
            continue
        }
        local s_bx  = _b[Z_it]
        local s_sex = _se[Z_it]
        local s_bs  = _b[Z_share_it]
        local s_ses = _se[Z_share_it]
        local s_N   = e(N)
        local s_r2  = e(r2)
        qui sum `yvar' if year < 2014 & e(sample)
        local pre_mean = r(mean)

        di as text "pooled_did `samp'`suf' `yvar':  base b=" %7.4f `b_b' " se=" %7.4f `b_se' ///
            "    +share b=" %7.4f `s_bx' " se=" %7.4f `s_sex' ///
            "    share_b=" %7.4f `s_bs' " se=" %7.4f `s_ses' ///
            "    pre-mean=" %7.4f `pre_mean'

        cap mat drop pdid_`yvar'
        mat pdid_`yvar' = J(7,2,.)
        mat pdid_`yvar'[1,1] = `b_b'
        mat pdid_`yvar'[2,1] = `b_se'
        mat pdid_`yvar'[5,1] = `b_pmn'
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

        mat row = `b_b', `b_se', `s_bx', `s_sex', `s_bs', `s_ses', `pre_mean'
        mat results = nullmat(results) \ row
        local kept_outcomes `kept_outcomes' `yvar'

        local var_name "`yvar'"
        if "`yvar'" == "cite_affl_wt"            local var_name "Citation weighted output"
        if "`yvar'" == "ppr_cnt"                 local var_name "Publication count"
        if "`yvar'" == "ln_cite_affl_wt"         local var_name "Log citation weighted output"
        if "`yvar'" == "ln_ppr_cnt"              local var_name "Log publication counts"
        if "`yvar'" == "cite_affl_wt_any"        local var_name "Citation weighted output (any position)"
        if "`yvar'" == "ppr_cnt_any"             local var_name "Publication count (any position)"
        if "`yvar'" == "ln_cite_affl_wt_any"     local var_name "Log citation weighted output (any position)"
        if "`yvar'" == "ln_ppr_cnt_any"          local var_name "Log publication counts (any position)"
        if "`yvar'" == "cite_affl_wt_notlast"    local var_name "Citation weighted output (non-last author)"
        if "`yvar'" == "ppr_cnt_notlast"         local var_name "Publication count (non-last author)"
        if "`yvar'" == "ln_cite_affl_wt_notlast" local var_name "Log citation weighted output (non-last author)"
        if "`yvar'" == "ln_ppr_cnt_notlast"      local var_name "Log publication counts (non-last author)"
        if "`yvar'" == "avg_num_coathrs"         local var_name "Avg coauthors"
        if "`yvar'" == "n_grants"                local var_name "# active NIH research grants"
        if "`yvar'" == "nih_total_cost"          local var_name "NIH award amount ($)"
        if "`yvar'" == "n_first_ppr"             local var_name "# first-author papers"
        if "`yvar'" == "n_middle_ppr"            local var_name "# middle-author papers"
        if "`yvar'" == "n_last_ppr"              local var_name "# last-author papers"
        if "`yvar'" == "avg_position"            local var_name "Avg author position"
        if "`yvar'" == "avg_position_rat"        local var_name "Avg author position ratio"
        if "`yvar'" == "avg_team_size_last"      local var_name "Team size (last-author papers)"
        if "`yvar'" == "avg_team_size_notlast"   local var_name "Team size (non-last papers)"

        /*
        preserve
            cap noi qui reghdfe `yvar' Z_share_it `wt', absorb(`fes') residuals(_y_r)
            if _rc == 0 cap noi qui reghdfe Z_it Z_share_it `wt', absorb(`fes') residuals(_Z_r)
            if _rc == 0 {
                local pds_b_str  : dis %7.3f `s_bx'
                local pds_se_str : dis %7.3f `s_sex'
                binscatter _y_r _Z_r `wt_bin', n(30) ///
                    xtitle("Exposure x post") ytitle("`var_name'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                    xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                    msymbol(O) mcolors(gs6) lcolors(ebblue) ///
                    note("{&beta} = `pds_b_str' (SE: `pds_se_str')") ///
                    plotregion(margin(sides))
                fig_export, path("../output/figures/`samp'/pdid_`yvar'`suf'_mshrctrl`wsuf'.pdf")
            }
            else di as error "pdid mshrctrl binscatter `yvar' failed; skipping plot."
        restore
        */
    }

    preserve
        clear
        svmat results
        rename (results1 results2 results3 results4 results5 results6 results7) ///
               (b_base se_base b_exp_wshr se_exp_wshr b_shr_wshr se_shr_wshr pre_mean)
        gen outcome = ""
        local i = 1
        foreach yvar of local kept_outcomes {
            replace outcome = "`yvar'" if _n == `i'
            local ++i
        }
        order outcome b_base se_base b_exp_wshr se_exp_wshr b_shr_wshr se_shr_wshr pre_mean
        save ../temp/pooled_did_`samp'`suf'`wsuf', replace
        list, sep(0) noobs abbrev(20)
    restore
end

program ppml_specs
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
    local fes athr_id year
    local vce_cl athr_id
    if "$FE_MODE" == "athr_clyr" {
        local fes athr_id i.cluster_30#i.year
    }
    if "$FE_MODE" == "inst_cluster" {
        local fes inst_id cluster_30 year
        local vce_cl inst_id
    }
    if "$FE_MODE" == "inst_cluster_fldyr" {
        local fes inst_id i.cluster_30#i.year
        local vce_cl inst_id
    }
    local wt ""
    local wsuf ""
    if "$WEIGHT_MSIM" == "1" {
        // ppmlhdfe rejects aw, binscatter rejects pw
        local wt "[pw=max_sim]"
        local wt_bin "[aw=max_sim]"
        local wsuf "_msimwt"
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"
    use ../external/prepped_samples/es_`samp'`suf', clear

    gen post = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post

    local position_outcomes ""
    if "$POSITION_OUTCOMES_AVAIL" == "1" {
        local position_outcomes n_middle_ppr
    }
    local outcomes cite_affl_wt ppr_cnt ///
                   cite_affl_wt_any ppr_cnt_any ///
                   cite_affl_wt_notlast ppr_cnt_notlast ///
                   avg_num_coathrs n_grants nih_total_cost ///
                   `position_outcomes'
    if "$QUICK_TOPJRNL" == "1" local outcomes ppr_cnt

    foreach yvar of local outcomes {
        foreach v in _mu_b _mu_s _dvarb _dvars {
            cap drop `v'
        }
        local b_b = .
        local b_se = .
        local b_N = .
        local b_r2 = .
        local b_pmn = .
        local s_bx = .
        local s_sex = .
        local s_bs = .
        local s_ses = .
        local s_N = .
        local s_r2 = .
        local s_pmn = .
        if "`yvar'" == "ppr_cnt" {
            cap noi ppmlhdfe `yvar' Z_it            `wt', absorb(`fes') vce(cluster `vce_cl') d(_dvarb)
            local rc = _rc
            if `rc' == 0 {
                local b_b  = _b[Z_it]
                local b_se = _se[Z_it]
                local b_N  = e(N)
                local b_r2 = e(r2_p)
                qui sum `yvar' if year < 2014 & e(sample)
                local b_pmn = r(mean)
                predict double _mu_b, mu
            }
            else di as error "ppml_pdid `yvar' base failed (rc=`rc')"
        }
        cap noi ppmlhdfe `yvar' Z_it Z_share_it `wt', absorb(`fes') vce(cluster `vce_cl') d(_dvars)
        local rc = _rc
        if `rc' == 0 {
            local s_bx  = _b[Z_it]
            local s_sex = _se[Z_it]
            local s_bs  = _b[Z_share_it]
            local s_ses = _se[Z_share_it]
            local s_N   = e(N)
            local s_r2  = e(r2_p)
            qui sum `yvar' if year < 2014 & e(sample)
            local s_pmn = r(mean)
            predict double _mu_s, mu
        }
        else di as error "ppml_pdid `yvar' +share failed (rc=`rc')"
        cap mat drop ppml_pdid_`yvar'
        mat ppml_pdid_`yvar' = J(7,2,.)
        mat ppml_pdid_`yvar'[1,1] = `b_b'
        mat ppml_pdid_`yvar'[2,1] = `b_se'
        mat ppml_pdid_`yvar'[5,1] = `b_pmn'
        mat ppml_pdid_`yvar'[6,1] = `b_N'
        mat ppml_pdid_`yvar'[7,1] = `b_r2'
        mat ppml_pdid_`yvar'[1,2] = `s_bx'
        mat ppml_pdid_`yvar'[2,2] = `s_sex'
        mat ppml_pdid_`yvar'[3,2] = `s_bs'
        mat ppml_pdid_`yvar'[4,2] = `s_ses'
        mat ppml_pdid_`yvar'[5,2] = `s_pmn'
        mat ppml_pdid_`yvar'[6,2] = `s_N'
        mat ppml_pdid_`yvar'[7,2] = `s_r2'
        mat rownames ppml_pdid_`yvar' = b_exposure se_exposure b_share se_share pre_mean N r2_p
        mat colnames ppml_pdid_`yvar' = base with_share

        di as text "ppml_specs `samp'`suf' `yvar': pdid b=" %7.4f ppml_pdid_`yvar'[1,1] ///
            "  pre_mean=" %7.4f `s_pmn'

        local var_name "`yvar'"
        if "`yvar'" == "cite_affl_wt"         local var_name "Citation weighted output"
        if "`yvar'" == "ppr_cnt"              local var_name "Publication count"
        if "`yvar'" == "affl_wt"              local var_name "Affiliation weighted output"
        if "`yvar'" == "cite_affl_wt_any"     local var_name "Citation weighted output (any position)"
        if "`yvar'" == "ppr_cnt_any"          local var_name "Publication count (any position)"
        if "`yvar'" == "affl_wt_any"          local var_name "Affiliation weighted output (any position)"
        if "`yvar'" == "cite_affl_wt_notlast" local var_name "Citation weighted output (non-last author)"
        if "`yvar'" == "ppr_cnt_notlast"      local var_name "Publication count (non-last author)"
        if "`yvar'" == "affl_wt_notlast"      local var_name "Affiliation weighted output (non-last author)"
        if "`yvar'" == "avg_num_coathrs"      local var_name "Avg coauthors"
        if "`yvar'" == "n_grants"             local var_name "# active NIH research grants"
        if "`yvar'" == "nih_total_cost"       local var_name "NIH award amount ($)"
        if "`yvar'" == "n_first_ppr"          local var_name "# first-author papers"
        if "`yvar'" == "n_middle_ppr"         local var_name "# middle-author papers"
        if "`yvar'" == "n_last_ppr"           local var_name "# last-author papers"
        local poisson_name "`var_name'"
        if "`yvar'" == "ppr_cnt"              local poisson_name "publications"
        if "`yvar'" == "cite_affl_wt"         local poisson_name "citation-weighted output"
        if "`yvar'" == "affl_wt"              local poisson_name "affiliation-weighted output"
        if "`yvar'" == "ppr_cnt_any"          local poisson_name "publications (any position)"
        if "`yvar'" == "cite_affl_wt_any"     local poisson_name "citation-weighted output (any position)"
        if "`yvar'" == "affl_wt_any"          local poisson_name "affiliation-weighted output (any position)"
        if "`yvar'" == "ppr_cnt_notlast"      local poisson_name "publications (non-last author)"
        if "`yvar'" == "cite_affl_wt_notlast" local poisson_name "citation-weighted output (non-last author)"
        if "`yvar'" == "affl_wt_notlast"      local poisson_name "affiliation-weighted output (non-last author)"
        if "`yvar'" == "avg_num_coathrs"      local poisson_name "coauthors"
        if "`yvar'" == "n_grants"             local poisson_name "active NIH research grants"
        if "`yvar'" == "nih_total_cost"       local poisson_name "NIH award dollars"

        if "`yvar'" == "ppr_cnt" {
        preserve
            cap confirm variable _mu_b
            if _rc == 0 {
                keep if !mi(_mu_b) & _mu_b > 0
                gen double _z_work = ln(_mu_b) + (`yvar' - _mu_b)/_mu_b
                gen double _fwlw = _mu_b
                if "$WEIGHT_MSIM" == "1" replace _fwlw = _mu_b * max_sim
                cap noi qui reghdfe _z_work [pw=_fwlw], absorb(`fes') residuals(_y_r)
                if _rc == 0 cap noi qui reghdfe Z_it [pw=_fwlw], absorb(`fes') residuals(_Z_r)
                if _rc {
                    di as error "ppml FWL `yvar' failed; skipping plot."
                }
                else {
                    local pb_str  : dis %7.3f ppml_pdid_`yvar'[1,1]
                    local pse_str : dis %7.3f ppml_pdid_`yvar'[2,1]
                    binscatter _y_r _Z_r [aw=_fwlw], n(30) ///
                        xtitle("Exposure x post") ///
                        ytitle("{&Delta} log expected `poisson_name'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                        xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                        msymbol(O) mcolors(gs6) lcolors(ebblue) ///
                        note("{&beta} = `pb_str' (SE: `pse_str')", size(small) pos(7) ring(1) justification(left)) ///
                        plotregion(margin(sides))
                    fig_export, path("../output/figures/`samp'/ppml_pdid_`yvar'`suf'`wsuf'.pdf")
                }
            }
        restore
        }

        preserve
            cap confirm variable _mu_s
            if _rc == 0 {
                keep if !mi(_mu_s) & _mu_s > 0
                gen double _z_work = ln(_mu_s) + (`yvar' - _mu_s)/_mu_s
                gen double _fwlw = _mu_s
                if "$WEIGHT_MSIM" == "1" replace _fwlw = _mu_s * max_sim
                cap noi qui reghdfe _z_work Z_share_it [pw=_fwlw], absorb(`fes') residuals(_y_r)
                if _rc == 0 cap noi qui reghdfe Z_it Z_share_it [pw=_fwlw], absorb(`fes') residuals(_Z_r)
                if _rc {
                    di as error "ppml FWL mshrctrl `yvar' failed; skipping plot."
                }
                else {
                    local pbs_str  : dis %7.3f ppml_pdid_`yvar'[1,2]
                    local pses_str : dis %7.3f ppml_pdid_`yvar'[2,2]
                    foreach fmode of global FIG_MODES {
                        local xt "Exposure x post"
                        local bnote note("{&beta} = `pbs_str' (SE: `pses_str')", size(small) pos(7) ring(1) justification(left))
                        local yfmt
                        if "`fmode'" == "paper" {
                            local xt "Exposure × Post"
                            local bnote
                            local yfmt ylab(, format(%4.2f))
                        }
                        binscatter _y_r _Z_r [aw=_fwlw], n(30) ///
                            xtitle("`xt'") ///
                            ytitle("{&Delta} log expected `poisson_name'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                            xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                            msymbol(O) mcolors(gs6) lcolors(ebblue) ///
                            `bnote' `yfmt' ///
                            plotregion(margin(sides))
                        fig_export, path("../output/figures/`samp'/ppml_pdid_`yvar'`suf'_mshrctrl`wsuf'.pdf") mode(`fmode')
                    }
                }
            }
        restore

        if !inlist("`yvar'", "n_grants", "nih_total_cost") {
        preserve
            keep if nih_athr == 1
            local n_b    = .
            local n_se   = .
            local n_N    = .
            local n_r2   = .
            local n_pmn  = .
            local ns_bx  = .
            local ns_sex = .
            local ns_bs  = .
            local ns_ses = .
            local ns_N   = .
            local ns_r2  = .
            local ns_pmn = .
            if "`yvar'" == "ppr_cnt" {
                cap noi ppmlhdfe `yvar' Z_it `wt', absorb(`fes') vce(cluster `vce_cl')
                if _rc == 0 {
                    local n_b   = _b[Z_it]
                    local n_se  = _se[Z_it]
                    local n_N   = e(N)
                    local n_r2  = e(r2_p)
                    qui sum `yvar' if year < 2014 & e(sample)
                    local n_pmn = r(mean)
                }
                else di as error "ppml_pdid `yvar' nih-only base failed"
            }
            foreach v in _mu_ns _dvarns {
                cap drop `v'
            }
            cap noi ppmlhdfe `yvar' Z_it Z_share_it `wt', absorb(`fes') vce(cluster `vce_cl') d(_dvarns)
            if _rc == 0 {
                local ns_bx  = _b[Z_it]
                local ns_sex = _se[Z_it]
                local ns_bs  = _b[Z_share_it]
                local ns_ses = _se[Z_share_it]
                local ns_N   = e(N)
                local ns_r2  = e(r2_p)
                qui sum `yvar' if year < 2014 & e(sample)
                local ns_pmn = r(mean)
                cap noi predict double _mu_ns, mu
                if _rc di as error "ppml_pdid `yvar' nih-only: predict mu failed -- binscatter SKIPPED."
            }
            else di as error "ppml_pdid `yvar' nih-only +share failed"
            cap mat drop nih_ppml_`yvar'
            mat nih_ppml_`yvar' = J(7,2,.)
            mat nih_ppml_`yvar'[1,1] = `n_b'
            mat nih_ppml_`yvar'[2,1] = `n_se'
            mat nih_ppml_`yvar'[5,1] = `n_pmn'
            mat nih_ppml_`yvar'[6,1] = `n_N'
            mat nih_ppml_`yvar'[7,1] = `n_r2'
            mat nih_ppml_`yvar'[1,2] = `ns_bx'
            mat nih_ppml_`yvar'[2,2] = `ns_sex'
            mat nih_ppml_`yvar'[3,2] = `ns_bs'
            mat nih_ppml_`yvar'[4,2] = `ns_ses'
            mat nih_ppml_`yvar'[5,2] = `ns_pmn'
            mat nih_ppml_`yvar'[6,2] = `ns_N'
            mat nih_ppml_`yvar'[7,2] = `ns_r2'
            mat rownames nih_ppml_`yvar' = b_exposure se_exposure b_share se_share pre_mean N r2_p
            mat colnames nih_ppml_`yvar' = base with_share

            qui gunique athr_id
            di as text "ppml_specs `samp'`suf' `yvar' (NIH-matched only, " r(unique) " PIs): pdid b=" ///
                %7.4f `ns_bx' "  pre_mean=" %7.4f `ns_pmn'

            cap confirm variable _mu_ns
            if _rc == 0 {
                keep if !mi(_mu_ns) & _mu_ns > 0
                gen double _z_work = ln(_mu_ns) + (`yvar' - _mu_ns)/_mu_ns
                gen double _fwlw = _mu_ns
                if "$WEIGHT_MSIM" == "1" replace _fwlw = _mu_ns * max_sim
                cap noi qui reghdfe _z_work Z_share_it [pw=_fwlw], absorb(`fes') residuals(_y_r)
                if _rc == 0 cap noi qui reghdfe Z_it Z_share_it [pw=_fwlw], absorb(`fes') residuals(_Z_r)
                if _rc {
                    di as error "ppml FWL nih-only `yvar' failed; skipping plot."
                }
                else {
                    local pbn_str  : dis %7.3f nih_ppml_`yvar'[1,2]
                    local psen_str : dis %7.3f nih_ppml_`yvar'[2,2]
                    binscatter _y_r _Z_r [aw=_fwlw], n(30) ///
                        xtitle("Exposure x post") ///
                        ytitle("{&Delta} log expected `poisson_name'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                        xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                        msymbol(O) mcolors(gs6) lcolors(ebblue) ///
                        title("NIH-matched PIs only", size(small)) ///
                        note("{&beta} = `pbn_str' (SE: `psen_str')", size(small) pos(7) ring(1) justification(left)) ///
                        plotregion(margin(sides))
                    fig_export, path("../output/figures/`samp'/ppml_pdid_`yvar'`suf'_mshrctrl_nih`wsuf'.pdf")
                }
            }
        restore
        }

        if "`yvar'" == "ppr_cnt" {
        preserve
            keep if foia_athr == 1
            local f_b    = .
            local f_se   = .
            local f_N    = .
            local f_r2   = .
            local f_pmn  = .
            local fs_bx  = .
            local fs_sex = .
            local fs_bs  = .
            local fs_ses = .
            local fs_N   = .
            local fs_r2  = .
            local fs_pmn = .
            cap noi ppmlhdfe `yvar' Z_it `wt', absorb(`fes') vce(cluster `vce_cl')
            if _rc == 0 {
                local f_b   = _b[Z_it]
                local f_se  = _se[Z_it]
                local f_N   = e(N)
                local f_r2  = e(r2_p)
                qui sum `yvar' if year < 2014 & e(sample)
                local f_pmn = r(mean)
            }
            else di as error "ppml_pdid `yvar' foia-only base failed"
            foreach v in _mu_fs _dvarfs {
                cap drop `v'
            }
            cap noi ppmlhdfe `yvar' Z_it Z_share_it `wt', absorb(`fes') vce(cluster `vce_cl') d(_dvarfs)
            if _rc == 0 {
                local fs_bx  = _b[Z_it]
                local fs_sex = _se[Z_it]
                local fs_bs  = _b[Z_share_it]
                local fs_ses = _se[Z_share_it]
                local fs_N   = e(N)
                local fs_r2  = e(r2_p)
                qui sum `yvar' if year < 2014 & e(sample)
                local fs_pmn = r(mean)
                cap noi predict double _mu_fs, mu
                if _rc di as error "ppml_pdid `yvar' foia-only: predict mu failed -- binscatter SKIPPED."
            }
            else di as error "ppml_pdid `yvar' foia-only +share failed"
            cap mat drop foia_ppml_`yvar'
            mat foia_ppml_`yvar' = J(7,2,.)
            mat foia_ppml_`yvar'[1,1] = `f_b'
            mat foia_ppml_`yvar'[2,1] = `f_se'
            mat foia_ppml_`yvar'[5,1] = `f_pmn'
            mat foia_ppml_`yvar'[6,1] = `f_N'
            mat foia_ppml_`yvar'[7,1] = `f_r2'
            mat foia_ppml_`yvar'[1,2] = `fs_bx'
            mat foia_ppml_`yvar'[2,2] = `fs_sex'
            mat foia_ppml_`yvar'[3,2] = `fs_bs'
            mat foia_ppml_`yvar'[4,2] = `fs_ses'
            mat foia_ppml_`yvar'[5,2] = `fs_pmn'
            mat foia_ppml_`yvar'[6,2] = `fs_N'
            mat foia_ppml_`yvar'[7,2] = `fs_r2'
            mat rownames foia_ppml_`yvar' = b_exposure se_exposure b_share se_share pre_mean N r2_p
            mat colnames foia_ppml_`yvar' = base with_share

            qui gunique athr_id
            di as text "ppml_specs `samp'`suf' `yvar' (FOIA PIs only, " r(unique) " PIs): pdid b=" ///
                %7.4f `fs_bx' "  pre_mean=" %7.4f `fs_pmn'

            cap confirm variable _mu_fs
            if _rc == 0 {
                keep if !mi(_mu_fs) & _mu_fs > 0
                gen double _z_work = ln(_mu_fs) + (`yvar' - _mu_fs)/_mu_fs
                gen double _fwlw = _mu_fs
                if "$WEIGHT_MSIM" == "1" replace _fwlw = _mu_fs * max_sim
                cap noi qui reghdfe _z_work Z_share_it [pw=_fwlw], absorb(`fes') residuals(_y_r)
                if _rc == 0 cap noi qui reghdfe Z_it Z_share_it [pw=_fwlw], absorb(`fes') residuals(_Z_r)
                if _rc {
                    di as error "ppml FWL foia-only `yvar' failed; skipping plot."
                }
                else {
                    local pbf_str  : dis %7.3f foia_ppml_`yvar'[1,2]
                    local psef_str : dis %7.3f foia_ppml_`yvar'[2,2]
                    binscatter _y_r _Z_r [aw=_fwlw], n(30) ///
                        xtitle("Exposure x post") ///
                        ytitle("{&Delta} log expected `poisson_name'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                        xlab(#6, format(%5.3f)) ///
                        msymbol(O) mcolors(gs6) lcolors(dkorange) ///
                        title("FOIA PIs only (observed exposure)", size(small)) ///
                        note("{&beta} = `pbf_str' (SE: `psef_str')", size(small) pos(7) ring(1) justification(left)) ///
                        plotregion(margin(sides))
                    fig_export, path("../output/figures/`samp'/ppml_pdid_`yvar'`suf'_mshrctrl_foia`wsuf'.pdf")
                }
            }
        restore
        }
    }
end

program placebo_treatment
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
    local fes athr_id year
    local vce_cl athr_id
    if "$FE_MODE" == "athr_clyr" {
        local fes athr_id i.cluster_30#i.year
    }
    if "$FE_MODE" == "inst_cluster" {
        local fes inst_id cluster_30 year
        local vce_cl inst_id
    }
    if "$FE_MODE" == "inst_cluster_fldyr" {
        local fes inst_id i.cluster_30#i.year
        local vce_cl inst_id
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"

    local outcomes ppr_cnt

    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'
    cap mkdir ../output/figures/`samp'

    foreach placebo_yr in 2011 2012 {
        use ../external/prepped_samples/es_`samp'`suf', clear
        keep if year <= 2013

        gen placebo_post   = year >= `placebo_yr'
        gen Z_placebo      = exposure      * placebo_post
        gen Z_share_placebo = mkt_spend_shr * placebo_post

        foreach yvar of local outcomes {
            local b     = .
            local se    = .
            local b_s   = .
            local se_s  = .
            local N     = .
            local r2_p  = .
            local pre_mean = .
            cap noi ppmlhdfe `yvar' Z_placebo Z_share_placebo, ///
                    absorb(`fes') vce(cluster `vce_cl')
            local rc = _rc
            if `rc' == 0 {
                local b    = _b[Z_placebo]
                local se   = _se[Z_placebo]
                local b_s  = _b[Z_share_placebo]
                local se_s = _se[Z_share_placebo]
                local N    = e(N)
                local r2_p = e(r2_p)
                qui sum `yvar' if year < `placebo_yr' & e(sample)
                local pre_mean = r(mean)
            }
            else di as error "placebo_treatment `yvar' (placebo=`placebo_yr') ppml failed (rc=`rc')"

            local t = cond(`se' > 0 & !mi(`se'), `b' / `se', .)
            di as text "placebo_treatment `samp'`suf' `yvar' (placebo=`placebo_yr'):" ///
                _newline "    ppmlhdfe (+share)  b=" %8.4f `b'   "  se=" %8.4f `se'   "  t=" %6.2f `t' ///
                "  b_share=" %8.4f `b_s' "  se_share=" %8.4f `se_s' ///
                "  pre_mean=" %8.4f `pre_mean' "  N=" %8.0f `N'

            cap mat drop placebo`placebo_yr'_`yvar'
            mat placebo`placebo_yr'_`yvar' = J(7,1,.)
            mat placebo`placebo_yr'_`yvar'[1,1] = `b'
            mat placebo`placebo_yr'_`yvar'[2,1] = `se'
            mat placebo`placebo_yr'_`yvar'[3,1] = `b_s'
            mat placebo`placebo_yr'_`yvar'[4,1] = `se_s'
            mat placebo`placebo_yr'_`yvar'[5,1] = `pre_mean'
            mat placebo`placebo_yr'_`yvar'[6,1] = `N'
            mat placebo`placebo_yr'_`yvar'[7,1] = `r2_p'
            mat rownames placebo`placebo_yr'_`yvar' = b_exp se_exp b_share se_share pre_mean N r2_p
            mat colnames placebo`placebo_yr'_`yvar' = ppmlhdfe_wshr
        }
    }

    foreach placebo_yr in 2011 2012 {
        foreach yvar in ppr_cnt {
            local poisson_name "publications"
            local ppml_ytit "Output-cost elasticity"

            use ../external/prepped_samples/es_`samp'`suf', clear
            cap drop pl_rel pl_int_lead* pl_int_lag* pl_mshr_lead* pl_mshr_lag*
            gen pl_rel = year - `placebo_yr'
            qui sum pl_rel
            local pl_abs_lag  = abs(r(max))
            local pl_abs_lead = abs(r(min))
            forval i = 1/`pl_abs_lead' {
                gen pl_int_lead`i'  = exposure      if pl_rel == -`i'
                gen pl_mshr_lead`i' = mkt_spend_shr if pl_rel == -`i'
            }
            forval i = 0/`pl_abs_lag' {
                gen pl_int_lag`i'  = exposure      if pl_rel == `i'
                gen pl_mshr_lag`i' = mkt_spend_shr if pl_rel == `i'
            }
            ds pl_int_lead* pl_int_lag* pl_mshr_lead* pl_mshr_lag*
            foreach v in `r(varlist)' {
                replace `v' = 0 if mi(`v')
            }
            local pl_int_leads
            local pl_int_lags
            local pl_mshr_leads
            local pl_mshr_lags
            forval i = 2/`pl_abs_lead' {
                local pl_int_leads  pl_int_lead`i'  `pl_int_leads'
                local pl_mshr_leads pl_mshr_lead`i' `pl_mshr_leads'
            }
            forval i = 0/`pl_abs_lag' {
                local pl_int_lags  `pl_int_lags'  pl_int_lag`i'
                local pl_mshr_lags `pl_mshr_lags' pl_mshr_lag`i'
            }

            cap noi ppmlhdfe `yvar' `pl_int_leads' `pl_int_lags' ///
                                    `pl_mshr_leads' `pl_mshr_lags', ///
                    absorb(`fes') vce(cluster `vce_cl')
            local rc = _rc
            if `rc' {
                di as error "placebo ES ppmlhdfe `yvar' yr`placebo_yr' failed (rc=`rc'); skipping."
                continue
            }

            preserve
            cap mat drop es
            foreach var in `pl_int_leads' `pl_int_lags' pl_int_lead1 {
                if "`var'" == "pl_int_lead1" {
                    mat row = 0,0
                }
                else {
                    mat row = _b[`var'], _se[`var']
                }
                mat es = nullmat(es) \ row
            }
            svmat es
            keep es1 es2
            drop if mi(es1)
            rename (es1 es2) (b se)
            gen ub = b + 1.96*se
            gen lb = b - 1.96*se
            gen rel = -`pl_abs_lead' if _n == 1
            replace rel = rel[_n-1]+1 if _n > 1
            replace rel = rel + 1 if rel >= -1
            replace rel = -1 if rel == `pl_abs_lag' + 1
            gen year = rel + `placebo_yr'
            hashsort rel
            sum ub, d
            local ymax = round(r(max), 0.1)
            sum lb, d
            local ymin = round(r(min), 0.1)
            if `ymin' > 0 local ymin = 0
            local ref_yr = `placebo_yr' - 1
            tw rcap ub lb year if year != `ref_yr', lcolor(dkorange%70) msize(vsmall) || ///
              scatter b year, mcolor(dkorange) ///
              , xlab(2010(1)2019) xtitle("Year (placebo treatment at `placebo_yr')") ///
                ytitle("`ppml_ytit'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                ylab(`ymin'(0.1)`ymax') yline(0, lcolor(gs10) lpattern(solid)) ///
                xline(2014, lpattern(dash) lcolor(gs10)) ///
                title("Placebo ES: treatment shifted to `placebo_yr' (real: 2014)", size(small)) ///
                legend(off) plotregion(margin(sides))
            fig_export, path("../output/figures/`samp'/placebo_es_`yvar'_yr`placebo_yr'`suf'.pdf")
            save ../temp/placebo_es_`yvar'_yr`placebo_yr'`suf', replace
            restore
        }
    }
end

program trim_top
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
    local fes athr_id year
    local vce_cl athr_id
    if "$FE_MODE" == "athr_clyr" {
        local fes athr_id i.cluster_30#i.year
    }
    if "$FE_MODE" == "inst_cluster" {
        local fes inst_id cluster_30 year
        local vce_cl inst_id
    }
    if "$FE_MODE" == "inst_cluster_fldyr" {
        local fes inst_id i.cluster_30#i.year
        local vce_cl inst_id
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"

    local outcomes ppr_cnt
    local trims 0 1 5 10 25

    cap mkdir ../output/tables/`samp'
    cap mkdir ../output/figures/`samp'

    foreach trim of local trims {
        use ../external/prepped_samples/es_`samp'`suf', clear
        qui gunique athr_id
        local n_pre = r(unique)
        if `trim' > 0 {
            bys athr_id: gen _one = _n == 1
            local p = 100 - `trim'
            qui _pctile pre_ppr_cnt_sum if _one == 1, p(`p')
            local cut = r(r1)
            drop if pre_ppr_cnt_sum > `cut'
            drop _one
            qui gunique athr_id
            local n_post = r(unique)
            di as text "trim_top `samp'`suf' trim=`trim'%: cut=" %7.2f `cut' ///
                "  PIs dropped " (`n_pre' - `n_post') " / `n_pre' (kept " %7.4f (`n_post' / `n_pre') ")"
        }
        else {
            local n_post = `n_pre'
            di as text "trim_top `samp'`suf' trim=0: full sample, N PIs = `n_post'"
        }

        gen post       = year >= 2014
        gen Z_it       = exposure      * post
        gen Z_share_it = mkt_spend_shr * post

        foreach yvar of local outcomes {
            local lb = .
            local lse = .
            local lN = .
            local l_pmn = .
            cap noi reghdfe `yvar' Z_it Z_share_it, absorb(`fes') vce(cluster `vce_cl')
            if _rc == 0 {
                local lb  = _b[Z_it]
                local lse = _se[Z_it]
                local lN  = e(N)
                qui sum `yvar' if year < 2014 & e(sample)
                local l_pmn = r(mean)
            }

            local pb = .
            local pse = .
            local pN = .
            local p_pmn = .
            cap noi ppmlhdfe `yvar' Z_it Z_share_it, absorb(`fes') vce(cluster `vce_cl')
            if _rc == 0 {
                local pb  = _b[Z_it]
                local pse = _se[Z_it]
                local pN  = e(N)
                qui sum `yvar' if year < 2014 & e(sample)
                local p_pmn = r(mean)
            }

            di as text "  trim=`trim'% `yvar': reghdfe b=" %8.4f `lb' "  se=" %8.4f `lse' ///
                "    ppml b=" %8.4f `pb' "  se=" %8.4f `pse' "    pre_mean=" %7.4f `l_pmn'

            cap mat drop trim`trim'_`yvar'
            mat trim`trim'_`yvar' = J(5,2,.)
            mat trim`trim'_`yvar'[1,1] = `lb'
            mat trim`trim'_`yvar'[2,1] = `lse'
            mat trim`trim'_`yvar'[3,1] = `l_pmn'
            mat trim`trim'_`yvar'[4,1] = `lN'
            mat trim`trim'_`yvar'[5,1] = `n_post'
            mat trim`trim'_`yvar'[1,2] = `pb'
            mat trim`trim'_`yvar'[2,2] = `pse'
            mat trim`trim'_`yvar'[3,2] = `p_pmn'
            mat trim`trim'_`yvar'[4,2] = `pN'
            mat trim`trim'_`yvar'[5,2] = `n_post'
            mat rownames trim`trim'_`yvar' = b se pre_mean N n_PIs
            mat colnames trim`trim'_`yvar' = reghdfe ppmlhdfe
        }
    }

    foreach yvar in ppr_cnt {
        local var_name "Publication count"
        local poisson_name "publications"
        local ppml_ytit "Output-cost elasticity"

        preserve
        clear
        set obs 5
        gen trim = .
        gen b  = .
        gen se = .
        local i = 1
        foreach t of local trims {
            replace trim = `t' in `i'
            cap confirm matrix trim`t'_`yvar'
            if !_rc {
                replace b  = trim`t'_`yvar'[1,1] in `i'
                replace se = trim`t'_`yvar'[2,1] in `i'
            }
            local ++i
        }
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        tw rcap ub lb trim, lcolor(ebblue%70) msize(small) || ///
           scatter b trim, mcolor(ebblue) msize(medium) ///
           , xlab(0 "Full sample" 1 "Drop top 1%" 5 "5%" 10 "10%" 25 "25%", labsize(small)) ///
             xtitle("Top-pre-pub PIs dropped") ///
             ytitle("pdid {&beta}: `var_name'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
             yline(0, lcolor(gs10) lpattern(solid)) ///
             title("Trim-top sensitivity: `var_name'", size(small)) ///
             legend(off) plotregion(margin(sides))
        fig_export, path("../output/figures/`samp'/trim_top_`yvar'`suf'.pdf")
        restore

        preserve
        clear
        set obs 5
        gen trim = .
        gen b  = .
        gen se = .
        local i = 1
        foreach t of local trims {
            replace trim = `t' in `i'
            cap confirm matrix trim`t'_`yvar'
            if !_rc {
                replace b  = trim`t'_`yvar'[1,2] in `i'
                replace se = trim`t'_`yvar'[2,2] in `i'
            }
            local ++i
        }
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        tw rcap ub lb trim, lcolor(dkorange%70) msize(small) || ///
           scatter b trim, mcolor(dkorange) msize(medium) ///
           , xlab(0 "Full sample" 1 "Drop top 1%" 5 "5%" 10 "10%" 25 "25%", labsize(small)) ///
             xtitle("Top-pre-pub PIs dropped") ///
             ytitle("`ppml_ytit'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
             yline(0, lcolor(gs10) lpattern(solid)) ///
             title("Trim-top sensitivity (ppml): `var_name'", size(small)) ///
             legend(off) plotregion(margin(sides))
        fig_export, path("../output/figures/`samp'/trim_top_ppml_`yvar'`suf'.pdf")
        restore
    }
end

program joint_outcome_test
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"
    use ../external/prepped_samples/es_`samp'`suf', clear

    foreach v in cite_affl_wt ppr_cnt {
        cap gen ln_`v' = ln(1+`v')
    }

    gen post = year >= 2014
    gen Z_it = exposure * post
    gen Z_share_it = mkt_spend_shr * post

    qui sum ppr_cnt      if year < 2014
    local mean_ppr = r(mean)
    qui sum cite_affl_wt if year < 2014
    local mean_cite = r(mean)

    keep athr_id year Z_it Z_share_it ppr_cnt cite_affl_wt ln_ppr_cnt ln_cite_affl_wt

    preserve
        gen outcome = 1
        gen y_raw = cite_affl_wt
        gen y_ln  = ln_cite_affl_wt
        gen y_nrm = cite_affl_wt / `mean_cite'
        keep athr_id year Z_it Z_share_it outcome y_raw y_ln y_nrm
        save ../temp/stack_cite_`samp'`suf', replace
    restore
    gen outcome = 0
    gen y_raw = ppr_cnt
    gen y_ln  = ln_ppr_cnt
    gen y_nrm = ppr_cnt / `mean_ppr'
    keep athr_id year Z_it Z_share_it outcome y_raw y_ln y_nrm
    append using ../temp/stack_cite_`samp'`suf'

    egen athr_outcome = group(athr_id outcome)
    egen year_outcome = group(year outcome)
    gen Z_it_cite = Z_it * (outcome == 1)
    gen Z_share_it_cite = Z_share_it * (outcome == 1)

    cap mat drop joint_`samp'`suf'
    mat joint_`samp'`suf' = J(8,3,.)
    mat rownames joint_`samp'`suf' = b_ppr se_ppr b_cite se_cite b_diff se_diff Wald_F p_value
    mat colnames joint_`samp'`suf' = log norm_levels ppml

    reghdfe y_ln Z_it Z_it_cite Z_share_it Z_share_it_cite, absorb(athr_outcome year_outcome) vce(cluster athr_id)
    local b_ppr_ln  = _b[Z_it]
    local se_ppr_ln = _se[Z_it]
    local b_diff_ln = _b[Z_it_cite]
    local se_diff_ln = _se[Z_it_cite]
    qui lincom Z_it + Z_it_cite
    local b_cite_ln  = r(estimate)
    local se_cite_ln = r(se)
    qui test Z_it_cite
    local F_ln = r(F)
    local p_ln = r(p)
    mat joint_`samp'`suf'[1,1] = `b_ppr_ln'
    mat joint_`samp'`suf'[2,1] = `se_ppr_ln'
    mat joint_`samp'`suf'[3,1] = `b_cite_ln'
    mat joint_`samp'`suf'[4,1] = `se_cite_ln'
    mat joint_`samp'`suf'[5,1] = `b_diff_ln'
    mat joint_`samp'`suf'[6,1] = `se_diff_ln'
    mat joint_`samp'`suf'[7,1] = `F_ln'
    mat joint_`samp'`suf'[8,1] = `p_ln'

    reghdfe y_nrm Z_it Z_it_cite Z_share_it Z_share_it_cite, absorb(athr_outcome year_outcome) vce(cluster athr_id)
    local b_ppr_nr  = _b[Z_it]
    local se_ppr_nr = _se[Z_it]
    local b_diff_nr = _b[Z_it_cite]
    local se_diff_nr = _se[Z_it_cite]
    qui lincom Z_it + Z_it_cite
    local b_cite_nr  = r(estimate)
    local se_cite_nr = r(se)
    qui test Z_it_cite
    local F_nr = r(F)
    local p_nr = r(p)
    mat joint_`samp'`suf'[1,2] = `b_ppr_nr'
    mat joint_`samp'`suf'[2,2] = `se_ppr_nr'
    mat joint_`samp'`suf'[3,2] = `b_cite_nr'
    mat joint_`samp'`suf'[4,2] = `se_cite_nr'
    mat joint_`samp'`suf'[5,2] = `b_diff_nr'
    mat joint_`samp'`suf'[6,2] = `se_diff_nr'
    mat joint_`samp'`suf'[7,2] = `F_nr'
    mat joint_`samp'`suf'[8,2] = `p_nr'

    local b_ppr_pp = .
    local se_ppr_pp = .
    local b_cite_pp = .
    local se_cite_pp = .
    local b_diff_pp = .
    local se_diff_pp = .
    local F_pp = .
    local p_pp = .
    cap noi ppmlhdfe y_raw Z_it Z_it_cite Z_share_it Z_share_it_cite, absorb(athr_outcome year_outcome) vce(cluster athr_id)
    local rc = _rc
    if `rc' == 0 {
        local b_ppr_pp  = _b[Z_it]
        local se_ppr_pp = _se[Z_it]
        local b_diff_pp = _b[Z_it_cite]
        local se_diff_pp = _se[Z_it_cite]
        qui lincom Z_it + Z_it_cite
        local b_cite_pp  = r(estimate)
        local se_cite_pp = r(se)
        qui test Z_it_cite
        local F_pp = r(F)
        local p_pp = r(p)
    }
    else di as error "joint_outcome_test ppml failed (rc=`rc'); ppml column left missing."
    mat joint_`samp'`suf'[1,3] = `b_ppr_pp'
    mat joint_`samp'`suf'[2,3] = `se_ppr_pp'
    mat joint_`samp'`suf'[3,3] = `b_cite_pp'
    mat joint_`samp'`suf'[4,3] = `se_cite_pp'
    mat joint_`samp'`suf'[5,3] = `b_diff_pp'
    mat joint_`samp'`suf'[6,3] = `se_diff_pp'
    mat joint_`samp'`suf'[7,3] = `F_pp'
    mat joint_`samp'`suf'[8,3] = `p_pp'

    di as text "joint outcome test `samp'`suf':  H0 beta_ppr = beta_cite (same H0 in three flavors)"
    di as text "  --- log      : β_ln_ppr    = " %9.4f `b_ppr_ln'  "  β_ln_cite    = " %9.4f `b_cite_ln'  "  diff = " %9.4f `b_diff_ln'  "  F = " %9.4f `F_ln'  "  p = " %9.4f `p_ln'
    di as text "  --- norm lvl : β_ppr/mean  = " %9.4f `b_ppr_nr'  "  β_cite/mean  = " %9.4f `b_cite_nr'  "  diff = " %9.4f `b_diff_nr'  "  F = " %9.4f `F_nr'  "  p = " %9.4f `p_nr'
    di as text "  --- ppml     : β_ppr (sel) = " %9.4f `b_ppr_pp'  "  β_cite (sel) = " %9.4f `b_cite_pp'  "  diff = " %9.4f `b_diff_pp'  "  F = " %9.4f `F_pp'  "  p = " %9.4f `p_pp'

    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'
    qui matrix_to_txt, saving("../output/tables/`samp'/joint_outcome_test`suf'.txt") ///
        matrix(joint_`samp'`suf') title(<tab:joint_outcome_test`suf'>) format(%20.4f) replace
end

program robustness
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
    local fes athr_id year
    local vce_cl athr_id
    if "$FE_MODE" == "athr_clyr" {
        local fes athr_id i.cluster_30#i.year
    }
    if "$FE_MODE" == "inst_cluster" {
        local fes inst_id cluster_30 year
        local vce_cl inst_id
    }
    if "$FE_MODE" == "inst_cluster_fldyr" {
        local fes inst_id i.cluster_30#i.year
        local vce_cl inst_id
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"
    cap mkdir "../output/figures/`samp'/robustness"
    cap mkdir "../output/tables"
    cap mkdir "../output/tables/`samp'"
    cap mkdir "../output/tables/`samp'/robustness"

    local outcomes ppr_cnt cite_affl_wt ppr_cnt_any cite_affl_wt_any ///
                   ppr_cnt_notlast cite_affl_wt_notlast
    if "$QUICK_TOPJRNL" == "1" local outcomes ppr_cnt

    foreach yvar of local outcomes {
        if "`yvar'" == "ppr_cnt"              local var_name "Publication count"
        if "`yvar'" == "cite_affl_wt"         local var_name "Citation weighted output"
        if "`yvar'" == "ppr_cnt_any"          local var_name "Publication count (any position)"
        if "`yvar'" == "cite_affl_wt_any"     local var_name "Citation weighted output (any position)"
        if "`yvar'" == "ppr_cnt_notlast"      local var_name "Publication count (non-last author)"
        if "`yvar'" == "cite_affl_wt_notlast" local var_name "Citation weighted output (non-last author)"
        local poisson_name "`var_name'"
        if "`yvar'" == "ppr_cnt"              local poisson_name "publications"
        if "`yvar'" == "cite_affl_wt"         local poisson_name "citation-weighted output"
        if "`yvar'" == "ppr_cnt_any"          local poisson_name "publications (any position)"
        if "`yvar'" == "cite_affl_wt_any"     local poisson_name "citation-weighted output (any position)"
        if "`yvar'" == "ppr_cnt_notlast"      local poisson_name "publications (non-last author)"
        if "`yvar'" == "cite_affl_wt_notlast" local poisson_name "citation-weighted output (non-last author)"
        local ppml_ytit "Output-cost elasticity"
        if regexm("`yvar'", "^ppr_cnt")      local gap 0.5
        if regexm("`yvar'", "^cite_affl_wt") local gap 1
        if regexm("`yvar'", "^ppr_cnt")      & "`samp'" == "top_jrnls" local gap 2
        if regexm("`yvar'", "^cite_affl_wt") & "`samp'" == "top_jrnls" local gap 2

        foreach spec in ageCtrl noattrit fldyr {
            if "`spec'" == "ageCtrl"  local title "Age x year controls"
            if "`spec'" == "noattrit" local title "PIs with last real pub year >= 2019"
            if "`spec'" == "fldyr"    local title "Author + field x year FE"
            local spec_fes `fes'
            if "`spec'" == "fldyr"    local spec_fes athr_id i.cluster_30#i.year

            use ../external/prepped_samples/es_`samp'`suf', clear
            cap drop rel int_lead* int_lag* mshr_lead* mshr_lag*
            gen rel = year - 2014
            qui sum rel
            local abs_lag  = abs(r(max))
            local abs_lead = abs(r(min))
            forval i = 1/`abs_lead' {
                gen int_lead`i'  = exposure      if rel == -`i'
                gen mshr_lead`i' = mkt_spend_shr if rel == -`i'
            }
            forval i = 1/`abs_lag' {
                gen int_lag`i'  = exposure      if rel == `i'
                gen mshr_lag`i' = mkt_spend_shr if rel == `i'
            }
            gen int_lag0  = exposure      if rel == 0
            gen mshr_lag0 = mkt_spend_shr if rel == 0
            ds int_lead* int_lag* mshr_lead* mshr_lag*
            foreach var in `r(varlist)' {
                replace `var' = 0 if mi(`var')
            }
            if "`spec'" == "noattrit" {
                keep if max_year >= 2019
            }
            qui sum rel
            local abs_lag  = abs(r(max))
            local abs_lead = abs(r(min))
            local int_leads
            local int_lags
            local mshr_leads
            local mshr_lags
            forval i = 2/`abs_lead' {
                local int_leads int_lead`i' `int_leads'
                local mshr_leads mshr_lead`i' `mshr_leads'
            }
            forval i = 0/`abs_lag' {
                local int_lags `int_lags' int_lag`i'
                local mshr_lags `mshr_lags' mshr_lag`i'
            }
            local addctrl
            if "`spec'" == "ageCtrl" local addctrl c.age_2014#i.year

            local ests ppmlhdfe
            if "`yvar'" == "ppr_cnt" local ests reghdfe ppmlhdfe

            foreach est of local ests {
            local esuf ""
            if "`est'" == "ppmlhdfe" local esuf "_ppml"
            cap noi `est' `yvar' `int_leads' `int_lags' `mshr_leads' `mshr_lags' `addctrl', ///
                    absorb(`spec_fes') vce(cluster `vce_cl')
            local rc = _rc
            if `rc' {
                di as error "robustness `samp'`suf' `yvar' `spec' `est' failed (rc=`rc'); skipping."
                continue
            }
            gunique athr_id if e(sample)
            local n_pi = r(unique)

            preserve
            cap mat drop es
            foreach var in `int_leads' `int_lags' int_lead1 {
                if "`var'" == "int_lead1" {
                    mat row = 0,0
                }
                else {
                    cap mat row = _b[`var'], _se[`var']
                    if _rc mat row = ., .
                }
                mat es = nullmat(es) \ row
            }
            svmat es
            keep es1 es2
            drop if mi(es1)
            rename (es1 es2) (b se)
            gen ub = b + 1.96*se
            gen lb = b - 1.96*se
            gen rel = -`abs_lead' if _n == 1
            replace rel = rel[_n-1]+1 if _n > 1
            replace rel = rel + 1 if rel >= -1
            replace rel = -1 if rel == `abs_lag' + 1
            gen year = rel + 2014
            hashsort rel
            save ../temp/robust_es_main_`yvar'`esuf'_`spec'_`samp'`suf', replace
            local ytit "`var_name'"
            local ylabopt ""
            if "`est'" == "ppmlhdfe" {
                local ytit "`ppml_ytit'"
                local ylabopt "ylab(#6)"
            }
            else {
                sum ub, d
                local ymax = round(r(max),`gap')
                sum lb, d
                local ymin = round(r(min),`gap')
                if `ymin' > 0 local ymin = 0
                local ylabopt "ylab(`ymin'(`gap')`ymax')"
            }
            cap graph drop _all
            cap noi tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
              scatter b year, mcolor(ebblue) ///
              , xlab(2010(1)2019) xtitle("Year") ytitle("`ytit'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                `ylabopt' yline(0, lcolor(gs10) lpattern(solid)) ///
                title("Main ES: `title' (N PIs = `n_pi')", size(small)) ///
                legend(off) plotregion(margin(sides))
            cap noi fig_export, path("../output/figures/`samp'/robustness/es_`yvar'_main`esuf'_`spec'`suf'.pdf")
            restore
            }
        }
    }

end

program exit_analysis
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
    local wt ""
    local wsuf ""
    if "$WEIGHT_MSIM" == "1" {
        local wt "[pw=max_sim]"
        local wsuf "_msimwt"
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"
    use ../external/prepped_samples/exit_`samp'`suf', clear

    foreach yvar in exit_gap exit_2022 exit_2024 {
        cap mat drop exit_`yvar'
        mat exit_`yvar' = J(8, 6, .)
        local c = 0
        foreach fe in fld inst {
            local absorb cluster_30
            if "`fe'" == "inst" local absorb cluster_30 inst_pre
            foreach g in all young old {
                local ++c
                cap noi qui reghdfe `yvar' exposure mkt_spend_shr if `g' == 1 `wt', ///
                    absorb(`absorb') vce(cluster inst_pre)
                if _rc {
                    di as error "exit_analysis `samp'`suf' `yvar' `g' `fe' failed (rc=" _rc ")."
                    continue
                }
                mat exit_`yvar'[1,`c'] = _b[exposure]
                mat exit_`yvar'[2,`c'] = _se[exposure]
                mat exit_`yvar'[3,`c'] = _b[mkt_spend_shr]
                mat exit_`yvar'[4,`c'] = _se[mkt_spend_shr]
                qui sum `yvar' if e(sample)
                mat exit_`yvar'[5,`c'] = r(mean)
                mat exit_`yvar'[6,`c'] = e(N)
                di as text "exit_analysis `samp'`suf' `yvar' `g' (`fe' FE): b=" %7.4f _b[exposure] ///
                    " se=" %7.4f _se[exposure] " mean=" %5.3f r(mean) " N=" e(N)
            }
            cap noi qui reghdfe `yvar' c.exposure##i.young c.mkt_spend_shr c.mkt_spend_shr#i.young `wt', ///
                absorb(`absorb') vce(cluster inst_pre)
            if _rc == 0 {
                local cy = cond("`fe'" == "fld", 2, 5)
                mat exit_`yvar'[7,`cy'] = _b[1.young#c.exposure]
                mat exit_`yvar'[8,`cy'] = _se[1.young#c.exposure]
            }
        }
        mat rownames exit_`yvar' = b_exposure se_exposure b_share se_share mean_y N b_early_minus_late se_early_minus_late
        mat colnames exit_`yvar' = all_fld early_fld late_fld all_inst early_inst late_inst
    }

    * Panel analog: any last-author paper in the year, author + field x year FE.
    use ../external/prepped_samples/exit_panel_`samp'`suf', clear
    keep if inrange(year, 2010, 2019)
    merge m:1 athr_id using ../external/prepped_samples/exit_`samp'`suf', ///
        keep(3) keepusing(exposure mkt_spend_shr cluster_30 max_sim young old all) nogen
    gen byte post  = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post
    cap mat drop exit_active
    mat exit_active = J(8, 6, .)
    local c = 0
    foreach fe in clyr yr {
        local absorb athr_id i.cluster_30#i.year
        if "`fe'" == "yr" local absorb athr_id year
        foreach g in all young old {
            local ++c
            cap noi qui reghdfe pub Z_it Z_share_it if `g' == 1 `wt', ///
                absorb(`absorb') vce(cluster athr_id)
            if _rc {
                di as error "exit_analysis `samp'`suf' active `g' `fe' failed (rc=" _rc ")."
                continue
            }
            mat exit_active[1,`c'] = _b[Z_it]
            mat exit_active[2,`c'] = _se[Z_it]
            mat exit_active[3,`c'] = _b[Z_share_it]
            mat exit_active[4,`c'] = _se[Z_share_it]
            qui sum pub if e(sample) & year < 2014
            mat exit_active[5,`c'] = r(mean)
            mat exit_active[6,`c'] = e(N)
            di as text "exit_analysis `samp'`suf' active `g' (`fe' FE): b=" %7.4f _b[Z_it] ///
                " se=" %7.4f _se[Z_it] " pre-mean=" %5.3f r(mean) " N=" e(N)
        }
        cap noi qui reghdfe pub c.Z_it##i.young c.Z_share_it c.Z_share_it#i.young `wt', ///
            absorb(`absorb') vce(cluster athr_id)
        if _rc == 0 {
            local cy = cond("`fe'" == "clyr", 2, 5)
            mat exit_active[7,`cy'] = _b[1.young#c.Z_it]
            mat exit_active[8,`cy'] = _se[1.young#c.Z_it]
        }
    }
    mat rownames exit_active = b_exposure se_exposure b_share se_share pre_mean N b_early_minus_late se_early_minus_late
    mat colnames exit_active = all_clyr early_clyr late_clyr all_yr early_yr late_yr

    cap mkdir "../output/figures/`samp'"
    preserve
        clear
        set obs 9
        gen byte outc = ceil(_n / 3)
        gen byte grp  = mod(_n - 1, 3) + 1
        gen b  = .
        gen se = .
        local o = 0
        foreach yvar in exit_gap exit_2022 exit_2024 {
            local ++o
            forval g = 1/3 {
                replace b  = exit_`yvar'[1,`g'] if outc == `o' & grp == `g'
                replace se = exit_`yvar'[2,`g'] if outc == `o' & grp == `g'
            }
        }
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        gen y = (3 - outc)*4 + 1 + (2 - grp)
        local ylabs `"9 "Five-year gap starting 2014-2019" 5 "No last-author paper 2020-2022" 1 "No last-author paper 2020-2024""'
        tw rcap ub lb y if grp == 1, horizontal lcolor(ebblue%70) msize(vsmall) || ///
           scatter y b if grp == 1, mcolor(ebblue) msize(small) || ///
           rcap ub lb y if grp == 2, horizontal lcolor(dkorange%70) msize(vsmall) || ///
           scatter y b if grp == 2, mcolor(dkorange) msymbol(D) msize(small) || ///
           rcap ub lb y if grp == 3, horizontal lcolor(lavender%70) msize(vsmall) || ///
           scatter y b if grp == 3, mcolor(lavender) msymbol(S) msize(small) ///
           , xline(0, lcolor(gs10) lpattern(solid)) ///
             yline(3 7, lcolor(gs12) lpattern(dash)) ///
             ylabel(`ylabs', angle(0) labsize(small) noticks nogrid) ///
             ytitle("") xtitle("Effect of exposure on Pr(Exit)", size(medsmall)) ///
             xlabel(#7, labsize(small)) ///
             legend(order(2 "All PIs" 4 "Early-career PIs" 6 "Late-career PIs") pos(6) ring(1) rows(1) size(small)) ///
             ysize(4) xsize(8) yscale(range(-0.5 10.5)) ///
             plotregion(margin(l=zero r=zero b=zero t=vsmall))
        fig_export, path("../output/figures/`samp'/exit_coefplot`suf'`wsuf'.pdf") xsize(8) ysize(4)
        di as text "wrote ../output/figures/`samp'/exit_coefplot`suf'`wsuf'.pdf"
    restore
end

program write_exit_tex
    syntax, samp(string) [suf(string) wsuf(string)]
    cap confirm matrix exit_exit_gap
    if _rc exit 0
    local out ../output/tables/`samp'/exit`suf'`wsuf'.tex
    tempname fh
    file open `fh' using "`out'", write replace
    file write `fh' "\begin{table}[htbp]" _n
    file write `fh' "\centering" _n
    file write `fh' "\caption{Effect of Merger Exposure on Exit}" _n
    file write `fh' "\label{tab:exit`suf'`wsuf'}" _n
    file write `fh' "\begin{tabular}{lccc}" _n
    file write `fh' "\toprule" _n
    file write `fh' " & (1) & (2) & (3) \\" _n
    file write `fh' " & All PIs & Early-Career PIs & Late-Career PIs \\" _n
    file write `fh' "\midrule" _n
    local lbl_exit_2022 "No last-author paper 2020--2022"
    local lbl_exit_2024 "No last-author paper 2020--2024"
    local lbl_exit_gap  "Five-year publishing gap starting 2014--2019"
    local lbl_active    "Any last-author paper in year (panel, author + field x year FE)"
    foreach yvar in exit_gap exit_2022 exit_2024 active {
        cap confirm matrix exit_`yvar'
        if _rc continue
        local line_b  "`lbl_`yvar''"
        local line_se ""
        local line_m  "\quad Mean"
        local line_n  "\quad Observations"
        forval c = 1/3 {
            local b  = exit_`yvar'[1,`c']
            local se = exit_`yvar'[2,`c']
            local m  = exit_`yvar'[5,`c']
            local n  = exit_`yvar'[6,`c']
            local t  = abs(`b' / `se')
            local st = cond(mi(`t'), "", cond(`t' >= 2.576, "^{***}", cond(`t' >= 1.960, "^{**}", cond(`t' >= 1.645, "^{*}", ""))))
            local b_s  : dis %6.3f `b'
            local se_s : dis %6.3f `se'
            local m_s  : dis %5.3f `m'
            local n_s  : dis %9.0fc `n'
            local line_b  "`line_b' & $`b_s'`st'$"
            local line_se "`line_se' & ($`se_s'$)"
            local line_m  "`line_m' & `m_s'"
            local line_n  "`line_n' & `n_s'"
        }
        file write `fh' "`line_b' \\" _n
        file write `fh' "`line_se' \\" _n
        file write `fh' "`line_m' \\" _n
        file write `fh' "`line_n' \\" _n
        file write `fh' "\addlinespace" _n
    }
    file write `fh' "\bottomrule" _n
    file write `fh' "\end{tabular}" _n
    file write `fh' "\end{table}" _n
    file close `fh'
    di as text "wrote `out'"
end

program output_tables
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
    local wsuf ""
    if "$WEIGHT_MSIM" == "1" local wsuf "_msimwt"
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"
    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'
    local position_outcomes ""
    if "$POSITION_OUTCOMES_AVAIL" == "1" {
        local position_outcomes n_middle_ppr avg_position avg_team_size_last avg_team_size_notlast
    }
    local outcomes cite_affl_wt ppr_cnt ln_ppr_cnt ///
                   cite_affl_wt_any ppr_cnt_any ///
                   cite_affl_wt_notlast ppr_cnt_notlast ///
                   avg_num_coathrs n_grants nih_total_cost ///
                   `position_outcomes'
    if "$QUICK_TOPJRNL" == "1" local outcomes ppr_cnt ln_ppr_cnt
    foreach prog in pdid ppml_pdid nih_ppml foia_ppml placebo2011 placebo2012 trim0 trim1 trim5 trim10 trim25 {
        foreach yvar of local outcomes {
            cap confirm matrix `prog'_`yvar'
            if !_rc {
                qui matrix_to_txt, saving("../output/tables/`samp'/`prog'_`yvar'`suf'`wsuf'.txt") ///
                    matrix(`prog'_`yvar') title(<tab:`prog'_`yvar'`suf'`wsuf'>) format(%20.4f) replace
            }
        }
    }

    foreach yvar in exit_gap exit_2022 exit_2024 active {
        cap confirm matrix exit_`yvar'
        if !_rc {
            qui matrix_to_txt, saving("../output/tables/`samp'/exit_`yvar'`suf'`wsuf'.txt") ///
                matrix(exit_`yvar') title(<tab:exit_`yvar'`suf'`wsuf'>) format(%20.4f) replace
        }
    }

    write_rf_main_tex, samp(`samp') suf(`suf') wsuf(`wsuf')
    write_exit_tex,    samp(`samp') suf(`suf') wsuf(`wsuf')
end

program write_rf_main_tex
    syntax, samp(string) [suf(string) wsuf(string)]
    cap confirm matrix ppml_pdid_ppr_cnt
    if _rc {
        di as text "write_rf_main_tex: ppml_pdid_ppr_cnt matrix missing; skipping."
        exit 0
    }

    local b_ms   = ppml_pdid_ppr_cnt[1,2]
    local se_ms  = ppml_pdid_ppr_cnt[2,2]
    local b_sh   = ppml_pdid_ppr_cnt[3,2]
    local se_sh  = ppml_pdid_ppr_cnt[4,2]
    local pmn    = ppml_pdid_ppr_cnt[5,2]
    local pmn_b  = ppml_pdid_ppr_cnt[5,1]
    local n_ms   = ppml_pdid_ppr_cnt[6,2]
    local b_base = ppml_pdid_ppr_cnt[1,1]
    local se_base= ppml_pdid_ppr_cnt[2,1]
    local n_base = ppml_pdid_ppr_cnt[6,1]

    if mi(`b_base') | mi(`se_base') | mi(`b_ms') | mi(`se_ms') {
        di as text "write_rf_main_tex: base or with-share PPML missing for ppr_cnt; skipping."
        exit 0
    }

    local t_ms   = abs(`b_ms'   / `se_ms')
    local t_base = abs(`b_base' / `se_base')
    local t_sh   = abs(`b_sh'   / `se_sh')
    local st_ms   = cond(`t_ms'   >= 2.576, "^{***}", cond(`t_ms'   >= 1.960, "^{**}", cond(`t_ms'   >= 1.645, "^{*}", "")))
    local st_base = cond(`t_base' >= 2.576, "^{***}", cond(`t_base' >= 1.960, "^{**}", cond(`t_base' >= 1.645, "^{*}", "")))
    local st_sh   = cond(mi(`t_sh'), "", cond(`t_sh' >= 2.576, "^{***}", cond(`t_sh' >= 1.960, "^{**}", cond(`t_sh' >= 1.645, "^{*}", ""))))

    local b_ms_s   : dis %6.3f `b_ms'
    local se_ms_s  : dis %6.3f `se_ms'
    local b_base_s : dis %6.3f `b_base'
    local se_base_s: dis %6.3f `se_base'
    local b_sh_s   : dis %6.3f `b_sh'
    local se_sh_s  : dis %6.3f `se_sh'
    local pmn_s    : dis %6.2f `pmn'
    local pmn_b_s  : dis %6.2f `pmn_b'
    local n_ms_s   : dis %12.0fc `n_ms'
    local n_base_s : dis %12.0fc `n_base'

    local out ../output/tables/`samp'/rf_main`suf'`wsuf'.tex
    tempname fh
    file open `fh' using "`out'", write replace
    file write `fh' "\begin{table}[htbp]" _n
    file write `fh' "\centering" _n
    file write `fh' "\caption{Effect of Merger Exposure on Publication Output}" _n
    file write `fh' "\label{tab:rf_main`suf'`wsuf'}" _n
    file write `fh' "\begin{tabular}{lcc}" _n
    file write `fh' "\toprule" _n
    file write `fh' " & (1) & (2) \\" _n
    file write `fh' " & With share control & Without share control \\" _n
    file write `fh' "\midrule" _n
    file write `fh' "Exposure measure            & $`b_ms_s'`st_ms'$ & $`b_base_s'`st_base'$ \\" _n
    file write `fh' "                            & ($`se_ms_s'$) & ($`se_base_s'$) \\" _n
    file write `fh' "\addlinespace" _n
    file write `fh' "Treated-market share \$S_i\$  & $`b_sh_s'`st_sh'$ &  \\" _n
    file write `fh' "                            & ($`se_sh_s'$) &  \\" _n
    file write `fh' "\midrule" _n
    file write `fh' "Pre-period mean             & `pmn_s' & `pmn_b_s' \\" _n
    file write `fh' "Observations                & `n_ms_s' & `n_base_s' \\" _n
    file write `fh' "\bottomrule" _n
    file write `fh' "\end{tabular}" _n
    file write `fh' "\end{table}" _n
    file close `fh'
    di as text "wrote `out'"
end

main
