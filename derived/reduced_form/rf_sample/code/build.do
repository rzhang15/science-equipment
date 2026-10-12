set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries, loadglob(../external/lib/globals.txt)
adopath ++ "../external/lib/stata"
version 17
set maxvar 20000

global NO_SOLO 0
global BUILD_NO_CLIN 1
global HISIM_PCTS ""
global EXTRA_SAMPS ""

program main
    cap mkdir ../output/prepped_samples
    gather_external_data
    foreach pub in 0 1 {
        restrict_samp, samp(all_jrnls) r1r2(1) public(`pub')
        exit_panel,    samp(all_jrnls) r1r2(1) public(`pub')
        restrict_samp, samp(all_jrnls) r1r2(1) public(`pub') r1_only(1)
        exit_panel,    samp(all_jrnls) r1r2(1) public(`pub') r1_only(1)
    }
    if $BUILD_NO_CLIN == 1 restrict_samp, samp(all_jrnls) r1r2(1) public(0) no_clin(1)
    foreach pct of global HISIM_PCTS {
        restrict_samp, samp(all_jrnls) r1r2(1) public(0) hisim(`pct')
    }
    foreach s of global EXTRA_SAMPS {
        restrict_samp, samp(`s') r1r2(1) public(0)
    }
end

program gather_external_data
    if "$EXPOSURE_FILE" == "" {
        import delimited "../external/exposure/final_imputed_shift_share_${EXPOSURE_VERSION}${EXPOSURE_FILTER}.csv", clear
    }
    else {
        copy ../external/exposure/$EXPOSURE_FILE ../temp/exposure_override.csv, replace
        import delimited ../temp/exposure_override.csv, clear
    }
    rename exposure_ss imputed
    rename sum_imputed_shares imputed_mkt_spend_shr
    save ../temp/exposure, replace

    cap use athr_id year n_grants n_new_grants nih_total_cost ///
            using ../external/nih_grants/nih_athr_year, clear
    if _rc {
        di as error "gather_external_data: nih_athr_year not found -- NIH outcomes SKIPPED (rerun derived/nih/match_pi_athr)."
    }
    else {
        gen byte has_nih = n_grants > 0
        duplicates drop athr_id year, force
        save ../temp/nih_athr_yr, replace

        use athr_id nih_pi_name using ../external/nih_grants/nih_names_by_athr, clear
        gen byte nih_matched = !mi(nih_pi_name)
        drop nih_pi_name
        merge 1:1 athr_id using ../external/nih_grants/nih_totals_by_athr, ///
            keepusing(n_grants_ever nih_cost_ever) keep(1 3) nogen
        merge 1:1 athr_id using ../external/nih_grants/nih_baseline_by_athr, ///
            keepusing(n_grants_pre nih_cost_pre nih_grants_baseline nih_funding_baseline) ///
            keep(1 3) nogen
        save ../temp/nih_athr_level, replace
    }

    import delimited ../external/cluster/author_static_clusters_30.csv, clear varnames(1)
    cap tostring athr_id, replace
    rename cluster_label cluster_30
    save ../temp/athr_cluster30, replace

    use athr_id max_sim using ../external/exposure/match_diagnostics, clear
    save ../temp/match_diag, replace

    * Use raw observed FOIA spending shares and exposure. Diagnostics files must
    * not automatically change the exposure definition when present on disk.
    use athr_id exposure mkt_spend_shr using ../external/real_exposure/athr_exposure_${EXPOSURE_VERSION}, clear
    di as text "observed FOIA exposure: raw spending shares (share shrinkage off)"
    save ../temp/observed_exposure, replace
    rename (exposure mkt_spend_shr) (exposure_all mkt_spend_shr_all)
    save ../temp/foia_observed_exposure, replace
end

program restrict_samp 
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0) hisim(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"

    // no "_r1" panel: R1-only reads the R1+R2 file then filters type=="r1"
    local input_suf ""
    if (`r1r2' == 1 & `public' == 0) local input_suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local input_suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local input_suf "_r1_r2"
    if (`r1_only' == 1 & `public' == 1) local input_suf "_r1_r2_public"
    if (`no_clin' == 1) local input_suf "_no_clin`input_suf'"
    local ns ""
    if ($NO_SOLO == 1) local ns "_no_solo"

    preserve
        cap use athr_id year ppr_cnt cite_affl_wt affl_wt ///
                ppr_cnt_notlast cite_affl_wt_notlast affl_wt_notlast ///
                avg_position avg_position_rat ///
                n_first_ppr n_middle_ppr n_last_ppr n_solo_ppr ///
                avg_team_size_last avg_team_size_notlast ///
                using ../external/samp/athr_panel_full_year`ns'_`samp'`input_suf', clear
        local _pos_rc = _rc
        local _nonlast_corrected = (`_pos_rc' == 0)
        if `_pos_rc' {
            cap use athr_id year ppr_cnt cite_affl_wt affl_wt ///
                    avg_position avg_position_rat ///
                    n_first_ppr n_middle_ppr n_last_ppr n_solo_ppr ///
                    avg_team_size_last avg_team_size_notlast ///
                    using ../external/samp/athr_panel_full_year`ns'_`samp'`input_suf', clear
            local _pos_rc = _rc
            if `_pos_rc' {
                use athr_id year ppr_cnt cite_affl_wt affl_wt ///
                    using ../external/samp/athr_panel_full_year`ns'_`samp'`input_suf', clear
            }
            di as error "WARNING: corrected non-last outcomes unavailable; using legacy subtraction and clipping until make_athr_yr_panel is rebuilt. Non-last/position results remain provisional."
        }
        global POSITION_OUTCOMES_AVAIL = cond(`_pos_rc' == 0, 1, 0)
        rename (ppr_cnt cite_affl_wt affl_wt) (ppr_cnt_any cite_affl_wt_any affl_wt_any)
        save ../temp/athr_any_`samp'`ns'`input_suf', replace

        bys athr_id: egen min_year_any = min(year)
        keep athr_id min_year_any
        duplicates drop
        save ../temp/athr_min_year_any_`samp'`ns'`input_suf', replace
    restore

    use ../external/samp/athr_panel_full_year_last`ns'_`samp'`input_suf',clear
    cap confirm variable cite_affl_wt_last_common n_solo_ppr
    local _last_corrected = (_rc == 0)
    if `_last_corrected' {
        gen ppr_cnt_nonsolo = ppr_cnt - n_solo_ppr
        assert ppr_cnt_nonsolo >= 0 & ppr_cnt_nonsolo <= ppr_cnt
    }
    else {
        di as error "WARNING: corrected last-author positions unavailable; using legacy non-solo construction until make_athr_yr_panel is rebuilt."
    }
    * Non-last outcomes must come from the any-author panel, not the last panel.
    foreach v in ppr_cnt_notlast cite_affl_wt_notlast affl_wt_notlast {
        cap drop `v'
    }
    if `r1_only' == 1 {
        keep if type == "r1"
        di as text "restrict_samp `samp'`suf' (r1_only=1): kept N=" _N " R1-only rows"
    }
    bys athr_id: egen max_year = max(year)
    bys athr_id: egen min_year = min(year)
    cap confirm variable avg_team_size
    if !_rc {
        gen _nonsolo_yr = year if avg_team_size > 0.001 & !mi(avg_team_size)
        bys athr_id: egen min_year_nonsolo = min(_nonsolo_yr)
        drop _nonsolo_yr
        preserve
            bys athr_id: keep if _n == 1
            qui count if mi(min_year_nonsolo)
            local n_allsolo = r(N)
            qui count
            di as text "restrict_samp `samp'`suf': min_year_nonsolo built; `n_allsolo' of " r(N) ///
                " PIs have no non-solo last-author paper (min_year_nonsolo missing)."
        restore
    }
    else di as error "restrict_samp `samp'`suf': avg_team_size not in panel -- min_year_nonsolo SKIPPED (rerun make_athr_yr_panel/code/build.do)."
    keep if min_year <= 2013
    keep if max_year >= 2015
    keep if inrange(year, 2010, 2019)
    * keep(1 3) so FOIA PIs without an imputed row survive
    merge m:1 athr_id using ../temp/exposure, keep(1 3) nogen
    merge m:1 athr_id using ../temp/observed_exposure, keep(1 3) nogen
    keep if !mi(imputed) | !mi(exposure)
    merge m:1 athr_id using ../temp/athr_cluster30, keep(1 3) nogen
    merge m:1 athr_id using ../temp/athr_min_year_any_`samp'`ns'`input_suf', keep(1 3) nogen
    replace min_year_any = min_year if mi(min_year_any)
    gen foia_athr = 1 if !mi(exposure)
    merge m:1 athr_id using ../temp/match_diag, keep(1 3) nogen
    replace max_sim = 1 if foia_athr == 1
    replace max_sim = 0 if mi(max_sim)
    bys athr_id (year): gen athr_indicator = _n == 1
    replace imputed = exposure if !mi(exposure)
    replace imputed_mkt_spend_shr = mkt_spend_shr if !mi(mkt_spend_shr)
    drop exposure
    rename imputed exposure
    drop mkt_spend_shr
    rename imputed_mkt_spend_shr mkt_spend_shr
    bys athr_id: egen num_yrs_pre = total(year < 2014)
    bys athr_id: egen num_yrs_post = total(year >= 2014)
    bys athr_id: gen tot_yrs = _N
    bys athr_id inst_id (year): gen plc_cntr = _n == 1
    bys athr_id : egen num_place = total(plc_cntr)
    drop if num_yrs_pre <=2 
    keep if num_place==1
    gegen athr = group(athr_id)
    preserve
    contract athr num_place athr_id exposure inst_id inst msa_comb msa_c_world min_year min_year_nonsolo min_year_any max_year type public mkt_spend_shr cluster_30 max_sim foia_athr
    drop _freq
    save ../temp/athr_xw, replace
    restore
    xtset athr year
    tsfill, full
    drop athr_id exposure inst_id inst msa_comb msa_c_world min_year min_year_nonsolo min_year_any max_year type public mkt_spend_shr cluster_30 max_sim foia_athr
    merge m:1 athr using ../temp/athr_xw, assert(3) keep(3) nogen
    foreach v in n_first_ppr n_middle_ppr n_last_ppr n_solo_ppr ///
                 avg_position avg_position_rat ///
                 avg_team_size_last avg_team_size_notlast {
        cap drop `v'
    }
    merge 1:1 athr_id year using ../temp/athr_any_`samp'`ns'`input_suf', keep(1 3) nogen
    foreach var in ppr_cnt cite_affl_wt affl_wt ppr_cnt_any cite_affl_wt_any affl_wt_any {
        replace `var' = 0 if mi(`var')
    }
    foreach var in n_first_ppr n_middle_ppr n_last_ppr n_solo_ppr {
        cap confirm variable `var'
        if !_rc replace `var' = 0 if mi(`var')
    }
    if `_last_corrected' {
        replace ppr_cnt_nonsolo = 0 if mi(ppr_cnt_nonsolo)
    }
    else {
        cap gen ppr_cnt_nonsolo = n_last_ppr - n_solo_ppr
    }
    cap confirm variable ppr_cnt_nonsolo
    if !_rc {
        qui sum ppr_cnt_nonsolo
        local ns_tot = r(sum)
        qui sum ppr_cnt
        local solo_shr = 100*(1 - `ns_tot'/r(sum))
        di as text "restrict_samp `samp'`suf': ppr_cnt_nonsolo built; solo papers are " ///
            %5.2f `solo_shr' "% of last-author papers."
    }
    gen pre_ppr_cnt = ppr_cnt if year < 2014
    bys athr_id: egen pre_ppr_cnt_sum = sum(pre_ppr_cnt)
    bys athr_id: egen pre_ppr_cnt_avg = mean(pre_ppr_cnt)
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
    cap confirm file ../temp/nih_athr_yr.dta
    if _rc di as error "restrict_samp `samp'`suf': ../temp/nih_athr_yr missing -- NIH outcomes unavailable this run."
    else {
        merge 1:1 athr_id year using ../temp/nih_athr_yr, keep(1 3) nogen
        merge m:1 athr_id using ../temp/nih_athr_level, keep(1 3) nogen
        replace nih_matched = 0 if mi(nih_matched)
        foreach v in n_grants n_new_grants nih_total_cost has_nih {
            replace `v' = 0 if mi(`v') & nih_matched == 1
        }
        foreach v in n_grants n_new_grants has_nih {
            replace `v' = . if nih_matched != 1 | mi(n_grants_pre) | n_grants_pre == 0
        }
        * Eligibility is fixed using pre-2014 awards, never future funding.
        replace nih_total_cost = . if nih_matched != 1 | mi(nih_cost_pre) | nih_cost_pre == 0
        qui gunique athr_id if !mi(n_grants)
        di as text "restrict_samp `samp'`suf': " r(unique) " PIs with pre-2014 research awards in the NIH grant-count sample"
        qui gunique athr_id if !mi(nih_total_cost)
        di as text "restrict_samp `samp'`suf': " r(unique) " PIs with positive pre-2014 research funding in the NIH award-amount sample"
    }

    cap confirm variable n_grants
    if _rc {
        gen byte nih_athr = 0
    }
    else {
        bys athr_id: egen byte nih_athr = max(!mi(n_grants))
    }

    if `_nonlast_corrected' {
        * Direct paper-level sums from rebuilt panels; absent author-years are zero.
        foreach v in ppr_cnt_notlast cite_affl_wt_notlast affl_wt_notlast {
            replace `v' = 0 if mi(`v')
            assert `v' >= 0 & !mi(`v')
        }
    }
    else {
        * Temporary compatibility with old panels. This reproduces old results,
        * including the known citation-weight mismatch; warnings above identify it.
        gen ppr_cnt_notlast = ppr_cnt_any - ppr_cnt
        gen cite_affl_wt_notlast = cite_affl_wt_any - cite_affl_wt
        gen affl_wt_notlast = affl_wt_any - affl_wt
        foreach v in ppr_cnt_notlast cite_affl_wt_notlast affl_wt_notlast {
            replace `v' = 0 if `v' < 0
        }
    }
    foreach v in cite_affl_wt affl_wt cite_affl_wt_any affl_wt_any ///
                 cite_affl_wt_notlast affl_wt_notlast {
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
    local out_suf `suf'
    if `hisim' > 0 {
        bys athr_id: gen byte _hs_one = _n == 1
        qui _pctile max_sim if _hs_one == 1 & foia_athr != 1, p(`=100 - `hisim'')
        local hs_cut = r(r1)
        qui gunique athr_id
        local hs_n0 = r(unique)
        keep if max_sim >= `hs_cut'
        drop _hs_one
        qui gunique athr_id
        di as text "restrict_samp `samp'`suf' hisim=`hisim': max_sim cut=" %6.4f `hs_cut' ///
            "  PIs kept " r(unique) " / `hs_n0'"
        local out_suf _hisim`hisim'`suf'
    }
    preserve
        keep if foia_athr != 1
        bys athr_id: keep if _n == 1
        keep athr_id exposure mkt_spend_shr
        rename (exposure mkt_spend_shr) (imputed imputed_mkt_spend_shr)
        save ../output/prepped_samples/exposure_inputs_`samp'`out_suf', replace
    restore
    save ../output/prepped_samples/es_`samp'`out_suf', replace
end

program exit_panel
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"
    local input_suf ""
    if (`r1r2' == 1 & `public' == 0) local input_suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local input_suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local input_suf "_r1_r2"
    if (`r1_only' == 1 & `public' == 1) local input_suf "_r1_r2_public"
    if (`no_clin' == 1) local input_suf "_no_clin`input_suf'"
    local ns ""
    if ($NO_SOLO == 1) local ns "_no_solo"

    * Exit sample is built from the raw last-author panel: the main sample
    * conditions on publishing in 2015+, which removes exiters by construction.
    use athr_id year ppr_cnt inst_id type using ///
        ../external/samp/athr_panel_full_year_last`ns'_`samp'`input_suf', clear
    if `r1_only' == 1 keep if type == "r1"
    keep if ppr_cnt > 0
    bys athr_id: egen min_year = min(year)
    bys athr_id: egen byte active_pre = max(inrange(year, 2010, 2013))
    keep if active_pre == 1
    keep if inrange(year, 2010, 2024)
    gen byte pub = 1
    gen _pre_ppr = ppr_cnt if year < 2014
    bys athr_id: egen pre_ppr_cnt_sum = total(_pre_ppr)
    gen _pre_yr = year if year < 2014
    bys athr_id: egen _last_pre = max(_pre_yr)
    gen inst_pre = inst_id if year == _last_pre
    gsort athr_id -inst_pre
    by athr_id: replace inst_pre = inst_pre[1]
    drop _pre_ppr _pre_yr _last_pre
    gegen athr = group(athr_id)
    preserve
        contract athr athr_id min_year inst_pre pre_ppr_cnt_sum
        drop _freq
        save ../temp/exit_xw_`samp'`suf', replace
    restore
    keep athr year pub
    xtset athr year
    tsfill, full
    replace pub = 0 if mi(pub)
    merge m:1 athr using ../temp/exit_xw_`samp'`suf', assert(3) keep(3) nogen

    * Exit (Hill-Stein five-year gap): five consecutive years with no
    * last-author paper, first empty year in 2014-2019 so the gap begins
    * before COVID. Window definitions (no paper in 2020-22 / 2020-24) are
    * kept as alternatives.
    sort athr year
    by athr: gen zrun = pub == 0 if _n == 1
    by athr: replace zrun = cond(pub == 0, zrun[_n-1] + 1, 0) if _n > 1
    bys athr: egen byte exit_gap  = max(zrun >= 5 & inrange(year, 2018, 2023))
    bys athr: egen byte _pub_2022 = max(pub == 1 & inrange(year, 2020, 2022))
    bys athr: egen byte _pub_2024 = max(pub == 1 & inrange(year, 2020, 2024))
    gen byte exit_2022 = 1 - _pub_2022
    gen byte exit_2024 = 1 - _pub_2024
    preserve
        keep athr_id year pub
        save ../output/prepped_samples/exit_panel_`samp'`suf', replace
    restore
    keep if year == 2014
    keep athr_id min_year inst_pre pre_ppr_cnt_sum exit_gap exit_2022 exit_2024
    merge m:1 athr_id using ../temp/exposure, keep(1 3) nogen
    merge m:1 athr_id using ../temp/observed_exposure, keep(1 3) nogen
    keep if !mi(imputed) | !mi(exposure)
    gen byte foia_athr = !mi(exposure)
    replace imputed = exposure if !mi(exposure)
    replace imputed_mkt_spend_shr = mkt_spend_shr if !mi(mkt_spend_shr)
    drop exposure mkt_spend_shr
    rename (imputed imputed_mkt_spend_shr) (exposure mkt_spend_shr)
    merge m:1 athr_id using ../temp/athr_cluster30, keep(1 3) nogen
    merge m:1 athr_id using ../temp/match_diag, keep(1 3) nogen
    replace max_sim = 1 if foia_athr == 1
    replace max_sim = 0 if mi(max_sim)
    drop if mi(exposure)
    drop if mi(mkt_spend_shr) | mkt_spend_shr <= 0
    drop if mi(cluster_30)
    qui count
    local n_raw = r(N)

    * Same PIs as the main analysis sample.
    preserve
        use athr_id using ../output/prepped_samples/es_`samp'`suf', clear
        duplicates drop
        save ../temp/exit_panel_ids_`samp'`suf', replace
    restore
    merge 1:1 athr_id using ../temp/exit_panel_ids_`samp'`suf', keep(3) nogen
    qui count
    local n_all = r(N)

    qui sum min_year, d
    local lastyr_med = r(p50)
    gen byte young = min_year >  `lastyr_med'
    gen byte old   = min_year <= `lastyr_med'
    gen byte all   = 1
    qui sum exit_2022
    local m_2022 = r(mean)
    qui sum exit_2024
    local m_2024 = r(mean)
    qui sum exit_gap
    local m_gap = r(mean)
    di as text "exit_analysis `samp'`suf': `n_raw' PIs active 2010-2013 with exposure; `n_all' in the main panel" ///
        "; min_year median=`lastyr_med'"
    di as text "exit_analysis `samp'`suf': 5-yr gap exit rate=" %5.3f `m_gap' ///
        " (no pub 2020-22: " %5.3f `m_2022' ", no pub 2020-24: " %5.3f `m_2024' ")"
    cap mkdir ../output/prepped_samples
    save ../output/prepped_samples/exit_`samp'`suf', replace
end

main
