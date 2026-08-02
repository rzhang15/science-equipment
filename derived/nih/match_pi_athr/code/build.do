set more off
clear all
capture log close
program drop _all
set scheme modern
version 17
set maxvar 120000

program main
    prep_grants
    apply_crosswalk
end

program prep_grants
    use ../external/reporter/reporter_2010_2019.dta, clear
    tostring org_ipf_code, replace force
    classify_grants
    count
    local n_raw = r(N)
    keep if research | training | r50
    count
    di as text "  kept `r(N)' of `n_raw' grant rows (research/training/R50)"
    gen long grant_id = _n

    preserve
        local extra
        foreach v in activity subproject_id core_project_num {
            capture confirm variable `v'
            if !_rc local extra `extra' `v'
        }
        keep grant_id fy total_cost project_start project_end budget_start ///
             budget_end full_project_num org_ipf_code org_name project_terms ///
             project_title research training r50 ctr_subproject ///
             appl_type supplement grant_key row_key `extra'
        save ../temp/grant_attrs, replace
    restore

    keep grant_id org_ipf_code pi_names
    split pi_names, parse(";") gen(pi_)
    drop pi_names
    reshape long pi_, i(grant_id) string
    rename pi_ pi_name
    replace pi_name = strtrim(pi_name)
    drop if mi(pi_name)
    gen str244 pi_name_s = pi_name
    drop pi_name
    rename pi_name_s pi_name
    save ../temp/pi_grant_long, replace
end

program apply_crosswalk
    build_crosswalk

    use ../temp/pi_grant_long, clear
    capture confirm string variable pi_name
    if _rc | substr("`: type pi_name'",1,4) == "strL" {
        gen str244 pi_name_s = pi_name
        drop pi_name
        rename pi_name_s pi_name
    }
    merge m:1 pi_name org_ipf_code using ../temp/pi_athr_crosswalk, ///
        keep(1 3) nogen
    save ../temp/grant_pi_athr_long, replace

    keep if !mi(athr_id)
    merge m:1 grant_id using ../temp/grant_attrs, keep(3) nogen
    gen int year = fy
    gen int start_year = year(project_start)
    label var year       "fiscal year of the grant-year record"
    label var start_year "project start year on THIS application row"

    * start_year is not constant within grant_key, contrary to what this file
    * used to claim: 14.3% of supplement rows carry a project_start that differs
    * from their parent's inside the same award-year, against 0.9% of
    * non-supplement rows, and the disagreement rate roughly quadrupled over
    * 2012-2019. Award start is a property of the award, so take it from the
    * non-supplement rows and fall back to all research rows only if an award
    * has none.
    gen double _par_start = project_start if research & !supplement
    gen double _any_start = project_start if research
    gegen double award_start = min(_par_start), by(grant_key)
    gegen double _fallback   = min(_any_start), by(grant_key)
    replace award_start = _fallback if mi(award_start)
    drop _par_start _any_start _fallback
    format %td award_start
    gen int award_start_year = year(award_start)
    label var award_start      "earliest project_start across the award's non-supplement rows"
    label var award_start_year "award start year (constant within grant_key)"
    save ../output/nih_grants_by_athr_id, replace

    collapse_athr_year

    local stubs                                     ///
        athr_panel_full_year_all_jrnls_r1_r2         ///
        athr_panel_full_year_all_jrnls_r1_r2_public  ///
        athr_panel_full_year_last_all_jrnls_r1_r2    ///
        athr_panel_full_year_last_all_jrnls_r1_r2_public
    foreach s of local stubs {
        merge_one_panel, file("`s'.dta") stub("`s'")
    }
end

program build_crosswalk
    import delimited using ../output/pi_athr_crosswalk.csv, ///
        varn(1) stringcols(_all) case(lower) clear
    destring name_score, replace force
    capture confirm variable match_src
    if _rc gen str8 match_src = "inst"
    gduplicates drop pi_name org_ipf_code, force
    di as text "  crosswalk: `=_N' unique (pi_name, org) links"
    tab match_src
    save ../temp/pi_athr_crosswalk, replace
end

