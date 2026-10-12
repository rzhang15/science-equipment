set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

global VALIDATION_REPS 2000
global VALIDATION_SEED 8975

adopath ++ "../external/lib/stata"

program main
    cap mkdir ../temp
    cap mkdir ../output/tables
    cap mkdir ../output/figures
    prepare_errors
    output_similarity
    output_career
    output_coverage
    select_cutoff
    validation_figure
end

program similarity_groups
    gen byte sim_group = .
    replace sim_group = 1 if max_sim < .15
    replace sim_group = 2 if max_sim >= .15 & max_sim < .20
    replace sim_group = 3 if max_sim >= .20 & max_sim < .27
    replace sim_group = 4 if max_sim >= .27 & max_sim < .
    label define similarity_group 1 "<0.15" 2 "0.15 to <0.20" ///
        3 "0.20 to <0.27" 4 ">=0.27" 5 "Missing similarity", replace
    label values sim_group similarity_group
end

program prepare_errors
    use ../output/validation_pi, clear
    similarity_groups
    gen byte valid_prediction = !missing(exposure, exposure_loo, exposure_null)
    gen double abs_error = abs(exposure - exposure_loo) if valid_prediction
    gen double abs_error_null = abs(exposure - exposure_null) if valid_prediction
    gen double sq_error = (exposure - exposure_loo)^2 if valid_prediction
    gen double sq_error_null = (exposure - exposure_null)^2 if valid_prediction
    gen double pred_error = exposure - exposure_loo if valid_prediction
    gen double pred_error_null = exposure - exposure_null if valid_prediction
    gen double mae_gain = abs_error_null - abs_error if valid_prediction
    label var mae_gain "PI-level absolute-error improvement over remaining-FOIA mean"
    save ../temp/validation_errors, replace
end

