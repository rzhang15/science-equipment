set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries, loadglob(../external/lib/globals.txt)
adopath ++ "../external/lib/stata"
version 17
set maxvar 20000

global HET_RUN_OLS 0
* DEBUG_YVAR: "" runs all outcomes; "nih_total_cost" runs NIH dollars,
* whose pooled PPML uses FY2010-2013 and FY2014-2019 annual award means.
global DEBUG_YVAR "ppr_cnt"
global HET_INCLUDE_INSTWTD 0
global HET_RUN_QUARTILES 0
global HET_IC_FULL 0
global HET_HORSERACE_ONLY 0
if "`1'" == "horserace" global HET_HORSERACE_ONLY 1
global HET_COEFPLOTS_ONLY 0
if "`1'" == "coefplots" global HET_COEFPLOTS_ONLY 1

program main
    cap mkdir ../temp
    cap mkdir "../output/figures/all_jrnls"
    het_group_labels
    if $HET_COEFPLOTS_ONLY == 1 {
        ppml_het_coefplot, samp(all_jrnls) r1r2(1) public(0)
        ppml_het_coefplot, samp(all_jrnls) r1r2(1) public(1)
        exit
    }
    foreach pub in 0 1 {
        build_het_panel, samp(all_jrnls) r1r2(1) public(`pub')
        if $HET_HORSERACE_ONLY == 0 event_study_het, samp(all_jrnls) r1r2(1) public(`pub')
        horse_race_nih,           samp(all_jrnls) r1r2(1) public(`pub')
        output_het_tables,        samp(all_jrnls) r1r2(1) public(`pub')
        output_split_diff_tables, samp(all_jrnls) r1r2(1) public(`pub')
    }
end

program event_study_het
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local fes athr_id year
    local vce_cl athr_id
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
    use ../temp/es_`samp'`suf', clear

    gen rel = year - 2014
    qui sum rel, d
    local abs_lag = abs(r(max))
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
    foreach v in ppr_cnt cite_affl_wt {
        gen ln_`v' = ln(1+`v')
    }

    local het_groups young old young_ns old_ns young_any old_any r1 r2 pub_inst priv_inst ///
                     high_nihg low_nihg high_nihd low_nihd ///
                     young_nih old_nih young_surv old_surv young_sb old_sb y_longtrain y_shorttrain new_lab est_lab big_msa small_msa ///
                     yhigh_nihd ylow_nihd yq4_nihd yq1_nihd ///
                     lab_lt10 lab_10_20 lab_20p ///
                     q1_labage q2_labage q3_labage q4_labage
    foreach a of global IC_ALIASES {
        local het_groups `het_groups' hiw_`a' low_`a'
        if "$HET_INCLUDE_INSTWTD" == "1" local het_groups `het_groups' hi_`a' lo_`a'
        if "$HET_RUN_QUARTILES" == "1" {
            local het_groups `het_groups' q1w_`a' midw_`a' q4w_`a'
            if "$HET_INCLUDE_INSTWTD" == "1" local het_groups `het_groups' q1_`a' mid_`a' q4_`a'
        }
    }
    if "$HET_RUN_QUARTILES" == "1" {
        foreach b of global PI_Q_BASES {
            local het_groups `het_groups' q1_`b' mid_`b' q4_`b'
        }
    }
    global HET_GROUPS_ACTIVE
    foreach grp of local het_groups {
        cap confirm variable `grp'
        if _rc {
            di as text "event_study_het `samp'`suf': dummy `grp' not built -- skipping."
            continue
        }
        qui sum `grp'
        if r(N) == 0 | r(min) == r(max) {
            di as text "event_study_het `samp'`suf': dummy `grp' degenerate -- skipping."
            continue
        }
        foreach v of local int_leads {
            gen `v'_`grp' = `v' * `grp'
        }
        foreach v of local int_lags {
            gen `v'_`grp' = `v' * `grp'
        }
        gen int_lead1_`grp' = int_lead1 * `grp'
        foreach v of local mshr_leads {
            gen `v'_`grp' = `v' * `grp'
        }
        foreach v of local mshr_lags {
            gen `v'_`grp' = `v' * `grp'
        }
        local leads_`grp'
        local lags_`grp'
        local mleads_`grp'
        local mlags_`grp'
        foreach v of local int_leads {
            local leads_`grp' `leads_`grp'' `v'_`grp'
        }
        foreach v of local int_lags {
            local lags_`grp' `lags_`grp'' `v'_`grp'
        }
        foreach v of local mshr_leads {
            local mleads_`grp' `mleads_`grp'' `v'_`grp'
        }
        foreach v of local mshr_lags {
            local mlags_`grp' `mlags_`grp'' `v'_`grp'
        }
        global HET_GROUPS_ACTIVE `"${HET_GROUPS_ACTIVE} `grp'"'
    }

    if "$POSITION_OUTCOMES_AVAIL" == "" {
        cap confirm variable n_first_ppr
        global POSITION_OUTCOMES_AVAIL = cond(_rc == 0, 1, 0)
    }
    local position_outcomes ""
    if "$POSITION_OUTCOMES_AVAIL" == "1" {
        local position_outcomes n_middle_ppr avg_position avg_team_size_last avg_team_size_notlast
    }

    cap drop post Z_it Z_share_it
    gen post       = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post

    local pi_pairs `" "young old" "young_ns old_ns" "young_any old_any" "young_nih old_nih" "young_surv old_surv" "young_sb old_sb" "y_longtrain y_shorttrain" "r1 r2" "pub_inst priv_inst" "high_nihg low_nihg" "high_nihd low_nihd" "new_lab est_lab" "big_msa small_msa" "yhigh_nihd ylow_nihd" "yq4_nihd yq1_nihd" "'
    global DUMMY_PAIRS_MED    `" `pi_pairs' ${IC_PAIRS_MED} "'
    global DUMMY_PAIRS_MED_PW `" `pi_pairs' ${IC_PAIRS_MED_PW} "'

    local ppml_het_skip avg_position avg_team_size_last avg_team_size_notlast

    mat drop _all
    local yvar_list ppr_cnt ppr_cnt_nonsolo cite_affl_wt avg_num_coathrs ///
                    n_grants n_new_grants nih_total_cost ///
                    `position_outcomes'
    if "$DEBUG_YVAR" != "" {
        local yvar_list $DEBUG_YVAR
        di as text "DEBUG_YVAR set -- restricting yvar loop to: $DEBUG_YVAR"
    }

    foreach yvar of local yvar_list {
        local pooled_fes `fes'
        local pooled_vce_cl `vce_cl'
        if "`yvar'" == "nih_total_cost" {
            local pooled_fes athr_id year
            local pooled_vce_cl athr_id
        }
        tempname ph_handle
        postfile `ph_handle' str30 yvar str24 grp str12 spec str20 split_type ///
            double(post_b post_se pre_b pre_se N r2_p) ///
            using "../temp/phet_results_`samp'`suf'_`yvar'", replace
        local gap 0.5
        if regexm("`yvar'", "^cite_affl_wt") local gap 1
        local ppml_ytit "Output-cost elasticity"
        if "`yvar'" == "n_grants"       local ppml_ytit "{&Delta} log expected active NIH research grants"
        if "`yvar'" == "n_new_grants"   local ppml_ytit "{&Delta} log expected new NIH research grants"
        if "`yvar'" == "nih_total_cost" local ppml_ytit "{&Delta} log expected NIH award dollars"

        if "$HET_RUN_OLS" == "1" & inlist("`yvar'", "ppr_cnt", "cite_affl_wt") {
            foreach pair of global DUMMY_PAIRS_MED {
                local g1: word 1 of `pair'
                local g2: word 2 of `pair'
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `g1' ") == 0 continue
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `g2' ") == 0 continue
                local g1_label = "${LBL_`g1'}"
                if "`g1_label'" == "" local g1_label "`g1'"
                local mshr_ctrls `mshr_leads' `mshr_lags' `mleads_`g1'' `mlags_`g1''
                local plot_suf "_mshrctrl"
                cap drop PT_`g1'
                gen PT_`g1' = post * `g1'
                cap noi reghdfe `yvar' `int_leads' `int_lags' ///
                               `leads_`g1'' `lags_`g1'' ///
                               `mshr_ctrls' PT_`g1', ///
                               absorb(`fes') vce(cluster `vce_cl')
                local rc = _rc
                if `rc' {
                    di as error "event_study_het `samp'`suf' `yvar' `g1' failed (rc=`rc'); skipping."
                    continue
                }
                gunique athr_id if e(sample) & `g1' == 1
                local num_athrs = r(unique)
                gunique inst_id if e(sample) & `g1' == 1
                local num_insts = r(unique)
                sum `yvar' if rel <= -1 & e(sample) & `g1' == 1, d
                local pre_mean : dis %4.3f r(mean)
                preserve
                cap mat drop es
                foreach var in `leads_`g1'' `lags_`g1'' int_lead1_`g1' {
                    if "`var'" == "int_lead1_`g1'" {
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
                gen rel = -`abs_lead' if _n == 1
                replace rel = rel[_n-1]+1 if _n > 1
                replace rel = rel + 1 if rel >= -1
                replace rel = -1 if rel == `abs_lag' + 1
                gen year = rel + 2014
                hashsort rel
                local stats_leg `"legend(on order(- "Num. PIs: `num_athrs'" "Num. insts: `num_insts'" "Pre-period avg : `pre_mean'") pos(7) ring(1) rows(3) bmargin(zero) size(small))"'
                local fdir ../output/figures/`samp'
                foreach fmode of global FIG_MODES {
                    if "`fmode'" == "paper" {
                        local stats_leg legend(off)
                        cap mkdir "`fdir'"
                    }
                    tw rcap ub lb year if year != 2013 , lcolor(ebblue%70) msize(vsmall) || ///
                      scatter b year, mcolor(ebblue) || ///
                    scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                      xlab(2010(1)2019, labsize(small)) xtitle("Year") ///
                      ytitle("Output-cost elasticity") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ylab(`ymin'(`gap')`ymax') ///
                      `stats_leg' ///
                      yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
                    fig_export, path("`fdir'/es_`yvar'`suf'_`g1'`plot_suf'.pdf") mode(`fmode')
                }
                save ../temp/es_`yvar'`suf'_`g1'`plot_suf', replace
                restore
            }

        }

        if strpos(" `ppml_het_skip' ", " `yvar' ") == 0 {
            cap mkdir "../output/figures/`samp'/es_ppml"
            local mmethods pw
            if "$HET_INCLUDE_INSTWTD" == "1" local mmethods inst pw
            foreach mmethod of local mmethods {
            local pairs_current
            if "`mmethod'" == "inst" {
                foreach pair of global DUMMY_PAIRS_MED {
                    local pairs_current `"`pairs_current' `"`pair'"' "'
                }
                local st_tag "med"
                local mplot_suf "_ppml_mshrctrl"
            }
            else {
                foreach pair of global DUMMY_PAIRS_MED_PW {
                    local pairs_current `"`pairs_current' `"`pair'"' "'
                }
                local st_tag "med_pi"
                local mplot_suf "_ppml_medpi_mshrctrl"
            }
            foreach pair of local pairs_current {
                local g1: word 1 of `pair'
                local g2: word 2 of `pair'
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `g1' ") == 0 continue
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `g2' ") == 0 continue

                cap drop Z_`g1' Z_`g2' S_`g1' S_`g2' PT_`g1'
                gen Z_`g1' = Z_it       * `g1'
                gen Z_`g2' = Z_it       * `g2'
                gen S_`g1' = Z_share_it * `g1'
                gen S_`g2' = Z_share_it * `g2'
                gen PT_`g1' = post * `g1'
                if "`yvar'" == "nih_total_cost" {
                    preserve
                    nih_award_period_means
                }
                cap noi ppmlhdfe `yvar' Z_`g1' Z_`g2' S_`g1' S_`g2' PT_`g1', ///
                               absorb(`pooled_fes') vce(cluster `pooled_vce_cl')
                local rc = _rc
                if `rc' {
                    if "`yvar'" == "nih_total_cost" restore
                    di as error "event_study_het `samp'`suf' `yvar' `g1'/`g2' `st_tag' pooled-DiD int ppml failed (rc=`rc'); skipping pair."
                    continue
                }
                local Nppml = e(N)
                local r2ppml = e(r2_p)
                foreach grp in `g1' `g2' {
                    gunique athr_id if e(sample) & `grp' == 1
                    local num_athrs = r(unique)
                    gunique inst_id if e(sample) & `grp' == 1
                    local num_insts = r(unique)
                    local b_post  = _b[Z_`grp']
                    local se_post = _se[Z_`grp']
                    di as text "pooled-DiD int PPML `samp'`suf' `yvar' `grp' `st_tag': b=" %8.4f `b_post' ///
                        " (se=" %8.4f `se_post' ")   N=" %9.0f `Nppml' " PIs=`num_athrs' Insts=`num_insts'"
                    post `ph_handle' ("`yvar'") ("`grp'") ("mshrctrl") ("`st_tag'") ///
                        (`b_post') (`se_post') (.) (.) (`Nppml') (`r2ppml')
                }

                cap noi lincom Z_`g1' - Z_`g2'
                if !_rc {
                    local b_diff  = r(estimate)
                    local se_diff = r(se)
                    local p_diff  = r(p)
                    di as text "pooled-DiD int PPML DIFF `samp'`suf' `yvar' `g1'-`g2' `st_tag': b=" %8.4f `b_diff' ///
                        " (se=" %8.4f `se_diff' ") p=" %6.4f `p_diff'
                    post `ph_handle' ("`yvar'") ("`g1'_diff") ("mshrctrl") ("`st_tag'_diff") ///
                        (`b_diff') (`se_diff') (`p_diff') (.) (`Nppml') (`r2ppml')
                }

                if "`yvar'" == "nih_total_cost" restore
                local mshr_ctrls `mleads_`g1'' `mlags_`g1'' `mleads_`g2'' `mlags_`g2''
                local plot_suf "`mplot_suf'"
                cap noi ppmlhdfe `yvar' `leads_`g1'' `lags_`g1'' `leads_`g2'' `lags_`g2'' ///
                               `mshr_ctrls' PT_`g1', ///
                               absorb(`fes') vce(cluster `vce_cl')
                if _rc {
                    di as error "event_study_het `samp'`suf' `yvar' `g1'/`g2' `st_tag' joint ES for PDFs failed; skipping ES plots."
                    continue
                }
                foreach grp in `g1' `g2' {
                    local grp_label = "${LBL_`grp'}"
                    if "`grp_label'" == "" local grp_label "`grp'"
                    gunique athr_id if e(sample) & `grp' == 1
                    local num_athrs = r(unique)
                    gunique inst_id if e(sample) & `grp' == 1
                    local num_insts = r(unique)
                    sum `yvar' if rel <= -1 & e(sample) & `grp' == 1, d
                    local pre_mean : dis %4.3f r(mean)
                    preserve
                    cap mat drop es
                    foreach var in `leads_`grp'' `lags_`grp'' int_lead1_`grp' {
                        if "`var'" == "int_lead1_`grp'" {
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
                    local pgap 0.2
                    gen ub = b + 1.96*se
                    gen lb = b - 1.96*se
                    local ymax = 1.2
                    local ymin = -2.2
                    gen rel = -`abs_lead' if _n == 1
                    replace rel = rel[_n-1]+1 if _n > 1
                    replace rel = rel + 1 if rel >= -1
                    replace rel = -1 if rel == `abs_lag' + 1
                    gen year = rel + 2014
                    hashsort rel
                    local stats_leg `"legend(on order(- "Num. PIs: `num_athrs'" "Num. insts: `num_insts'" "Pre-period avg : `pre_mean'") pos(7) ring(1) rows(3) bmargin(zero) size(small))"'
                    local fdir ../output/figures/`samp'/es_ppml
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
                          xlab(2010(1)2019, labsize(small)) xtitle("Year") ///
                          ytitle("`ppml_ytit'") ysc(titlegap($FIG_YTITLEGAP) outergap(0) `ysc_r') `ylab_m' ///
                          `stats_leg' ///
                          yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
                        fig_export, path("`fdir'/es_`yvar'`suf'_`grp'`plot_suf'.pdf") mode(`fmode')
                    }
                    save ../temp/es_`yvar'`suf'_`grp'`plot_suf', replace
                    restore
                }
                if "`g1'" == "young" & "`g2'" == "old" {
                    preserve
                    use ../temp/es_`yvar'`suf'_young`plot_suf', clear
                    gen grp = 1
                    append using ../temp/es_`yvar'`suf'_old`plot_suf'
                    replace grp = 2 if mi(grp)
                    replace year = year - 0.1 if grp == 1
                    replace year = year + 0.1 if grp == 2
                    local ymax = 1.2
                    local ymin = -2.2
                    local pgap 0.2
                    local fdir ../output/figures/`samp'/es_ppml
                    foreach fmode of global FIG_MODES {
                        if "`fmode'" == "paper" {
                            cap mkdir "`fdir'"
                        }
                        foreach hide in 0 1 {
                            local ocol dkorange
                            local ocol_ci dkorange%70
                            local olbl "${LBL_old}"
                            local fsuf young_old
                            if `hide' {
                                local ocol none
                                local ocol_ci none
                                local olbl " "
                                local fsuf young_old_hideold
                            }
                            local ylab_m ylab(`ymin'(`pgap')`ymax') ytick(`ymin'(0.2)`ymax')
                            local ysc_r
                            if "`fmode'" == "paper" {
                                local ylab_m ylab(-2(0.5)1, format(%3.1f))
                                local ysc_r r(`ymin' `ymax')
                            }
                            tw rcap ub lb year if rel != -1 & grp == 1, lcolor(ebblue%70) msize(vsmall) || ///
                              scatter b year if grp == 1, mcolor(ebblue) || ///
                              rcap ub lb year if rel != -1 & grp == 2, lcolor(`ocol_ci') msize(vsmall) || ///
                              scatter b year if grp == 2, mcolor(`ocol') || ///
                            scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                              xlab(2010(1)2019, labsize(small)) xtitle("Year") ///
                              ytitle("`ppml_ytit'") ysc(titlegap($FIG_YTITLEGAP) outergap(0) `ysc_r') `ylab_m' ///
                              legend(on order(2 "${LBL_young}" 4 "`olbl'") pos(6) ring(1) rows(1) size(small)) ///
                              yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
                            fig_export, path("`fdir'/es_`yvar'`suf'_`fsuf'`plot_suf'.pdf") mode(`fmode')
                        }
                    }
                    restore
                }
            }
            }

            foreach aspec in age3 ageq4 {
                if "`aspec'" == "age3"  local agrps lab_lt10 lab_10_20 lab_20p
                if "`aspec'" == "ageq4" local agrps q1_labage q2_labage q3_labage q4_labage
                local aok 1
                foreach grp of local agrps {
                    if strpos(" ${HET_GROUPS_ACTIVE} ", " `grp' ") == 0 local aok 0
                }
                if `aok' {
                local nb : word count `agrps'
                local abase : word `nb' of `agrps'
                local Zs
                local Ss
                local PTs
                foreach grp of local agrps {
                    cap drop Z_`grp'
                    cap drop S_`grp'
                    cap drop PT_`grp'
                    gen Z_`grp' = Z_it       * `grp'
                    gen S_`grp' = Z_share_it * `grp'
                    local Zs `Zs' Z_`grp'
                    local Ss `Ss' S_`grp'
                    if "`grp'" != "`abase'" {
                        gen PT_`grp' = post * `grp'
                        local PTs `PTs' PT_`grp'
                    }
                }
                if "`yvar'" == "nih_total_cost" {
                    preserve
                    nih_award_period_means
                }
                cap noi ppmlhdfe `yvar' `Zs' `Ss' `PTs', ///
                               absorb(`pooled_fes') vce(cluster `pooled_vce_cl')
                local rc = _rc
                if `rc' {
                    if "`yvar'" == "nih_total_cost" restore
                    di as error "event_study_het `samp'`suf' `yvar' `aspec' pooled-DiD int ppml failed (rc=`rc'); skipping."
                }
                else {
                    local Nppml = e(N)
                    local r2ppml = e(r2_p)
                    foreach grp of local agrps {
                        gunique athr_id if e(sample) & `grp' == 1
                        local num_athrs = r(unique)
                        gunique inst_id if e(sample) & `grp' == 1
                        local num_insts = r(unique)
                        local b_post  = _b[Z_`grp']
                        local se_post = _se[Z_`grp']
                        di as text "pooled-DiD int PPML `samp'`suf' `yvar' `grp' `aspec': b=" %8.4f `b_post' ///
                            " (se=" %8.4f `se_post' ")   N=" %9.0f `Nppml' " PIs=`num_athrs' Insts=`num_insts'"
                        post `ph_handle' ("`yvar'") ("`grp'") ("mshrctrl") ("`aspec'") ///
                            (`b_post') (`se_post') (.) (.) (`Nppml') (`r2ppml')
                    }

                    if "`yvar'" == "nih_total_cost" restore
                    local all_leads
                    local all_lags
                    local all_mshr
                    foreach grp of local agrps {
                        local all_leads `all_leads' `leads_`grp''
                        local all_lags  `all_lags'  `lags_`grp''
                        local all_mshr  `all_mshr'  `mleads_`grp'' `mlags_`grp''
                    }
                    local plot_suf "_ppml_`aspec'_mshrctrl"
                    cap noi ppmlhdfe `yvar' `all_leads' `all_lags' ///
                                            `all_mshr' `PTs', ///
                                            absorb(`fes') vce(cluster `vce_cl')
                    if _rc {
                        di as error "event_study_het `samp'`suf' `yvar' `aspec' joint ES for PDFs failed; skipping ES plots."
                    }
                    else {
                        foreach grp of local agrps {
                            local grp_label = "${LBL_`grp'}"
                            if "`grp_label'" == "" local grp_label "`grp'"
                            gunique athr_id if e(sample) & `grp' == 1
                            local num_athrs = r(unique)
                            gunique inst_id if e(sample) & `grp' == 1
                            local num_insts = r(unique)
                            sum `yvar' if rel <= -1 & e(sample) & `grp' == 1, d
                            local pre_mean : dis %4.3f r(mean)
                            preserve
                            cap mat drop es
                            foreach var in `leads_`grp'' `lags_`grp'' int_lead1_`grp' {
                                if "`var'" == "int_lead1_`grp'" {
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
                            local ymax = 1.2
                            local ymin = -2.2
                            local pgap 0.2
                            gen rel = -`abs_lead' if _n == 1
                            replace rel = rel[_n-1]+1 if _n > 1
                            replace rel = rel + 1 if rel >= -1
                            replace rel = -1 if rel == `abs_lag' + 1
                            gen year = rel + 2014
                            hashsort rel
                            local stats_leg `"legend(on order(- "Num. PIs: `num_athrs'" "Num. insts: `num_insts'" "Pre-period avg : `pre_mean'") pos(7) ring(1) rows(3) bmargin(zero) size(small))"'
                            local fdir ../output/figures/`samp'/es_ppml
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
                                  xlab(2010(1)2019, labsize(small)) xtitle("Year") ///
                                  ytitle("`ppml_ytit'") ysc(titlegap($FIG_YTITLEGAP) outergap(0) `ysc_r') `ylab_m' ///
                                  `stats_leg' ///
                                  yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
                                fig_export, path("`fdir'/es_`yvar'`suf'_`grp'`plot_suf'.pdf") mode(`fmode')
                            }
                            save ../temp/es_`yvar'`suf'_`grp'`plot_suf', replace
                            restore
                        }
                    }
                }
                }
            }

            local qmethods
            if "$HET_RUN_QUARTILES" == "1" local qmethods pw
            if "$HET_RUN_QUARTILES" == "1" & "$HET_INCLUDE_INSTWTD" == "1" local qmethods inst pw
            foreach qmethod of local qmethods {
            local quart_all
            if "`qmethod'" == "inst" {
                foreach pair of global IC_PAIRS_Q {
                    local quart_all `"`quart_all' `"`pair'"' "'
                }
                local st_tag "quart"
                local qplot_suf "_ppml_q_mshrctrl"
            }
            else {
                foreach pair of global IC_PAIRS_Q_PW {
                    local quart_all `"`quart_all' `"`pair'"' "'
                }
                local st_tag "quart_pi"
                local qplot_suf "_ppml_qpi_mshrctrl"
            }
            foreach pair of global PI_PAIRS_Q {
                local quart_all `"`quart_all' `"`pair'"' "'
            }
            foreach pair of local quart_all {
                local g1: word 1 of `pair'
                local g2: word 2 of `pair'
                if substr("`g1'", 1, 4) == "q4w_" {
                    local base = substr("`g1'", 5, .)
                    local gm "midw_`base'"
                }
                else {
                    local base = substr("`g1'", 4, .)
                    local gm "mid_`base'"
                }
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `g1' ") == 0 continue
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `g2' ") == 0 continue
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `gm' ") == 0 continue

                cap drop Z_`g1' Z_`g2' Z_`gm' S_`g1' S_`g2' S_`gm' PT_`g1' PT_`gm'
                gen Z_`g1' = Z_it       * `g1'
                gen Z_`g2' = Z_it       * `g2'
                gen Z_`gm' = Z_it       * `gm'
                gen S_`g1' = Z_share_it * `g1'
                gen S_`g2' = Z_share_it * `g2'
                gen S_`gm' = Z_share_it * `gm'
                gen PT_`g1' = post * `g1'
                gen PT_`gm' = post * `gm'
                if "`yvar'" == "nih_total_cost" {
                    preserve
                    nih_award_period_means
                }
                cap noi ppmlhdfe `yvar' Z_`g1' Z_`g2' Z_`gm' S_`g1' S_`g2' S_`gm' PT_`g1' PT_`gm', ///
                                        absorb(`pooled_fes') vce(cluster `pooled_vce_cl')
                local rc = _rc
                if `rc' {
                    if "`yvar'" == "nih_total_cost" restore
                    di as error "event_study_het `samp'`suf' `yvar' `g1'/`g2' `st_tag' pooled-DiD int ppml failed (rc=`rc'); skipping pair."
                    continue
                }
                local Nppml = e(N)
                local r2ppml = e(r2_p)
                foreach grp in `g1' `g2' {
                    gunique athr_id if e(sample) & `grp' == 1
                    local num_athrs = r(unique)
                    gunique inst_id if e(sample) & `grp' == 1
                    local num_insts = r(unique)
                    local b_post  = _b[Z_`grp']
                    local se_post = _se[Z_`grp']
                    di as text "pooled-DiD int PPML `samp'`suf' `yvar' `grp' `st_tag': b=" %8.4f `b_post' ///
                        " (se=" %8.4f `se_post' ")   N=" %9.0f `Nppml' " PIs=`num_athrs' Insts=`num_insts'"
                    post `ph_handle' ("`yvar'") ("`grp'") ("mshrctrl") ("`st_tag'") ///
                        (`b_post') (`se_post') (.) (.) (`Nppml') (`r2ppml')
                }

                if "`yvar'" == "nih_total_cost" restore
                local mshr_ctrls `mleads_`g1'' `mlags_`g1'' ///
                                 `mleads_`g2'' `mlags_`g2'' ///
                                 `mleads_`gm'' `mlags_`gm''
                local plot_suf "`qplot_suf'"
                cap noi ppmlhdfe `yvar' `leads_`g1'' `lags_`g1'' ///
                                        `leads_`g2'' `lags_`g2'' ///
                                        `leads_`gm'' `lags_`gm'' ///
                                        `mshr_ctrls' PT_`g1' PT_`gm', ///
                                        absorb(`fes') vce(cluster `vce_cl')
                if _rc {
                    di as error "event_study_het `samp'`suf' `yvar' `g1'/`g2' `st_tag' joint ES for PDFs failed; skipping ES plots."
                    continue
                }
                foreach grp in `g1' `g2' {
                    local grp_label = "${LBL_`grp'}"
                    if "`grp_label'" == "" local grp_label "`grp'"
                    gunique athr_id if e(sample) & `grp' == 1
                    local num_athrs = r(unique)
                    gunique inst_id if e(sample) & `grp' == 1
                    local num_insts = r(unique)
                    sum `yvar' if rel <= -1 & e(sample) & `grp' == 1, d
                    local pre_mean : dis %4.3f r(mean)
                    preserve
                    cap mat drop es
                    foreach var in `leads_`grp'' `lags_`grp'' int_lead1_`grp' {
                        if "`var'" == "int_lead1_`grp'" {
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
                    local ymax = 1.2
                    local ymin = -2.2
                    local pgap 0.2
                    gen rel = -`abs_lead' if _n == 1
                    replace rel = rel[_n-1]+1 if _n > 1
                    replace rel = rel + 1 if rel >= -1
                    replace rel = -1 if rel == `abs_lag' + 1
                    gen year = rel + 2014
                    hashsort rel
                    local stats_leg `"legend(on order(- "Num. PIs: `num_athrs'" "Num. insts: `num_insts'" "Pre-period avg : `pre_mean'") pos(7) ring(1) rows(3) bmargin(zero) size(small))"'
                    local fdir ../output/figures/`samp'/es_ppml
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
                          xlab(2010(1)2019, labsize(small)) xtitle("Year") ///
                          ytitle("`ppml_ytit'") ysc(titlegap($FIG_YTITLEGAP) outergap(0) `ysc_r') `ylab_m' ///
                          `stats_leg' ///
                          yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
                        fig_export, path("`fdir'/es_`yvar'`suf'_`grp'`plot_suf'.pdf") mode(`fmode')
                    }
                    save ../temp/es_`yvar'`suf'_`grp'`plot_suf', replace
                    restore
                }
            }
            }

            foreach a of global JOINT_AE_CHARS {
                cap confirm variable y_hi_`a'
                if _rc continue
                foreach grp in y_hi_`a' y_lo_`a' o_hi_`a' o_lo_`a' {
                    cap drop Z_`grp' S_`grp' PT_`grp'
                    gen Z_`grp' = Z_it       * `grp'
                    gen S_`grp' = Z_share_it * `grp'
                    gen PT_`grp' = post * `grp'
                }
                if "`yvar'" == "nih_total_cost" {
                    preserve
                    nih_award_period_means
                }
                cap noi ppmlhdfe `yvar' Z_y_hi_`a' Z_y_lo_`a' Z_o_hi_`a' Z_o_lo_`a' ///
                                        S_y_hi_`a' S_y_lo_`a' S_o_hi_`a' S_o_lo_`a' ///
                                        PT_y_hi_`a' PT_y_lo_`a' PT_o_hi_`a', ///
                                        absorb(`pooled_fes') vce(cluster `pooled_vce_cl')
                if _rc {
                    if "`yvar'" == "nih_total_cost" restore
                    di as error "event_study_het `samp'`suf' `yvar' joint-ae `a' ppml failed; skipping."
                    continue
                }
                local Nppml = e(N)
                local r2ppml = e(r2_p)
                foreach grp in y_hi_`a' y_lo_`a' o_hi_`a' o_lo_`a' {
                    gunique athr_id if e(sample) & `grp' == 1
                    local num_athrs = r(unique)
                    gunique inst_id if e(sample) & `grp' == 1
                    local num_insts = r(unique)
                    local b_post  = _b[Z_`grp']
                    local se_post = _se[Z_`grp']
                    di as text "joint-ae PPML `samp'`suf' `yvar' `grp': b=" %8.4f `b_post' ///
                        " (se=" %8.4f `se_post' ")   N=" %9.0f `Nppml' " PIs=`num_athrs' Insts=`num_insts'"
                    post `ph_handle' ("`yvar'") ("`grp'") ("mshrctrl") ("joint_ae") ///
                        (`b_post') (`se_post') (.) (.) (`Nppml') (`r2ppml')
                }
                foreach age in y o {
                    cap noi lincom Z_`age'_hi_`a' - Z_`age'_lo_`a'
                    if _rc continue
                    local b_diff  = r(estimate)
                    local se_diff = r(se)
                    local p_diff  = r(p)
                    di as text "joint-ae DIFF `samp'`suf' `yvar' `age'_`a': b=" %8.4f `b_diff' ///
                        " (se=" %8.4f `se_diff' ") p=" %6.4f `p_diff'
                    post `ph_handle' ("`yvar'") ("`age'_diff_`a'") ("mshrctrl") ("joint_ae_diff") ///
                        (`b_diff') (`se_diff') (`p_diff') (.) (`Nppml') (`r2ppml')
                }
                foreach hl in hi lo {
                    cap noi lincom Z_o_`hl'_`a' - Z_y_`hl'_`a'
                    if _rc continue
                    local b_gap  = r(estimate)
                    local se_gap = r(se)
                    local p_gap  = r(p)
                    di as text "joint-ae GAP `samp'`suf' `yvar' `hl'_`a' (late - early): b=" %8.4f `b_gap' ///
                        " (se=" %8.4f `se_gap' ") p=" %6.4f `p_gap'
                    post `ph_handle' ("`yvar'") ("`hl'_gap_`a'") ("mshrctrl") ("joint_ae_gap") ///
                        (`b_gap') (`se_gap') (`p_gap') (.) (`Nppml') (`r2ppml')
                }
                if "`yvar'" == "nih_total_cost" restore
            }

        }
        postclose `ph_handle'

        if strpos(" `ppml_het_skip' ", " `yvar' ") == 0 {
            cap noi ppml_pdid_het_binscatter, samp(`samp') r1r2(`r1r2') public(`public') r1_only(`r1_only') yvar(`yvar')
        }
        cap noi ppml_het_coefplot, samp(`samp') r1r2(`r1r2') public(`public') r1_only(`r1_only') yvar(`yvar')
    }

    preserve
    clear
    foreach yvar of local yvar_list {
        cap append using ../temp/phet_results_`samp'`suf'_`yvar'
    }
    save ../temp/phet_results_`samp'`suf', replace
    restore
end

program ppml_pdid_het_binscatter
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) yvar(string)]
    if "`yvar'" == "" local yvar ppr_cnt
    local fes athr_id year
    local vce_cl athr_id
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
    cap mkdir "../output/figures/`samp'/ppml_pdid_het_bs"

    local bs_lbl "`yvar'"
    if "`yvar'" == "ppr_cnt"           local bs_lbl "publications"
    if "`yvar'" == "cite_affl_wt"      local bs_lbl "citation-weighted output"
    if "`yvar'" == "avg_num_coathrs"   local bs_lbl "coauthors"
    if "`yvar'" == "n_grants"          local bs_lbl "active NIH research grants"
    if "`yvar'" == "n_new_grants"      local bs_lbl "new NIH research grants"
    if "`yvar'" == "nih_total_cost"    local bs_lbl "NIH award dollars"
    if "`yvar'" == "n_middle_ppr"      local bs_lbl "middle-author papers"
    if "`yvar'" == "ppr_cnt_nonsolo"   local bs_lbl "publications (excl. solo)"

    local dummy_pairs `" "young old" "young_ns old_ns" "young_any old_any" "young_nih old_nih" "young_surv old_surv" "young_sb old_sb" "y_longtrain y_shorttrain" "r1 r2" "pub_inst priv_inst" "high_nihg low_nihg" "high_nihd low_nihd" "new_lab est_lab" "big_msa small_msa" "yhigh_nihd ylow_nihd" "yq4_nihd yq1_nihd" ${IC_PAIRS_MED_PW} "'
    if "$HET_INCLUDE_INSTWTD" == "1" local dummy_pairs `" `dummy_pairs' ${IC_PAIRS_MED} "'

    preserve
        use ../temp/es_`samp'`suf', clear
        gen post       = year >= 2014
        gen Z_it       = exposure      * post
        gen Z_share_it = mkt_spend_shr * post
        if "`yvar'" == "nih_total_cost" {
            nih_award_period_means
            local fes athr_id year
            local vce_cl athr_id
            local bs_lbl "average annual NIH award dollars"
        }

        foreach pair of local dummy_pairs {
            local g1 : word 1 of `pair'
            local g2 : word 2 of `pair'

            if strpos(" ${HET_GROUPS_ACTIVE} ", " `g1' ") == 0 continue
            if strpos(" ${HET_GROUPS_ACTIVE} ", " `g2' ") == 0 continue

            foreach v in Z_`g1' Z_`g2' S_`g1' S_`g2' PT_`g1' _mu _z_work _dvar _fwlw _y_r _Z_r {
                cap drop `v'
            }
            gen Z_`g1' = Z_it       * `g1'
            gen Z_`g2' = Z_it       * `g2'
            gen S_`g1' = Z_share_it * `g1'
            gen S_`g2' = Z_share_it * `g2'
            gen PT_`g1' = post * `g1'

            cap noi ppmlhdfe `yvar' Z_`g1' Z_`g2' S_`g1' S_`g2' PT_`g1', ///
                    absorb(`fes') vce(cluster `vce_cl') d(_dvar)
            local rc = _rc
            if `rc' {
                di as error "ppml_pdid_het_bs `samp'`suf' `yvar' `g1'/`g2' joint failed (rc=`rc'); skipping pair."
                continue
            }
            local b_`g1'  = _b[Z_`g1']
            local se_`g1' = _se[Z_`g1']
            local b_`g2'  = _b[Z_`g2']
            local se_`g2' = _se[Z_`g2']

            predict double _mu, mu
            gen double _z_work = ln(_mu) + (`yvar' - _mu)/_mu if !mi(_mu) & _mu > 0
            gen double _fwlw = _mu if !mi(_mu) & _mu > 0

            foreach grp in `g1' `g2' {
                local other = cond("`grp'" == "`g1'", "`g2'", "`g1'")

                foreach v in _y_r _Z_r {
                    cap drop `v'
                }
                cap noi qui reghdfe _z_work Z_`other' S_`g1' S_`g2' PT_`g1' if !mi(_fwlw) [pw=_fwlw], ///
                        absorb(`fes') residuals(_y_r)
                if _rc == 0 cap noi qui reghdfe Z_`grp' Z_`other' S_`g1' S_`g2' PT_`g1' if !mi(_fwlw) [pw=_fwlw], ///
                        absorb(`fes') residuals(_Z_r)
                if _rc {
                    di as error "ppml_pdid_het_bs FWL `grp' failed; skipping plot."
                    continue
                }
                gunique athr_id if `grp' == 1 & !mi(_y_r) & !mi(_Z_r)
                local n_pis = r(unique)
                gunique inst_id if `grp' == 1 & !mi(_y_r) & !mi(_Z_r)
                local n_insts = r(unique)
                local b_str  : dis %7.3f `b_`grp''
                local se_str : dis %7.3f `se_`grp''
                local bs_note `"note("Num. PIs: `n_pis'   Num. Insts: `n_insts'" "{&beta} = `b_str' (SE: `se_str')", size(small) pos(7) ring(1) justification(left))"'
                local fdir ../output/figures/`samp'/ppml_pdid_het_bs
                foreach fmode of global FIG_MODES {
                    local mc gs6
                    if "`fmode'" == "paper" {
                        local mc gs9
                        local bs_note `"legend(on order(- "{&beta} = `=strtrim("`b_str'")' (SE: `=strtrim("`se_str'")')") ring(0) position(11) cols(1) region(lcolor(none)) size(small))"'
                        cap mkdir "`fdir'"
                    }
                    binscatter _y_r _Z_r [aw=_fwlw] if `grp' == 1 & !mi(_y_r) & !mi(_Z_r), n(30) ///
                        xtitle("Exposure × Post") ///
                        ytitle("{&Delta} log expected `bs_lbl'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                        xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                        msymbol(O) mcolors(`mc') lcolors(ebblue) ///
                        `bs_note' ///
                        plotregion(margin(sides))
                    fig_export, path("`fdir'/ppml_pdid_`yvar'_`grp'_mshrctrl`suf'.pdf") mode(`fmode')
                }
            }
        }

        foreach aspec in age3 ageq4 {
            if "`aspec'" == "age3"  local agrps lab_lt10 lab_10_20 lab_20p
            if "`aspec'" == "ageq4" local agrps q1_labage q2_labage q3_labage q4_labage
            local aok 1
            foreach grp of local agrps {
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `grp' ") == 0 local aok 0
            }
            if `aok' {
            foreach v in _mu _z_work _dvar _fwlw _y_r _Z_r {
                cap drop `v'
            }
            local nb : word count `agrps'
            local abase : word `nb' of `agrps'
            local Zs
            local Ss
            local PTs
            foreach grp of local agrps {
                cap drop Z_`grp'
                cap drop S_`grp'
                cap drop PT_`grp'
                gen Z_`grp' = Z_it       * `grp'
                gen S_`grp' = Z_share_it * `grp'
                local Zs `Zs' Z_`grp'
                local Ss `Ss' S_`grp'
                if "`grp'" != "`abase'" {
                    gen PT_`grp' = post * `grp'
                    local PTs `PTs' PT_`grp'
                }
            }

            cap noi ppmlhdfe `yvar' `Zs' `Ss' `PTs', ///
                    absorb(`fes') vce(cluster `vce_cl') d(_dvar)
            local rc = _rc
            if `rc' {
                di as error "ppml_pdid_het_bs `samp'`suf' `yvar' `aspec' joint failed (rc=`rc'); skipping."
            }
            else {
                foreach grp of local agrps {
                    local b_`grp'  = _b[Z_`grp']
                    local se_`grp' = _se[Z_`grp']
                }

                predict double _mu, mu
                gen double _z_work = ln(_mu) + (`yvar' - _mu)/_mu if !mi(_mu) & _mu > 0
                gen double _fwlw = _mu if !mi(_mu) & _mu > 0

                foreach grp of local agrps {
                    local others
                    foreach o of local agrps {
                        if "`o'" != "`grp'" local others `others' Z_`o'
                    }
                    foreach v in _y_r _Z_r {
                        cap drop `v'
                    }
                    cap noi qui reghdfe _z_work `others' `Ss' `PTs' if !mi(_fwlw) [pw=_fwlw], ///
                            absorb(`fes') residuals(_y_r)
                    if _rc == 0 cap noi qui reghdfe Z_`grp' `others' `Ss' `PTs' if !mi(_fwlw) [pw=_fwlw], ///
                            absorb(`fes') residuals(_Z_r)
                    if _rc {
                        di as error "ppml_pdid_het_bs FWL `grp' failed; skipping plot."
                        continue
                    }
                    gunique athr_id if `grp' == 1 & !mi(_y_r) & !mi(_Z_r)
                    local n_pis = r(unique)
                    gunique inst_id if `grp' == 1 & !mi(_y_r) & !mi(_Z_r)
                    local n_insts = r(unique)
                    local b_str  : dis %7.3f `b_`grp''
                    local se_str : dis %7.3f `se_`grp''
                    local bs_note `"note("Num. PIs: `n_pis'   Num. Insts: `n_insts'" "{&beta} = `b_str' (SE: `se_str')", size(small) pos(7) ring(1) justification(left))"'
                    local fdir ../output/figures/`samp'/ppml_pdid_het_bs
                    foreach fmode of global FIG_MODES {
                        local mc gs6
                        if "`fmode'" == "paper" {
                            local mc gs9
                            local bs_note `"legend(on order(- "{&beta} = `=strtrim("`b_str'")' (SE: `=strtrim("`se_str'")')") ring(0) position(11) cols(1) region(lcolor(none)) size(small))"'
                            cap mkdir "`fdir'"
                        }
                        binscatter _y_r _Z_r [aw=_fwlw] if `grp' == 1 & !mi(_y_r) & !mi(_Z_r), n(30) ///
                            xtitle("Exposure × Post") ///
                            ytitle("{&Delta} log expected `bs_lbl'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                            xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                            msymbol(O) mcolors(`mc') lcolors(ebblue) ///
                            `bs_note' ///
                            plotregion(margin(sides))
                        fig_export, path("`fdir'/ppml_pdid_`yvar'_`grp'_mshrctrl`suf'.pdf") mode(`fmode')
                    }
                }
            }
            }
        }
    restore
