set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries, loadglob(../external/lib/globals.txt)
adopath ++ "../external/lib/stata"
version 17
global WEIGHT_MSIM 0

program main
    detect_position_outcomes
    local pubs 0
    if "$RUN_PUBLIC" == "1" local pubs 0 1
    local r1_opts 0
    if "$RUN_R1_ONLY" == "1" local r1_opts 0 1
    cap mkdir "../output/figures/all_jrnls"
    foreach pub of local pubs {
        foreach r1 of local r1_opts {
            foreach wmode in 0 1 {
                global WEIGHT_MSIM `wmode'
                di as text _newline "=========================================="
                di as text "  RUNNING sample=all_jrnls WEIGHT_MSIM=`wmode' PUBLIC=`pub' R1_ONLY=`r1'"
                di as text "=========================================="
                mat drop _all
                event_study,   samp(all_jrnls) r1r2(1) public(`pub') r1_only(`r1')
                pooled_did,    samp(all_jrnls) r1r2(1) public(`pub') r1_only(`r1')
                ppml_specs,    samp(all_jrnls) r1r2(1) public(`pub') r1_only(`r1')
                output_tables, samp(all_jrnls) r1r2(1) public(`pub') r1_only(`r1')
            }
            global WEIGHT_MSIM 0
        }
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
                    xtitle("Exposure × Post") ytitle("`var_name'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
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
                        xtitle("Exposure × Post") ///
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
                        local xt "Exposure × Post"
                        local bnote note("{&beta} = `pbs_str' (SE: `pses_str')", size(small) pos(7) ring(1) justification(left))
                        local yfmt
                        local mc gs6
                        if "`fmode'" == "paper" {
                            local bnote legend(on order(- "{&beta} = `=strtrim("`pbs_str'")' (SE: `=strtrim("`pses_str'")')") ring(0) position(11) cols(1) region(lcolor(none)) size(small))
                            local yfmt ylab(, format(%4.2f))
                            local mc gs9
                        }
                        binscatter _y_r _Z_r [aw=_fwlw], n(30) ///
                            xtitle("`xt'") ///
                            ytitle("{&Delta} log expected `poisson_name'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                            xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                            msymbol(O) mcolors(`mc') lcolors(ebblue) ///
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
                        xtitle("Exposure × Post") ///
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
                        xtitle("Exposure × Post") ///
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
    foreach prog in pdid ppml_pdid nih_ppml foia_ppml {
        foreach yvar of local outcomes {
            cap confirm matrix `prog'_`yvar'
            if !_rc {
                qui matrix_to_txt, saving("../output/tables/`samp'/`prog'_`yvar'`suf'`wsuf'.txt") ///
                    matrix(`prog'_`yvar') title(<tab:`prog'_`yvar'`suf'`wsuf'>) format(%20.4f) replace
            }
        }
    }

    write_rf_main_tex, samp(`samp') suf(`suf') wsuf(`wsuf')
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