// All statistics use the same complete prediction pairs within a requested group.
program sample_stats, rclass
    syntax [if] [in]
    marksample touse
    markout `touse' exposure exposure_loo exposure_null
    qui count if `touse'
    local n = r(N)
    foreach v in abs_error abs_error_null sq_error sq_error_null ///
                 pred_error pred_error_null mae_gain {
        qui su `v' if `touse', meanonly
        local `v' = r(mean)
    }
    qui su exposure if `touse'
    local sd_observed = r(sd)
    qui su exposure_loo if `touse'
    local sd_predicted = r(sd)
    local corr = .
    local intercept = .
    local slope = .
    if `n' > 2 & `sd_observed' > 0 & `sd_observed' < . ///
                  & `sd_predicted' > 0 & `sd_predicted' < . {
        qui corr exposure exposure_loo if `touse'
        local corr = r(rho)
    }
    if `n' > 2 & `sd_predicted' > 0 & `sd_predicted' < . {
        qui reg exposure exposure_loo if `touse'
        local intercept = _b[_cons]
        local slope = _b[exposure_loo]
    }
    return scalar n = `n'
    return scalar mae = `abs_error'
    return scalar mae_null = `abs_error_null'
    return scalar rmse = sqrt(`sq_error')
    return scalar rmse_null = sqrt(`sq_error_null')
    return scalar bias = `pred_error'
    return scalar bias_null = `pred_error_null'
    return scalar gain = `mae_gain'
    return scalar corr = `corr'
    return scalar intercept = `intercept'
    return scalar slope = `slope'
    return scalar sd_observed = `sd_observed'
    return scalar sd_predicted = `sd_predicted'
end

program output_similarity
    use ../temp/validation_errors, clear
    tempname results
    postfile `results' byte sim_group long n double mae mae_null rmse rmse_null ///
        corr intercept slope sd_observed sd_predicted bias bias_null ///
        using ../output/tables/validation_by_similarity, replace
    sample_stats
    post `results' (0) (r(n)) (r(mae)) (r(mae_null)) (r(rmse)) (r(rmse_null)) ///
        (r(corr)) (r(intercept)) (r(slope)) (r(sd_observed)) (r(sd_predicted)) ///
        (r(bias)) (r(bias_null))
    foreach g of numlist 1/4 {
        sample_stats if sim_group == `g'
        post `results' (`g') (r(n)) (r(mae)) (r(mae_null)) (r(rmse)) (r(rmse_null)) ///
            (r(corr)) (r(intercept)) (r(slope)) (r(sd_observed)) (r(sd_predicted)) ///
            (r(bias)) (r(bias_null))
    }
    // Keep missing similarity visible in the table, outside the ordered groups.
    sample_stats if missing(sim_group)
    post `results' (5) (r(n)) (r(mae)) (r(mae_null)) (r(rmse)) (r(rmse_null)) ///
        (r(corr)) (r(intercept)) (r(slope)) (r(sd_observed)) (r(sd_predicted)) ///
        (r(bias)) (r(bias_null))
    postclose `results'
    use ../output/tables/validation_by_similarity, clear
    label define similarity_group 0 "All validation PIs" 1 "<0.15" 2 "0.15 to <0.20" ///
        3 "0.20 to <0.27" 4 ">=0.27" 5 "Missing similarity", replace
    label values sim_group similarity_group
    decode sim_group, gen(similarity_range)
    save ../output/tables/validation_by_similarity, replace
    export delimited using ../output/tables/validation_by_similarity.csv, replace
end

program output_career
    use ../temp/validation_errors, clear
    tempname results
    postfile `results' byte career_stage long n double mae mae_null rmse rmse_null ///
        bias bias_null mean_similarity using ../output/tables/validation_by_career, replace
    foreach g of numlist 1/4 {
        qui su max_sim if career_stage == `g' & valid_prediction, meanonly
        local sim = r(mean)
        sample_stats if career_stage == `g'
        post `results' (`g') (r(n)) (r(mae)) (r(mae_null)) (r(rmse)) (r(rmse_null)) ///
            (r(bias)) (r(bias_null)) (`sim')
    }
    postclose `results'
    use ../output/tables/validation_by_career, clear
    label define career_group 1 "Early: <10 years" 2 "Mid: 10 to <20 years" ///
        3 "Late: >=20 years" 4 "Unknown", replace
    label values career_stage career_group
    decode career_stage, gen(career_stage_label)
    label var career_stage "Years since first last-author publication in 2014"
    save ../output/tables/validation_by_career, replace
    export delimited using ../output/tables/validation_by_career.csv, replace
end

program output_coverage
    tempname results
    postfile `results' str32 population byte sim_group long n n_population ///
        double share using ../output/tables/similarity_coverage, replace
    use ../output/validation_pi, clear
    similarity_groups
    local total = _N
    foreach g of numlist 1/5 {
        if `g' < 5 qui count if sim_group == `g'
        else qui count if missing(sim_group)
        post `results' ("Held-out FOIA PIs") (`g') (r(N)) (`total') (r(N) / `total')
    }
    use ../output/panel_pi, clear
    similarity_groups
    foreach f in 0 1 {
        local pop "Non-FOIA estimation PIs"
        if `f' == 1 local pop "FOIA estimation PIs"
        qui count if foia_athr == `f'
        local total = r(N)
        foreach g of numlist 1/5 {
            if `g' < 5 qui count if sim_group == `g' & foia_athr == `f'
            else qui count if missing(sim_group) & foia_athr == `f'
            post `results' ("`pop'") (`g') (r(N)) (`total') (r(N) / `total')
        }
    }
    postclose `results'
    use ../output/tables/similarity_coverage, clear
    label define similarity_group 1 "<0.15" 2 "0.15 to <0.20" ///
        3 "0.20 to <0.27" 4 ">=0.27" 5 "Missing similarity", replace
    label values sim_group similarity_group
    decode sim_group, gen(similarity_range)
    save ../output/tables/similarity_coverage, replace
    export delimited using ../output/tables/similarity_coverage.csv, replace
end

program mean_gain, rclass
    qui su mae_gain, meanonly
    return scalar mae_gain = r(mean)
end

// The candidate set and criteria are fixed before any output regressions are read.
// Each draw resamples held-out PIs, preserving the method/benchmark error pair.
// Predictions and market price estimates remain fixed within draws.
program select_cutoff
    tempname results
    postfile `results' double cutoff long n_upper n_lower double ///
        mae mae_null mae_reduction rmse rmse_null slope ///
        gain_upper gain_lower gain_ci_low gain_ci_high ///
        long n_panel n_nonfoia double share_panel share_nonfoia ///
        byte eligible str244 reason using ../output/tables/validation_candidates, replace
    foreach c in .20 .27 {
        use ../output/panel_pi, clear
        local panel_total = _N
        qui count if max_sim >= `c' & max_sim < .
        local n_panel = r(N)
        qui count if foia_athr == 0
        local nonfoia_total = r(N)
        qui count if foia_athr == 0 & max_sim >= `c' & max_sim < .
        local n_nonfoia = r(N)
        local share_panel = `n_panel' / `panel_total'
        local share_nonfoia = `n_nonfoia' / `nonfoia_total'

        use ../temp/validation_errors, clear
        sample_stats if max_sim < `c'
        local n_lower = r(n)
        local gain_lower = r(gain)
        sample_stats if max_sim >= `c' & max_sim < .
        foreach s in mae mae_null rmse rmse_null slope {
            local `s' = r(`s')
        }
        local n_upper = r(n)
        local gain_upper = r(gain)
        local reduction = (`mae_null' - `mae') / `mae_null'
        local ci_low = .
        local ci_high = .
        if `n_upper' >= 30 {
            keep if valid_prediction & max_sim >= `c' & max_sim < .
            local suffix = round(100 * `c')
            bootstrap mae_gain=r(mae_gain), reps($VALIDATION_REPS) ///
                seed($VALIDATION_SEED) nodots ///
                saving(../temp/mae_gain_`suffix', replace double): mean_gain
            use ../temp/mae_gain_`suffix', clear
            qui centile mae_gain, centile(2.5 97.5)
            local ci_low = r(c_1)
            local ci_high = r(c_2)
        }
        local eligible = 1
        local reason ""
        if `n_upper' < 30 {
            local eligible = 0
            local reason "`reason'Fewer than 30 upper-tail validation PIs; "
        }
        if `reduction' < .10 | missing(`reduction') {
            local eligible = 0
            local reason "`reason'MAE reduction below 10%; "
        }
        if `rmse' >= `rmse_null' | missing(`rmse', `rmse_null') {
            local eligible = 0
            local reason "`reason'RMSE does not improve; "
        }
        if `slope' <= 0 | missing(`slope') {
            local eligible = 0
            local reason "`reason'Calibration slope not positive; "
        }
        if `gain_upper' <= `gain_lower' | missing(`gain_upper', `gain_lower') {
            local eligible = 0
            local reason "`reason'MAE gain does not exceed lower-tail gain; "
        }
        if `eligible' local reason "Descriptive validation criteria satisfied"
        if `eligible' & `ci_low' <= 0 {
            local reason "`reason'; conditional MAE-gain interval includes zero"
        }
        post `results' (`c') (`n_upper') (`n_lower') (`mae') (`mae_null') (`reduction') ///
            (`rmse') (`rmse_null') (`slope') (`gain_upper') (`gain_lower') (`ci_low') ///
            (`ci_high') (`n_panel') (`n_nonfoia') (`share_panel') (`share_nonfoia') ///
            (`eligible') ("`reason'")
    }
    postclose `results'
    use ../output/tables/validation_candidates, clear
    sort cutoff
    gen byte gain_ci_includes_zero = gain_ci_low <= 0 & gain_ci_high >= 0 ///
        if !missing(gain_ci_low, gain_ci_high)
    label var gain_ci_low "2.5th percentile paired PI-bootstrap MAE gain"
    label var gain_ci_high "97.5th percentile paired PI-bootstrap MAE gain"
    label var mae_reduction "Proportional MAE reduction against remaining-FOIA mean"
    save ../output/tables/validation_candidates, replace
    export delimited using ../output/tables/validation_candidates.csv, replace
    qui count if eligible == 1
    if r(N) {
        keep if eligible == 1
        keep in 1
        local selected = cutoff[1]
        local selected_eligible = 1
        replace reason = "Lowest fixed cutoff satisfying descriptive validation criteria"
        replace reason = reason + "; conditional MAE-gain interval includes zero" ///
            if gain_ci_includes_zero == 1
    }
    else {
        keep in 1
        replace cutoff = .
        replace eligible = 0
        replace reason = "Neither fixed cutoff (.20, .27) satisfies all validation criteria; restricted output check not selected"
        local selected = .
        local selected_eligible = 0
    }
    keep eligible cutoff reason
    gen int bootstrap_reps = $VALIDATION_REPS
    gen long bootstrap_seed = $VALIDATION_SEED
    save ../output/validation_selection, replace
    tempname selection
    file open `selection' using ../output/validation_selection.do, write replace
    file write `selection' "// Chosen exclusively from held-out exposure validation." _n
    file write `selection' "global VALIDATION_ELIGIBLE `selected_eligible'" _n
    file write `selection' "global VALIDATION_CUTOFF `selected'" _n
    file close `selection'
    tempname report
    file open `report' using ../output/validation_selection.txt, write replace
    file write `report' "Fixed candidate cutoffs: 0.20 and 0.27 (lowest eligible selected)." _n
    file write `report' "Descriptive eligibility: n>=30; MAE reduction>=10%; lower RMSE; positive calibration slope;" _n
    file write `report' "upper-tail MAE gain>lower-tail gain. The error-gain interval is reported, not used as a significance gate." _n
    file write `report' "This selects one exploratory output check; an interval spanning zero leaves accuracy gains uncertain." _n
    file write `report' "Bootstrap: $VALIDATION_REPS resamples, seed $VALIDATION_SEED; fixed predictions and market prices." _n
    file write `report' "Eligible: `selected_eligible'; selected cutoff: `selected'." _n
    file write `report' "" (reason[1]) _n
    file write `report' "Candidate evidence: tables/validation_candidates.csv." _n
    file close `report'
