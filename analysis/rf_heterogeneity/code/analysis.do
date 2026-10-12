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
global HET_AGE_BINW 10
global HET_AGE_BIN_MINPI 30
global HET_AGE_TOPCODE 40
global HET_HORSERACE_ONLY 0
if "`1'" == "horserace" global HET_HORSERACE_ONLY 1
global HET_COEFPLOTS_ONLY 0
if "`1'" == "coefplots" global HET_COEFPLOTS_ONLY 1
global HET_MATCHED_ONLY 0
if "`1'" == "matched" global HET_MATCHED_ONLY 1
global HET_MATCH_OUT_BINS 4
global HET_MATCH_FUND_BINS 3

program main
    if $HET_COEFPLOTS_ONLY == 1 {
        define_group_labels
        ppml_het_coefplot, samp(all_jrnls) r1r2(1) public(0)
        ppml_het_coefplot, samp(all_jrnls) r1r2(1) public(1)
        exit
    }
    if $HET_MATCHED_ONLY == 1 {
        cap mkdir ../temp
        cap mkdir "../output/figures/all_jrnls"
        define_group_labels
        add_het_splits, samp(all_jrnls) r1r2(1) public(0)
        matched_career_comparison, samp(all_jrnls) r1r2(1) public(0)
        output_matched_tables, samp(all_jrnls) r1r2(1) public(0)
        exit
    }
    define_group_labels
    local s all_jrnls
    cap mkdir "../output/figures/`s'"
    if $HET_HORSERACE_ONLY == 1 {
        cap mkdir ../temp
        add_het_splits, samp(`s') r1r2(1) public(0)
        add_het_splits, samp(`s') r1r2(1) public(1)
        desc_exposure_by_age, samp(`s') r1r2(1) public(0)
        desc_exposure_by_age, samp(`s') r1r2(1) public(1)
    }
    if $HET_HORSERACE_ONLY == 0 {
        add_het_splits, samp(`s') r1r2(1) public(0)
        desc_pre_output_by_age, samp(`s') r1r2(1) public(0)
        desc_exposure_by_age, samp(`s') r1r2(1) public(0)
        event_study_het, samp(`s') r1r2(1) public(0)
        ppml_age_gradient, samp(`s') r1r2(1) public(0)
    }
    horse_race_nih, samp(`s') r1r2(1) public(0)
    output_het_tables, samp(`s') r1r2(1) public(0)
    output_split_diff_tables, samp(`s') r1r2(1) public(0)
    if $HET_HORSERACE_ONLY == 0 {
        matched_career_comparison, samp(`s') r1r2(1) public(0)
        output_matched_tables, samp(`s') r1r2(1) public(0)
    }

    if $HET_HORSERACE_ONLY == 0 {
        add_het_splits, samp(all_jrnls) r1r2(1) public(1)
        desc_pre_output_by_age, samp(all_jrnls) r1r2(1) public(1)
        desc_exposure_by_age, samp(all_jrnls) r1r2(1) public(1)
        event_study_het, samp(all_jrnls) r1r2(1) public(1)
        ppml_age_gradient, samp(all_jrnls) r1r2(1) public(1)
    }
    horse_race_nih, samp(all_jrnls) r1r2(1) public(1)
    output_het_tables, samp(all_jrnls) r1r2(1) public(1)
    output_split_diff_tables, samp(all_jrnls) r1r2(1) public(1)
    if $HET_HORSERACE_ONLY == 0 {
        matched_career_comparison, samp(all_jrnls) r1r2(1) public(1)
        output_matched_tables, samp(all_jrnls) r1r2(1) public(1)
    }
end

global PI_Q_BASES pre_ppr nihg nihd

program define_group_labels
    global LBL_young        "Early-career PIs"
    global LBL_old          "Late-career PIs"
    global LBL_young_ns     "Early-career PIs (excl. solo)"
    global LBL_old_ns       "Late-career PIs (excl. solo)"
    global LBL_young_any    "Early-career PIs (first pub ever)"
    global LBL_old_any      "Late-career PIs (first pub ever)"
    global LBL_lab_lt10     "Early-career PIs (<10 yrs)"
    global LBL_lab_10_20    "Mid-career PIs (10-20 yrs)"
    global LBL_lab_20p      "Late-career PIs (20+ yrs)"
    global LBL_q1_labage    "Q1 lab age (newest labs)"
    global LBL_q2_labage    "Q2 lab age"
    global LBL_q3_labage    "Q3 lab age"
    global LBL_q4_labage    "Q4 lab age (most established)"
    global LBL_r1           "R1"
    global LBL_r2           "R2"
    global LBL_pub_inst     "Public institutions"
    global LBL_priv_inst    "Private institutions"
    global LBL_high_nihg    "More NIH grants at baseline"
    global LBL_low_nihg     "Fewer NIH grants at baseline"
    global LBL_high_nihd    "More NIH funding at baseline"
    global LBL_low_nihd     "Less NIH funding at baseline"
    global LBL_young_nih    "Early-career PIs (NIH-matched)"
    global LBL_old_nih      "Late-career PIs (NIH-matched)"
    global LBL_young_surv   "Early-career PIs (publishing in 2020-22)"
    global LBL_old_surv     "Late-career PIs"
    global LBL_young_sb     "Early-career PIs (publishing in 2020-22)"
    global LBL_old_sb       "Late-career PIs (publishing in 2020-22)"
    global LBL_y_longtrain  "Early-career PIs, longer training"
    global LBL_y_shorttrain "Early-career PIs, shorter training"
    global LBL_yhigh_nihd   "Early-career, more NIH (young median)"
    global LBL_ylow_nihd    "Early-career, less NIH (young median)"
    global LBL_yq4_nihd     "Early-career, Q4 NIH (young quartiles)"
    global LBL_yq1_nihd     "Early-career, Q1 NIH (young quartiles)"
    global LBL_new_lab      "Newer labs"
    global LBL_est_lab      "Established labs"
    global LBL_big_msa      "Larger MSAs"
    global LBL_small_msa    "Smaller MSAs"

    global LBL_q1_pre_ppr   "Q1 baseline productivity"
    global LBL_q4_pre_ppr   "Q4 baseline productivity"
    global LBL_q1_nihg      "Q1 baseline NIH grants"
    global LBL_q4_nihg      "Q4 baseline NIH grants"
    global LBL_q1_nihd      "Q1 baseline NIH funding"
    global LBL_q4_nihd      "Q4 baseline NIH funding"

    local ic_lbl_contr "Total contract funding"
    local ic_lbl_fdlsb "Federal life-sci biology funding"
    local ic_lbl_fdls  "Federal life-sci funding"
    local ic_lbl_fdlsh "Federal life-sci health-sci funding"
    local ic_lbl_gntsf "Grants funding"
    local ic_lbl_hhlsb "HHS life-sci biology funding"
    local ic_lbl_hhls  "HHS life-sci funding"
    local ic_lbl_hhlsh "HHS life-sci health-sci funding"
    local ic_lbl_nflsb "Non-federal life-sci biology funding"
    local ic_lbl_nfls  "Non-federal life-sci funding"
    local ic_lbl_nflsh "Non-federal life-sci health-sci funding"
    local ic_lbl_subrf "Subrecipient funding"
    local ic_lbl_busf  "Business funding"
    local ic_lbl_fedf  "Total federal funding"
    local ic_lbl_tfnd  "Institutional R&D funding"
    local ic_lbl_instf "Institutional funding"
    local ic_lbl_nonpf "Non-profit funding"
    local ic_lbl_statf "State funding"
    local ic_lbl_lsf   "Institutional life-sci funding"
    local ic_lbl_hsf   "Health-sci funding"
    local ic_lbl_biof  "Biology funding"
    local ic_lbl_applx "Applied research expenditures"
    local ic_lbl_apfx  "Federal applied research expenditures"
    local ic_lbl_basx  "Basic research expenditures"
    local ic_lbl_bfx   "Federal basic research expenditures"
    local ic_lbl_clinx "Clinical trial expenditures"
    local ic_lbl_devx  "Development expenditures"
    local ic_lbl_lscx  "Life-sci capital expenditures"
    local ic_lbl_medx  "Medical school expenditures"
    local ic_lbl_endow "Institutional endowment"
    local ic_lbl_nihd  "NIH funding at baseline"
    global LBL_ic_nihd "`ic_lbl_nihd'"
    global JOINT_AE_CHARS ${IC_ALIASES} nihd
    foreach a of global IC_ALIASES {
        global LBL_ic_`a'   "`ic_lbl_`a''"
        global LBL_hi_`a'   "High `ic_lbl_`a''"
        global LBL_lo_`a'   "Low `ic_lbl_`a''"
        global LBL_q1_`a'   "Q1 `ic_lbl_`a''"
        global LBL_q4_`a'   "Q4 `ic_lbl_`a''"
        global LBL_mid_`a'  "Mid `ic_lbl_`a''"
        global LBL_hiw_`a'  "High `ic_lbl_`a''"
        global LBL_low_`a'  "Low `ic_lbl_`a''"
        global LBL_q1w_`a'  "Q1 `ic_lbl_`a''"
        global LBL_q4w_`a'  "Q4 `ic_lbl_`a''"
        global LBL_midw_`a' "Mid `ic_lbl_`a''"
        global LBL_y_hi_`a' "Early-Career x Hi `ic_lbl_`a''"
        global LBL_y_lo_`a' "Early-Career x Lo `ic_lbl_`a''"
        global LBL_o_hi_`a' "Late-Career x Hi `ic_lbl_`a''"
        global LBL_o_lo_`a' "Late-Career x Lo `ic_lbl_`a''"
    }

    global IC_PAIRS_MED
    global IC_PAIRS_MED_PW
    global IC_PAIRS_Q
    global IC_PAIRS_Q_PW
    foreach a of global IC_ALIASES {
        global IC_PAIRS_MED    `"${IC_PAIRS_MED} "hi_`a' lo_`a'" "'
        global IC_PAIRS_MED_PW `"${IC_PAIRS_MED_PW} "hiw_`a' low_`a'" "'
        global IC_PAIRS_Q      `"${IC_PAIRS_Q} "q4_`a' q1_`a'" "'
        global IC_PAIRS_Q_PW   `"${IC_PAIRS_Q_PW} "q4w_`a' q1w_`a'" "'
    }
    global PI_PAIRS_Q
    foreach b of global PI_Q_BASES {
        global PI_PAIRS_Q `"${PI_PAIRS_Q} "q4_`b' q1_`b'" "'
    }
    global COEFPLOT_PI_PAIRS `" "young old" "r1 r2" "pub_inst priv_inst" "high_nihd low_nihd" "'
end

program add_het_splits
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"

    use ../external/prepped_samples/es_`samp'`suf', clear
    drop nih_total_cost n_grants n_new_grants has_nih
    merge 1:1 athr_id year using ../external/groups/nih_outcomes`suf', assert(3) nogen
    foreach v in nih_grants_baseline nih_funding_baseline nih_funding_baseline_pi {
        cap drop `v'
    }
    merge m:1 athr_id using ../external/groups/pi_groups`suf', assert(3) nogen
    replace min_year = lab_clock_min_year
    drop lab_clock_min_year
    cap drop athr_indicator
    bys athr_id (year): gen athr_indicator = _n == 1
    compress
    save ../temp/es_`samp'`suf', replace
end

program nih_award_period_means
    * Called only for pooled NIH-dollar specifications. Keep the same eligible
    * PIs in both windows; no-award years are already zero in the annual panel.
    * Reject incomplete windows rather than averaging only observed/funded years.
    keep if !mi(nih_total_cost)
    assert inrange(year, 2010, 2019)
    assert nih_total_cost >= 0
    isid athr_id year
    assert post == (year >= 2014)
    quietly ds, has(type numeric)
    local numeric `r(varlist)'
    local exclude athr_id inst_id year post nih_total_cost
    local carry : list numeric - exclude
    collapse (sum) nih_total_cost (count) nih_period_years=year ///
             (firstnm) `carry' inst_id, by(athr_id post)
    assert nih_period_years == cond(post, 6, 4)
    bysort athr_id: assert _N == 2
    replace nih_total_cost = nih_total_cost / cond(post, 6, 4)
    * Existing FE code uses year; here it indexes the two periods.
    gen int year = cond(post, 2014, 2010)
    label var nih_total_cost "Mean annual NIH award dollars: FY2010-2013 / FY2014-2019"
    label var nih_period_years "Calendar years contributing to period mean"
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
                    if "`fmode'" == "paper" {
                        local bs_note `"note("{&beta} = `b_str' (SE: `se_str')", size(small) pos(7) ring(1) justification(left))"'
                        cap mkdir "`fdir'"
                    }
                    binscatter _y_r _Z_r [aw=_fwlw] if `grp' == 1 & !mi(_y_r) & !mi(_Z_r), n(30) ///
                        xtitle("Exposure x post") ///
                        ytitle("{&Delta} log expected `bs_lbl'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                        xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                        msymbol(O) mcolors(gs6) lcolors(ebblue) ///
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
                        if "`fmode'" == "paper" {
                            local bs_note `"note("{&beta} = `b_str' (SE: `se_str')", size(small) pos(7) ring(1) justification(left))"'
                            cap mkdir "`fdir'"
                        }
                        binscatter _y_r _Z_r [aw=_fwlw] if `grp' == 1 & !mi(_y_r) & !mi(_Z_r), n(30) ///
                            xtitle("Exposure x post") ///
                            ytitle("{&Delta} log expected `bs_lbl'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                            xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                            msymbol(O) mcolors(gs6) lcolors(ebblue) ///
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

program ppml_age_gradient
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
    cap mkdir "../output/figures/`samp'"

    local yvar_list ppr_cnt cite_affl_wt
    if "$DEBUG_YVAR" != "" local yvar_list $DEBUG_YVAR
    local ppml_skip avg_position avg_team_size_last avg_team_size_notlast

    use ../temp/es_`samp'`suf', clear
    gen post       = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post

    local binw = $HET_AGE_BINW
    foreach agevar in lab_age_any_2014 lab_age_2014 lab_age_ns_2014 {
    cap confirm variable `agevar'
    if _rc {
        di as error "ppml_age_gradient `samp'`suf': `agevar' not in panel -- skipped."
        continue
    }
    local gpfx labanygrad
    local gtmp lab_any_gradient
    local gxtit "Years since first publication in 2014"
    if "`agevar'" == "lab_age_2014" {
        local gpfx labgrad
        local gtmp lab_gradient
        local gxtit "Years running lab in 2014"
    }
    if "`agevar'" == "lab_age_ns_2014" {
        local gpfx labnsgrad
        local gtmp lab_ns_gradient
        local gxtit "Years running lab in 2014 (excl. solo papers)"
    }
    cap drop agebin
    gen _agebin_pi = floor(min(max(`agevar', 0), $HET_AGE_TOPCODE) / `binw') + 1 if athr_indicator == 1
    bys athr_id: egen agebin = max(_agebin_pi)
    drop _agebin_pi
    qui sum agebin if athr_indicator == 1
    local K = r(max)
    while `K' > 1 {
        gunique athr_id if agebin == `K' & athr_indicator == 1
        if r(unique) >= $HET_AGE_BIN_MINPI continue, break
        replace agebin = `K' - 1 if agebin == `K'
        local --K
    }

    local zvars
    local svars
    local bins_used
    forval k = 1/`K' {
        qui count if agebin == `k' & athr_indicator == 1
        if r(N) == 0 {
            di as error "ppml_age_gradient `samp'`suf': age bin `k' empty -- skipped."
            continue
        }
        cap drop Z_a`k'
        cap drop S_a`k'
        gen Z_a`k' = Z_it       * (agebin == `k')
        gen S_a`k' = Z_share_it * (agebin == `k')
        local zvars `zvars' Z_a`k'
        local svars `svars' S_a`k'
        local bins_used `bins_used' `k'
    }
    local ptvars
    local nb : word count `bins_used'
    forval i = 1/`=`nb'-1' {
        local k : word `i' of `bins_used'
        cap drop PT_a`k'
        gen PT_a`k' = post * (agebin == `k')
        local ptvars `ptvars' PT_a`k'
    }

    foreach yvar of local yvar_list {
        if strpos(" `ppml_skip' ", " `yvar' ") > 0 {
            di as text "ppml_age_gradient: `yvar' not a count outcome -- skipped."
            continue
        }
        local pooled_fes `fes'
        local pooled_vce_cl `vce_cl'
        if "`yvar'" == "nih_total_cost" {
            * Plotting below already uses preserve/restore in this program.
            tempfile annual_nih_age
            quietly save `annual_nih_age', replace
            nih_award_period_means
            local pooled_fes athr_id year
            local pooled_vce_cl athr_id
        }
        local ppml_ytit "Output-cost elasticity"
        if "`yvar'" == "n_grants"       local ppml_ytit "{&Delta} log expected active NIH research grants"
        if "`yvar'" == "n_new_grants"   local ppml_ytit "{&Delta} log expected new NIH research grants"
        if "`yvar'" == "nih_total_cost" local ppml_ytit "{&Delta} log expected average annual NIH award dollars"

        cap noi ppmlhdfe `yvar' `zvars' `svars' `ptvars' if !mi(agebin), ///
            absorb(`pooled_fes') vce(cluster `pooled_vce_cl')
        local rc = _rc
        if `rc' {
            if "`yvar'" == "nih_total_cost" use `annual_nih_age', clear
            di as error "ppml_age_gradient `samp'`suf' `yvar' failed (rc=`rc'); skipping."
            continue
        }
        gunique athr_id if e(sample)
        local n_pis = r(unique)
        gunique inst_id if e(sample)
        local n_insts = r(unique)
        cap mat drop AG
        foreach k of local bins_used {
            if _se[Z_a`k'] == 0 {
                di as error "ppml_age_gradient `samp'`suf' `yvar': Z_a`k' dropped/degenerate -- omitted from plot."
                continue
            }
            qui sum `agevar' if athr_indicator == 1 & agebin == `k'
            mat AG = nullmat(AG) \ (`k', r(mean), (`k' - 0.5) * `binw', r(N), _b[Z_a`k'], _se[Z_a`k'])
        }
        preserve
        clear
        svmat AG
        rename (AG1 AG2 AG3 AG4 AG5 AG6) (bin age_mean age_mid n_pis b se)
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        save ../temp/`gtmp'_`samp'`suf'_`yvar', replace
        qui reg b age_mid [aw=1/(se*se)]
        local slope_lbl = "Slope: " + strtrim(string(_b[age_mid], "%7.3f")) + " (" + strtrim(string(_se[age_mid], "%7.3f")) + ")"
        local xlab
        forval i = 1/`=_N' {
            local k = bin[`i']
            local lo = (`k' - 1) * `binw'
            if `k' == `K' local xlab `xlab' `=age_mid[`i']' "`lo'+"
            else          local xlab `xlab' `=age_mid[`i']' "`lo'-`=`lo' + `binw' - 1'"
        }
        local ygap 0.3
        qui sum ub
        local ymax : di %5.2f ceil(r(max) / `ygap') * `ygap'
        qui sum lb
        local ymin : di %5.2f floor(r(min) / `ygap') * `ygap'
        if `ymin' > 0 local ymin = 0
        if `ymax' < 0 local ymax = 0
        local stats_leg `"legend(on order(- "Num. PIs: `n_pis'" "Num. insts: `n_insts'" "`slope_lbl'") pos(7) ring(1) rows(3) bmargin(zero) size(small))"'
        local fdir ../output/figures/`samp'
        foreach fmode of global FIG_MODES {
            if "`fmode'" == "paper" {
                local stats_leg `"legend(on order(- "`slope_lbl'") pos(7) ring(1) rows(1) bmargin(zero) size(small))"'
                cap mkdir "`fdir'"
            }
            local slope_col = cond("`fmode'" == "paper", "gs8", "dkorange")
            local ylab_m ylab(`ymin'(`ygap')`ymax')
            if "`fmode'" == "paper" local ylab_m ylab(`ymin'(`ygap')`ymax', format(%3.1f))
            tw rcap ub lb age_mid, lcolor(ebblue%70) msize(vsmall) || ///
               scatter b age_mid, mcolor(ebblue) || ///
               lfit b age_mid [aw=1/(se*se)], lcolor(`slope_col') lpattern(dash) ///
               xlab(`xlab', noticks) xsc(r(0 `=`K' * `binw'')) xtitle("`gxtit'") ytitle("`ppml_ytit'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
               `ylab_m' ///
               yline(0, lcolor(gs10) lpattern(solid)) ///
               `stats_leg' ///
               plotregion(margin(sides))
            fig_export, path("`fdir'/`gpfx'_`yvar'`suf'_ppml_mshrctrl.pdf") mode(`fmode')
        }
        restore
        if "`yvar'" == "nih_total_cost" use `annual_nih_age', clear
    }
    }
end

program desc_exposure_by_age
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    cap mkdir "../output/figures/`samp'"

    use ../temp/es_`samp'`suf', clear
    cap confirm variable nih_pi
    if _rc gen byte nih_pi = .
    egen long inst_num = group(inst_id)
    gcollapse (firstnm) exposure young nih_pi inst_num, by(athr_id)
    drop if mi(young) | mi(exposure)

    local tag_all ""
    local tag_nih "_nih"
    local cond_all "1"
    local cond_nih "nih_pi == 1"
    foreach s in all nih {
        qui count if `cond_`s'' & young == 1
        local n_y = r(N)
        qui count if `cond_`s'' & young == 0
        local n_o = r(N)
        if `n_y' == 0 | `n_o' == 0 {
            di as error "desc_exposure_by_age `samp'`suf' [`s']: empty group -- SKIPPED."
            continue
        }
        qui sum exposure if `cond_`s'' & young == 1, d
        local mu_y = strtrim(string(r(mean), "%6.3f"))
        local md_y = strtrim(string(r(p50),  "%6.3f"))
        qui sum exposure if `cond_`s'' & young == 0, d
        local mu_o = strtrim(string(r(mean), "%6.3f"))
        local md_o = strtrim(string(r(p50),  "%6.3f"))
        di as text _n "desc_exposure_by_age `samp'`suf' [`s']: N young = `n_y' (mean=`mu_y' p50=`md_y'), N old = `n_o' (mean=`mu_o' p50=`md_o')"
        cap noi ksmirnov exposure if `cond_`s'', by(young)
        qui reg exposure young if `cond_`s'', vce(cluster inst_num)
        di as text "  young-old diff = " %8.4f _b[young] " (se " %8.4f _se[young] ")"

        qui sum exposure if `cond_`s'', d
        local xcap = r(p99)
        cap drop _kx _kd_y _kd_o _kd_c
        gen _kx = `xcap' * (_n - 1) / 199 if _n <= 200
        kdensity exposure if `cond_`s'' & young == 1 & exposure <= `xcap', at(_kx) gen(_kd_y) nograph
        kdensity exposure if `cond_`s'' & young == 0 & exposure <= `xcap', at(_kx) gen(_kd_o) nograph
        gen _kd_c = min(_kd_y, _kd_o)
        local leg_y "Early-Career (N=`n_y'): mean=`mu_y'"
        local leg_o "Late-Career (N=`n_o'): mean=`mu_o'"
        local kd_leg `"legend(order(3 "`leg_y'" 4 "`leg_o'") pos(2) ring(0) rows(2) size(small))"'
        local fdir ../output/figures/`samp'
        foreach fmode of global FIG_MODES {
            if "`fmode'" == "paper" {
                local kd_leg `"legend(order(3 "${LBL_young}" 4 "${LBL_old}") pos(2) ring(0) rows(2) size(small))"'
                cap mkdir "`fdir'"
            }
            tw (rarea _kd_c _kd_y _kx, color(ebblue*0.3) lwidth(none)) ///
               (rarea _kd_c _kd_o _kx, color(dkorange*0.3) lwidth(none)) ///
               (line _kd_y _kx, lcolor(ebblue) lwidth(medthick)) ///
               (line _kd_o _kx, lcolor(dkorange) lwidth(medthick)) ///
               , xtitle("Exposure measure") ytitle("Density") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                 `kd_leg' ///
                 plotregion(margin(sides))
            fig_export, path("`fdir'/desc_kd_exposure`tag_`s''`suf'.pdf") mode(`fmode')
        }
        cap drop _kx _kd_y _kd_o _kd_c
    }
end

program desc_pre_output_by_age
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    cap mkdir "../output/figures/`samp'"

    use ../temp/es_`samp'`suf', clear
    keep if year < 2014
    qui sum year
    local y0 = r(min)
    local y1 = r(max)

    local sum_src   ppr_cnt cite_affl_wt n_first_ppr n_last_ppr
    local sum_alias ppr_tot cite         first       last
    local mean_src   ppr_cnt
    local mean_alias ppr_yr
    local lbl_ppr_tot "total papers"
    local lbl_ppr_yr  "papers per year"
    local lbl_cite    "affiliation-weighted citations"
    local lbl_first   "first-authored papers"
    local lbl_last    "last-authored papers"
    local fmt_ppr_tot %6.1f
    local fmt_ppr_yr  %5.2f
    local fmt_cite    %8.1f
    local fmt_first   %6.1f
    local fmt_last    %6.1f

    local coll_sum
    local coll_mean
    local keep_alias
    foreach stat in sum mean {
        local nsrc : word count ``stat'_src'
        forvalues i = 1/`nsrc' {
            local src : word `i' of ``stat'_src'
            local a   : word `i' of ``stat'_alias'
            cap confirm variable `src'
            if _rc {
                di as error "desc_pre_output_by_age `samp'`suf': `src' not in panel -- `a' density SKIPPED."
                continue
            }
            local coll_`stat' `coll_`stat'' pre_`a'=`src'
            local keep_alias `keep_alias' `a'
        }
    }
    if "`keep_alias'" == "" {
        di as error "desc_pre_output_by_age `samp'`suf': no outcomes available -- nothing plotted."
        exit
    }
    local coll_sum_part = cond("`coll_sum'" == "", "", "(sum) `coll_sum'")
    local coll_mean_part = cond("`coll_mean'" == "", "", "(mean) `coll_mean'")

    egen long inst_num = group(inst_id)
    gcollapse `coll_sum_part' `coll_mean_part' (firstnm) young inst_num, by(athr_id)
    drop if mi(young)

    qui count if young == 1
    local n_y = r(N)
    qui count if young == 0
    local n_o = r(N)
    di as text _n "desc_pre_output_by_age `samp'`suf': pre-period = `y0'-`y1', N young = `n_y', N old = `n_o'"

    foreach a of local keep_alias {
        local f "`fmt_`a''"
        qui sum pre_`a' if young == 1, d
        local mu_y = strtrim(string(r(mean), "`f'"))
        local md_y = strtrim(string(r(p50),  "`f'"))
        qui sum pre_`a' if young == 0, d
        local mu_o = strtrim(string(r(mean), "`f'"))
        local md_o = strtrim(string(r(p50),  "`f'"))
        local leg_y "Early-Career (N=`n_y'): mean=`mu_y'"
        local leg_o "Late-Career (N=`n_o'): mean=`mu_o'"
        di as text "  `a': young mean=`mu_y' p50=`md_y' | old mean=`mu_o' p50=`md_o'"
        cap noi ksmirnov pre_`a', by(young)
        qui reg pre_`a' young, vce(cluster inst_num)
        di as text "  `a': young-old diff = " %8.3f _b[young] " (se " %8.3f _se[young] ")"

        gen double ln_pre_`a' = ln(1 + pre_`a')
        qui sum ln_pre_`a'
        cap drop _kx _kd_y _kd_o _kd_c
        gen _kx = r(min) + (r(max) - r(min)) * (_n - 1) / 199 if _n <= 200
        kdensity ln_pre_`a' if young == 1, at(_kx) gen(_kd_y) nograph
        kdensity ln_pre_`a' if young == 0, at(_kx) gen(_kd_o) nograph
        gen _kd_c = min(_kd_y, _kd_o)
        local kd_leg `"legend(order(3 "`leg_y'" 4 "`leg_o'") pos(2) ring(0) rows(2) size(small))"'
        local fdir ../output/figures/`samp'
        foreach fmode of global FIG_MODES {
            if "`fmode'" == "paper" {
                local kd_leg `"legend(order(3 "${LBL_young}" 4 "${LBL_old}") pos(2) ring(0) rows(2) size(small))"'
                cap mkdir "`fdir'"
            }
            tw (rarea _kd_c _kd_y _kx, color(ebblue*0.3) lwidth(none)) ///
               (rarea _kd_c _kd_o _kx, color(dkorange*0.3) lwidth(none)) ///
               (line _kd_y _kx, lcolor(ebblue) lwidth(medthick)) ///
               (line _kd_o _kx, lcolor(dkorange) lwidth(medthick)) ///
               , xtitle("ln(1 + pre-period `lbl_`a'', `y0'-`y1')") ytitle("Density") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                 `kd_leg' ///
                 plotregion(margin(sides))
            fig_export, path("`fdir'/desc_kd_pre_`a'_ln`suf'.pdf") mode(`fmode')
        }

        qui sum pre_`a', d
        local xcap = r(p95)
        cap drop _kx _kd_y _kd_o _kd_c
        gen _kx = `xcap' * (_n - 1) / 199 if _n <= 200
        kdensity pre_`a' if young == 1 & pre_`a' <= `xcap', at(_kx) gen(_kd_y) nograph
        kdensity pre_`a' if young == 0 & pre_`a' <= `xcap', at(_kx) gen(_kd_o) nograph
        gen _kd_c = min(_kd_y, _kd_o)
        local kd_leg `"legend(order(3 "`leg_y'" 4 "`leg_o'") pos(2) ring(0) rows(2) size(small))"'
        local fdir ../output/figures/`samp'
        foreach fmode of global FIG_MODES {
            if "`fmode'" == "paper" {
                local kd_leg `"legend(order(3 "${LBL_young}" 4 "${LBL_old}") pos(2) ring(0) rows(2) size(small))"'
                cap mkdir "`fdir'"
            }
            tw (rarea _kd_c _kd_y _kx, color(ebblue*0.3) lwidth(none)) ///
               (rarea _kd_c _kd_o _kx, color(dkorange*0.3) lwidth(none)) ///
               (line _kd_y _kx, lcolor(ebblue) lwidth(medthick)) ///
               (line _kd_o _kx, lcolor(dkorange) lwidth(medthick)) ///
               , xtitle("Pre-period `lbl_`a'', `y0'-`y1' (x capped at pooled p95)") ytitle("Density") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                 `kd_leg' ///
                 plotregion(margin(sides))
            fig_export, path("`fdir'/desc_kd_pre_`a'_raw`suf'.pdf") mode(`fmode')
        }
        cap drop _kx _kd_y _kd_o _kd_c
    }

    save ../temp/desc_pre_output_`samp'`suf', replace
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
        di as error "horse_race_nih `samp'`suf': ../temp/es_`samp'`suf'.dta not found -- run add_het_splits first."
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

program matched_career_comparison
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
    cap mkdir "../output/figures/`samp'"
    cap mkdir "../output/figures/`samp'/matched"

    use ../temp/es_`samp'`suf', clear
    foreach v in young old nih_pi cluster_30 pre_ppr_cnt_sum pre_nihd lab_age_2014 {
        cap confirm variable `v'
        if _rc {
            di as error "matched_career_comparison `samp'`suf': `v' not in panel -- SKIPPED."
            exit
        }
    }
    keep if !mi(young)
    foreach v in post post1 post2 cell cs w_cem out_bin fund_bin {
        cap drop `v'
    }
    gen _pre_cite = cite_affl_wt if year < 2014
    bys athr_id: egen pre_cite_sum = total(_pre_cite)
    drop _pre_cite
    gen byte any_award = nih_pi == 1 & !mi(pre_nihd)
    gen double ln_nihd = cond(any_award == 1, ln(1 + pre_nihd), 0) if nih_pi == 1
    gen double ln_pre_out = ln(pre_ppr_cnt_sum)
    gen byte post  = year >= 2014
    gen byte post1 = inrange(year, 2014, 2016)
    gen byte post2 = inrange(year, 2017, 2019)
    foreach g in young old {
        gen Z_`g' = exposure      * post * `g'
        gen S_`g' = mkt_spend_shr * post * `g'
        foreach k in 1 2 {
            gen Z`k'_`g' = exposure      * post`k' * `g'
            gen S`k'_`g' = mkt_spend_shr * post`k' * `g'
        }
    }
    gen PT_young  = post  * young
    gen PT1_young = post1 * young
    gen PT2_young = post2 * young
    save ../temp/matched_panel_`samp'`suf', replace

    local bal_vars_all lab_age_2014 pre_ppr_cnt_sum pre_cite_sum exposure mkt_spend_shr
    local bal_vars_nih `bal_vars_all' ln_nihd any_award
    foreach u in nih all {
        use ../temp/matched_panel_`samp'`suf', clear
        keep if athr_indicator == 1
        if "`u'" == "nih" keep if nih_pi == 1
        xtile out_bin = pre_ppr_cnt_sum, nq($HET_MATCH_OUT_BINS)
        if "`u'" == "nih" {
            xtile fund_bin = pre_nihd if any_award == 1, nq($HET_MATCH_FUND_BINS)
            replace fund_bin = 0 if any_award == 0
            egen long cell = group(cluster_30 out_bin fund_bin)
        }
        else {
            gen byte fund_bin = .
            egen long cell = group(cluster_30 out_bin)
        }
        bys cell: egen n_y_cell = total(young == 1)
        bys cell: egen n_o_cell = total(young == 0)
        gen byte cs = n_y_cell > 0 & n_o_cell > 0
        qui count if cs == 1 & young == 1
        local N_y = r(N)
        qui count if cs == 1 & young == 0
        local N_o = r(N)
        gen double w_cem = cond(young == 1, 1, (n_y_cell / n_o_cell) * (`N_o' / `N_y')) if cs == 1
        gunique cell
        local n_cells = r(unique)
        gunique cell if cs == 1
        local n_cells_cs = r(unique)
        qui count if young == 1
        local n_y_all = r(N)
        qui count if young == 0
        local n_o_all = r(N)
        di as text "matched_career_comparison `samp'`suf' [`u']: `n_cells' cells (`n_cells_cs' with both career stages); " ///
            "early-career PIs in common support `N_y'/`n_y_all', late-career `N_o'/`n_o_all'"
        mat mcs_`u'`suf' = (`n_cells', `n_cells_cs', `n_y_all', `N_y', `n_o_all', `N_o', ., ., ., .)
        mat colnames mcs_`u'`suf' = n_cells n_cells_cs n_young n_young_cs n_old n_old_cs ps_lo ps_hi ps_share_young ps_share_old

        cap mat drop mbal_`u'`suf'
        local bal_rows
        foreach v of local bal_vars_`u' {
            qui sum `v' if young == 1
            local m_y0 = r(mean)
            local v_y0 = r(Var)
            qui sum `v' if young == 0
            local m_o0 = r(mean)
            local v_o0 = r(Var)
            local sd_pool = sqrt((`v_y0' + `v_o0') / 2)
            if `sd_pool' == 0 continue
            qui sum `v' if young == 1 & cs == 1
            local m_y1 = r(mean)
            qui sum `v' [aw=w_cem] if young == 0 & cs == 1
            local m_o1 = r(mean)
            mat mbal_`u'`suf' = nullmat(mbal_`u'`suf') \ ///
                (`m_y0', `m_o0', (`m_y0' - `m_o0') / `sd_pool', `m_y1', `m_o1', (`m_y1' - `m_o1') / `sd_pool')
            local bal_rows `bal_rows' `v'
        }
        qui levelsof cluster_30, local(clusters)
        local sum_abs0 0
        local sum_abs1 0
        local max_abs0 0
        local max_abs1 0
        local n_cl 0
        foreach c of local clusters {
            cap drop _cl
            gen byte _cl = cluster_30 == `c'
            qui sum _cl if young == 1
            local m_y0 = r(mean)
            local v_y0 = r(Var)
            qui sum _cl if young == 0
            local m_o0 = r(mean)
            local v_o0 = r(Var)
            local sd_pool = sqrt((`v_y0' + `v_o0') / 2)
            if `sd_pool' == 0 continue
            qui sum _cl if young == 1 & cs == 1
            local m_y1 = r(mean)
            qui sum _cl [aw=w_cem] if young == 0 & cs == 1
            local m_o1 = r(mean)
            local a0 = abs((`m_y0' - `m_o0') / `sd_pool')
            local a1 = abs((`m_y1' - `m_o1') / `sd_pool')
            local sum_abs0 = `sum_abs0' + `a0'
            local sum_abs1 = `sum_abs1' + `a1'
            local max_abs0 = max(`max_abs0', `a0')
            local max_abs1 = max(`max_abs1', `a1')
            local ++n_cl
        }
        cap drop _cl
        if `n_cl' > 0 {
            mat mbal_`u'`suf' = mbal_`u'`suf' \ (., ., `sum_abs0' / `n_cl', ., ., `sum_abs1' / `n_cl')
            mat mbal_`u'`suf' = mbal_`u'`suf' \ (., ., `max_abs0', ., ., `max_abs1')
            local bal_rows `bal_rows' topic_mean_abs topic_max_abs
        }
        mat rownames mbal_`u'`suf' = `bal_rows'
        mat colnames mbal_`u'`suf' = mean_early mean_late smd mean_early_cs mean_late_rw smd_rw
        di as result _n "== balance `samp'`suf' [`u']: early minus late, standardized; before | common support with late-career reweighted =="
        matlist mbal_`u'`suf', format(%9.3f) lines(oneline)

        if "`u'" == "nih" {
            cap noi logit young i.cluster_30 c.ln_pre_out c.ln_nihd i.any_award, iterate(100)
            local rc = _rc
            if `rc' di as error "matched_career_comparison `samp'`suf': propensity logit failed (rc=`rc'); overlap figure skipped."
            else {
                predict double ps, pr
                qui sum ps if young == 1
                local ps_y_lo = r(min)
                local ps_y_hi = r(max)
                qui sum ps if young == 0
                local ps_lo = max(`ps_y_lo', r(min))
                local ps_hi = min(`ps_y_hi', r(max))
                qui count if young == 1 & inrange(ps, `ps_lo', `ps_hi')
                local sh_y = r(N) / `n_y_all'
                qui count if young == 0 & inrange(ps, `ps_lo', `ps_hi')
                local sh_o = r(N) / `n_o_all'
                di as text "matched_career_comparison `samp'`suf' [nih]: propensity-score overlap [" %5.3f `ps_lo' ", " %5.3f `ps_hi' ///
                    "] holds " %5.1f 100 * `sh_y' "% of early-career and " %5.1f 100 * `sh_o' "% of late-career PIs"
                mat mcs_`u'`suf'[1, 7]  = `ps_lo'
                mat mcs_`u'`suf'[1, 8]  = `ps_hi'
                mat mcs_`u'`suf'[1, 9]  = `sh_y'
                mat mcs_`u'`suf'[1, 10] = `sh_o'
                cap drop _kx _kd_y _kd_o _kd_c
                gen _kx = (_n - 1) / 199 if _n <= 200
                kdensity ps if young == 1, at(_kx) gen(_kd_y) nograph
                kdensity ps if young == 0, at(_kx) gen(_kd_o) nograph
                gen _kd_c = min(_kd_y, _kd_o)
                tw (rarea _kd_c _kd_y _kx, color(ebblue*0.3) lwidth(none)) ///
                   (rarea _kd_c _kd_o _kx, color(dkorange*0.3) lwidth(none)) ///
                   (line _kd_y _kx, lcolor(ebblue) lwidth(medthick)) ///
                   (line _kd_o _kx, lcolor(dkorange) lwidth(medthick)) ///
                   , xtitle("Estimated probability of being early-career") ytitle("Density") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                     xlab(0(0.2)1) ///
                     legend(order(3 "${LBL_young}" 4 "${LBL_old}") pos(2) ring(0) rows(2) size(small)) ///
                     plotregion(margin(sides))
                fig_export, path("../output/figures/`samp'/matched/pscore_overlap`suf'.pdf")
                cap drop _kx _kd_y _kd_o _kd_c ps
            }

            preserve
            clear
            local nb = rowsof(mbal_nih`suf')
            local rn : rownames mbal_nih`suf'
            svmat double mbal_nih`suf', names(col)
            gen str32 rowname = ""
            forval i = 1/`nb' {
                replace rowname = "`: word `i' of `rn''" in `i'
            }
            drop if inlist(rowname, "lab_age_2014", "topic_max_abs")
            gen y = _N - _n + 1
            local ylabs
            forval i = 1/`=_N' {
                local rname = rowname[`i']
                local lbl "`rname'"
                if "`rname'" == "pre_ppr_cnt_sum" local lbl "Pre-merger last-author papers"
                if "`rname'" == "pre_cite_sum"    local lbl "Pre-merger citation-weighted output"
                if "`rname'" == "ln_nihd"         local lbl "Log baseline NIH funding"
                if "`rname'" == "any_award"       local lbl "Any baseline NIH research award"
                if "`rname'" == "exposure"        local lbl "Exposure"
                if "`rname'" == "mkt_spend_shr"   local lbl "Treated-market spending share"
                if "`rname'" == "topic_mean_abs"  local lbl "Research topic (mean abs. diff. across clusters)"
                local ylabs `"`ylabs' `=y[`i']' "`lbl'""'
            }
            qui sum smd
            local xmin = min(-0.5, floor(r(min) / 0.25) * 0.25)
            local xmax = max(0.5, ceil(r(max) / 0.25) * 0.25)
            tw scatter y smd, mcolor(dkorange) msymbol(D) msize(small) || ///
               scatter y smd_rw, mcolor(ebblue) msymbol(O) msize(small) ///
               , xline(0, lcolor(gs10) lpattern(solid)) xline(-0.1 0.1, lcolor(gs12) lpattern(dash)) ///
                 ylabel(`ylabs', angle(0) labsize(small) noticks nogrid) ytitle("") ///
                 xtitle("Standardized difference, early minus late career", size(medsmall)) ///
                 xlabel(`xmin'(0.25)`xmax', labsize(small)) ///
                 legend(order(1 "Before matching" 2 "After matching") pos(6) ring(1) rows(1) size(small)) ///
                 ysize(4) xsize(8) yscale(range(0.5 `=_N + 0.5')) ///
                 plotregion(margin(l=zero r=zero b=zero t=vsmall))
            fig_export, path("../output/figures/`samp'/matched/balance`suf'.pdf") xsize(8) ysize(4)
            restore
        }
        keep athr_id cell out_bin fund_bin cs w_cem
        save ../temp/matched_w_`u'_`samp'`suf', replace
    }

    local yvar_list ppr_cnt cite_affl_wt
    if "$DEBUG_YVAR" != "" local yvar_list $DEBUG_YVAR
    local specs all_unm nih_unm nih_cs nih_cem all_cem
    local per_specs all_unm nih_unm nih_cem
    foreach yvar of local yvar_list {
        if "`yvar'" == "nih_total_cost" {
            di as text "matched_career_comparison: `yvar' uses period means elsewhere -- skipped."
            continue
        }
        mat mcar_`yvar'`suf' = J(5, 11, .)
        mat rownames mcar_`yvar'`suf' = `specs'
        mat colnames mcar_`yvar'`suf' = b_young se_young b_old se_old b_diff se_diff p_diff N n_pis_young n_pis_old n_cells
        mat mper_`yvar'`suf' = J(3, 21, .)
        mat rownames mper_`yvar'`suf' = `per_specs'
        mat colnames mper_`yvar'`suf' = b_young1 se_young1 b_old1 se_old1 b_diff1 se_diff1 p_diff1 ///
                                        b_young2 se_young2 b_old2 se_old2 b_diff2 se_diff2 p_diff2 ///
                                        b_gapchg se_gapchg p_gapchg b_young21 se_young21 p_young21 N
        local r 0
        foreach spec of local specs {
            local ++r
            local u = substr("`spec'", 1, 3)
            use ../temp/matched_panel_`samp'`suf', clear
            merge m:1 athr_id using ../temp/matched_w_`u'_`samp'`suf', keep(3) nogen
            local wt ""
            if inlist("`spec'", "nih_cs", "nih_cem", "all_cem") keep if cs == 1
            if inlist("`spec'", "nih_cem", "all_cem") local wt "[pw=w_cem]"
            cap noi ppmlhdfe `yvar' Z_young Z_old S_young S_old PT_young `wt', ///
                absorb(`fes') vce(cluster `vce_cl')
            local rc = _rc
            if `rc' {
                di as error "matched_career_comparison `samp'`suf' `yvar' `spec' pooled ppml failed (rc=`rc'); row left missing."
                continue
            }
            local Nppml = e(N)
            gunique athr_id if e(sample) & young == 1
            local n_y = r(unique)
            gunique athr_id if e(sample) & young == 0
            local n_o = r(unique)
            gunique cell if e(sample)
            local n_cells = r(unique)
            local b_y  = _b[Z_young]
            local se_y = _se[Z_young]
            local b_o  = _b[Z_old]
            local se_o = _se[Z_old]
            qui lincom Z_young - Z_old
            mat mcar_`yvar'`suf'[`r', 1]  = `b_y'
            mat mcar_`yvar'`suf'[`r', 2]  = `se_y'
            mat mcar_`yvar'`suf'[`r', 3]  = `b_o'
            mat mcar_`yvar'`suf'[`r', 4]  = `se_o'
            mat mcar_`yvar'`suf'[`r', 5]  = r(estimate)
            mat mcar_`yvar'`suf'[`r', 6]  = r(se)
            mat mcar_`yvar'`suf'[`r', 7]  = r(p)
            mat mcar_`yvar'`suf'[`r', 8]  = `Nppml'
            mat mcar_`yvar'`suf'[`r', 9]  = `n_y'
            mat mcar_`yvar'`suf'[`r', 10] = `n_o'
            mat mcar_`yvar'`suf'[`r', 11] = `n_cells'
            di as text "matched PPML `samp'`suf' `yvar' `spec': early=" %8.4f `b_y' " (" %6.4f `se_y' ")  late=" %8.4f `b_o' ///
                " (" %6.4f `se_o' ")  diff=" %8.4f r(estimate) " (" %6.4f r(se) ") p=" %6.4f r(p) ///
                "  N=" %9.0f `Nppml' " PIs=`n_y'/`n_o' cells=`n_cells'"

            if strpos(" `per_specs' ", " `spec' ") == 0 continue
            local pr : list posof "`spec'" in per_specs
            cap noi ppmlhdfe `yvar' Z1_young Z1_old Z2_young Z2_old S1_young S1_old S2_young S2_old ///
                PT1_young PT2_young `wt', absorb(`fes') vce(cluster `vce_cl')
            local rc = _rc
            if `rc' {
                di as error "matched_career_comparison `samp'`suf' `yvar' `spec' window ppml failed (rc=`rc'); persistence row left missing."
                continue
            }
            mat mper_`yvar'`suf'[`pr', 21] = e(N)
            foreach k in 1 2 {
                local c0 = cond(`k' == 1, 0, 7)
                mat mper_`yvar'`suf'[`pr', `c0' + 1] = _b[Z`k'_young]
                mat mper_`yvar'`suf'[`pr', `c0' + 2] = _se[Z`k'_young]
                mat mper_`yvar'`suf'[`pr', `c0' + 3] = _b[Z`k'_old]
                mat mper_`yvar'`suf'[`pr', `c0' + 4] = _se[Z`k'_old]
                qui lincom Z`k'_young - Z`k'_old
                mat mper_`yvar'`suf'[`pr', `c0' + 5] = r(estimate)
                mat mper_`yvar'`suf'[`pr', `c0' + 6] = r(se)
                mat mper_`yvar'`suf'[`pr', `c0' + 7] = r(p)
            }
            qui lincom (Z2_young - Z2_old) - (Z1_young - Z1_old)
            mat mper_`yvar'`suf'[`pr', 15] = r(estimate)
            mat mper_`yvar'`suf'[`pr', 16] = r(se)
            mat mper_`yvar'`suf'[`pr', 17] = r(p)
            qui lincom Z2_young - Z1_young
            mat mper_`yvar'`suf'[`pr', 18] = r(estimate)
            mat mper_`yvar'`suf'[`pr', 19] = r(se)
            mat mper_`yvar'`suf'[`pr', 20] = r(p)
            di as text "matched PPML windows `samp'`suf' `yvar' `spec': 2014-16 early=" %8.4f _b[Z1_young] " late=" %8.4f _b[Z1_old] ///
                "  2017-19 early=" %8.4f _b[Z2_young] " late=" %8.4f _b[Z2_old] ///
                "  gap change=" %8.4f mper_`yvar'`suf'[`pr', 15] " (" %6.4f mper_`yvar'`suf'[`pr', 16] ") p=" %6.4f mper_`yvar'`suf'[`pr', 17]
        }

        matched_coefplot, samp(`samp') yvar(`yvar') suf(`suf')
    }
end

program matched_coefplot
    syntax, samp(string) yvar(string) [suf(string)]
    cap confirm matrix mcar_`yvar'`suf'
    if _rc exit 0
    preserve
    clear
    set obs 10
    gen byte row   = ceil(_n / 2)
    gen byte early = mod(_n, 2) == 1
    gen double b  = .
    gen double se = .
    local i 0
    foreach spec in all_unm nih_unm nih_cem {
        local ++i
        local rr = rownumb(mcar_`yvar'`suf', "`spec'")
        qui replace b  = mcar_`yvar'`suf'[`rr', 1] if row == `i' & early == 1
        qui replace se = mcar_`yvar'`suf'[`rr', 2] if row == `i' & early == 1
        qui replace b  = mcar_`yvar'`suf'[`rr', 3] if row == `i' & early == 0
        qui replace se = mcar_`yvar'`suf'[`rr', 4] if row == `i' & early == 0
    }
    local rr = rownumb(mper_`yvar'`suf', "nih_cem")
    foreach k in 1 2 {
        local ++i
        local c0 = cond(`k' == 1, 0, 7)
        qui replace b  = mper_`yvar'`suf'[`rr', `c0' + 1] if row == `i' & early == 1
        qui replace se = mper_`yvar'`suf'[`rr', `c0' + 2] if row == `i' & early == 1
        qui replace b  = mper_`yvar'`suf'[`rr', `c0' + 3] if row == `i' & early == 0
        qui replace se = mper_`yvar'`suf'[`rr', `c0' + 4] if row == `i' & early == 0
    }
    drop if mi(b)
    if _N > 0 {
        gen ub = b + 1.96 * se
        gen lb = b - 1.96 * se
        gen double y = cond(row <= 3, 8 - row, 7.5 - row) + cond(early == 1, 0.15, -0.15)
        local ylabs `"7 "All PIs" 6 "PIs with NIH records" 5 "Matched on topic, pre-merger output, and NIH funding" 3.5 "Matched, 2014-2016" 2.5 "Matched, 2017-2019""'
        qui sum lb
        local xmin = floor(r(min) / 0.5) * 0.5
        qui sum ub
        local xmax = ceil(r(max) / 0.5) * 0.5
        tw rcap ub lb y if early == 1, horizontal lcolor(ebblue%70) msize(vsmall) || ///
           scatter y b if early == 1, mcolor(ebblue) msize(small) || ///
           rcap ub lb y if early == 0, horizontal lcolor(dkorange%70) msize(vsmall) || ///
           scatter y b if early == 0, mcolor(dkorange) msymbol(D) msize(small) ///
           , xline(0, lcolor(gs10) lpattern(solid)) yline(4.25, lcolor(gs12) lpattern(dash)) ///
             ylabel(`ylabs', angle(0) labsize(small) noticks nogrid) ytitle("") ///
             xtitle("Output-cost elasticity", size(medsmall)) xlabel(`xmin'(0.5)`xmax', labsize(small)) ///
             legend(order(2 "${LBL_young}" 4 "${LBL_old}") pos(6) ring(1) rows(1) size(small)) ///
             ysize(4) xsize(8) yscale(range(1.9 7.6)) ///
             plotregion(margin(l=zero r=zero b=zero t=vsmall))
        fig_export, path("../output/figures/`samp'/matched/coefplot_`yvar'`suf'.pdf") xsize(8) ysize(4)
    }
    restore
end

program _mc_fmt, rclass
    args b se
    if mi(`b') | mi(`se') {
        return local b_s "--"
        return local se_s ""
        exit
    }
    local t = abs(`b' / `se')
    local st = cond(`t' >= 2.576, "^{***}", cond(`t' >= 1.960, "^{**}", cond(`t' >= 1.645, "^{*}", "")))
    local b_s  : dis %7.3f `b'
    local se_s : dis %7.3f `se'
    return local b_s  "$`b_s'`st'$"
    return local se_s "($`se_s'$)"
end

program _mc_num, rclass
    args v fmt
    if mi(`v') {
        return local s ""
        exit
    }
    local s : dis `fmt' `v'
    local s = strtrim("`s'")
    return local s "`s'"
end

program write_matched_tex
    syntax, samp(string) yvar(string) [suf(string)]
    cap confirm matrix mcar_`yvar'`suf'
    if _rc exit 0
    local out ../output/tables/`samp'/matched_career_`yvar'`suf'.tex
    local lbl_all_unm "All PIs"
    local lbl_nih_unm "PIs with NIH records"
    local lbl_nih_cs  "\quad Common support on topic $\times$ output $\times$ funding"
    local lbl_nih_cem "\quad Common support, late-career reweighted"
    local lbl_all_cem "All PIs, common support on topic $\times$ output, reweighted"
    local plbl_all_unm "All PIs"
    local plbl_nih_cem "Matched PIs"
    tempname fh
    file open `fh' using "`out'", write replace
    file write `fh' "\begin{table}[htbp]" _n
    file write `fh' "\centering" _n
    file write `fh' "\caption{Career Stage and the Output Response among Comparable PIs}" _n
    file write `fh' "\label{tab:matched_career_`yvar'`suf'}" _n
    file write `fh' "\begin{tabular}{lcccc}" _n
    file write `fh' "\toprule" _n
    file write `fh' " & Early-career PIs & Late-career PIs & Difference & PIs (early / late) \\" _n
    file write `fh' "\midrule" _n
    file write `fh' "\multicolumn{5}{l}{\textit{Panel A: Pooled post-period, 2014--2019}} \\" _n
    foreach spec in all_unm nih_unm nih_cs nih_cem all_cem {
        local rr = rownumb(mcar_`yvar'`suf', "`spec'")
        if mi(mcar_`yvar'`suf'[`rr', 1]) continue
        local line_b  "`lbl_`spec''"
        local line_se ""
        forval j = 1(2)5 {
            _mc_fmt `=mcar_`yvar'`suf'[`rr', `j']' `=mcar_`yvar'`suf'[`rr', `j' + 1]'
            local line_b  "`line_b' & `r(b_s)'"
            local line_se "`line_se' & `r(se_s)'"
        }
        _mc_num `=mcar_`yvar'`suf'[`rr', 9]' %9.0fc
        local n_y "`r(s)'"
        _mc_num `=mcar_`yvar'`suf'[`rr', 10]' %9.0fc
        local n_o "`r(s)'"
        file write `fh' "`line_b' & `n_y' / `n_o' \\" _n
        file write `fh' "`line_se' & \\" _n
    }
    cap confirm matrix mper_`yvar'`suf'
    if !_rc {
        file write `fh' "\addlinespace" _n
        file write `fh' "\multicolumn{5}{l}{\textit{Panel B: Persistence of the career-stage gap}} \\" _n
        foreach spec in all_unm nih_cem {
            local rr = rownumb(mper_`yvar'`suf', "`spec'")
            if mi(mper_`yvar'`suf'[`rr', 1]) continue
            local rc_ = rownumb(mcar_`yvar'`suf', "`spec'")
            _mc_num `=mcar_`yvar'`suf'[`rc_', 9]' %9.0fc
            local n_y "`r(s)'"
            _mc_num `=mcar_`yvar'`suf'[`rc_', 10]' %9.0fc
            local n_o "`r(s)'"
            foreach k in 1 2 {
                local c0 = cond(`k' == 1, 0, 7)
                local win = cond(`k' == 1, "2014--2016", "2017--2019")
                local line_b  "`plbl_`spec'', `win'"
                local line_se ""
                forval j = 1(2)5 {
                    _mc_fmt `=mper_`yvar'`suf'[`rr', `c0' + `j']' `=mper_`yvar'`suf'[`rr', `c0' + `j' + 1]'
                    local line_b  "`line_b' & `r(b_s)'"
                    local line_se "`line_se' & `r(se_s)'"
                }
                file write `fh' "`line_b' & `n_y' / `n_o' \\" _n
                file write `fh' "`line_se' & \\" _n
            }
            _mc_fmt `=mper_`yvar'`suf'[`rr', 15]' `=mper_`yvar'`suf'[`rr', 16]'
            file write `fh' "\quad Change in gap, 2017--19 minus 2014--16 & & & `r(b_s)' & \\" _n
            file write `fh' " & & & `r(se_s)' & \\" _n
            file write `fh' "\addlinespace" _n
        }
    }
    file write `fh' "\bottomrule" _n
    file write `fh' "\end{tabular}" _n
    file write `fh' "\end{table}" _n
    file close `fh'
    di as text "wrote `out'"
end

program write_matched_balance_tex
    syntax, samp(string) [suf(string)]
    cap confirm matrix mbal_nih`suf'
    if _rc exit 0
    local out ../output/tables/`samp'/matched_balance`suf'.tex
    local lbl_lab_age_2014    "Years running lab in 2014"
    local lbl_pre_ppr_cnt_sum "Pre-merger last-author papers, 2010--2013"
    local lbl_pre_cite_sum    "Pre-merger citation-weighted output"
    local lbl_exposure        "Exposure"
    local lbl_mkt_spend_shr   "Treated-market spending share"
    local lbl_ln_nihd         "Log baseline NIH funding (zero if no award)"
    local lbl_any_award       "Any baseline NIH research award"
    local lbl_topic_mean_abs  "Research topic, mean abs.\ std.\ diff.\ across clusters"
    local lbl_topic_max_abs   "Research topic, max abs.\ std.\ diff.\ across clusters"
    local fmt_lab_age_2014    %9.1f
    local fmt_pre_ppr_cnt_sum %9.1f
    local fmt_pre_cite_sum    %9.1f
    local fmt_exposure        %9.3f
    local fmt_mkt_spend_shr   %9.3f
    local fmt_ln_nihd         %9.2f
    local fmt_any_award       %9.2f
    tempname fh
    file open `fh' using "`out'", write replace
    file write `fh' "\begin{table}[htbp]" _n
    file write `fh' "\centering" _n
    file write `fh' "\caption{Covariate Balance: Early- versus Late-Career PIs with NIH Records}" _n
    file write `fh' "\label{tab:matched_balance`suf'}" _n
    file write `fh' "\begin{tabular}{lcccccc}" _n
    file write `fh' "\toprule" _n
    file write `fh' " & \multicolumn{3}{c}{All PIs with NIH records} & \multicolumn{3}{c}{Common support, late-career reweighted} \\" _n
    file write `fh' "\cmidrule(lr){2-4} \cmidrule(lr){5-7}" _n
    file write `fh' " & Early & Late & Std.\ diff. & Early & Late & Std.\ diff. \\" _n
    file write `fh' "\midrule" _n
    local rn : rownames mbal_nih`suf'
    local nb = rowsof(mbal_nih`suf')
    forval i = 1/`nb' {
        local v : word `i' of `rn'
        local lbl "`lbl_`v''"
        if "`lbl'" == "" local lbl "`v'"
        local f "`fmt_`v''"
        if "`f'" == "" local f %9.3f
        local line "`lbl'"
        forval j = 1/6 {
            local cf = cond(inlist(`j', 3, 6), "%9.3f", "`f'")
            _mc_num `=mbal_nih`suf'[`i', `j']' `cf'
            local line "`line' & `r(s)'"
        }
        file write `fh' "`line' \\" _n
    }
    cap confirm matrix mcs_nih`suf'
    if !_rc {
        file write `fh' "\midrule" _n
        _mc_num `=mcs_nih`suf'[1, 3]' %9.0fc
        local a "`r(s)'"
        _mc_num `=mcs_nih`suf'[1, 5]' %9.0fc
        local b "`r(s)'"
        _mc_num `=mcs_nih`suf'[1, 4]' %9.0fc
        local c "`r(s)'"
        _mc_num `=mcs_nih`suf'[1, 6]' %9.0fc
        local d "`r(s)'"
        file write `fh' "PIs & `a' & `b' & & `c' & `d' & \\" _n
        _mc_num `=mcs_nih`suf'[1, 1]' %9.0fc
        local a "`r(s)'"
        _mc_num `=mcs_nih`suf'[1, 2]' %9.0fc
        local b "`r(s)'"
        file write `fh' "Matching cells (topic $\times$ pre-merger output $\times$ NIH funding) & \multicolumn{3}{c}{`a'} & \multicolumn{3}{c}{`b' with both career stages} \\" _n
    }
    file write `fh' "\bottomrule" _n
    file write `fh' "\end{tabular}" _n
    file write `fh' "\end{table}" _n
    file close `fh'
    di as text "wrote `out'"
end

program output_matched_tables
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'
    foreach m in mcs_nih mcs_all mbal_nih mbal_all {
        cap confirm matrix `m'`suf'
        if _rc continue
        qui matrix_to_txt, saving("../output/tables/`samp'/matched_`m'`suf'.txt") ///
            matrix(`m'`suf') title(<tab:matched_`m'`suf'>) format(%20.4f) replace
    }
    local yvar_list ppr_cnt cite_affl_wt
    if "$DEBUG_YVAR" != "" local yvar_list $DEBUG_YVAR
    foreach yvar of local yvar_list {
        foreach m in mcar mper {
            cap confirm matrix `m'_`yvar'`suf'
            if _rc continue
            qui matrix_to_txt, saving("../output/tables/`samp'/matched_`m'_`yvar'`suf'.txt") ///
                matrix(`m'_`yvar'`suf') title(<tab:matched_`m'_`yvar'`suf'>) format(%20.4f) replace
        }
        write_matched_tex, samp(`samp') yvar(`yvar') suf(`suf')
    }
    write_matched_balance_tex, samp(`samp') suf(`suf')
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
