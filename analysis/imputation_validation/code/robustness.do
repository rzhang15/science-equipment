set more off
clear all
capture log close
program drop _all
version 17

* Run from this code directory, after validation.do has frozen its decision.
* Inputs are read-only links. All saved data, logs, and tables stay in this module.
* Main paper specification: annual last-author publication count, PPML,
* author and year fixed effects, post x treated-share control, PI clustering.
* This exercise holds the existing exposure and market price estimates fixed.

program main
    cap mkdir ../temp
    cap mkdir ../output
    cap mkdir ../output/tables
    log using ../output/robustness.log, text replace

    cap which ppmlhdfe
    if _rc {
        di as error "ppmlhdfe is required; no existing analysis files were run."
        exit 499
    }

    use ../output/validation_selection, clear
    assert _N == 1
    assert inlist(eligible, 0, 1)
    assert !mi(cutoff) & inrange(cutoff, 0, 1) if eligible == 1
    local eligible = eligible[1]
    local cutoff = cutoff[1]
    local reason = reason[1]
    local samples full
    if `eligible' == 1 local samples full restricted
    else {
        * Remove only this module's generated restricted artifacts on a rerun.
        foreach f in output_ppml_restricted.ster ///
            output_sample_pi_restricted_input.dta output_sample_pi_restricted_estimated.dta {
            cap erase ../output/`f'
        }
    }
    di as text "Validation decision fixed before output regressions: `reason'"

    gather_panel

    tempname regpost comppost
    postfile `regpost' str12 sample long N_rows N_pis N_clusters N_insts N_fields ///
        double b_exposure se_exposure ci_lo ci_hi b_share se_share ///
        exposure_mean exposure_sd exposure_min exposure_max ///
        share_mean share_sd similarity_mean pre_output_mean ///
        long N_foia N_early N_mid N_late N_stage_missing ///
        double full_reference_exposure decline_pct decline_ci_lo decline_ci_hi ///
        using ../output/output_regressions, replace
    postfile `comppost' str24 sample str20 characteristic str120 category ///
        long N_pis double share using ../output/output_composition, replace

    local full_reference = .
    foreach s of local samples {
        use ../temp/output_panel, clear
        if "`s'" == "restricted" {
            * Preserve all observed FOIA PIs, as in the current upper-half check.
            * A missing non-FOIA match score never satisfies the restriction.
            keep if foia_athr == 1 | (!mi(max_sim) & max_sim >= `cutoff')
        }
        assert _N > 0
        gen byte post = year >= 2014
        gen double Z_it = exposure * post
        gen double Z_share_it = mkt_spend_shr * post

        preserve
            bys athr_id (year): keep if _n == 1
            save ../output/output_sample_pi_`s'_input, replace
            post_composition, samp(`s'_input) handle(`comppost')
        restore

        ppmlhdfe ppr_cnt Z_it Z_share_it, absorb(athr_id year) vce(cluster athr_id)
        local b = _b[Z_it]
        local se = _se[Z_it]
        local bs = _b[Z_share_it]
        local ses = _se[Z_share_it]
        local N = e(N)
        * Match the normal 95% intervals used in robustness_summary.do.
        local lb = `b' - invnormal(.975) * `se'
        local ub = `b' + invnormal(.975) * `se'
        gen byte output_esample = e(sample)
        estimates save ../output/output_ppml_`s', replace
        qui sum ppr_cnt if output_esample == 1 & year < 2014
        local premean = r(mean)

        preserve
            keep if output_esample == 1
            bys athr_id (year): keep if _n == 1
            local N_pi = _N
            * The inference clusters are PIs. Count them on the actual e(sample).
            local N_cl = `N_pi'
            egen byte _inst_tag = tag(inst_id)
            qui count if _inst_tag == 1 & !mi(inst_id)
            local N_inst = r(N)
            egen byte _field_tag = tag(cluster_30)
            qui count if _field_tag == 1 & !mi(cluster_30)
            local N_field = r(N)
            qui sum exposure
            local xm = r(mean)
            local xsd = r(sd)
            local xmin = r(min)
            local xmax = r(max)
            if "`s'" == "full" local full_reference = `xm'
            qui sum mkt_spend_shr
            local sm = r(mean)
            local ssd = r(sd)
            qui sum max_sim if foia_athr != 1
            local simm = r(mean)
            qui count if foia_athr == 1
            local N_foia = r(N)
            qui count if career_stage == 1
            local N_early = r(N)
            qui count if career_stage == 2
            local N_mid = r(N)
            qui count if career_stage == 3
            local N_late = r(N)
            qui count if mi(career_stage)
            local N_missing = r(N)
            * Use full-sample mean exposure for both columns, so effects differ
            * because of coefficients rather than a changed reporting scale.
            local decline = 100 * (1 - exp(`b' * `full_reference'))
            local endpoint1 = 100 * (1 - exp(`ub' * `full_reference'))
            local endpoint2 = 100 * (1 - exp(`lb' * `full_reference'))
            local decline_lo = min(`endpoint1', `endpoint2')
            local decline_hi = max(`endpoint1', `endpoint2')
            post `regpost' ("`s'") (`N') (`N_pi') (`N_cl') (`N_inst') (`N_field') ///
                (`b') (`se') (`lb') (`ub') (`bs') (`ses') ///
                (`xm') (`xsd') (`xmin') (`xmax') (`sm') (`ssd') (`simm') (`premean') ///
                (`N_foia') (`N_early') (`N_mid') (`N_late') (`N_missing') ///
                (`full_reference') (`decline') (`decline_lo') (`decline_hi')
            drop _inst_tag _field_tag
            save ../output/output_sample_pi_`s'_estimated, replace
            post_composition, samp(`s'_estimated) handle(`comppost')
        restore
    }
    postclose `regpost'
    postclose `comppost'

    use ../output/output_composition, clear
    export delimited using ../output/tables/output_composition.csv, replace

    use ../output/output_regressions, clear
    gen byte restriction_eligible = `eligible'
    gen double validation_cutoff = `cutoff'
    gen str244 selection_reason = "`reason'"
    gen str80 specification = "PPML ppr_cnt; author + year FE; post x treated share; PI clustering"
    gen str24 ci_method = "Normal 95% (1.96 SE)"
    gen str20 exposure_version = "hc_all3_cf_k3"
    label var N_rows "PI-year observations in e(sample)"
    label var N_pis "Unique PIs in e(sample)"
    label var N_clusters "Inference clusters (PIs) in e(sample)"
    label var exposure_mean "PI-level exposure mean in e(sample)"
    label var exposure_sd "PI-level exposure SD in e(sample)"
    label var similarity_mean "Mean absolute max similarity, non-FOIA PIs"
    label var decline_pct "Implied decline at the full-sample mean exposure (%)"
    save ../output/output_regressions, replace
    export delimited using ../output/tables/output_regressions.csv, replace
    write_table, eligible(`eligible') cutoff(`cutoff') reason("`reason'")
    log close
end

program gather_panel
    use athr_id year ppr_cnt exposure mkt_spend_shr max_sim foia_athr ///
        inst_id inst cluster_30 min_year type public ///
        using ../external/rf/prepped_samples/es_all_jrnls_r1_r2, clear
    isid athr_id year
    assert inrange(year, 2010, 2019)
    assert !mi(athr_id, exposure, mkt_spend_shr, ppr_cnt)
    assert ppr_cnt >= 0
    bys athr_id (year): assert exposure == exposure[1]
    bys athr_id (year): assert mkt_spend_shr == mkt_spend_shr[1]
    bys athr_id (year): assert max_sim == max_sim[1]
    bys athr_id (year): assert foia_athr == foia_athr[1]
    gen double lab_age_2014 = 2014 - min_year if !mi(min_year)
    gen byte career_stage = 1 if lab_age_2014 < 10 & !mi(lab_age_2014)
    replace career_stage = 2 if inrange(lab_age_2014, 10, 19)
    replace career_stage = 3 if lab_age_2014 >= 20 & !mi(lab_age_2014)
    label define career_stage 1 "Early: <10 lab years" ///
        2 "Mid: 10-19 lab years" 3 "Late: 20+ lab years"
    label values career_stage career_stage
    label var lab_age_2014 "2014 minus first last-author year (panel lab clock)"
    save ../temp/output_panel, replace

    * Refuse stale exposures or diagnostics instead of silently changing the
    * existing estimation panel or rerunning its sample construction.
    tempfile pi current_imputed current_observed current_diag
    bys athr_id (year): keep if _n == 1
    save `pi'
    import delimited ../external/exposure/final_imputed_shift_share_hc_all3_cf_k3.csv, ///
        clear varnames(1)
    keep athr_id exposure_ss sum_imputed_shares
    rename (exposure_ss sum_imputed_shares) (_imputed_check _share_check)
    isid athr_id
    save `current_imputed'
    use athr_id exposure mkt_spend_shr ///
        using ../external/real_exposure/athr_exposure_hc_all3, clear
    rename (exposure mkt_spend_shr) (_observed_check _observed_share_check)
    isid athr_id
    save `current_observed'
    use athr_id max_sim using ../external/exposure/match_diagnostics, clear
    rename max_sim _similarity_check
    isid athr_id
    save `current_diag'
    use `pi', clear
    merge 1:1 athr_id using `current_imputed', keep(1 3) nogen
    merge 1:1 athr_id using `current_observed', keep(1 3) nogen
    merge 1:1 athr_id using `current_diag', keep(1 3) nogen
    assert !mi(_imputed_check, _share_check, _similarity_check) if foia_athr != 1
    assert abs(exposure - _imputed_check) < 1e-6 if foia_athr != 1
    assert abs(mkt_spend_shr - _share_check) < 1e-6 if foia_athr != 1
    assert abs(max_sim - _similarity_check) < 1e-6 if foia_athr != 1
    assert !mi(_observed_check, _observed_share_check) if foia_athr == 1
    assert abs(exposure - _observed_check) < 1e-6 if foia_athr == 1
    assert abs(mkt_spend_shr - _observed_share_check) < 1e-6 if foia_athr == 1
    di as text "Canonical RF panel matches current fixed exposures and match diagnostics (tolerance 1e-6)."
end

program post_composition
    syntax, samp(string) handle(name)
    local total = _N
    tempfile composition_source
    save `composition_source'
    foreach v in career_stage inst_id cluster_30 type public foia_athr {
        use `composition_source', clear
        capture confirm string variable `v'
        if !_rc gen str120 _category = `v'
        else {
            capture decode `v', gen(_category)
            if _rc gen str120 _category = string(`v', "%12.0g")
        }
        replace _category = "Missing" if mi(`v')
        contract _category, freq(N_pis)
        gen double share = N_pis / `total'
        forval i = 1/`=_N' {
            post `handle' ("`samp'") ("`v'") (_category[`i']) (N_pis[`i']) (share[`i'])
        }
    }
    use `composition_source', clear
end

program write_table
    syntax, eligible(integer) cutoff(real) reason(string)
    tempname fh
    file open `fh' using ../output/tables/output_robustness.txt, write replace
    file write `fh' "Validation-based output robustness" _n
    file write `fh' "Outcome: annual last-author publication count, 2010-2019." _n
    file write `fh' "PPML; PI and year fixed effects; post x treated-share control; PI-clustered SE." _n
    file write `fh' "Fixed prices and exposures; no similarity weights. Normal 95% confidence intervals." _n
    file write `fh' "Selection decision: `reason'" _n
    if `eligible' == 1 {
        file write `fh' "Restricted sample: all observed FOIA PIs and non-FOIA PIs with max_sim >= " %7.4f (`cutoff') "." _n
    }
    else file write `fh' "Restricted regression skipped: validation did not support a restriction." _n
    file write `fh' "Lab career stage uses 2014 minus first last-author year; exposure summaries give equal weight to each PI." _n _n
    forval i = 1/`=_N' {
        local s = sample[`i']
        file write `fh' "`s'" _n
        file write `fh' "  Exposure coefficient (SE): " %9.4f (b_exposure[`i']) " (" %9.4f (se_exposure[`i']) ")" _n
        file write `fh' "  95% CI: [" %9.4f (ci_lo[`i']) ", " %9.4f (ci_hi[`i']) "]" _n
        file write `fh' "  PI-years / PIs / PI inference clusters: " %10.0f (N_rows[`i']) " / " %8.0f (N_pis[`i']) " / " %8.0f (N_clusters[`i']) _n
        file write `fh' "  Institutions / research clusters / FOIA PIs: " %6.0f (N_insts[`i']) " / " %4.0f (N_fields[`i']) " / " %5.0f (N_foia[`i']) _n
        file write `fh' "  PI exposure mean / SD / min / max: " %9.5f (exposure_mean[`i']) " / " %9.5f (exposure_sd[`i']) " / " %9.5f (exposure_min[`i']) " / " %9.5f (exposure_max[`i']) _n
        file write `fh' "  PI treated-share mean / SD: " %9.5f (share_mean[`i']) " / " %9.5f (share_sd[`i']) _n
        file write `fh' "  Early / mid / late lab-career PIs / missing: " %7.0f (N_early[`i']) " / " %7.0f (N_mid[`i']) " / " %7.0f (N_late[`i']) " / " %5.0f (N_stage_missing[`i']) _n
        file write `fh' "  Implied decline at full-sample mean exposure (%): " %8.2f (decline_pct[`i']) "; 95% CI [" %8.2f (decline_ci_lo[`i']) ", " %8.2f (decline_ci_hi[`i']) "]" _n _n
    }
    file write `fh' "Sample composition by career stage, institution, research cluster, R1/R2, public status, and FOIA status is in output_composition.csv." _n
    file write `fh' "Interpret the restricted estimate with its precision and composition; this code never searches output results for another cutoff." _n
    file close `fh'
end

main
