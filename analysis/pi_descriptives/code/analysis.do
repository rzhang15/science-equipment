set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17
set maxvar 120000, perm

program main
    gather_external_data
    raw_labels
    foreach samp in all_jrnls_r1_r2 all_jrnls_r1_r2_public {
        cap mkdir "../output/figures/`samp'"
        cap mkdir "../output/tables/`samp'"
        restrict_samp, samp(`samp')
        describe_pis,          samp(`samp')
        describe_over_time,    samp(`samp')
        plot_time_series,      samp(`samp')
        plot_ts_by_exposure,   samp(`samp')
        plot_grant_trends,     samp(`samp')
        plot_distributions,    samp(`samp')
        plot_raw_overall,      samp(`samp')
        describe_by_inst,      samp(`samp')
    }
end

program raw_labels
    global lbl_ppr_cnt              "Publications per PI-year (last author)"
    global lbl_ppr_cnt_any          "Publications per PI-year (any position)"
    global lbl_cite_affl_wt         "Citation-weighted output (last author)"
    global lbl_cite_affl_wt_any     "Citation-weighted output (any position)"
    global lbl_affl_wt              "Affiliation-weighted pubs (last author)"
    global lbl_affl_wt_any          "Affiliation-weighted pubs (any position)"
    global lbl_n_first_ppr          "First-author publications"
    global lbl_n_middle_ppr         "Middle-author publications"
    global lbl_n_last_ppr           "Last-author publications"
    global lbl_avg_position         "Avg author position"
    global lbl_avg_position_rat     "Avg author position (relative)"
    global lbl_avg_team_size_last   "Team size (last-author papers)"
    global lbl_avg_team_size_notlast "Team size (non-last-author papers)"
    global lbl_avg_num_coathrs      "Coauthors per PI-year"
    global lbl_num_grants           "# grants per PI-year (OpenAlex-linked)"
    global lbl_n_grants             "# NIH grants per PI-year (as coded)"
    global lbl_nih_total_cost       "NIH funding per PI-year (USD, as coded)"
    global lbl_n_grants_raw         "# active NIH grants (raw RePORTER)"
    global lbl_n_new_raw            "# new NIH grants (flow, raw)"
    global lbl_nih_cost_raw         "NIH award dollars (raw)"
    global lbl_has_nih              "Share with >=1 NIH grant (as coded)"
    global lbl_has_grant_raw        "Share with >=1 active NIH grant (raw)"
    global lbl_in_pub_panel         "Share of PI-years in the publication panel"
    global lbl_pub_any              "Share with any last-author pub"
    global lbl_grants_per_paper     "Grants per paper (OpenAlex-linked)"
    global lbl_grant_density        "Grants per pre-period paper (OpenAlex-linked)"
    global lbl_nih_per_paper        "NIH grants per paper"
    global lbl_nih_density          "NIH grants per pre-period paper"
    global lbl_tot_ppr              "Total last-author pubs 2010-2019"
    global lbl_tot_ppr_any          "Total pubs, any position, 2010-2019"
    global lbl_tot_cite             "Total citation-weighted output 2010-2019"
    global lbl_tot_num_grants       "Total grants 2010-2019 (OpenAlex-linked)"
    global lbl_tot_n_grants         "Total NIH grants 2010-2019"
    global lbl_tot_nih_cost         "Total NIH funding 2010-2019 (USD)"
    global lbl_pre_ppr_cnt_sum      "Pre-2014 total publications"
    global lbl_pre_ppr_cnt_avg      "Pre-2014 avg publications per year"
    global lbl_exposure             "Exposure (observed or imputed)"
    global lbl_mkt_spend_shr        "Sum of product-market spending shares"
    global lbl_max_sim              "Max FOIA match similarity"
    global lbl_age_2014             "Approx career age at 2014"
end

program gather_external_data
    import delimited ../external/exposure/final_imputed_shift_share_hc_cf, clear
    rename exposure_ss imputed
    rename sum_imputed_shares imputed_mkt_spend_shr
    save ../temp/exposure, replace

    use ../external/grants/pi_grants_clean, clear
    bys athr_id year: gen num_grants = _N
    contract athr_id year num_grants
    drop _freq
    save ../temp/athr_yr_grnt_cnt, replace

    import delimited ../external/cluster/author_static_clusters_30.csv, clear varnames(1)
    cap tostring athr_id, replace
    rename cluster_label cluster_30
    save ../temp/athr_cluster30, replace

    use athr_id max_sim using ../external/exposure/match_diagnostics, clear
    save ../temp/match_diag, replace

    build_raw_nih
end

* ---------------------------------------------------------------------------
* Author-year NIH measures built straight off the grant-level file. The shipped
* n_grants / nih_total_cost are merged onto the last-author publication panel
* with keep(1 3), so a PI-year with an active award but no last-author paper is
* dropped there and then zero-filled downstream. These *_raw measures carry no
* publication-panel filter and are the ones to trust for a level trend.
* ---------------------------------------------------------------------------
program build_raw_nih
    use athr_id year grant_key row_key research total_cost start_year ///
        using ../external/nih_panel/nih_grants_by_athr_id, clear
    drop if mi(year)
    duplicates drop athr_id year row_key, force

    egen byte tag_res = tag(athr_id year grant_key) if research
    gen byte res_grant = tag_res == 1
    gen byte new_grant = res_grant & start_year == year
    gen double res_cost = total_cost if research
    gcollapse (sum) n_grants_raw = res_grant ///
              (sum) n_new_raw    = new_grant ///
              (sum) nih_cost_raw = res_cost, by(athr_id year) fast
    save ../temp/nih_raw_athr_yr, replace

    use athr_id using ../external/nih_panel/nih_grants_by_athr_id, clear
    duplicates drop
    gen byte reporter_matched = 1
    save ../temp/nih_reporter_matched, replace
end

program restrict_samp
    syntax, samp(string)
    preserve
        cap use athr_id year ppr_cnt cite_affl_wt affl_wt ///
                avg_position avg_position_rat ///
                n_first_ppr n_middle_ppr n_last_ppr ///
                avg_team_size_last avg_team_size_notlast ///
                using ../external/nih_panel/athr_panel_full_year_`samp'_with_nih, clear
        local _pos_rc = _rc
        if `_pos_rc' {
            di as text "restrict_samp `samp': position vars not in panel; falling back."
            use athr_id year ppr_cnt cite_affl_wt affl_wt ///
                using ../external/nih_panel/athr_panel_full_year_`samp'_with_nih, clear
        }
        global POSITION_OUTCOMES_AVAIL = cond(`_pos_rc' == 0, 1, 0)
        rename (ppr_cnt cite_affl_wt affl_wt) (ppr_cnt_any cite_affl_wt_any affl_wt_any)
        save ../temp/athr_any_`samp', replace

        bys athr_id: egen min_year_any = min(year)
        keep athr_id min_year_any
        duplicates drop
        save ../temp/athr_min_year_any_`samp', replace
    restore

    * Main (last-author) panel + NIH fields carried through
    use ../external/nih_panel/athr_panel_full_year_last_`samp'_with_nih, clear
    bys athr_id: egen max_year = max(year)
    bys athr_id: egen min_year = min(year)
    keep if min_year <= 2013
    keep if max_year >= 2015
    keep if inrange(year, 2010, 2019)
    merge m:1 athr_id using ../temp/exposure, keep(3) nogen
    merge m:1 athr_id using ../external/real_exposure/athr_exposure_hc, keep(1 3) nogen
    merge m:1 athr_id using ../temp/athr_cluster30, keep(1 3) nogen
    merge m:1 athr_id using ../temp/athr_min_year_any_`samp', keep(1 3) nogen
    replace min_year_any = min_year if mi(min_year_any)
    gen foia_athr = 1 if !mi(exposure)
    merge m:1 athr_id using ../temp/match_diag, keep(1 3) nogen
    replace max_sim = 1 if foia_athr == 1
    replace max_sim = 0 if mi(max_sim)
    bys athr_id: gen athr_indicator = _n == 1
    replace imputed = exposure if !mi(exposure)
    replace imputed_mkt_spend_shr = mkt_spend_shr if !mi(mkt_spend_shr)
    drop exposure
    rename imputed exposure
    drop mkt_spend_shr
    rename imputed_mkt_spend_shr mkt_spend_shr
    bys athr_id: egen num_yrs_pre = total(year < 2014)
    bys athr_id: gen tot_yrs = _N
    bys athr_id inst_id: gen plc_cntr = _n == 1
    bys athr_id: egen num_place = total(plc_cntr)
    drop if num_yrs_pre <= 2
    keep if num_place == 1
    gegen athr = group(athr_id)

    preserve
        contract athr num_place athr_id exposure inst_id inst msa_comb msa_c_world ///
                 min_year min_year_any type public mkt_spend_shr cluster_30 max_sim foia_athr ///
                 nih_pi_name nih_org_name nih_athr_name
        drop _freq
        save ../temp/athr_xw_`samp', replace
    restore

    * Flags rows that exist in the last-author publication panel. tsfill'd rows
    * (in_pub_panel==0) are exactly the PI-years where the shipped NIH measures
    * were dropped upstream and are zero-filled here.
    gen byte in_pub_panel = 1
    xtset athr year
    tsfill, full
    replace in_pub_panel = 0 if mi(in_pub_panel)
    drop athr_id exposure inst_id inst msa_comb msa_c_world min_year min_year_any ///
         type public mkt_spend_shr cluster_30 max_sim foia_athr ///
         nih_pi_name nih_org_name nih_athr_name
    merge m:1 athr using ../temp/athr_xw_`samp', assert(3) keep(3) nogen

    foreach v in n_first_ppr n_middle_ppr n_last_ppr n_solo_ppr ///
                 avg_position avg_position_rat ///
                 avg_team_size_last avg_team_size_notlast {
        cap drop `v'
    }
    merge 1:1 athr_id year using ../temp/athr_any_`samp', keep(1 3) nogen
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
    * Both p5 cuts from the pre-trim distribution, matching reduced_form
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
    replace avg_num_coathrs = . if ppr_cnt_any == 0
    merge 1:1 athr_id year using ../temp/athr_yr_grnt_cnt, keep(1 3) nogen
    replace num_grants = 0 if mi(num_grants)

    * NIH fields: zero-fill counts / cost; leave PI/org name blanks alone
    foreach v in n_grants nih_total_cost {
        cap confirm variable `v'
        if !_rc replace `v' = 0 if mi(`v')
    }
    cap drop has_nih
    gen byte has_nih = n_grants > 0 if !mi(n_grants)

    merge 1:1 athr_id year using ../temp/nih_raw_athr_yr, keep(1 3) nogen
    merge m:1 athr_id using ../temp/nih_reporter_matched, keep(1 3) nogen
    replace reporter_matched = 0 if mi(reporter_matched)
    foreach v in n_grants_raw n_new_raw nih_cost_raw {
        replace `v' = 0 if mi(`v') & reporter_matched == 1
        replace `v' = . if reporter_matched == 0
    }
    gen byte has_grant_raw = n_grants_raw > 0 if !mi(n_grants_raw)
    gen double grant_gap = n_grants_raw - n_grants if !mi(n_grants_raw)
    bys athr_id: egen pre_raw = max(cond(year < 2014, n_grants_raw, .))
    gen byte pre_holder = pre_raw > 0 & !mi(pre_raw)

    gen grants_per_paper = num_grants / ppr_cnt         if ppr_cnt > 0
    gen grant_density    = num_grants / pre_ppr_cnt_avg if pre_ppr_cnt_avg > 0
    gen nih_per_paper    = n_grants   / ppr_cnt         if ppr_cnt > 0
    gen nih_density      = n_grants   / pre_ppr_cnt_avg if pre_ppr_cnt_avg > 0

    * PI-level indicator refreshed after all merges/drops
    cap drop athr_indicator
    bys athr_id: gen athr_indicator = _n == 1

    assert !mi(athr_id)
    assert !mi(exposure)
    assert !mi(mkt_spend_shr)
    cap mkdir ../output/prepped_samples
    compress
    save ../output/prepped_samples/pi_desc_`samp', replace
end

* ---------------------------------------------------------------------------
* PI-level summary: N, share w/ NIH grant, share FOIA, share public inst,
*                   share top-15, share broad_affl, plus distributions of
*                   pre-period publication and NIH grant intensity
* ---------------------------------------------------------------------------
program describe_pis
    syntax, samp(string)
    use ../output/prepped_samples/pi_desc_`samp', clear

    * PI-level dataset (one row per athr_id) built from time-invariant vars
    * plus PI-level totals of time-varying counts across the observed window.
    preserve
        bys athr_id: egen tot_ppr        = total(ppr_cnt)
        bys athr_id: egen tot_ppr_any    = total(ppr_cnt_any)
        bys athr_id: egen tot_cite       = total(cite_affl_wt)
        bys athr_id: egen tot_num_grants = total(num_grants)
        bys athr_id: egen tot_n_grants   = total(n_grants)
        bys athr_id: egen tot_nih_cost   = total(nih_total_cost)
        bys athr_id: egen any_nih_pi     = max(has_nih)
        keep if athr_indicator == 1
        keep athr_id foia_athr tot_ppr tot_ppr_any tot_cite tot_num_grants ///
             tot_n_grants tot_nih_cost any_nih_pi pre_ppr_cnt_sum pre_ppr_cnt_avg ///
             exposure mkt_spend_shr max_sim public control broad_affl hhmi_affl ///
             has_top_15 age_2014 cluster_30 inst_id inst msa_comb type ///
             nih_pi_name nih_org_name nih_athr_name
        save ../temp/pi_level_`samp', replace

        cap mat drop pi_summary
        local rownames ""

        qui count
        local n_pi = r(N)
        mat pi_summary = nullmat(pi_summary) \ (`n_pi', .)
        local rownames "`rownames' N_PIs"

        qui count if foia_athr == 1
        local n_foia = r(N)
        mat pi_summary = nullmat(pi_summary) \ (`n_foia', `n_foia'/`n_pi')
        local rownames "`rownames' N_FOIA_PIs"

        qui count if any_nih_pi == 1
        local n_nih = r(N)
        mat pi_summary = nullmat(pi_summary) \ (`n_nih', `n_nih'/`n_pi')
        local rownames "`rownames' N_PIs_matched_NIH"

        qui count if foia_athr == 1 & any_nih_pi == 1
        local n_foia_nih = r(N)
        mat pi_summary = nullmat(pi_summary) \ (`n_foia_nih', ///
            cond(`n_foia' > 0, `n_foia_nih'/`n_foia', .))
        local rownames "`rownames' N_FOIA_and_NIH"

        foreach v in public broad_affl hhmi_affl has_top_15 {
            qui count if `v' == 1
            local n = r(N)
            mat pi_summary = nullmat(pi_summary) \ (`n', `n'/`n_pi')
            local rownames "`rownames' N_`v'"
        }

        mat colnames pi_summary = N Share
        mat rownames pi_summary = `rownames'

        qui matrix_to_txt, saving("../output/tables/`samp'/pi_summary.txt") ///
            matrix(pi_summary) title(<tab:pi_summary_`samp'>) format(%14.4f) replace

        * PI-level distributions
        cap mat drop pi_dist
        local rownames_d ""
        foreach v in pre_ppr_cnt_sum pre_ppr_cnt_avg tot_ppr tot_ppr_any tot_cite ///
                     tot_num_grants tot_n_grants tot_nih_cost exposure mkt_spend_shr ///
                     max_sim age_2014 {
            qui sum `v', d
            mat pi_dist = nullmat(pi_dist) \ (r(mean), r(sd), r(p10), r(p25), ///
                r(p50), r(p75), r(p90), r(p99), r(N))
            local rownames_d "`rownames_d' `v'"
        }
        mat colnames pi_dist = mean sd p10 p25 p50 p75 p90 p99 N
        mat rownames pi_dist = `rownames_d'
        qui matrix_to_txt, saving("../output/tables/`samp'/pi_distributions.txt") ///
            matrix(pi_dist) title(<tab:pi_distributions_`samp'>) format(%14.4f) replace

        di as text "describe_pis `samp': N=" `n_pi' "  FOIA=" `n_foia' "  NIH-matched=" `n_nih'
    restore
end

* ---------------------------------------------------------------------------
* Year-level totals + means (all PIs vs FOIA-PIs vs NIH-matched)
* ---------------------------------------------------------------------------
program describe_over_time
    syntax, samp(string)
    use ../output/prepped_samples/pi_desc_`samp', clear

    preserve
        gen one = 1
        gcollapse (sum) n_pi_active = one ///
                  (sum) total_ppr        = ppr_cnt ///
                  (sum) total_ppr_any    = ppr_cnt_any ///
                  (sum) total_cite       = cite_affl_wt ///
                  (sum) total_num_grants = num_grants ///
                  (sum) total_n_grants   = n_grants ///
                  (sum) total_nih_cost   = nih_total_cost ///
                  (mean) mean_ppr        = ppr_cnt ///
                  (mean) mean_ppr_any    = ppr_cnt_any ///
                  (mean) mean_cite       = cite_affl_wt ///
                  (mean) mean_num_grants = num_grants ///
                  (mean) mean_n_grants   = n_grants ///
                  (mean) mean_nih_cost   = nih_total_cost ///
                  (mean) mean_team_last  = avg_team_size_last ///
                  (mean) mean_coathrs    = avg_num_coathrs ///
                  (mean) mean_grants_raw = n_grants_raw ///
                  (mean) mean_new_raw    = n_new_raw ///
                  (mean) mean_cost_raw   = nih_cost_raw ///
                  (mean) share_in_panel  = in_pub_panel, ///
                  by(year) fast
        order year n_pi_active total_* mean_*
        list, sep(0) noobs abbrev(20)
        export delimited using ../output/tables/`samp'/year_totals_all_pis.csv, replace
    restore

    * Same collapse restricted to FOIA PIs (the treated set)
    preserve
        keep if foia_athr == 1
        gen one = 1
        gcollapse (sum) n_pi_active = one ///
                  (sum) total_ppr        = ppr_cnt ///
                  (sum) total_ppr_any    = ppr_cnt_any ///
                  (sum) total_cite       = cite_affl_wt ///
                  (sum) total_num_grants = num_grants ///
                  (sum) total_n_grants   = n_grants ///
                  (sum) total_nih_cost   = nih_total_cost ///
                  (mean) mean_ppr        = ppr_cnt ///
                  (mean) mean_ppr_any    = ppr_cnt_any ///
                  (mean) mean_cite       = cite_affl_wt ///
                  (mean) mean_num_grants = num_grants ///
                  (mean) mean_n_grants   = n_grants ///
                  (mean) mean_nih_cost   = nih_total_cost ///
                  (mean) mean_team_last  = avg_team_size_last ///
                  (mean) mean_coathrs    = avg_num_coathrs, ///
                  by(year) fast
        export delimited using ../output/tables/`samp'/year_totals_foia_pis.csv, replace
    restore

    * Only NIH-matched PIs
    preserve
        keep if has_nih == 1
        gen one = 1
        gcollapse (sum) n_pi_active = one ///
                  (sum) total_n_grants   = n_grants ///
                  (sum) total_nih_cost   = nih_total_cost ///
                  (mean) mean_n_grants   = n_grants ///
                  (mean) mean_nih_cost   = nih_total_cost, ///
                  by(year) fast
        export delimited using ../output/tables/`samp'/year_totals_nih_matched_pis.csv, replace
    restore
end

* ---------------------------------------------------------------------------
* Time-series plots (all-PI vs FOIA-PI overlay)
* ---------------------------------------------------------------------------
program plot_time_series
    syntax, samp(string)
    use ../output/prepped_samples/pi_desc_`samp', clear

    * Collapse to yearly means, split by foia_athr
    preserve
        gen one = 1
        gcollapse (mean) mean_ppr        = ppr_cnt ///
                  (mean) mean_ppr_any    = ppr_cnt_any ///
                  (mean) mean_cite       = cite_affl_wt ///
                  (mean) mean_num_grants = num_grants ///
                  (mean) mean_n_grants   = n_grants ///
                  (mean) mean_nih_cost   = nih_total_cost ///
                  (mean) mean_team_last  = avg_team_size_last ///
                  (mean) mean_coathrs    = avg_num_coathrs ///
                  (sum)  n_pi_active     = one, ///
                  by(year foia_athr) fast
        save ../temp/yr_means_by_foia_`samp', replace
    restore

    use ../temp/yr_means_by_foia_`samp', clear

    * Recenter each FOIA-group series at its own 2013 value (0 at 2013)
    gen byte foia_grp = foia_athr == 1
    foreach y in mean_ppr mean_ppr_any mean_cite mean_num_grants mean_n_grants ///
                 mean_nih_cost mean_team_last mean_coathrs {
        gen _base = `y' if year == 2013
        bys foia_grp: egen `y'_base = max(_base)
        drop _base
        gen `y'_c = `y' - `y'_base
    }
    sort foia_grp year

    * Two-line overlay: FOIA vs non-FOIA. Uses ebblue + dkorange per house style.
    foreach y in mean_ppr mean_ppr_any mean_cite mean_num_grants mean_n_grants ///
                 mean_nih_cost mean_team_last mean_coathrs n_pi_active {
        if "`y'" == "mean_ppr"        local ytitle "Avg publications per PI (last author)"
        if "`y'" == "mean_ppr_any"    local ytitle "Avg publications per PI (any position)"
        if "`y'" == "mean_cite"       local ytitle "Avg citation-weighted output"
        if "`y'" == "mean_num_grants" local ytitle "Avg # grants per PI (OpenAlex-linked)"
        if "`y'" == "mean_n_grants"   local ytitle "Avg # NIH grants per PI"
        if "`y'" == "mean_nih_cost"   local ytitle "Avg NIH funding per PI (USD)"
        if "`y'" == "mean_team_last"  local ytitle "Avg team size (last-author papers)"
        if "`y'" == "mean_coathrs"    local ytitle "Avg # coauthors per PI"
        if "`y'" == "n_pi_active"     local ytitle "# PIs active in year"

        tw (line `y' year if foia_athr == 1, lcolor(dkorange) lwidth(medthick)) ///
           (line `y' year if mi(foia_athr), lcolor(ebblue) lwidth(medthick)), ///
           xlab(2010(1)2019) xtitle("Year") ytitle("`ytitle'") ///
           xline(2014, lpattern(dash) lcolor(gs10)) ///
           legend(order(1 "FOIA PIs" 2 "Non-FOIA PIs") pos(6) ring(1) rows(1)) ///
           plotregion(margin(sides))
        graph export ../output/figures/`samp'/ts_`y'.pdf, replace

        if "`y'" != "n_pi_active" {
            tw (line `y'_c year if foia_athr == 1, lcolor(dkorange) lwidth(medthick)) ///
               (line `y'_c year if mi(foia_athr), lcolor(ebblue) lwidth(medthick)), ///
               xlab(2010(1)2019) xtitle("Year") ytitle("`ytitle' (recentered at 2013)") ///
               xline(2014, lpattern(dash) lcolor(gs10)) ///
               yline(0, lcolor(gs10) lpattern(solid)) ///
               legend(order(1 "FOIA PIs" 2 "Non-FOIA PIs") pos(6) ring(1) rows(1)) ///
               plotregion(margin(sides))
            graph export ../output/figures/`samp'/ts_recentered_`y'.pdf, replace
        }
    }

    * Pooled (all PIs, no split) time series — same series, single line
    preserve
        use ../output/prepped_samples/pi_desc_`samp', clear
        gen one = 1
        gcollapse (mean) mean_ppr        = ppr_cnt ///
                  (mean) mean_ppr_any    = ppr_cnt_any ///
                  (mean) mean_cite       = cite_affl_wt ///
                  (mean) mean_num_grants = num_grants ///
                  (mean) mean_n_grants   = n_grants ///
                  (mean) mean_nih_cost   = nih_total_cost ///
                  (mean) mean_team_last  = avg_team_size_last ///
                  (mean) mean_coathrs    = avg_num_coathrs ///
                  (sum)  n_pi_active     = one, ///
                  by(year) fast
        save ../temp/yr_means_pooled_`samp', replace
    restore
    use ../temp/yr_means_pooled_`samp', clear

    foreach y in mean_ppr mean_ppr_any mean_cite mean_num_grants mean_n_grants ///
                 mean_nih_cost mean_team_last mean_coathrs n_pi_active {
        if "`y'" == "mean_ppr"        local ytitle "Avg publications per PI (last author)"
        if "`y'" == "mean_ppr_any"    local ytitle "Avg publications per PI (any position)"
        if "`y'" == "mean_cite"       local ytitle "Avg citation-weighted output"
        if "`y'" == "mean_num_grants" local ytitle "Avg # grants per PI (OpenAlex-linked)"
        if "`y'" == "mean_n_grants"   local ytitle "Avg # NIH grants per PI"
        if "`y'" == "mean_nih_cost"   local ytitle "Avg NIH funding per PI (USD)"
        if "`y'" == "mean_team_last"  local ytitle "Avg team size (last-author papers)"
        if "`y'" == "mean_coathrs"    local ytitle "Avg # coauthors per PI"
        if "`y'" == "n_pi_active"     local ytitle "# PIs active in year"

        tw (line `y' year, lcolor(ebblue) lwidth(medthick)), ///
            xlab(2010(1)2019) xtitle("Year") ytitle("`ytitle'") ///
            xline(2014, lpattern(dash) lcolor(gs10)) ///
            legend(off) plotregion(margin(sides))
        graph export ../output/figures/`samp'/ts_pooled_`y'.pdf, replace
    }
end

* ---------------------------------------------------------------------------
* Time-series plots split by exposure quartile — the "most exposed vs less
* exposed" cut. Two variants:
*   (a) quartiles among ALL PIs on the analysis-sample exposure measure
*       (imputed for non-FOIA PIs). This is the treatment-intensity split
*       reduced_form uses.
*   (b) quartiles among FOIA PIs only, using real observed exposure.
* Pre-period divergence would flag a differential-trends concern.
* ---------------------------------------------------------------------------
program plot_ts_by_exposure
    syntax, samp(string)
    use ../output/prepped_samples/pi_desc_`samp', clear

    * PI-level quartile assignment (exposure is constant within athr_id)
    xtile _q_all = exposure if athr_indicator == 1, nq(4)
    bys athr_id: egen exp_q4 = max(_q_all)
    drop _q_all
    xtile _q_foia = exposure if athr_indicator == 1 & foia_athr == 1, nq(4)
    bys athr_id: egen foia_exp_q4 = max(_q_foia)
    drop _q_foia

    * Report the exposure cut points so the labels have context
    preserve
        keep if athr_indicator == 1
        di as text _n "===== exposure quartile cuts (all PIs) ====="
        tabstat exposure, by(exp_q4) stat(min max mean n) columns(stat)
        di as text _n "===== exposure quartile cuts (FOIA PIs only) ====="
        tabstat exposure if foia_athr == 1, by(foia_exp_q4) stat(min max mean n) columns(stat)
    restore

    * Snapshot the panel with both quartile assignments so we can reload it
    * at the top of each loop iteration (the first iteration's collapse
    * replaces the in-memory data).
    save ../temp/pi_desc_expQ_`samp', replace

    foreach grpvar in exp_q4 foia_exp_q4 {
        local suf = cond("`grpvar'" == "exp_q4", "expQ4", "foiaExpQ4")
        local title_grp = cond("`grpvar'" == "exp_q4", "all PIs", "FOIA PIs only")

        use ../temp/pi_desc_expQ_`samp', clear
        gen one = 1
        * Decompose the common decline: extensive margin (share publishing at
        * all) vs intensive margin (mean pubs conditional on publishing).
        * Attrition-with-zeros shows up in share_pub; true intensity in
        * mean_ppr_cond.
        gen byte pub_any = ppr_cnt > 0
        gen ppr_pos = ppr_cnt if ppr_cnt > 0
        gcollapse (mean) mean_ppr        = ppr_cnt ///
                  (mean) mean_ppr_any    = ppr_cnt_any ///
                  (mean) mean_cite       = cite_affl_wt ///
                  (mean) mean_num_grants = num_grants ///
                  (mean) mean_n_grants   = n_grants ///
                  (mean) mean_nih_cost   = nih_total_cost ///
                  (mean) mean_team_last  = avg_team_size_last ///
                  (mean) mean_coathrs    = avg_num_coathrs ///
                  (mean) share_pub       = pub_any ///
                  (mean) mean_ppr_cond   = ppr_pos ///
                  (mean) mean_grants_raw = n_grants_raw ///
                  (mean) mean_new_raw    = n_new_raw ///
                  (mean) mean_cost_raw   = nih_cost_raw ///
                  (mean) share_grant_raw = has_grant_raw ///
                  (mean) share_in_panel  = in_pub_panel ///
                  (sum)  n_pi_active     = one, ///
                  by(year `grpvar') fast
        drop if mi(`grpvar')

        * Recenter each series so line hits 0 at 2013: subtract each group's
        * 2013 value from every year. Groups missing 2013 stay missing (no
        * base to anchor to — flagged in the log).
        foreach y in mean_ppr mean_ppr_any mean_cite mean_num_grants ///
                     mean_n_grants mean_nih_cost mean_team_last mean_coathrs ///
                     share_pub mean_ppr_cond mean_grants_raw mean_new_raw ///
                     mean_cost_raw share_grant_raw share_in_panel {
            gen _base = `y' if year == 2013
            bys `grpvar': egen `y'_base = max(_base)
            drop _base
            gen `y'_c = `y' - `y'_base
            qui count if mi(`y'_base)
            if r(N) > 0 di as text "  recenter `suf' `y': `r(N)' rows lack 2013 baseline"
        }
        * bys re-sorts by group only, leaving year order arbitrary within
        * group — line plots connect in data order, so re-sort before plotting
        sort `grpvar' year
        save ../temp/yr_means_by_`suf'_`samp', replace

        foreach y in mean_ppr mean_ppr_any mean_cite mean_num_grants ///
                     mean_n_grants mean_nih_cost mean_team_last mean_coathrs ///
                     share_pub mean_ppr_cond mean_grants_raw mean_new_raw ///
                     mean_cost_raw share_grant_raw share_in_panel {
            if "`y'" == "mean_ppr"        local ytitle "Avg publications per PI (last author)"
            if "`y'" == "mean_ppr_any"    local ytitle "Avg publications per PI (any position)"
            if "`y'" == "mean_cite"       local ytitle "Avg citation-weighted output"
            if "`y'" == "mean_num_grants" local ytitle "Avg # grants per PI (OpenAlex-linked)"
            if "`y'" == "mean_n_grants"   local ytitle "Avg # NIH grants per PI"
            if "`y'" == "mean_nih_cost"   local ytitle "Avg NIH funding per PI (USD)"
            if "`y'" == "mean_team_last"  local ytitle "Avg team size (last-author papers)"
            if "`y'" == "mean_coathrs"    local ytitle "Avg # coauthors per PI"
            if "`y'" == "share_pub"       local ytitle "Share of PIs with any last-author pub"
            if "`y'" == "mean_ppr_cond"   local ytitle "Avg pubs per PI, conditional on publishing"
            if "`y'" == "mean_grants_raw" local ytitle "Avg # active NIH grants (raw RePORTER)"
            if "`y'" == "mean_new_raw"    local ytitle "Avg # new NIH grants (flow, raw)"
            if "`y'" == "mean_cost_raw"   local ytitle "Avg NIH award dollars (raw)"
            if "`y'" == "share_grant_raw" local ytitle "Share holding >=1 active NIH grant (raw)"
            if "`y'" == "share_in_panel"  local ytitle "Share of PI-years in the publication panel"

            * Top vs bottom quartile only — cleanest "most vs less exposed" contrast
            tw (line `y' year if `grpvar' == 1, lcolor(ebblue) lwidth(medthick)) ///
               (line `y' year if `grpvar' == 4, lcolor(dkorange) lwidth(medthick)), ///
               xlab(2010(1)2019) xtitle("Year") ytitle("`ytitle'") ///
               xline(2014, lpattern(dash) lcolor(gs10)) ///
               legend(order(1 "Bottom quartile exposure (`title_grp')" ///
                            2 "Top quartile exposure (`title_grp')") ///
                      pos(6) ring(1) rows(1) size(small)) ///
               plotregion(margin(sides))
            graph export ../output/figures/`samp'/ts_`suf'_topbot_`y'.pdf, replace

            * All four quartiles — shows the gradient
            tw (line `y' year if `grpvar' == 1, lcolor(ebblue) lwidth(medthick)) ///
               (line `y' year if `grpvar' == 2, lcolor(ebblue%55) lwidth(medthick) lpattern(dash)) ///
               (line `y' year if `grpvar' == 3, lcolor(dkorange%55) lwidth(medthick) lpattern(dash)) ///
               (line `y' year if `grpvar' == 4, lcolor(dkorange) lwidth(medthick)), ///
               xlab(2010(1)2019) xtitle("Year") ytitle("`ytitle'") ///
               xline(2014, lpattern(dash) lcolor(gs10)) ///
               legend(order(1 "Q1 (lowest)" 2 "Q2" 3 "Q3" 4 "Q4 (highest)") ///
                      pos(6) ring(1) rows(1) size(small)) ///
               plotregion(margin(sides))
            graph export ../output/figures/`samp'/ts_`suf'_all_`y'.pdf, replace

            * Recentered versions: each line = 0 at 2013
            tw (line `y'_c year if `grpvar' == 1, lcolor(ebblue) lwidth(medthick)) ///
               (line `y'_c year if `grpvar' == 4, lcolor(dkorange) lwidth(medthick)), ///
               xlab(2010(1)2019) xtitle("Year") ytitle("`ytitle' (recentered at 2013)") ///
               xline(2014, lpattern(dash) lcolor(gs10)) ///
               yline(0, lcolor(gs10) lpattern(solid)) ///
               legend(order(1 "Bottom quartile exposure (`title_grp')" ///
                            2 "Top quartile exposure (`title_grp')") ///
                      pos(6) ring(1) rows(1) size(small)) ///
               plotregion(margin(sides))
            graph export ../output/figures/`samp'/ts_`suf'_topbot_recentered_`y'.pdf, replace

            tw (line `y'_c year if `grpvar' == 1, lcolor(ebblue) lwidth(medthick)) ///
               (line `y'_c year if `grpvar' == 2, lcolor(ebblue%55) lwidth(medthick) lpattern(dash)) ///
               (line `y'_c year if `grpvar' == 3, lcolor(dkorange%55) lwidth(medthick) lpattern(dash)) ///
               (line `y'_c year if `grpvar' == 4, lcolor(dkorange) lwidth(medthick)), ///
               xlab(2010(1)2019) xtitle("Year") ytitle("`ytitle' (recentered at 2013)") ///
               xline(2014, lpattern(dash) lcolor(gs10)) ///
               yline(0, lcolor(gs10) lpattern(solid)) ///
               legend(order(1 "Q1 (lowest)" 2 "Q2" 3 "Q3" 4 "Q4 (highest)") ///
                      pos(6) ring(1) rows(1) size(small)) ///
               plotregion(margin(sides))
            graph export ../output/figures/`samp'/ts_`suf'_all_recentered_`y'.pdf, replace
        }

        * Q4 - Q1 gap in the recentered series: nets out the common decline
        * and shows the differential path of the most- vs least-exposed as a
        * single line. Flat at 0 pre-2014 = parallel trends.
        preserve
            keep year `grpvar' *_c
            keep if inlist(`grpvar', 1, 4)
            reshape wide *_c, i(year) j(`grpvar')
            foreach y in mean_ppr mean_ppr_any mean_cite mean_num_grants ///
                         mean_n_grants mean_nih_cost mean_team_last mean_coathrs ///
                         share_pub mean_ppr_cond mean_grants_raw mean_new_raw ///
                         mean_cost_raw share_grant_raw share_in_panel {
                gen `y'_gap = `y'_c4 - `y'_c1
                if "`y'" == "mean_ppr"        local ytitle "Avg publications per PI (last author)"
                if "`y'" == "mean_ppr_any"    local ytitle "Avg publications per PI (any position)"
                if "`y'" == "mean_cite"       local ytitle "Avg citation-weighted output"
                if "`y'" == "mean_num_grants" local ytitle "Avg # grants per PI (OpenAlex-linked)"
                if "`y'" == "mean_n_grants"   local ytitle "Avg # NIH grants per PI"
                if "`y'" == "mean_nih_cost"   local ytitle "Avg NIH funding per PI (USD)"
                if "`y'" == "mean_team_last"  local ytitle "Avg team size (last-author papers)"
                if "`y'" == "mean_coathrs"    local ytitle "Avg # coauthors per PI"
                if "`y'" == "share_pub"       local ytitle "Share of PIs with any last-author pub"
                if "`y'" == "mean_ppr_cond"   local ytitle "Avg pubs per PI, conditional on publishing"
                if "`y'" == "mean_grants_raw" local ytitle "Avg # active NIH grants (raw RePORTER)"
                if "`y'" == "mean_new_raw"    local ytitle "Avg # new NIH grants (flow, raw)"
                if "`y'" == "mean_cost_raw"   local ytitle "Avg NIH award dollars (raw)"
                if "`y'" == "share_grant_raw" local ytitle "Share holding >=1 active NIH grant (raw)"
                if "`y'" == "share_in_panel"  local ytitle "Share of PI-years in the publication panel"

                tw (line `y'_gap year, lcolor(ebblue) lwidth(medthick)), ///
                   xlab(2010(1)2019) xtitle("Year") ///
                   ytitle("Q4 - Q1 gap: `ytitle'") ///
                   xline(2014, lpattern(dash) lcolor(gs10)) ///
                   yline(0, lcolor(gs10) lpattern(solid)) ///
                   legend(off) plotregion(margin(sides))
                graph export ../output/figures/`samp'/ts_`suf'_gap_`y'.pdf, replace
            }
        restore
    }
end

* ---------------------------------------------------------------------------
* Shipped vs raw NIH measures. The shipped n_grants only exists for PI-years
* that survive into the last-author publication panel; every other PI-year is
* zero-filled. If share_in_panel trends, so does the measurement error, and any
* post-period movement in a grant event study is partly that trend.
*
* Also splits the two sample-conditioning rules apart: "any grant 2010-2019"
* (the shipped rule, which conditions on a post-period outcome) vs "grant in
* 2010-2013" (pre-determined).
* ---------------------------------------------------------------------------
program plot_grant_trends
    syntax, samp(string)
    use ../output/prepped_samples/pi_desc_`samp', clear
    keep if reporter_matched == 1

    di as text _n "===== publication-panel coverage and grant understatement ====="
    table year, stat(mean in_pub_panel) stat(mean n_grants) ///
                stat(mean n_grants_raw) stat(mean grant_gap) nformat(%9.4f)

    di as text _n "===== PIs by conditioning rule ====="
    preserve
        keep if athr_indicator == 1
        qui count
        di as text "  RePORTER-matched PIs: " r(N)
        qui count if pre_holder == 1
        di as text "  holds a grant in 2010-2013 (pre-determined): " r(N)
        qui count if pre_holder == 0
        di as text "  enters only via a post-2013 grant: " r(N)
        di as text _n "  late-entrant share by exposure quartile:"
        xtile _q = exposure, nq(4)
        table _q, stat(mean pre_holder) stat(freq) nformat(%9.4f)
    restore

    xtile _q_all = exposure if athr_indicator == 1, nq(4)
    bys athr_id: egen exp_q4 = max(_q_all)
    drop _q_all

    preserve
        gcollapse (mean) ship = n_grants (mean) raw = n_grants_raw ///
                  (mean) cov = in_pub_panel, by(year) fast
        sort year
        tw (line ship year, lcolor(ebblue) lwidth(medthick)) ///
           (line raw  year, lcolor(dkorange) lwidth(medthick)), ///
           xlab(2010(1)2019) xtitle("Year") ytitle("Avg # active NIH research grants") ///
           xline(2014, lpattern(dash) lcolor(gs10)) ///
           legend(order(1 "As coded (merged through pub panel)" ///
                        2 "Raw RePORTER (no pub-panel filter)") ///
                  pos(6) ring(1) rows(1) size(small)) ///
           plotregion(margin(sides))
        graph export ../output/figures/`samp'/grants_ship_vs_raw.pdf, replace

        tw (line cov year, lcolor(ebblue) lwidth(medthick)), ///
           xlab(2010(1)2019) xtitle("Year") ///
           ytitle("Share of PI-years in the publication panel") ///
           xline(2014, lpattern(dash) lcolor(gs10)) ///
           legend(off) plotregion(margin(sides))
        graph export ../output/figures/`samp'/grants_panel_coverage.pdf, replace
        export delimited using ../output/tables/`samp'/grants_ship_vs_raw.csv, replace
    restore

    * Raw trend under each conditioning rule, top vs bottom exposure quartile.
    foreach rule in everrule prerule {
        preserve
            if "`rule'" == "prerule" keep if pre_holder == 1
            local rlab = cond("`rule'" == "prerule", ///
                "pre-2014 grant holders", "any grant 2010-2019")
            gcollapse (mean) raw = n_grants_raw (mean) new = n_new_raw ///
                      (mean) cost = nih_cost_raw (mean) share = has_grant_raw, ///
                      by(year exp_q4) fast
            drop if mi(exp_q4)
            sort exp_q4 year
            foreach y in raw new cost share {
                if "`y'" == "raw"   local yt "Avg # active NIH grants"
                if "`y'" == "new"   local yt "Avg # new NIH grants (flow)"
                if "`y'" == "cost"  local yt "Avg NIH award dollars"
                if "`y'" == "share" local yt "Share holding >=1 active grant"
                tw (line `y' year if exp_q4 == 1, lcolor(ebblue) lwidth(medthick)) ///
                   (line `y' year if exp_q4 == 4, lcolor(dkorange) lwidth(medthick)), ///
                   xlab(2010(1)2019) xtitle("Year") ytitle("`yt'") ///
                   xline(2014, lpattern(dash) lcolor(gs10)) ///
                   legend(order(1 "Q1 exposure" 2 "Q4 exposure") ///
                          pos(6) ring(1) rows(1) size(small)) ///
                   title("`rlab'", size(small)) ///
                   plotregion(margin(sides))
                graph export ../output/figures/`samp'/grants_`rule'_`y'.pdf, replace
            }
            export delimited using ../output/tables/`samp'/grants_`rule'_trends.csv, replace
        restore
    }
end

* ---------------------------------------------------------------------------
* PI-level distribution plots (histograms + kdensity) for pre-period vars
* ---------------------------------------------------------------------------
program plot_distributions
    syntax, samp(string)
    use ../temp/pi_level_`samp', clear

    * Pre-period pubs (sum + avg)
    tw hist pre_ppr_cnt_sum, bin(60) color(ebblue%70) ///
        xtitle("Pre-2014 total publications") ytitle("Density") ///
        plotregion(margin(sides))
    graph export ../output/figures/`samp'/hist_pre_ppr_cnt_sum.pdf, replace

    tw hist pre_ppr_cnt_avg, bin(60) color(ebblue%70) ///
        xtitle("Pre-2014 avg publications per year") ytitle("Density") ///
        plotregion(margin(sides))
    graph export ../output/figures/`samp'/hist_pre_ppr_cnt_avg.pdf, replace

    * Career total pubs (last author + any)
    tw hist tot_ppr, bin(60) color(ebblue%70) ///
        xtitle("Total last-author pubs 2010-2019") ytitle("Density") ///
        plotregion(margin(sides))
    graph export ../output/figures/`samp'/hist_tot_ppr.pdf, replace

    tw hist tot_ppr_any, bin(60) color(ebblue%70) ///
        xtitle("Total pubs (any position) 2010-2019") ytitle("Density") ///
        plotregion(margin(sides))
    graph export ../output/figures/`samp'/hist_tot_ppr_any.pdf, replace

    * NIH funding intensity (PIs with n_grants > 0 only)
    tw hist tot_n_grants if tot_n_grants > 0, bin(40) color(dkorange%70) ///
        xtitle("# NIH grants 2010-2019 (NIH-matched PIs)") ytitle("Density") ///
        plotregion(margin(sides))
    graph export ../output/figures/`samp'/hist_tot_n_grants.pdf, replace

    qui sum tot_nih_cost if tot_nih_cost > 0, d
    local cost_p99 = r(p99)
    tw hist tot_nih_cost if tot_nih_cost > 0 & tot_nih_cost <= `cost_p99', ///
        bin(40) color(dkorange%70) ///
        xtitle("Total NIH funding 2010-2019 (USD, p99-cut)") ytitle("Density") ///
        plotregion(margin(sides))
    graph export ../output/figures/`samp'/hist_tot_nih_cost.pdf, replace

    * Age distribution
    tw hist age_2014, bin(30) color(ebblue%70) ///
        xtitle("Approx career age at 2014 (yrs since first pub + 30)") ytitle("Density") ///
        plotregion(margin(sides))
    graph export ../output/figures/`samp'/hist_age_2014.pdf, replace

    * FOIA-vs-non-FOIA overlays for key measures
    qui sum pre_ppr_cnt_sum if foia_athr == 1, d
    local mean_f : di %5.2f r(mean)
    qui sum pre_ppr_cnt_sum if mi(foia_athr), d
    local mean_n : di %5.2f r(mean)
    tw (kdensity pre_ppr_cnt_sum if foia_athr == 1, lcolor(dkorange)) ///
       (kdensity pre_ppr_cnt_sum if mi(foia_athr),  lcolor(ebblue)),  ///
       xtitle("Pre-2014 total publications") ytitle("Density") ///
       legend(order(1 "FOIA PIs (mean=`mean_f')" 2 "Non-FOIA PIs (mean=`mean_n')") ///
           pos(6) ring(1) rows(1) size(small)) ///
       plotregion(margin(sides))
    graph export ../output/figures/`samp'/kd_pre_ppr_cnt_sum.pdf, replace

    qui sum tot_n_grants if foia_athr == 1, d
    local mean_f : di %5.2f r(mean)
    qui sum tot_n_grants if mi(foia_athr), d
    local mean_n : di %5.2f r(mean)
    tw (kdensity tot_n_grants if foia_athr == 1, lcolor(dkorange)) ///
       (kdensity tot_n_grants if mi(foia_athr),  lcolor(ebblue)),  ///
       xtitle("# NIH grants 2010-2019") ytitle("Density") ///
       legend(order(1 "FOIA PIs (mean=`mean_f')" 2 "Non-FOIA PIs (mean=`mean_n')") ///
           pos(6) ring(1) rows(1) size(small)) ///
       plotregion(margin(sides))
    graph export ../output/figures/`samp'/kd_tot_n_grants.pdf, replace
end

* ---------------------------------------------------------------------------
* Overall raw plots: every variable on its own, pooled across the whole sample
* with no exposure / FOIA / quartile split. Two figures per variable —
*   raw_ts_<var>.pdf   : pooled yearly mean, levels (not recentered)
*   raw_dist_<var>.pdf : pooled distribution over the full support
* plus a p99-trimmed distribution where the right tail dominates the axis, and
* pooled summary tables at the PI-year and PI level.
* ---------------------------------------------------------------------------
program plot_raw_overall
    syntax, samp(string)

    local cand_yr ppr_cnt ppr_cnt_any cite_affl_wt cite_affl_wt_any ///
                  affl_wt affl_wt_any n_first_ppr n_middle_ppr n_last_ppr ///
                  avg_position avg_position_rat avg_team_size_last ///
                  avg_team_size_notlast avg_num_coathrs num_grants n_grants ///
                  nih_total_cost n_grants_raw n_new_raw nih_cost_raw ///
                  grants_per_paper grant_density nih_per_paper nih_density
    local cand_bin has_nih has_grant_raw in_pub_panel pub_any
    local cand_pi  tot_ppr tot_ppr_any tot_cite tot_num_grants tot_n_grants ///
                   tot_nih_cost pre_ppr_cnt_sum pre_ppr_cnt_avg exposure ///
                   mkt_spend_shr max_sim age_2014

    use ../output/prepped_samples/pi_desc_`samp', clear
    gen byte pub_any = ppr_cnt > 0

    local yrvars ""
    foreach v in `cand_yr' `cand_bin' {
        cap confirm variable `v'
        if !_rc local yrvars "`yrvars' `v'"
    }

    preserve
        gen one = 1
        gcollapse (mean) `yrvars' (sum) n_obs = one, by(year) fast
        sort year
        export delimited using ../output/tables/`samp'/raw_year_means.csv, replace
        foreach v in `yrvars' {
            local yt "${lbl_`v'}"
            if "`yt'" == "" local yt "`v'"
            tw (line `v' year, lcolor(ebblue) lwidth(medthick)), ///
               xlab(2010(1)2019) xtitle("Year") ytitle("`yt'") ///
               xline(2014, lpattern(dash) lcolor(gs10)) ///
               legend(off) plotregion(margin(sides))
            graph export ../output/figures/`samp'/raw_ts_`v'.pdf, replace
        }
        tw (line n_obs year, lcolor(ebblue) lwidth(medthick)), ///
           xlab(2010(1)2019) xtitle("Year") ytitle("# PI-year observations") ///
           xline(2014, lpattern(dash) lcolor(gs10)) ///
           legend(off) plotregion(margin(sides))
        graph export ../output/figures/`samp'/raw_ts_n_obs.pdf, replace
    restore

    cap mat drop raw_yr_dist
    local rn_yr ""
    foreach v in `yrvars' {
        qui sum `v', d
        if r(N) == 0 continue
        mat raw_yr_dist = nullmat(raw_yr_dist) \ (r(mean), r(sd), r(min), ///
            r(p10), r(p25), r(p50), r(p75), r(p90), r(p99), r(max), r(N))
        local rn_yr "`rn_yr' `v'"
    }
    mat colnames raw_yr_dist = mean sd min p10 p25 p50 p75 p90 p99 max N
    mat rownames raw_yr_dist = `rn_yr'
    qui matrix_to_txt, saving("../output/tables/`samp'/raw_pi_year_distributions.txt") ///
        matrix(raw_yr_dist) title(<tab:raw_pi_year_distributions_`samp'>) ///
        format(%14.4f) replace

    foreach v in `yrvars' {
        local skip 0
        foreach b in `cand_bin' {
            if "`v'" == "`b'" local skip 1
        }
        if `skip' continue
        qui sum `v', d
        if r(N) == 0 | r(min) == r(max) continue
        local p99 = r(p99)
        local vmax = r(max)
        local yt "${lbl_`v'}"
        if "`yt'" == "" local yt "`v'"

        tw hist `v', bin(60) percent color(ebblue%70) ///
            xtitle("`yt'") ytitle("Percent of PI-years") ///
            plotregion(margin(sides))
        graph export ../output/figures/`samp'/raw_dist_`v'.pdf, replace

        if `p99' > 0 & `vmax' > 2 * `p99' {
            tw hist `v' if `v' <= `p99', bin(60) percent color(ebblue%70) ///
                xtitle("`yt' (p99-cut)") ytitle("Percent of PI-years") ///
                plotregion(margin(sides))
            graph export ../output/figures/`samp'/raw_dist_`v'_p99.pdf, replace
        }
    }

    use ../temp/pi_level_`samp', clear
    local pivars ""
    foreach v in `cand_pi' {
        cap confirm variable `v'
        if !_rc local pivars "`pivars' `v'"
    }

    cap mat drop raw_pi_dist
    local rn_pi ""
    foreach v in `pivars' {
        qui sum `v', d
        if r(N) == 0 continue
        mat raw_pi_dist = nullmat(raw_pi_dist) \ (r(mean), r(sd), r(min), ///
            r(p10), r(p25), r(p50), r(p75), r(p90), r(p99), r(max), r(N))
        local rn_pi "`rn_pi' `v'"
        if r(min) == r(max) continue
        local p99 = r(p99)
        local vmax = r(max)
        local yt "${lbl_`v'}"
        if "`yt'" == "" local yt "`v'"

        tw hist `v', bin(60) percent color(ebblue%70) ///
            xtitle("`yt'") ytitle("Percent of PIs") ///
            plotregion(margin(sides))
        graph export ../output/figures/`samp'/raw_dist_pi_`v'.pdf, replace

        if `p99' > 0 & `vmax' > 2 * `p99' {
            tw hist `v' if `v' <= `p99', bin(60) percent color(ebblue%70) ///
                xtitle("`yt' (p99-cut)") ytitle("Percent of PIs") ///
                plotregion(margin(sides))
            graph export ../output/figures/`samp'/raw_dist_pi_`v'_p99.pdf, replace
        }
    }
    mat colnames raw_pi_dist = mean sd min p10 p25 p50 p75 p90 p99 max N
    mat rownames raw_pi_dist = `rn_pi'
    qui matrix_to_txt, saving("../output/tables/`samp'/raw_pi_distributions.txt") ///
        matrix(raw_pi_dist) title(<tab:raw_pi_distributions_`samp'>) ///
        format(%14.4f) replace

    di as text "plot_raw_overall `samp': PI-year vars = `: word count `yrvars'', PI vars = `: word count `pivars''"
end

* ---------------------------------------------------------------------------
* PI counts by institution / geography (top 20 lists + coverage matrix).
* Non-mover sample: 1 PI = 1 inst, so these are strict PI counts (not
* PI-year cells) and each PI is attributed to a single institution.
* ---------------------------------------------------------------------------
program describe_by_inst
    syntax, samp(string)
    use ../temp/pi_level_`samp', clear

    * Sanity check the non-mover invariant on the PI-level dataset
    qui gunique athr_id
    local n_pi = r(unique)
    qui gunique athr_id inst_id
    local n_pair = r(unique)
    di as text "describe_by_inst `samp': N PIs = `n_pi', N (PI, inst) pairs = `n_pair' (must match)"
    assert `n_pi' == `n_pair'

    * Top-20 institutions by PI count
    preserve
        contract inst_id inst
        gsort -_freq
        keep in 1/20
        rename _freq n_pis
        list, sep(0) noobs abbrev(45)
        export delimited using ../output/tables/`samp'/top20_insts_by_pi_count.csv, replace
    restore

    * PI counts by MSA (top 20)
    preserve
        contract msa_comb
        gsort -_freq
        keep in 1/20
        rename _freq n_pis
        export delimited using ../output/tables/`samp'/top20_msas_by_pi_count.csv, replace
    restore

    * Cluster (research topic) counts
    preserve
        contract cluster_30
        gsort -_freq
        rename _freq n_pis
        export delimited using ../output/tables/`samp'/cluster_pi_counts.csv, replace
    restore

    * Type breakdown (r1/r2 × public/private): rows = type, cols = public
    preserve
        contract type public
        gsort type public
        rename _freq n_pis
        export delimited using ../output/tables/`samp'/type_public_pi_counts.csv, replace
    restore
end

main
