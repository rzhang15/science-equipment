/* ---------------------------------------------------------------------------
 build.do  --  derived/openalex/predict_impact

 Merges Phase 2 predicted-tier counts (../temp/pi_year_pred_tiers.dta) and
 Phase 3 self-management variables (../temp/pi_year_self_mgmt.dta,
 ../temp/pi_static_self_mgmt.dta) onto the existing PI-year panel.

 For each samp in {all_jrnls, all_jrnls_r1_r2, all_jrnls_r1_r2_public}:
   - load ../external/samp/athr_panel_full_year_last_<samp>.dta
   - 1:1 merge predicted-tier counts on (athr_id, year), fill missing as 0
   - 1:1 merge main-line / side-line counts on (athr_id, year), fill missing as 0
   - m:1 merge static portfolio_hhi / lab_size_pre on athr_id (no fill)
   - save to ../output/panel/athr_panel_full_year_last_<samp>.dta

 The output filenames match the existing convention so restrict_samp in
 analysis/predicted_impact/code/analysis.do (a clone of the reduced-form file)
 can pick them up unchanged via links.txt.

 top_jrnls panels are intentionally NOT produced here. The predicted-tier
 counts are built over the full scoring universe (all_jrnls), so merging onto
 top_jrnls would mostly produce zeros.
--------------------------------------------------------------------------- */

clear all
program drop _all
set more off

cap mkdir ../output
cap mkdir ../output/panel

program merge_one_samp
    syntax, samp(string)

    local src ../external/samp/athr_panel_full_year_last_`samp'.dta
    cap confirm file `src'
    if _rc {
        di as error "build.do: missing `src'; skipping samp=`samp'"
        exit 0
    }

    use `src', clear
    local n0 = _N
    di as text "build.do: `samp'  start N=`n0'"

    /* Phase 2: predicted-tier counts */
    cap confirm file ../temp/pi_year_pred_tiers.dta
    if _rc {
        di as error "  missing ../temp/pi_year_pred_tiers.dta; run step 05 first"
        exit 198
    }
    merge 1:1 athr_id year using ../temp/pi_year_pred_tiers.dta, ///
        keep(match master) nogen
    foreach v in n_pred_high n_pred_mid n_pred_low                        ///
                 n_pred_high_topdecile n_pred_low_topdecile               ///
                 n_pred_high_top15 n_pred_low_top15                       ///
                 n_real_high n_real_low                                   ///
                 n_large_team n_small_team n_high_junior n_low_junior     ///
                 n_scored {
        cap confirm variable `v'
        if !_rc replace `v' = 0 if mi(`v')
    }

    /* Phase 3.2: main-line vs side-line counts (PI-year) */
    cap confirm file ../temp/pi_year_self_mgmt.dta
    if _rc {
        di as error "  missing ../temp/pi_year_self_mgmt.dta; run step 06 first"
        exit 198
    }
    merge 1:1 athr_id year using ../temp/pi_year_self_mgmt.dta, ///
        keep(match master) nogen
    foreach v in n_main_line n_side_line {
        cap confirm variable `v'
        if !_rc replace `v' = 0 if mi(`v')
    }

    /* Phase 3.1: static portfolio_hhi + lab_size_pre */
    cap confirm file ../temp/pi_static_self_mgmt.dta
    if _rc {
        di as error "  missing ../temp/pi_static_self_mgmt.dta; run step 06 first"
        exit 198
    }
    merge m:1 athr_id using ../temp/pi_static_self_mgmt.dta, ///
        keep(match master) nogen

    /* Sanity: n_pred_high + n_pred_mid + n_pred_low == n_scored,
       row count unchanged                                       */
    local n1 = _N
    if `n0' != `n1' {
        di as error "  WARNING: row count `n0' -> `n1'"
    }
    cap noi gen __sumpred = n_pred_high + n_pred_mid + n_pred_low
    cap noi count if !mi(n_scored) & __sumpred != n_scored
    if `r(N)' > 0 di as error "  WARNING: `r(N)' rows where pred-tier counts don't sum to n_scored"
    cap drop __sumpred

    save ../output/panel/athr_panel_full_year_last_`samp'.dta, replace
    di as text "build.do: `samp'  saved N=`n1'"
end

program main
    foreach samp in all_jrnls all_jrnls_r1_r2 all_jrnls_r1_r2_public {
        merge_one_samp, samp(`samp')
    }
end

main