end

program validation_figure
    use ../output/tables/validation_by_similarity, clear
    keep if inrange(sim_group, 1, 4)
    foreach g of numlist 1/4 {
        qui su n if sim_group == `g', meanonly
        local n`g' = r(mean)
    }
    gen double xpos_method = sim_group - .16
    gen double xpos_null = sim_group + .16
    twoway (bar mae xpos_method, barwidth(.28) color(ebblue) base(0)) ///
           (bar mae_null xpos_null, barwidth(.28) color(gs10) base(0)), ///
        title("A. Leave-one-out prediction error", size(medium)) ///
        xtitle("Absolute nearest-donor similarity") ytitle("Mean absolute exposure error") ///
        yscale(range(0)) ylabel(#6) ///
        xlabel(1 `""<0.15" "(N=`n1')""' 2 `""0.15-<0.20" "(N=`n2')""' ///
               3 `""0.20-<0.27" "(N=`n3')""' 4 `"">=0.27" "(N=`n4')""', labsize(small)) ///
        legend(order(1 "Imputation" 2 "Remaining-FOIA mean") pos(6) rows(1) size(small)) ///
        name(validation_errors, replace)

    use ../output/validation_pi, clear
    keep max_sim
    gen byte population = 1
    tempfile foia
    save `foia'
    use ../output/panel_pi, clear
    keep if foia_athr == 0
    keep max_sim
    gen byte population = 2
    append using `foia'
    qui count if population == 1 & max_sim < .
    local n_foia = r(N)
    qui count if population == 2 & max_sim < .
    local n_nonfoia = r(N)
    qui su max_sim, meanonly
    local hist_start = floor(r(min) / .025) * .025
    twoway (histogram max_sim if population == 1, percent start(`hist_start') ///
                width(.025) color(ebblue%35) lcolor(ebblue)) ///
           (histogram max_sim if population == 2, percent start(`hist_start') ///
                width(.025) color(dkorange%35) lcolor(dkorange)), ///
        title("B. Validation and estimation support", size(medium)) ///
        xtitle("Absolute nearest-donor similarity") ytitle("Percent of PIs") ///
        legend(order(1 "Held-out FOIA (N=`n_foia')" ///
                     2 "Non-FOIA panel (N=`n_nonfoia')") pos(6) rows(2) size(small)) ///
        name(validation_similarity, replace)
    graph combine validation_errors validation_similarity, cols(2) ///
        xsize(12) ysize(4) imargin(small)
    graph save ../output/figures/validation_similarity.gph, replace
    // The combined graph sets the canvas size; exporter sizes control font scale.
    fig_export, path("../output/figures/validation_similarity.pdf") xsize(6) ysize(4)
    graph display, scale(1)
    graph export ../output/figures/paper/validation_similarity.png, width(2400) replace
end

args task
if "`task'" == "figure" {
    validation_figure
}
else {
    main
}