program classify_grants
    capture confirm variable activity
    if _rc {
        gen str3 activity = cond(real(substr(full_project_num,1,1)) < ., ///
                                 substr(full_project_num,2,3),         ///
                                 substr(full_project_num,1,3))
    }
    replace activity = upper(strtrim(activity))

    * Leading digit of full_project_num: 1 new, 2 competing renewal,
    * 3 administrative supplement, 5 non-competing continuation.
    gen byte appl_type  = real(substr(strtrim(full_project_num), 1, 1))
    gen byte supplement = appl_type == 3
    label var appl_type  "NIH application type (leading digit of full_project_num)"
    label var supplement "administrative supplement row"

    capture confirm variable total_cost_sub_project
    if !_rc {
        replace total_cost = total_cost_sub_project ///
            if mi(total_cost) & !mi(total_cost_sub_project)
    }

    local res_core  R01 R37 R56 RF1 R35
    local res_dp    DP1 DP2 DP5
    local res_coop  U01 UM1 UG1 UG3 UH2 UH3
    local res_small R21 R33 R61 R03 R34
    local res_indep R00 R15 R16
    local train_k   K01 K08 K22 K23 K25 K76 K99

    gen byte research = 0
    foreach a in `res_core' `res_dp' `res_coop' `res_small' `res_indep' {
        replace research = 1 if activity == "`a'"
    }
    gen byte training = 0
    foreach a in `train_k' {
        replace training = 1 if activity == "`a'"
    }
    gen byte r50 = activity == "R50"

    gen byte ctr_subproject = .
    capture confirm variable subproject_id
    if !_rc {
        replace ctr_subproject = inlist(activity,"P01","P50") & !mi(subproject_id)
        replace research = 1 if ctr_subproject == 1
    }
    else {
        di as text "  note: no subproject_id; P01/P50 subprojects not identified"
    }

    capture confirm variable core_project_num
    if _rc {
        gen str32 core_project_num = cond(real(substr(full_project_num,1,1)) < ., ///
                                          substr(full_project_num,2,.), full_project_num)
        replace core_project_num = substr(core_project_num,1,strpos(core_project_num,"-")-1) ///
            if strpos(core_project_num,"-")
    }
    capture confirm variable subproject_id
    if _rc gen str8 subproject_id = ""

    gen str48 grant_key = strtrim(core_project_num) + "_" + strtrim(subproject_id)
    gen str64 row_key   = strtrim(full_project_num) + "_" + strtrim(subproject_id)

    label var grant_key      "unique award (core project num + subproject)"
    label var row_key        "award-fiscal-year record"
    label var research       "R/DP/U/R00/R15-16 activity (+ P01,P50 subprojects if identified)"
    label var training       "individual K award (K01 K08 K22 K23 K25 K76 K99)"
    label var r50            "R50 staff-scientist award (borderline)"
    label var ctr_subproject "P01/P50 subproject row (missing if subproject_id unavailable)"
end

