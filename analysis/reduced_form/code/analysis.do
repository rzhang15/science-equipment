set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

* EXPOSURE_VERSION : hc | all | treated_hc
* EXPOSURE_FILTER  : "" | _cf | _cf2 | _cf5
* EXPOSURE_FILE    : "" = final_imputed_shift_share_${EXPOSURE_VERSION}${EXPOSURE_FILTER}
*                    else a literal filename under external/exposure/ (e.g. "ok")
* FE_MODE          : author | inst_cluster | inst_cluster_fldyr
*                    (inst_cluster modes absorb cluster_30: PIs unmatched to
*                    the cluster file have cluster_30 missing and are silently
*                    dropped by reghdfe/ppmlhdfe under those modes.)
* QUICK_TOPJRNL    : 1 = top_jrnls sample, ppr_cnt only, single pass (pub=0, unweighted)
global EXPOSURE_VERSION "hc"
global EXPOSURE_FILTER  ""
global EXPOSURE_Filter "ok"
global FE_MODE "author"
global WEIGHT_MSIM 1
global QUICK_TOPJRNL 0

program main
    gather_external_data
    if "$QUICK_TOPJRNL" == "1" {
        cap mkdir "../output/figures/top_jrnls"
        restrict_samp, samp(top_jrnls) r1r2(1) public(0) 
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
    foreach pub in 0 1 {
        foreach s in all_jrnls {
            cap mkdir "../output/figures/`s'"
            restrict_samp, samp(`s') r1r2(1) public(`pub')
            foreach wmode in 0 1 {
                global WEIGHT_MSIM `wmode'
                di as text _newline "=========================================="
                di as text "  RUNNING sample=`s' WEIGHT_MSIM=`wmode' PUBLIC=`pub'"
                di as text "=========================================="
                mat drop _all
                event_study, samp(`s') r1r2(1) public(`pub')
                pooled_did, samp(`s') r1r2(1) public(`pub')
                ppml_specs, samp(`s') r1r2(1) public(`pub')
                if `wmode' == 0 {
                    placebo_treatment, samp(`s') r1r2(1) public(`pub')
                    trim_top, samp(`s') r1r2(1) public(`pub')
                    robustness, samp(`s') r1r2(1) public(`pub')
                }
                output_tables, samp(`s') r1r2(1) public(`pub')
            }
            global WEIGHT_MSIM 0
        }
       * joint_outcome_test, samp(all_jrnls) r1r2(1) public(`pub')

        restrict_samp, samp(all_jrnls) r1r2(1) public(`pub') r1_only(1)
        foreach wmode in 0 1 {
            global WEIGHT_MSIM `wmode'
            di as text _newline "=========================================="
            di as text "  RUNNING sample=all_jrnls WEIGHT_MSIM=`wmode' PUBLIC=`pub' (R1-only)"
            di as text "=========================================="
            mat drop _all
            event_study, samp(all_jrnls) r1r2(1) public(`pub') r1_only(1)
            pooled_did,  samp(all_jrnls) r1r2(1) public(`pub') r1_only(1)
            ppml_specs,  samp(all_jrnls) r1r2(1) public(`pub') r1_only(1)
            if `wmode' == 0 {
                placebo_treatment, samp(all_jrnls) r1r2(1) public(`pub') r1_only(1)
                trim_top,          samp(all_jrnls) r1r2(1) public(`pub') r1_only(1)
                robustness,        samp(all_jrnls) r1r2(1) public(`pub') r1_only(1)
            }
            output_tables, samp(all_jrnls) r1r2(1) public(`pub') r1_only(1)
        }
        global WEIGHT_MSIM 0
    }
end

program gather_external_data
    if "$EXPOSURE_FILE" == "" {
        import delimited ../external/exposure/final_imputed_shift_share_${EXPOSURE_VERSION}${EXPOSURE_FILTER}, clear
    }
    else {
        // extensionless files: copy first, import delimited assumes .csv
        copy ../external/exposure/$EXPOSURE_FILE ../temp/exposure_override.csv, replace
        import delimited ../temp/exposure_override.csv, clear
    }
    rename exposure_ss imputed
    rename sum_imputed_shares imputed_mkt_spend_shr
    save ../temp/exposure, replace

    * Author-year NIH measures straight from the grant-level build. The
    * *_with_nih panels merge these onto the last-author publication panel with
    * keep(1 3), so a funded PI-year with no last-author paper is dropped there
    * and would be zero-filled downstream (see derived/nih/match_pi_athr).
    cap use athr_id year n_grants n_new_grants nih_total_cost ///
            using ../external/nih_grants/nih_athr_year, clear
    if _rc {
        di as error "gather_external_data: nih_athr_year not found -- NIH outcomes SKIPPED (rerun derived/nih/match_pi_athr)."
    }
    else {
        gen byte has_nih = n_grants > 0
        duplicates drop athr_id year, force
        save ../temp/nih_athr_yr, replace

        * nih_pi_name is left blank without a RePORTER match: that is the flag.
        use athr_id nih_pi_name using ../external/nih_grants/nih_names_by_athr, clear
        gen byte nih_matched = !mi(nih_pi_name)
        drop nih_pi_name
        merge 1:1 athr_id using ../external/nih_grants/nih_totals_by_athr, ///
            keepusing(n_grants_ever nih_cost_ever) keep(1 3) nogen
        save ../temp/nih_athr_level, replace
    }

    import delimited ../external/cluster/author_static_clusters_30.csv, clear varnames(1)
    cap tostring athr_id, replace
    rename cluster_label cluster_30
    save ../temp/athr_cluster30, replace

    use athr_id max_sim using ../external/exposure/match_diagnostics, clear
    save ../temp/match_diag, replace

    * Observed FOIA exposure held aside before any panel gate, so the "observed"
    * curve in the distribution figures is the same 213 PIs in every variant.
    * Drawn from the merged panel it moved with min_year/max_year, r1_only and
    * EXPOSURE_FILTER even though the FOIA set never changes.
    use athr_id exposure mkt_spend_shr using ../external/real_exposure/athr_exposure_${EXPOSURE_VERSION}, clear
    rename (exposure mkt_spend_shr) (exposure_all mkt_spend_shr_all)
    save ../temp/foia_observed_exposure, replace
end

program restrict_samp
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"

    // No "_r1" panel — R1-only reads the R1+R2 file then filters type=="r1"
    local input_suf ""
    if (`r1r2' == 1 & `public' == 0) local input_suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local input_suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local input_suf "_r1_r2"
    if (`r1_only' == 1 & `public' == 1) local input_suf "_r1_r2_public"
    if (`no_clin' == 1) local input_suf "_no_clin`input_suf'"

    preserve
        cap use athr_id year ppr_cnt cite_affl_wt affl_wt ///
                avg_position avg_position_rat ///
                n_first_ppr n_middle_ppr n_last_ppr ///
                avg_team_size_last avg_team_size_notlast ///
                using ../external/samp/athr_panel_full_year_`samp'`input_suf', clear
        local _pos_rc = _rc
        if `_pos_rc' {
            di as text "restrict_samp `samp'`suf': position vars not in panel yet — falling back to base _any outcomes. Rerun make_athr_yr_panel/code/build.do to enable them."
            use athr_id year ppr_cnt cite_affl_wt affl_wt ///
                using ../external/samp/athr_panel_full_year_`samp'`input_suf', clear
        }
        global POSITION_OUTCOMES_AVAIL = cond(`_pos_rc' == 0, 1, 0)
        rename (ppr_cnt cite_affl_wt affl_wt) (ppr_cnt_any cite_affl_wt_any affl_wt_any)
        save ../temp/athr_any_`samp'`input_suf', replace

        // Use all-position min_year for age_2014 — last-only would count a PI as spuriously young
        bys athr_id: egen min_year_any = min(year)
        keep athr_id min_year_any
        duplicates drop
        save ../temp/athr_min_year_any_`samp'`input_suf', replace
    restore

    use ../external/samp/athr_panel_full_year_last_`samp'`input_suf',clear
    if `r1_only' == 1 {
        keep if type == "r1"
        di as text "restrict_samp `samp'`suf' (r1_only=1): kept N=" _N " R1-only rows"
    }
    bys athr_id: egen max_year = max(year)
    bys athr_id: egen min_year = min(year)
    keep if min_year <= 2013
    keep if max_year >= 2015
    keep if inrange(year, 2010, 2019)
    * keep(1 3), not keep(3): 13 FOIA PIs have observed exposure but no imputed
    * row (they are not in the cleaned US life-science corpus, so they never
    * enter universe_ids). keep(3) dropped them here, before the
    * "replace imputed = exposure" below would have used their observed value
    * anyway. They skew high -- mean 0.0403 vs 0.0260 for the 195 survivors.
    merge m:1 athr_id using ../temp/exposure, keep(1 3) nogen
    merge m:1 athr_id using ../external/real_exposure/athr_exposure_${EXPOSURE_VERSION}, keep(1 3) nogen
    keep if !mi(imputed) | !mi(exposure)
    merge m:1 athr_id using ../temp/athr_cluster30, keep(1 3) nogen
    merge m:1 athr_id using ../temp/athr_min_year_any_`samp'`input_suf', keep(1 3) nogen
    replace min_year_any = min_year if mi(min_year_any)
    gen foia_athr = 1 if !mi(exposure)
    // Real FOIA PIs anchor themselves (max_sim=1); unmatched (rare) get 0 so they drop from pw regs
    merge m:1 athr_id using ../temp/match_diag, keep(1 3) nogen
    replace max_sim = 1 if foia_athr == 1
    replace max_sim = 0 if mi(max_sim)
    bys athr_id : gen athr_indicator = _n == 1
    * Observed curve comes from ../temp/foia_observed_exposure (all 213 PIs,
    * pre-gate) so it is invariant across samp/suf/EXPOSURE_FILTER. The imputed
    * curve is sample-specific by design -- that is the object being compared.
    preserve
        keep if athr_indicator == 1
        keep athr_id imputed imputed_mkt_spend_shr
        append using ../temp/foia_observed_exposure
        sum exposure_all, d
        local mean : di %4.3f r(mean)
        local sd   : di %4.3f r(sd)
        sum imputed, d
        local imputed_mean : di %4.3f r(mean)
        local imputed_sd   : di %4.3f r(sd)
        sum mkt_spend_shr_all, d
        local mshr_mean : di %4.3f r(mean)
        local mshr_sd   : di %4.3f r(sd)
        sum imputed_mkt_spend_shr, d
        local imshr_mean : di %4.3f r(mean)
        local imshr_sd   : di %4.3f r(sd)
        tw kdensity exposure_all, lcolor(ebblue)   || kdensity imputed, lcolor(dkorange)   xtitle("Exposure Measure") ytitle("Density") ///
            xlab(#15) ///
            legend(on label(1 "FOIA PI Observed Exposure (mean = `mean', sd = `sd')") label(2 "Imputed Exposure (mean = `imputed_mean', sd = `imputed_sd')") pos(7) ring(1) size(small))
        graph export ../output/figures/`samp'/exposure_dist`suf'.pdf, replace
        tw kdensity mkt_spend_shr_all, lcolor(ebblue)  || kdensity imputed_mkt_spend_shr, lcolor(dkorange)   xtitle("Market Spend Share") ytitle("Density") ///
            xlab(#15) ///
            legend(on label(1 "FOIA PI Observed (mean = `mshr_mean', sd = `mshr_sd')") label(2 "Imputed (mean = `imshr_mean', sd = `imshr_sd')") pos(7) ring(1) size(small))
        graph export ../output/figures/`samp'/mkt_spend_shr_dist`suf'.pdf, replace
    restore
    replace imputed = exposure if !mi(exposure)
    replace imputed_mkt_spend_shr = mkt_spend_shr if !mi(mkt_spend_shr)
    drop exposure
    rename imputed exposure
    drop mkt_spend_shr
    rename imputed_mkt_spend_shr mkt_spend_shr
    bys athr_id: egen num_yrs_pre = total(year < 2014)
    bys athr_id: egen num_yrs_post = total(year >= 2014)
    bys athr_id: gen tot_yrs = _N
    bys athr_id inst_id: gen plc_cntr = _n == 1
    bys athr_id : egen num_place = total(plc_cntr)
    * [F5] spelled out (was `num_yrs', which relied on abbreviation)
    drop if num_yrs_pre <=2 
   * drop if num_yrs_post < 2
*    drop if tot_yrs <= 4
    keep if num_place==1
    gegen athr = group(athr_id)
    preserve
    contract athr num_place athr_id exposure inst_id inst msa_comb msa_c_world min_year min_year_any type public mkt_spend_shr cluster_30 max_sim foia_athr
    drop _freq
    save ../temp/athr_xw, replace
    restore
    xtset athr year
    tsfill, full
    drop athr_id exposure inst_id inst msa_comb msa_c_world min_year min_year_any type public mkt_spend_shr cluster_30 max_sim foia_athr
    merge m:1 athr using ../temp/athr_xw, assert(3) keep(3) nogen
    // Drop position vars from master before athr_any merge — Stata silently keeps master, and the last-only versions are degenerate
    foreach v in n_first_ppr n_middle_ppr n_last_ppr n_solo_ppr ///
                 avg_position avg_position_rat ///
                 avg_team_size_last avg_team_size_notlast {
        cap drop `v'
    }
    merge 1:1 athr_id year using ../temp/athr_any_`samp'`input_suf', keep(1 3) nogen
    foreach var in ppr_cnt cite_affl_wt affl_wt ppr_cnt_any cite_affl_wt_any affl_wt_any {
        replace `var' = 0 if mi(`var')
    }
    foreach var in n_first_ppr n_middle_ppr n_last_ppr {
        cap confirm variable `var'
        if !_rc replace `var' = 0 if mi(`var')
    }
    gen pre_ppr_cnt = ppr_cnt if year < 2014
    bys athr_id: egen pre_ppr_cnt_sum = sum(pre_ppr_cnt)
    bys athr_id: egen pre_ppr_cnt_avg = mean(pre_ppr_cnt)
    // Both p5 cuts from the pre-trim distribution so the drops don't compound
    qui sum pre_ppr_cnt_avg if athr_indicator == 1, d
    local p5_avg = r(p5)
    qui sum pre_ppr_cnt_sum if athr_indicator == 1, d
    local p5_sum = r(p5)
    drop if pre_ppr_cnt_avg <= `p5_avg'
    drop if pre_ppr_cnt_sum <= `p5_sum'
    gen age_2014 = 2014 - min_year_any + 30
    drop if mi(exposure)
    drop if mi(mkt_spend_shr) | mkt_spend_shr <= 0
    merge 1:1 athr_id year using ../external/coathrs/avg_coathrs, keep(1 3) nogen
    replace avg_num_coathrs = 0 if mi(avg_num_coathrs)
    // [F6] Intensive margin: undefined when the PI publishes nothing that
    // year IN ANY POSITION (was keyed to last-author ppr_cnt only).
    replace avg_num_coathrs = . if ppr_cnt_any == 0
    * NIH outcomes are estimated only on PIs who match RePORTER AND hold at
    * least one research award 2010-19. A PI who never matches, or whose measure
    * is zero in every year, carries no NIH information: set the measures
    * missing so those PIs drop from the NIH regressions only. Within a retained
    * PI, zero years are real and are kept.
    cap confirm file ../temp/nih_athr_yr.dta
    if _rc di as error "restrict_samp `samp'`suf': ../temp/nih_athr_yr missing -- NIH outcomes unavailable this run."
    else {
        merge 1:1 athr_id year using ../temp/nih_athr_yr, keep(1 3) nogen
        merge m:1 athr_id using ../temp/nih_athr_level, keep(1 3) nogen
        replace nih_matched = 0 if mi(nih_matched)
        * The source file has no publication filter, so a non-merging year for
        * a matched PI really is a year with no award record.
        foreach v in n_grants n_new_grants nih_total_cost has_nih {
            replace `v' = 0 if mi(`v') & nih_matched == 1
        }
        foreach v in n_grants n_new_grants has_nih {
            replace `v' = . if nih_matched != 1 | mi(n_grants_ever) | n_grants_ever == 0
        }
        replace nih_total_cost = . if nih_matched != 1 | mi(nih_cost_ever) | nih_cost_ever == 0
        qui gunique athr_id if !mi(n_grants)
        di as text "restrict_samp `samp'`suf': " r(unique) " PIs in the NIH grant-count sample"
        qui gunique athr_id if !mi(nih_total_cost)
        di as text "restrict_samp `samp'`suf': " r(unique) " PIs in the NIH award-amount sample"
    }

    * PI-level flag for the RePORTER-matched, grant-holding sample
    cap confirm variable n_grants
    if _rc {
        gen byte nih_athr = 0
    }
    else {
        bys athr_id: egen byte nih_athr = max(!mi(n_grants))
    }

    gen ppr_cnt_notlast      = ppr_cnt_any      - ppr_cnt
    gen cite_affl_wt_notlast = cite_affl_wt_any - cite_affl_wt
    gen affl_wt_notlast      = affl_wt_any      - affl_wt
    foreach v in ppr_cnt_notlast cite_affl_wt_notlast affl_wt_notlast {
        replace `v' = 0 if `v' < 0
    }
    foreach v in cite_affl_wt affl_wt cite_affl_wt_any affl_wt_any ///
                 cite_affl_wt_notlast affl_wt_notlast {
        // p99 cut from pre-period only so the truncation point is unaffected by treatment
        qui sum `v' if year < 2014, d
        local p99_`v' = r(p99)
        replace `v' = `p99_`v'' if `v' > `p99_`v'' & !mi(`v')
        di as text "restrict_samp `samp'`suf' winsorized `v' at pre-period p99=`p99_`v''"
    }

    assert !mi(athr_id)
    assert !mi(exposure)
    assert !mi(mkt_spend_shr)
    cap mkdir ../output/prepped_samples
    compress
    save ../output/prepped_samples/es_`samp'`suf', replace
end

program event_study
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
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
    use ../output/prepped_samples/es_`samp'`suf', clear

    gen rel = year - 2014
    qui sum rel, d
    local abs_lag  = abs(r(max))
    local abs_lead = abs(r(min))
    * [F12] Only the observed window is generated; unused time dummies removed.
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
        if "`yvar'" == "cite_affl_wt" local var_name = "Citation Weighted Output"
        if "`yvar'" == "cite_affl_wt" local gap  1
        if "`yvar'" == "ppr_cnt" local var_name = "Publication Count"
        if "`yvar'" == "ppr_cnt" local gap 0.5
        if "`yvar'" == "ln_ppr_cnt"      local var_name = "Log Publication Counts"
        if "`yvar'" == "ln_ppr_cnt"      local gap 0.1
        if "`yvar'" == "ppr_cnt"      & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "cite_affl_wt" & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "ppr_cnt_any"         local var_name = "Publication Count (any position)"
        if "`yvar'" == "ppr_cnt_any"         local gap 0.5
        if "`yvar'" == "cite_affl_wt_any"    local var_name = "Citation Weighted Output (any position)"
        if "`yvar'" == "cite_affl_wt_any"    local gap 1
        if "`yvar'" == "ppr_cnt_any"         & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "cite_affl_wt_any"    & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "ppr_cnt_notlast"         local var_name = "Publication Count (non-last author)"
        if "`yvar'" == "ppr_cnt_notlast"         local gap 0.5
        if "`yvar'" == "cite_affl_wt_notlast"    local var_name = "Citation Weighted Output (non-last author)"
        if "`yvar'" == "cite_affl_wt_notlast"    local gap 1
        if "`yvar'" == "ppr_cnt_notlast"         & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "cite_affl_wt_notlast"    & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "avg_num_coathrs"   local var_name = "Average Team Size"
        if "`yvar'" == "avg_num_coathrs"   local gap 0.5
        if "`yvar'" == "n_grants"          local var_name = "# Active NIH Research Grants"
        if "`yvar'" == "n_grants"          local gap 0.5
        if "`yvar'" == "nih_total_cost"    local var_name = "NIH Award Amount ($)"
        if "`yvar'" == "nih_total_cost"    local gap 50000
        if "`yvar'" == "n_first_ppr"           local var_name = "# First-Author Papers"
        if "`yvar'" == "n_first_ppr"           local gap 0.5
        if "`yvar'" == "n_middle_ppr"          local var_name = "# Middle-Author Papers"
        if "`yvar'" == "n_middle_ppr"          local gap 0.5
        if "`yvar'" == "n_last_ppr"            local var_name = "# Last-Author Papers"
        if "`yvar'" == "n_last_ppr"            local gap 0.5
        if "`yvar'" == "avg_position"          local var_name = "Avg Author Position (1=first, N=last)"
        if "`yvar'" == "avg_position"          local gap 0.5
        if "`yvar'" == "avg_position_rat"      local var_name = "Avg Author Position / Team Size (0-1)"
        if "`yvar'" == "avg_position_rat"      local gap 0.05
        if "`yvar'" == "avg_team_size_last"    local var_name = "Team Size (papers where PI is last)"
        if "`yvar'" == "avg_team_size_last"    local gap 0.5
        if "`yvar'" == "avg_team_size_notlast" local var_name = "Team Size (papers where PI is not last)"
        if "`yvar'" == "avg_team_size_notlast" local gap 0.5
        local poisson_name "`var_name'"
        if "`yvar'" == "ppr_cnt"              local poisson_name "Publications"
        if "`yvar'" == "cite_affl_wt"         local poisson_name "Citation-Weighted Output"
        if "`yvar'" == "ppr_cnt_any"          local poisson_name "Publications (any position)"
        if "`yvar'" == "cite_affl_wt_any"     local poisson_name "Citation-Weighted Output (any position)"
        if "`yvar'" == "ppr_cnt_notlast"      local poisson_name "Publications (non-last author)"
        if "`yvar'" == "cite_affl_wt_notlast" local poisson_name "Citation-Weighted Output (non-last author)"
        if "`yvar'" == "avg_num_coathrs"      local poisson_name "Coauthors"
        if "`yvar'" == "n_grants"             local poisson_name "Active NIH Research Grants"
        if "`yvar'" == "nih_total_cost"       local poisson_name "NIH Award Dollars"
        local ppml_ytit "Output-Cost Elasticity"
        if inlist("`yvar'", "n_grants", "n_new_grants", "nih_total_cost") ///
            local ppml_ytit "{&Delta} Log Expected `poisson_name'"

        // PPML is the reported estimator everywhere; OLS runs only for the
        // ppr_cnt OLS-vs-Poisson comparison and for outcomes PPML can't take
        // (logs and conditional-mean outcomes).
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
        tw rcap ub lb year if year != 2013 , lcolor(ebblue%70) msize(vsmall) || ///
          scatter b year, mcolor(ebblue) || ///
          scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
          xlab(2010(1)2019) xtitle("Year") ///
          ytitle("`var_name'") ylab(`ymin'(`gap')`ymax') ///
          yline(0, lcolor(gs10) lpattern(solid)) ///
          legend(on order(- "Num. PIs: `num_athrs'" "Num. Institutions: `num_insts'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) plotregion(margin(sides))
        graph export ../output/figures/`samp'/es_`yvar'`suf'_mshrctrl`wsuf'.pdf, replace
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
            gen ub = b + 1.96*se
            sum ub, d
            local ymax = round(r(max), 0.1)
            gen lb = b - 1.96*se
            sum lb, d
            local ymin = round(r(min), 0.1)
            if `ymin' > 0 local ymin = 0
            gen rel = -`abs_lead' if _n == 1
            replace rel = rel[_n-1]+1 if _n > 1
            replace rel = rel + 1 if rel >= -1
            replace rel = -1 if rel == `abs_lag' + 1
            gen year = rel + 2014
            hashsort rel
            tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
              scatter b year, mcolor(ebblue) || ///
              scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
              xlab(2010(1)2019) xtitle("Year") ///
              ytitle("`ppml_ytit'") ylab(`ymin'(0.1)`ymax') ///
              yline(0, lcolor(gs10) lpattern(solid)) ///
              legend(on order(- "Num. PIs: `num_athrs'" "Num. Institutions: `num_insts'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) plotregion(margin(sides))
            graph export ../output/figures/`samp'/es_`yvar'`suf'_ppml_mshrctrl`wsuf'.pdf, replace
            save ../temp/es_`yvar'`suf'_ppml_mshrctrl`wsuf', replace
            restore
            }
        }

        // FOIA PIs only (observed, non-imputed exposure), PPML with share controls
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
                    // small FOIA-only sample: a collinear term can drop out of e(b)
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
            tw rcap ub lb year if year != 2013, lcolor(dkorange%70) msize(vsmall) || ///
              scatter b year, mcolor(dkorange) || ///
              scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
              xlab(2010(1)2019) xtitle("Year") ///
              ytitle("`ppml_ytit'") ylab(#6) ///
              yline(0, lcolor(gs10) lpattern(solid)) ///
              title("FOIA PIs only (observed exposure)", size(small)) ///
              legend(on order(- "Num. PIs: `num_athrs'" "Num. Institutions: `num_insts'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) plotregion(margin(sides))
            graph export ../output/figures/`samp'/es_`yvar'`suf'_ppml_mshrctrl_foia`wsuf'.pdf, replace
            save ../temp/es_`yvar'`suf'_ppml_mshrctrl_foia`wsuf', replace
            restore
            }
        }

        // NIH-matched PIs only (RePORTER match with >=1 research award), PPML with share controls
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
            tw rcap ub lb year if year != 2013, lcolor(lavender%70) msize(vsmall) || ///
              scatter b year, mcolor(lavender) || ///
              scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
              xlab(2010(1)2019) xtitle("Year") ///
              ytitle("`ppml_ytit'") ylab(#6) ///
              yline(0, lcolor(gs10) lpattern(solid)) ///
              title("NIH-matched PIs only", size(small)) ///
              legend(on order(- "Num. PIs: `num_athrs'" "Num. Institutions: `num_insts'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) plotregion(margin(sides))
            graph export ../output/figures/`samp'/es_`yvar'`suf'_ppml_mshrctrl_nih`wsuf'.pdf, replace
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
        // ppmlhdfe rejects aw, binscatter rejects pw — mixing is fine, β identical
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
    use ../output/prepped_samples/es_`samp'`suf', clear

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
    * [F1] label bookkeeping: rows and labels now appended together
    local kept_outcomes
    // OLS is reported only for the ppr_cnt OLS-vs-Poisson comparison; every
    // other outcome ppml_specs covers is Poisson-only.
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

        // Base (no share) only for ppr_cnt — the with/without-share comparison
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
        if "`yvar'" == "cite_affl_wt"            local var_name "Citation Weighted Output"
        if "`yvar'" == "ppr_cnt"                 local var_name "Publication Count"
        if "`yvar'" == "ln_cite_affl_wt"         local var_name "Log Citation Weighted Output"
        if "`yvar'" == "ln_ppr_cnt"              local var_name "Log Publication Counts"
        if "`yvar'" == "cite_affl_wt_any"        local var_name "Citation Weighted Output (any position)"
        if "`yvar'" == "ppr_cnt_any"             local var_name "Publication Count (any position)"
        if "`yvar'" == "ln_cite_affl_wt_any"     local var_name "Log Citation Weighted Output (any position)"
        if "`yvar'" == "ln_ppr_cnt_any"          local var_name "Log Publication Counts (any position)"
        if "`yvar'" == "cite_affl_wt_notlast"    local var_name "Citation Weighted Output (non-last author)"
        if "`yvar'" == "ppr_cnt_notlast"         local var_name "Publication Count (non-last author)"
        if "`yvar'" == "ln_cite_affl_wt_notlast" local var_name "Log Citation Weighted Output (non-last author)"
        if "`yvar'" == "ln_ppr_cnt_notlast"      local var_name "Log Publication Counts (non-last author)"
        if "`yvar'" == "avg_num_coathrs"         local var_name "Avg Coauthors"
        if "`yvar'" == "n_grants"                local var_name "# Active NIH Research Grants"
        if "`yvar'" == "nih_total_cost"          local var_name "NIH Award Amount ($)"
        if "`yvar'" == "n_first_ppr"             local var_name "# First-Author Papers"
        if "`yvar'" == "n_middle_ppr"            local var_name "# Middle-Author Papers"
        if "`yvar'" == "n_last_ppr"              local var_name "# Last-Author Papers"
        if "`yvar'" == "avg_position"            local var_name "Avg Author Position"
        if "`yvar'" == "avg_position_rat"        local var_name "Avg Author Position Ratio"
        if "`yvar'" == "avg_team_size_last"      local var_name "Team Size (last-author papers)"
        if "`yvar'" == "avg_team_size_notlast"   local var_name "Team Size (non-last papers)"

        // pdid FWL binscatter figures commented out; uncomment to reproduce.
        /*
        preserve
            cap noi qui reghdfe `yvar' Z_share_it `wt', absorb(`fes') residuals(_y_r)
            if _rc == 0 cap noi qui reghdfe Z_it Z_share_it `wt', absorb(`fes') residuals(_Z_r)
            if _rc == 0 {
                local pds_b_str  : dis %7.3f `s_bx'
                local pds_se_str : dis %7.3f `s_sex'
                binscatter _y_r _Z_r `wt_bin', n(30) ///
                    xtitle("Exposure x Post") ytitle("`var_name'") ///
                    xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                    msymbol(O) mcolors(gs6) lcolors(ebblue) ///
                    note("{&beta} = `pds_b_str' (SE: `pds_se_str')") ///
                    plotregion(margin(sides))
                graph export ../output/figures/`samp'/pdid_`yvar'`suf'_mshrctrl`wsuf'.pdf, replace
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
    // ppmlhdfe analog of pooled_did; may drop separated obs or fail to converge (hence cap noi)
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
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
    local wt ""
    local wsuf ""
    if "$WEIGHT_MSIM" == "1" {
        // ppmlhdfe rejects aw, binscatter rejects pw — mixing is fine, β identical
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
    use ../output/prepped_samples/es_`samp'`suf', clear

    gen post = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post

    // Mean-based POSITION metrics (avg_position, avg_team_size_*) excluded.
    // avg_num_coathrs is deliberately kept: PPML is a valid pseudo-likelihood
    // for any nonnegative outcome, and this mirrors the headline coauthor spec.
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
        // Base (no share) only for ppr_cnt — feeds the rf_main "no share" column.
        // d() + predict mu here so the FWL binscatters below reuse the fit
        // instead of re-estimating.
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
        if "`yvar'" == "cite_affl_wt"         local var_name "Citation Weighted Output"
        if "`yvar'" == "ppr_cnt"              local var_name "Publication Count"
        if "`yvar'" == "affl_wt"              local var_name "Affiliation Weighted Output"
        if "`yvar'" == "cite_affl_wt_any"     local var_name "Citation Weighted Output (any position)"
        if "`yvar'" == "ppr_cnt_any"          local var_name "Publication Count (any position)"
        if "`yvar'" == "affl_wt_any"          local var_name "Affiliation Weighted Output (any position)"
        if "`yvar'" == "cite_affl_wt_notlast" local var_name "Citation Weighted Output (non-last author)"
        if "`yvar'" == "ppr_cnt_notlast"      local var_name "Publication Count (non-last author)"
        if "`yvar'" == "affl_wt_notlast"      local var_name "Affiliation Weighted Output (non-last author)"
        if "`yvar'" == "avg_num_coathrs"      local var_name "Avg Coauthors"
        if "`yvar'" == "n_grants"             local var_name "# Active NIH Research Grants"
        if "`yvar'" == "nih_total_cost"       local var_name "NIH Award Amount ($)"
        if "`yvar'" == "n_first_ppr"          local var_name "# First-Author Papers"
        if "`yvar'" == "n_middle_ppr"         local var_name "# Middle-Author Papers"
        if "`yvar'" == "n_last_ppr"           local var_name "# Last-Author Papers"
        local poisson_name "`var_name'"
        if "`yvar'" == "ppr_cnt"              local poisson_name "Publications"
        if "`yvar'" == "cite_affl_wt"         local poisson_name "Citation-Weighted Output"
        if "`yvar'" == "affl_wt"              local poisson_name "Affiliation-Weighted Output"
        if "`yvar'" == "ppr_cnt_any"          local poisson_name "Publications (any position)"
        if "`yvar'" == "cite_affl_wt_any"     local poisson_name "Citation-Weighted Output (any position)"
        if "`yvar'" == "affl_wt_any"          local poisson_name "Affiliation-Weighted Output (any position)"
        if "`yvar'" == "ppr_cnt_notlast"      local poisson_name "Publications (non-last author)"
        if "`yvar'" == "cite_affl_wt_notlast" local poisson_name "Citation-Weighted Output (non-last author)"
        if "`yvar'" == "affl_wt_notlast"      local poisson_name "Affiliation-Weighted Output (non-last author)"
        if "`yvar'" == "avg_num_coathrs"      local poisson_name "Coauthors"
        if "`yvar'" == "n_grants"             local poisson_name "Active NIH Research Grants"
        if "`yvar'" == "nih_total_cost"       local poisson_name "NIH Award Dollars"

        // Base FWL binscatter only for ppr_cnt (mirrors the base ppmlhdfe gate above)
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
                * [F10]+flow: failure skips only THIS plot, not the rest of
                * the yvar iteration (was `continue', which also skipped the
                * mshrctrl binscatter below)
                if _rc {
                    di as error "ppml FWL `yvar' failed; skipping plot."
                }
                else {
                    local pb_str  : dis %7.3f ppml_pdid_`yvar'[1,1]
                    local pse_str : dis %7.3f ppml_pdid_`yvar'[2,1]
                    binscatter _y_r _Z_r [aw=_fwlw], n(30) ///
                        xtitle("Exposure x Post") ///
                        ytitle("{&Delta} Log Expected `poisson_name'") ///
                        xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                        msymbol(O) mcolors(gs6) lcolors(ebblue) ///
                        note("{&beta} = `pb_str' (SE: `pse_str')", size(small) pos(7) ring(1) justification(left)) ///
                        plotregion(margin(sides))
                    graph export ../output/figures/`samp'/ppml_pdid_`yvar'`suf'`wsuf'.pdf, replace
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
                    binscatter _y_r _Z_r [aw=_fwlw], n(30) ///
                        xtitle("Exposure x Post") ///
                        ytitle("{&Delta} Log Expected `poisson_name'") ///
                        xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                        msymbol(O) mcolors(gs6) lcolors(ebblue) ///
                        note("{&beta} = `pbs_str' (SE: `pses_str')", size(small) pos(7) ring(1) justification(left)) ///
                        plotregion(margin(sides))
                    graph export ../output/figures/`samp'/ppml_pdid_`yvar'`suf'_mshrctrl`wsuf'.pdf, replace
                }
            }
        restore

        // NIH-matched PIs only (RePORTER match with >=1 research award).
        // n_grants / nih_total_cost already estimate on this sample by construction.
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
            // d() so the NIH-only FWL binscatter below can predict mu
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
                        xtitle("Exposure x Post") ///
                        ytitle("{&Delta} Log Expected `poisson_name'") ///
                        xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                        msymbol(O) mcolors(gs6) lcolors(ebblue) ///
                        title("NIH-matched PIs only", size(small)) ///
                        note("{&beta} = `pbn_str' (SE: `psen_str')", size(small) pos(7) ring(1) justification(left)) ///
                        plotregion(margin(sides))
                    graph export ../output/figures/`samp'/ppml_pdid_`yvar'`suf'_mshrctrl_nih`wsuf'.pdf, replace
                }
            }
        restore
        }
    }
end

program placebo_treatment
    // Fake-treatment placebo on year<=2013 subsample: β on Z_placebo should be ~0 if parallel trends hold
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
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
    if (`no_clin' == 1) local suf "_no_clin`suf'"

    local outcomes ppr_cnt

    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'
    cap mkdir ../output/figures/`samp'

    foreach placebo_yr in 2011 2012 {
        use ../output/prepped_samples/es_`samp'`suf', clear
        keep if year <= 2013     // strictly pre-treatment window

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

    // Full-panel placebo ES: fake treatment year as omitted reference; real effect should still start at 2014 (dashed line)
    foreach placebo_yr in 2011 2012 {
        foreach yvar in ppr_cnt {
            local poisson_name "Publications"
            local ppml_ytit "Output-Cost Elasticity"

            use ../output/prepped_samples/es_`samp'`suf', clear
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

            // pl_int_lead1 / pl_mshr_lead1 are the omitted reference — excluded so rel=-1 stays the reference year
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
                ytitle("`ppml_ytit'") ///
                ylab(`ymin'(0.1)`ymax') yline(0, lcolor(gs10) lpattern(solid)) ///
                xline(2014, lpattern(dash) lcolor(gs10)) ///
                title("Placebo ES: treatment shifted to `placebo_yr' (real: 2014)", size(small)) ///
                legend(off) plotregion(margin(sides))
            graph export ../output/figures/`samp'/placebo_es_`yvar'_yr`placebo_yr'`suf'.pdf, replace
            save ../temp/placebo_es_`yvar'_yr`placebo_yr'`suf', replace
            restore
        }
    }
end

program trim_top
    // Composition check: drop top {1,5,10,25}% of PIs by pre_ppr_cnt_sum, re-estimate.
    // [F3] trim=0 (full sample) is estimated here too, with the SAME
    // with-share spec, so the sensitivity figures have a comparable baseline.
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
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
    if (`no_clin' == 1) local suf "_no_clin`suf'"

    local outcomes ppr_cnt
    local trims 0 1 5 10 25

    cap mkdir ../output/tables/`samp'
    cap mkdir ../output/figures/`samp'

    foreach trim of local trims {
        use ../output/prepped_samples/es_`samp'`suf', clear
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
        local var_name "Publication Count"
        local poisson_name "Publications"
        local ppml_ytit "Output-Cost Elasticity"

        * [F3] both figures read trim`t' matrices only — baseline (trim=0) is
        * now the same with-share spec as every trimmed point.
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
             ytitle("pdid {&beta}: `var_name'") ///
             yline(0, lcolor(gs10) lpattern(solid)) ///
             title("Trim-top sensitivity: `var_name'", size(small)) ///
             legend(off) plotregion(margin(sides))
        graph export ../output/figures/`samp'/trim_top_`yvar'`suf'.pdf, replace
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
             ytitle("`ppml_ytit'") ///
             yline(0, lcolor(gs10) lpattern(solid)) ///
             title("Trim-top sensitivity (ppml): `var_name'", size(small)) ///
             legend(off) plotregion(margin(sides))
        graph export ../output/figures/`samp'/trim_top_ppml_`yvar'`suf'.pdf, replace
        restore
    }
end

program joint_outcome_test
    // H0: β_ppr = β_cite, tested three ways (log, y/pre-mean, ppml semi-elasticity)
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"
    use ../output/prepped_samples/es_`samp'`suf', clear

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

    // Stress tests on the main mshrctrl ES: +age×year controls / drop PIs without a real pub after 2018
    local outcomes ppr_cnt cite_affl_wt ppr_cnt_any cite_affl_wt_any ///
                   ppr_cnt_notlast cite_affl_wt_notlast
    if "$QUICK_TOPJRNL" == "1" local outcomes ppr_cnt

    foreach yvar of local outcomes {
        if "`yvar'" == "ppr_cnt"              local var_name "Publication Count"
        if "`yvar'" == "cite_affl_wt"         local var_name "Citation Weighted Output"
        if "`yvar'" == "ppr_cnt_any"          local var_name "Publication Count (any position)"
        if "`yvar'" == "cite_affl_wt_any"     local var_name "Citation Weighted Output (any position)"
        if "`yvar'" == "ppr_cnt_notlast"      local var_name "Publication Count (non-last author)"
        if "`yvar'" == "cite_affl_wt_notlast" local var_name "Citation Weighted Output (non-last author)"
        local poisson_name "`var_name'"
        if "`yvar'" == "ppr_cnt"              local poisson_name "Publications"
        if "`yvar'" == "cite_affl_wt"         local poisson_name "Citation-Weighted Output"
        if "`yvar'" == "ppr_cnt_any"          local poisson_name "Publications (any position)"
        if "`yvar'" == "cite_affl_wt_any"     local poisson_name "Citation-Weighted Output (any position)"
        if "`yvar'" == "ppr_cnt_notlast"      local poisson_name "Publications (non-last author)"
        if "`yvar'" == "cite_affl_wt_notlast" local poisson_name "Citation-Weighted Output (non-last author)"
        local ppml_ytit "Output-Cost Elasticity"
        if regexm("`yvar'", "^ppr_cnt")      local gap 0.5
        if regexm("`yvar'", "^cite_affl_wt") local gap 1
        if regexm("`yvar'", "^ppr_cnt")      & "`samp'" == "top_jrnls" local gap 2
        if regexm("`yvar'", "^cite_affl_wt") & "`samp'" == "top_jrnls" local gap 2

        foreach spec in ageCtrl noattrit {
            if "`spec'" == "ageCtrl"  local title "Age x year controls"
            if "`spec'" == "noattrit" local title "PIs with last real pub year >= 2018"

            use ../output/prepped_samples/es_`samp'`suf', clear
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
                bys athr_id: egen latest_pub = max(cond(ppr_cnt > 0, year, .))
                * [F11-adjacent] guard: missing latest_pub must NOT pass a >= test
                keep if latest_pub >= 2018 & !mi(latest_pub)
                drop latest_pub
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

            // Poisson is the reported estimator; OLS runs only for ppr_cnt
            local ests ppmlhdfe
            if "`yvar'" == "ppr_cnt" local ests reghdfe ppmlhdfe

            foreach est of local ests {
            local esuf ""
            if "`est'" == "ppmlhdfe" local esuf "_ppml"

            * [F4] int_lead1 is OMITTED as the reference (was included with
            * post-hoc re-centering, which made every plotted SE wrong for
            * the b_j - b_lead1 contrast).
            cap noi `est' `yvar' `int_leads' `int_lags' `mshr_leads' `mshr_lags' `addctrl', ///
                    absorb(`fes') vce(cluster `vce_cl')
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
              , xlab(2010(1)2019) xtitle("Year") ytitle("`ytit'") ///
                `ylabopt' yline(0, lcolor(gs10) lpattern(solid)) ///
                title("Main ES: `title' (N PIs = `n_pi')", size(small)) ///
                legend(off) plotregion(margin(sides))
            cap noi graph export ../output/figures/`samp'/robustness/es_`yvar'_main`esuf'_`spec'`suf'.pdf, replace
            restore
            }
        }
    }

end

program output_tables
    // Dumps pdid / ppml_pdid / placebo / trim matrices to txt via matrix_to_txt
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
    // main() clears matrices between wmodes, so cap confirm silently skips missing ones
    // [F13] trim0 added (full-sample baseline written by trim_top)
    foreach prog in pdid ppml_pdid nih_ppml placebo2011 placebo2012 trim0 trim1 trim5 trim10 trim25 {
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
    // Fills rf_main.tex from ppml_pdid_ppr_cnt (needs base + mshrctrl cols populated by ppml_specs)
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

    * [F9] guard BOTH columns — a missing estimate would otherwise print "."
    * with *** stars (missing compares as +infinity in cond()).
    if mi(`b_base') | mi(`se_base') | mi(`b_ms') | mi(`se_ms') {
        di as text "write_rf_main_tex: base or with-share PPML missing for ppr_cnt; skipping."
        exit 0
    }

    // Star helpers via absolute t-stat (normal approx)
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
    * [F9] per-column N (base and with-share samples can differ)
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
    file write `fh' "Treated-market share $S_i$  & $`b_sh_s'`st_sh'$ &  \\" _n
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

**
main