end

program horse_race_nih
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local fes athr_id year
    local vce_cl athr_id
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

    cap confirm file "../temp/es_`samp'`suf'.dta"
    if _rc {
        di as error "horse_race_nih `samp'`suf': ../temp/es_`samp'`suf'.dta not found -- run build_het_panel first."
        exit
    }
    use ../temp/es_`samp'`suf', clear
    foreach v in young low_nihd {
        cap confirm variable `v'
        if _rc {
            di as error "horse_race_nih `samp'`suf': `v' not in panel -- SKIPPED."
            exit
        }
    }
    keep if !mi(young) & !mi(low_nihd)
    foreach v in young low_nihd {
        qui sum `v'
        if r(N) == 0 | r(min) == r(max) {
            di as error "horse_race_nih `samp'`suf': `v' degenerate on the PI sample -- SKIPPED."
            exit
        }
    }

    gen post       = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post
    gen Z_early    = Z_it * young
    gen Z_lownih   = Z_it * low_nihd
    gen PT_early   = post * young
    gen PT_lownih  = post * low_nihd

    local yvar_list ppr_cnt cite_affl_wt
    if "$DEBUG_YVAR" != "" local yvar_list $DEBUG_YVAR
    local nyv : word count `yvar_list'

    mat hrace`suf' = J(22, `nyv', .)
    mat rownames hrace`suf' = b_z_base_career se_z_base_career b_z_early_alone se_z_early_alone ///
                              b_z_base_fund se_z_base_fund b_z_lownih_alone se_z_lownih_alone ///
                              b_z_base se_z_base b_z_early se_z_early b_z_lownih se_z_lownih ///
                              early_shift lownih_shift b_diff se_diff p_eq ///
                              N n_pis n_pis_early
    mat colnames hrace`suf' = `yvar_list'

    tempfile annual_horse_race
    save `annual_horse_race', replace
    local col 0
    foreach yvar of local yvar_list {
        local ++col
        use `annual_horse_race', clear
        if "`yvar'" == "nih_total_cost" nih_award_period_means
        cap drop hr_samp
        cap noi ppmlhdfe `yvar' Z_it Z_early Z_lownih PT_early PT_lownih Z_share_it, ///
            absorb(`fes') vce(cluster `vce_cl')
        local rc = _rc
        if `rc' {
            di as error "horse_race_nih `samp'`suf' `yvar' joint spec failed (rc=`rc'); column left missing."
            continue
        }
        gen byte hr_samp = e(sample)
        local Nppml = e(N)
        local b_base     = _b[Z_it]
        local se_base    = _se[Z_it]
        local b_early    = _b[Z_early]
        local se_early   = _se[Z_early]
        local b_lownih   = _b[Z_lownih]
        local se_lownih  = _se[Z_lownih]
        qui lincom Z_early - Z_lownih
        local b_diff  = r(estimate)
        local se_diff = r(se)
        qui test Z_early = Z_lownih
        local p_eq = r(p)
        gunique athr_id if hr_samp
        local n_pis = r(unique)
        gunique athr_id if hr_samp & young == 1
        local n_early = r(unique)

        cap noi ppmlhdfe `yvar' Z_it Z_early PT_early Z_share_it if hr_samp, ///
            absorb(`fes') vce(cluster `vce_cl')
        local rc = _rc
        if `rc' {
            di as error "horse_race_nih `samp'`suf' `yvar' career-only spec failed (rc=`rc'); column left missing."
            continue
        }
        local b_base_c   = _b[Z_it]
        local se_base_c  = _se[Z_it]
        local b_early_a  = _b[Z_early]
        local se_early_a = _se[Z_early]

        cap noi ppmlhdfe `yvar' Z_it Z_lownih PT_lownih Z_share_it if hr_samp, ///
            absorb(`fes') vce(cluster `vce_cl')
        local rc = _rc
        if `rc' {
            di as error "horse_race_nih `samp'`suf' `yvar' funding-only spec failed (rc=`rc'); column left missing."
            continue
        }
        local b_base_f    = _b[Z_it]
        local se_base_f   = _se[Z_it]
        local b_lownih_a  = _b[Z_lownih]
        local se_lownih_a = _se[Z_lownih]

        mat hrace`suf'[1,`col']  = `b_base_c'
        mat hrace`suf'[2,`col']  = `se_base_c'
        mat hrace`suf'[3,`col']  = `b_early_a'
        mat hrace`suf'[4,`col']  = `se_early_a'
        mat hrace`suf'[5,`col']  = `b_base_f'
        mat hrace`suf'[6,`col']  = `se_base_f'
        mat hrace`suf'[7,`col']  = `b_lownih_a'
        mat hrace`suf'[8,`col']  = `se_lownih_a'
        mat hrace`suf'[9,`col']  = `b_base'
        mat hrace`suf'[10,`col'] = `se_base'
        mat hrace`suf'[11,`col'] = `b_early'
        mat hrace`suf'[12,`col'] = `se_early'
        mat hrace`suf'[13,`col'] = `b_lownih'
        mat hrace`suf'[14,`col'] = `se_lownih'
        mat hrace`suf'[15,`col'] = `b_early' - `b_early_a'
        mat hrace`suf'[16,`col'] = `b_lownih' - `b_lownih_a'
        mat hrace`suf'[17,`col'] = `b_diff'
        mat hrace`suf'[18,`col'] = `se_diff'
        mat hrace`suf'[19,`col'] = `p_eq'
        mat hrace`suf'[20,`col'] = `Nppml'
        mat hrace`suf'[21,`col'] = `n_pis'
        mat hrace`suf'[22,`col'] = `n_early'

        mat hrp_`yvar' = (`b_early_a', `se_early_a' \ `b_lownih_a', `se_lownih_a' \ ///
                          `b_early', `se_early' \ `b_lownih', `se_lownih')

        di as text "horse_race_nih `samp'`suf' `yvar' (PI sample, N = " %9.0f `Nppml' ", PIs = `n_pis', early = `n_early'):"
        di as text "  career only   : Z x Early     = " %9.4f `b_early_a'  "  (se " %7.4f `se_early_a' ")"
        di as text "  funding only  : Z x LowNIH    = " %9.4f `b_lownih_a' "  (se " %7.4f `se_lownih_a' ")"
        di as text "  horse race    : Z x Early     = " %9.4f `b_early'    "  (se " %7.4f `se_early' ")   shift = " %8.4f `=`b_early' - `b_early_a''
        di as text "                  Z x LowNIH    = " %9.4f `b_lownih'   "  (se " %7.4f `se_lownih' ")   shift = " %8.4f `=`b_lownih' - `b_lownih_a''
        di as text "  early - lownih (joint) = " %9.4f `b_diff' "  (se " %7.4f `se_diff' ")   p(equal) = " %6.4f `p_eq'
    }

    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'
    qui matrix_to_txt, saving("../output/tables/`samp'/horse_race_nih`suf'.txt") ///
        matrix(hrace`suf') title(<tab:horse_race_nih`suf'>) format(%20.4f) replace

    cap mkdir "../output/figures/`samp'/coefplot_evavg"
    clear
    foreach yvar of local yvar_list {
        cap confirm matrix hrp_`yvar'
        if _rc continue
        clear
        svmat double hrp_`yvar', names(col)
        rename (c1 c2) (b se)
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        gen byte career = inlist(_n, 1, 3)
        gen y = cond(_n == 1, 4.7, cond(_n == 2, 3.7, cond(_n == 3, 2, 1)))
        qui sum lb
        local xmin = floor(r(min)/0.5)*0.5
        qui sum ub
        local xmax = ceil(r(max)/0.5)*0.5
        local ylabs `"4.7 "Early-career {&minus} late-career PIs" 3.7 "Below {&minus} above median NIH funding" 2 "Early-career {&minus} late-career PIs, given funding" 1 "Below {&minus} above median NIH, given career stage""'
        tw rcap ub lb y if career == 1, horizontal lcolor(ebblue%70) msize(vsmall) || ///
           scatter y b if career == 1, mcolor(ebblue) msize(small) || ///
           rcap ub lb y if career == 0, horizontal lcolor(dkorange%70) msize(vsmall) || ///
           scatter y b if career == 0, mcolor(dkorange) msymbol(D) msize(small) ///
           , xline(0, lcolor(gs10) lpattern(solid)) ///
             yline(2.85, lcolor(gs12) lpattern(dash)) ///
             ylabel(`ylabs', angle(0) labsize(small) noticks nogrid) ///
             ytitle("") xtitle("Output-cost elasticity", size(medsmall)) ///
             xlabel(`xmin'(0.5)`xmax', labsize(small)) ///
             legend(off) ///
             ysize(4) xsize(8) yscale(range(0.6 5.1)) ///
             plotregion(margin(l=zero r=zero b=zero t=vsmall))
        fig_export, path("../output/figures/`samp'/coefplot_evavg/horse_race_nih_coefplot_`yvar'`suf'.pdf") xsize(8) ysize(4)
        di as text "wrote ../output/figures/`samp'/coefplot_evavg/horse_race_nih_coefplot_`yvar'`suf'.pdf"
    }
end

program output_het_tables
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'

    cap confirm file "../temp/phet_results_`samp'`suf'.dta"
    if !_rc {
        preserve
        use "../temp/phet_results_`samp'`suf'.dta", clear
        export delimited using "../output/tables/`samp'/phet_results`suf'.txt", replace delim(tab)
        restore
    }
end

program output_split_diff_tables
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    cap confirm file "../temp/phet_results_`samp'`suf'.dta"
    if _rc {
        di as error "output_split_diff_tables `samp'`suf': phet_results not found -- skipping."
        exit 0
    }
    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'

    local pairs `"${COEFPLOT_PI_PAIRS}"'
    foreach a of global IC_ALIASES {
        local pairs `"`pairs' "hiw_`a' low_`a'" "'
    }

    foreach yvar in ppr_cnt cite_affl_wt {
        preserve
        use "../temp/phet_results_`samp'`suf'.dta", clear
        keep if yvar == "`yvar'" & spec == "mshrctrl" & inlist(split_type, "med_pi", "med_pi_diff")
        cap mat drop sdiff
        local rows
        foreach pair of local pairs {
            local g1 : word 1 of `pair'
            local g2 : word 2 of `pair'
            qui count if grp == "`g1'_diff" & split_type == "med_pi_diff"
            if r(N) == 0 continue
            foreach g in `g1' `g2' {
                qui sum post_b  if grp == "`g'" & split_type == "med_pi"
                local b_`g'  = r(mean)
                qui sum post_se if grp == "`g'" & split_type == "med_pi"
                local se_`g' = r(mean)
            }
            qui sum post_b  if grp == "`g1'_diff" & split_type == "med_pi_diff"
            local b_diff = r(mean)
            qui sum post_se if grp == "`g1'_diff" & split_type == "med_pi_diff"
            local se_diff = r(mean)
            qui sum pre_b   if grp == "`g1'_diff" & split_type == "med_pi_diff"
            local p_diff = r(mean)
            qui sum N       if grp == "`g1'_diff" & split_type == "med_pi_diff"
            local Nfit = r(mean)
            mat sdiff = nullmat(sdiff) \ ///
                (`b_`g1'', `se_`g1'', `b_`g2'', `se_`g2'', `b_diff', `se_diff', `p_diff', `Nfit')
            local rows `rows' `g1'
        }
        restore
        if "`rows'" == "" continue
        mat colnames sdiff = b_g1 se_g1 b_g2 se_g2 b_diff se_diff p_diff N
        mat rownames sdiff = `rows'
        di as result _n "== split_diff `samp'`suf' `yvar': g1 - g2 off the joint VCE (rows = g1 of each coefplot pair) =="
        matlist sdiff, format(%9.4f) lines(oneline)
        qui matrix_to_txt, saving("../output/tables/`samp'/split_diff_`yvar'`suf'.txt") ///
            matrix(sdiff) title(<tab:split_diff_`yvar'`suf'>) format(%20.4f) replace
    }
end

program ppml_het_coefplot
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) yvar(string)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"

    if "`yvar'" != "" {
        local resfile "../temp/phet_results_`samp'`suf'_`yvar'.dta"
    }
    else {
        local resfile "../temp/phet_results_`samp'`suf'.dta"
    }
    cap confirm file "`resfile'"
    if _rc {
        di as error "ppml_het_coefplot: `resfile' not found -- skipping"
        exit 0
    }

    local ppml_het_yvars ppr_cnt ppr_cnt_nonsolo cite_affl_wt avg_num_coathrs ///
                        n_grants n_new_grants nih_total_cost ///
                        n_middle_ppr
    if "`yvar'" != "" local ppml_het_yvars `yvar'

    local ic_fund_aliases tfnd lsf
    local ic_expx_aliases endow
    if $HET_IC_FULL == 1 {
        local ic_fund_aliases contr fdlsb fdls fdlsh gntsf hhlsb hhls hhlsh nflsb nfls nflsh subrf busf fedf tfnd instf nonpf statf lsf hsf biof
        local ic_expx_aliases applx apfx basx bfx clinx devx lscx medx endow
    }

    local st_list med_pi joint_ae
    if "$HET_INCLUDE_INSTWTD" == "1" local st_list med `st_list'
    if "$HET_RUN_QUARTILES" == "1" {
        local st_list `st_list' quart_pi
        if "$HET_INCLUDE_INSTWTD" == "1" local st_list `st_list' quart
    }
    foreach st of local st_list {
        local groups_core
        local groups_core_any
        if strpos("`st'", "joint_") == 1 {
            local groups_pi
            local groups_ic_fund
            local groups_ic_expx
        }
        else if "`st'" == "med" {
            local groups_pi
            foreach pair of global COEFPLOT_PI_PAIRS {
                local groups_pi `groups_pi' `pair'
            }
            local groups_ic_fund
            foreach a of local ic_fund_aliases {
                local groups_ic_fund `groups_ic_fund' hi_`a' lo_`a'
            }
            local groups_ic_expx
            foreach a of local ic_expx_aliases {
                local groups_ic_expx `groups_ic_expx' hi_`a' lo_`a'
            }
            local groups_core young old hi_tfnd lo_tfnd hi_endow lo_endow
        }
        else if "`st'" == "med_pi" {
            local groups_pi
            foreach pair of global COEFPLOT_PI_PAIRS {
                local groups_pi `groups_pi' `pair'
            }
            local groups_ic_fund
            foreach a of local ic_fund_aliases {
                local groups_ic_fund `groups_ic_fund' hiw_`a' low_`a'
            }
            local groups_ic_expx
            foreach a of local ic_expx_aliases {
                local groups_ic_expx `groups_ic_expx' hiw_`a' low_`a'
            }
            local groups_core young old hiw_tfnd low_tfnd hiw_endow low_endow
            local groups_core_any young old young_any old_any hiw_tfnd low_tfnd hiw_endow low_endow
        }
        else if "`st'" == "quart" {
            local groups_pi
            foreach b of global PI_Q_BASES {
                local groups_pi `groups_pi' q4_`b' q1_`b'
            }
            local groups_ic_fund
            foreach a of local ic_fund_aliases {
                local groups_ic_fund `groups_ic_fund' q4_`a' q1_`a'
            }
            local groups_ic_expx
            foreach a of local ic_expx_aliases {
                local groups_ic_expx `groups_ic_expx' q4_`a' q1_`a'
            }
        }
        else {
            local groups_pi
            foreach b of global PI_Q_BASES {
                local groups_pi `groups_pi' q4_`b' q1_`b'
            }
            local groups_ic_fund
            foreach a of local ic_fund_aliases {
                local groups_ic_fund `groups_ic_fund' q4w_`a' q1w_`a'
            }
            local groups_ic_expx
            foreach a of local ic_expx_aliases {
                local groups_ic_expx `groups_ic_expx' q4w_`a' q1w_`a'
            }
        }

        foreach spec_tag in mshrctrl {
            local spec_folder = cond($HET_IC_FULL == 1, "coefplot_evavg_full", "coefplot_evavg")
            cap mkdir "../output/figures/`samp'/`spec_folder'"

        local groups_all `groups_pi' `groups_ic_fund' `groups_ic_expx'
        foreach panel in pi ic_fund ic_expx core core_any all {
            local groups `groups_`panel''
            local n_groups : word count `groups'
            if `n_groups' == 0 continue

            foreach yv of local ppml_het_yvars {
                preserve
                use "`resfile'", clear
                keep if yvar == "`yv'" & split_type == "`st'" & spec == "`spec_tag'"
                if _N == 0 {
                    restore
                    continue
                }

                local groups_present
                foreach g of local groups {
                    qui count if grp == "`g'" & !mi(post_b)
                    if r(N) > 0 local groups_present `groups_present' `g'
                }
                local groups `groups_present'
                local n_groups : word count `groups'
                if `n_groups' == 0 {
                    restore
                    continue
                }

                local within 0.6
                local between 1.25
                local npairs = ceil(`n_groups'/2)
                gen double y = .
                local ylabs ""
                local i = 0
                foreach g of local groups {
                    local ++i
                    local pair = int((`i'-1)/2)
                    local ypos = (`n_groups' - `i')*`within' + (`npairs' - 1 - `pair')*(`between' - `within') + 1
                    qui replace y = `ypos' if grp == "`g'"
                    local lbl = "${LBL_`g'}"
                    if "`lbl'" == "" local lbl "`g'"
                    if length("`lbl'") > 40 local lbl = substr("`lbl'", 1, 37) + "..."
                    local ylabs `"`ylabs' `ypos' "`lbl'""'
                }
                drop if mi(y) | mi(post_b)
                if _N == 0 {
                    restore
                    continue
                }
                gen ub = post_b + 1.96*post_se
                gen lb = post_b - 1.96*post_se

                qui sum lb
                local xmin = min(-2, floor(r(min)/0.5)*0.5)
                qui sum ub
                local xmax = max(1, ceil(r(max)/0.5)*0.5)
                local xstep 0.5

                local ysize = round(0.28 * ((`n_groups' - 1)*`within' + (`npairs' - 1)*(`between' - `within') + 1), 0.1)
                local ysize = max(2, min(14, `ysize'))
                local xsize 6

                gen byte hl = inlist(grp, "young", "old", "young_any", "old_any") & strpos("`panel'", "core") == 1
                local hl_plots
                qui count if hl == 1
                if r(N) > 0 {
                    local hl_plots `" || rcap ub lb y if hl == 1, horizontal lcolor(dkorange%70) msize(half_tiny) || scatter y post_b if hl == 1, mcolor(dkorange) msize(tiny)"'
                }

                foreach fmode of global FIG_MODES {
                    local xlab_m xlabel(`xmin'(`xstep')`xmax', labsize(small))
                    if "`fmode'" == "paper" local xlab_m xlabel(`xmin'(`xstep')`xmax', labsize(small) format(%3.1f))
                    tw rcap ub lb y if hl == 0, horizontal lcolor(ebblue%70) msize(half_tiny) || ///
                       scatter y post_b if hl == 0, mcolor(ebblue) msize(tiny) `hl_plots' ///
                       , xline(0, lcolor(gs10) lpattern(solid)) ///
                         ylabel(`ylabs', angle(0) labsize(medsmall) noticks nogrid) ///
                         ytitle("") xtitle("Output-cost elasticity", size(medium)) ///
                         `xlab_m' ///
                         legend(off) ///
                         ysize(`ysize') xsize(`xsize') ///
                         yscale(range(0.9 .)) ///
                         plotregion(margin(l=zero r=zero b=zero t=vsmall))
                    fig_export, path("../output/figures/`samp'/`spec_folder'/ppml_het_coefplot_`yv'_`st'_`panel'`suf'.pdf") xsize(`xsize') ysize(`ysize') mode(`fmode')
                }
                di as text "wrote ../output/figures/`samp'/`spec_folder'/ppml_het_coefplot_`yv'_`st'_`panel'`suf'.pdf"
                restore
            }
        }

        if "`st'" == "joint_ae" {
            local pfx_len   1
            local hi_pfx    y
            local lo_pfx    o
            local hi_leg    "Early-career"
            local lo_leg    "Late-career"
            local filename_stem joint_ae_paired
            local hilo_pos = `pfx_len' + 2
            local char_pos = `pfx_len' + 5
            foreach yv of local ppml_het_yvars {
                preserve
                use "`resfile'", clear
                keep if yvar == "`yv'" & split_type == "`st'" & spec == "`spec_tag'"
                if _N == 0 {
                    restore
                    continue
                }
                gen str2  pfx_c  = substr(grp, 1, `pfx_len')
                gen str2  hilo_c = substr(grp, `hilo_pos', 2)
                gen str12 char_c = substr(grp, `char_pos', .)
                gen byte  is_hi_side = (pfx_c == "`hi_pfx'")
                gen char_idx = .
                local ii = 0
                foreach a of global IC_ALIASES {
                    local ++ii
                    qui replace char_idx = `ii' if char_c == "`a'"
                }
                qui drop if mi(char_idx)
                if _N == 0 {
                    restore
                    continue
                }
                qui sum char_idx
                local nchars = r(max)
                gen double y_group = (`nchars' + 1 - char_idx) * 3.2
                gen double y_pos   = y_group ///
                    + cond(hilo_c == "hi" & is_hi_side == 1,  1.0, ///
                      cond(hilo_c == "hi" & is_hi_side == 0,  0.4, ///
                      cond(hilo_c == "lo" & is_hi_side == 1, -0.4, -1.0)))
                gen ub = post_b + 1.96*post_se
                gen lb = post_b - 1.96*post_se

                local ylabs
                forvalues i = 1/`nchars' {
                    qui levelsof char_c if char_idx == `i', local(cname) clean
                    local clbl = "${LBL_ic_`cname'}"
                    if "`clbl'" == "" local clbl "`cname'"
                    local base = (`nchars' + 1 - `i') * 3.2
                    local pos_hi = `base' + 1.0
                    local pos_lo = `base' - 0.4
                    local ylabs `"`ylabs' `pos_hi' "High `clbl'""'
                    local ylabs `"`ylabs' `pos_lo' "Low `clbl'""'
                }

                qui sum lb
                local xmin = floor(r(min)/0.5)*0.5
                qui sum ub
                local xmax = ceil(r(max)/0.5)*0.5

                tw rcap ub lb y_pos if is_hi_side == 1, horizontal lcolor(ebblue%70) msize(vsmall)   || ///
                   scatter y_pos post_b if is_hi_side == 1, mcolor(ebblue) msize(small)              || ///
                   rcap ub lb y_pos if is_hi_side == 0, horizontal lcolor(dkorange%70) msize(vsmall) || ///
                   scatter y_pos post_b if is_hi_side == 0, mcolor(dkorange) msymbol(D) msize(small) ///
                   , xline(0, lcolor(gs10) lpattern(solid)) ///
                     ylabel(`ylabs', angle(0) labsize(small) noticks nogrid) ///
                     ytitle("") xtitle("Output-cost elasticity", size(medsmall)) ///
                     xlabel(`xmin'(0.5)`xmax', labsize(small)) ///
                     legend(order(2 "`hi_leg'" 4 "`lo_leg'") pos(6) ring(1) rows(1) span size(small)) ///
                     xsize(4) ysize(`=max(8, `nchars'*1.6) * 4/9') ///
                     yscale(range(2.1 .)) ///
                     plotregion(margin(l=zero r=zero b=zero t=vsmall))
                fig_export, path("../output/figures/`samp'/`spec_folder'/ppml_het_coefplot_`yv'_`filename_stem'`suf'.pdf")
                di as text "wrote `filename_stem' coefplot for `yv' `spec_tag'"
                restore
            }
            joint_ae_panel_coefplot, resfile("`resfile'") yvars(`ppml_het_yvars') samp(`samp') ///
                suf(`suf') spec_folder(`spec_folder') spec_tag(`spec_tag')
        }

        }
    }
end

program joint_ae_panel_coefplot
    syntax, resfile(string) yvars(string) samp(string) spec_folder(string) spec_tag(string) [suf(string)]
    foreach a of global JOINT_AE_CHARS {
        local clbl = "${LBL_ic_`a'}"
        if "`clbl'" == "" local clbl "`a'"
        foreach yv of local yvars {
            preserve
            use "`resfile'", clear
            keep if yvar == "`yv'" & spec == "`spec_tag'" & split_type == "joint_ae"
            keep if inlist(grp, "y_hi_`a'", "o_hi_`a'", "y_lo_`a'", "o_lo_`a'")
            qui count if split_type == "joint_ae" & !mi(post_b)
            if r(N) < 4 {
                restore
                continue
            }
            gen byte early = substr(grp, 1, 1) == "y"
            gen ub = post_b + 1.96*post_se
            gen lb = post_b - 1.96*post_se

            gen double x = .
            replace x = 1   if grp == "y_hi_`a'"
            replace x = 2   if grp == "o_hi_`a'"
            replace x = 3.5 if grp == "y_lo_`a'"
            replace x = 4.5 if grp == "o_lo_`a'"
            local lbl_hi "${LBL_hiw_`a'}"
            local lbl_lo "${LBL_low_`a'}"
            if "`a'" == "nihd" {
                local lbl_hi "${LBL_high_nihd}"
                local lbl_lo "${LBL_low_nihd}"
            }
            gen double b_early = post_b if early == 1
            gen double b_late  = post_b if early == 0
            sort x

            qui sum lb
            local ymin = min(-2, floor(r(min)/0.5)*0.5)
            qui sum ub
            local ymax = max(1, ceil(r(max)/0.5)*0.5)
            local ystep 0.5

            foreach fmode of global FIG_MODES {
                local late_col = cond("`fmode'" == "paper", "gs8", "dkorange")
                local ylab_m ylabel(`ymin'(`ystep')`ymax')
                if "`fmode'" == "paper" local ylab_m ylabel(`ymin'(`ystep')`ymax', format(%3.1f))
                tw rcap ub lb x if early == 1, lcolor(ebblue%70) msize(vsmall) || ///
                   rcap ub lb x if early == 0, lcolor(`late_col'%70) msize(vsmall) || ///
                   connected b_early x, cmissing(n) lcolor(ebblue%70) mcolor(ebblue) || ///
                   connected b_late  x, cmissing(n) lcolor(`late_col'%70) mcolor(`late_col') ///
                   , yline(0, lcolor(gs10) lpattern(solid)) ///
                     xline(2.75, lcolor(gs12) lpattern(dash)) ///
                     xlabel(1.5 "`lbl_hi'" 4 "`lbl_lo'", labsize(medsmall) noticks nogrid) ///
                     xsc(r(0.5 5)) xtitle("") ///
                     `ylab_m' ytitle("Output-cost elasticity", size(medium)) ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                     legend(order(3 "${LBL_young}" 4 "${LBL_old}") pos(6) ring(1) rows(1) symxsize(*0.4) size(small)) ///
                     plotregion(margin(sides))
                fig_export, path("../output/figures/`samp'/`spec_folder'/ppml_het_coefplot_`yv'_joint_ae_panel_`a'`suf'.pdf") mode(`fmode')
            }
            di as text "wrote ../output/figures/`samp'/`spec_folder'/ppml_het_coefplot_`yv'_joint_ae_panel_`a'`suf'.pdf"
            restore
        }
    }
end

if "$HET_SKIP_MAIN" != "1" main