program collapse_athr_year
    use ../output/nih_grants_by_athr_id, clear
    drop if mi(year)

    preserve
        keep athr_id pi_name org_name athr_name
        foreach v in pi_name org_name athr_name {
            replace `v' = "" if mi(`v')
        }
        contract athr_id pi_name org_name athr_name
        gsort athr_id -_freq pi_name
        by athr_id: keep if _n == 1
        drop _freq
        rename (pi_name org_name athr_name) ///
               (nih_pi_name nih_org_name nih_athr_name)
        save ../temp/nih_names_by_athr, replace
    restore

    duplicates drop athr_id year row_key, force

    preserve
        keep if research
        egen byte tag_ever = tag(athr_id grant_key)
        gcollapse (sum) n_grants_ever  = tag_ever ///
                  (sum) nih_cost_ever  = total_cost, by(athr_id) fast
        label var n_grants_ever "distinct research grants ever held, 2010-2019"
        label var nih_cost_ever "total research obligations, 2010-2019"
        save ../temp/nih_totals_by_athr, replace
    restore

    * Regression guard on the assumption this file used to make silently.
    qui count if research
    local n_res = r(N)
    qui count if research & !mi(start_year) & start_year != award_start_year
    di as text "  `r(N)' of `n_res' research rows disagree with their award start"

    * tag() marks whichever row sorts first within the group, with no preference
    * for the parent application. That is fine for counting distinct awards but
    * must never decide the value of a variable -- see new_grant below.
    egen byte tag_res   = tag(athr_id year grant_key) if research
    egen byte tag_train = tag(athr_id year grant_key) if training
    egen byte tag_r50   = tag(athr_id year grant_key) if r50
    egen byte tag_res_ns = tag(athr_id year grant_key) if research & !supplement

    gen byte res_grant_ns = tag_res_ns == 1
    gen double res_cost_ns = total_cost if research & !supplement
    gen byte supp_row = research & supplement

    gen byte res_grant   = tag_res   == 1
    gen byte train_grant = tag_train == 1
    gen byte r50_grant   = tag_r50   == 1
    gen byte any_grant   = res_grant | train_grant | r50_grant
    * Keyed to the award, not to the tagged row. Under the old row-level rule a
    * sort-order flip could book a continuing award as brand new in whichever
    * year it happened to receive a supplement.
    gen byte new_grant   = res_grant & award_start_year == year

    gen double res_cost   = total_cost    if research
    gen double train_cost = total_cost    if training
    gen double res_start  = project_start if research
    gen double res_end    = project_end   if research

    gcollapse (sum) n_grants            = res_grant ///
              (sum) n_new_grants        = new_grant ///
              (sum) nih_total_cost      = res_cost ///
              (min) first_project_start = res_start ///
              (max) last_project_end    = res_end ///
              (sum) n_train_grants      = train_grant ///
              (sum) nih_train_cost      = train_cost ///
              (sum) n_r50_grants        = r50_grant ///
              (sum) n_grants_all        = any_grant ///
              (sum) nih_total_cost_all  = total_cost ///
              (sum) n_grants_nosupp     = res_grant_ns ///
              (sum) nih_cost_nosupp     = res_cost_ns ///
              (sum) n_supp_rows         = supp_row, ///
              by(athr_id year) fast

    format %td first_project_start last_project_end
    * Counts include supplement rows on purpose: an award cannot be supplemented
    * unless it is live, so a supplement row is evidence of activity in that FY,
    * and it folds into the parent's grant_key rather than adding a second
    * award. Dollars include them on purpose too -- supplement obligations are
    * real money. n_grants_nosupp / nih_cost_nosupp are the robustness handles.
    label var n_new_grants       "research awards whose AWARD start year is this year"
    label var n_grants           "distinct research awards active this year (supplements incl.)"
    label var nih_total_cost     "total cost, research rows incl. supplements"
    label var n_train_grants     "individual K training awards"
    label var n_r50_grants       "R50 awards (borderline, excluded from n_grants)"
    label var n_grants_all       "all retained grants (research + training + R50)"
    label var nih_total_cost_all "total cost, retained grants"
    label var n_grants_nosupp    "research grants, administrative supplements excluded"
    label var nih_cost_nosupp    "total cost, research grants ex supplements"
    label var n_supp_rows        "administrative supplement rows this year"
    save ../temp/nih_by_athr_year, replace

    * Shipped to output as well: merge_one_panel joins these onto the
    * publication panel with keep(1 3), so a PI-year with an active award but no
    * paper row is lost there. Downstream code that needs the true author-year
    * series must merge this file, not the *_with_nih panels.
    save ../output/nih_athr_year, replace
    use ../temp/nih_names_by_athr, clear
    save ../output/nih_names_by_athr, replace
    use ../temp/nih_totals_by_athr, clear
    save ../output/nih_totals_by_athr, replace
end

program merge_one_panel
    syntax, file(string) stub(string)
    use ../external/athr_panel/`file', clear
    capture confirm variable year
    if _rc {
        di as error "  skipping `file' (no year variable)"
        exit
    }
    merge m:1 athr_id year using ../temp/nih_by_athr_year, ///
        keep(1 3) nogen
    merge m:1 athr_id using ../temp/nih_names_by_athr, ///
        keep(1 3) nogen
    merge m:1 athr_id using ../temp/nih_totals_by_athr, ///
        keep(1 3) nogen
    foreach v in n_grants n_new_grants nih_total_cost n_train_grants ///
                 nih_train_cost n_r50_grants n_grants_all nih_total_cost_all ///
                 n_grants_nosupp nih_cost_nosupp n_supp_rows ///
                 n_grants_ever nih_cost_ever {
        replace `v' = 0 if mi(`v')
    }
    gen byte has_nih = n_grants > 0
    label var has_nih "holds >=1 active research grant this year"
    save ../output/`stub'_with_nih, replace
end

main
