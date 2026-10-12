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
    * Keep excluded umbrella budgets available for inspection. Identify them
    * before PI matching and activity filtering, so unmatched/excluded component
    * leaders cannot cause the full parent budget to be credited to another PI.
    preserve
        keep if multi_project_parent
        save ../output/nih_excluded_parent_records, replace
    restore
    count if multi_project_parent
    di as text "  excluding `r(N)' parent rows with reported subprojects"
    drop if multi_project_parent
    preserve
        keep if !nih_award | shared_core
        save ../output/nih_excluded_agency_core_records, replace
    restore
    count if !nih_award
    di as text "  excluding `r(N)' non-NIH or unrecognized awarding-component rows"
    count if shared_core & nih_award
    di as text "  excluding `r(N)' NIH shared/admin core rows"
    keep if nih_award & !shared_core
    preserve
        keep if institutional_award
        save ../output/nih_excluded_program_center_records, replace
    restore
    count if institutional_award
    di as text "  excluding `r(N)' P01/P50 program/center and UM1 complex-program rows"
    drop if institutional_award
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
             appl_type supplement grant_key row_key nih_ic nih_award shared_core institutional_award `extra'
        save ../temp/grant_attrs, replace
    restore

    keep grant_id org_ipf_code pi_names
    * Count all nonblank listed PIs before matching, including unmatched PIs.
    split pi_names, parse(";") gen(pi_)
    drop pi_names
    reshape long pi_, i(grant_id) string
    rename pi_ pi_name
    replace pi_name = strtrim(pi_name)
    drop if mi(pi_name)
    bysort grant_id: gen int n_listed_pis = _N
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
    gen double total_cost_pi = total_cost / n_listed_pis
    label var total_cost_pi "total award cost divided by all listed PIs"
    label var n_listed_pis "number of nonblank PIs listed before author matching"
    gen int year = fy
    gen int start_year = year(project_start)
    label var year       "fiscal year of the grant-year record"
    label var start_year "project start year on THIS application row"

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
    local res_coop  U01 UG1 UG3 UH2 UH3
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
    }
    else {
        di as text "  note: no subproject_id; P01/P50 subprojects not identified"
    }

    * PI research-project funding excludes program/center awards, including
    * their research components, and complex UM1 programs. Retained multi-PI
    * research projects still give each named PI full credit.
    gen byte institutional_award = inlist(activity, "P01", "P50", "UM1")
    label var institutional_award "excluded program/center or complex-program mechanism"

    capture confirm variable core_project_num
    if _rc {
        gen str32 core_project_num = cond(real(substr(full_project_num,1,1)) < ., ///
                                          substr(full_project_num,2,.), full_project_num)
        replace core_project_num = substr(core_project_num,1,strpos(core_project_num,"-")-1) ///
            if strpos(core_project_num,"-")
    }
    capture confirm variable subproject_id
    if _rc gen str8 subproject_id = ""

    * NIH-only awarding components, including historical NCRR (RR) and
    * NCCAM (AT). RePORTER also contains AHRQ, CDC, FDA, VA, etc.; activity
    * codes alone do not identify NIH awards. The core number is ACTIVITY+IC+SERIAL.
    gen str2 nih_ic = upper(substr(strtrim(core_project_num), 4, 2))
    gen byte nih_award = 0
    local nih_ics AA AG AI AR AT CA CL DA DC DE DK EB ES EY GM HD HG HL LM MD MH NR NS OD RR TR TW
    foreach ic of local nih_ics {
        replace nih_award = 1 if nih_ic == "`ic'"
    }
    label var nih_ic "awarding component parsed from core project number"
    label var nih_award "NIH awarding component (historical codes included)"

    * Shared service/admin budgets are not individual research-project budgets.
    * Restrict this screen to component records. Recognize role labels rather
    * than any occurrence of CORE (e.g., 'catalytic core' is research).
    tempvar core_title
    gen strL `core_title' = upper(itrim(strtrim(ustrregexra(project_title, "[^A-Za-z0-9 ]", " "))))
    gen byte shared_core = !mi(strtrim(subproject_id)) & ( ///
        regexm(`core_title', "(^| )CORES?( ([A-Z][0-9]?[0-9]?|[0-9][0-9]?[0-9]?))?$") | ///
        regexm(`core_title', "^CORES?( |$)") | ///
        regexm(`core_title', "(^| )CORES? [A-Z0-9]( |$)") | ///
        regexm(`core_title', "(^| )CORES? (FACILITY|FACILITIES|LABORATORY|LABORATORIES|RESOURCE|RESOURCES|SUPPORT|SUBCONTRACT|FOR|AND|INSTITUTE|SITE|SITES|COMPONENT|COMPONENTS|UNIT|UNITS|BUDGET|PATIENT|WILL|EXPANSION|CLINICAL TRIAL SITE|RESEARCH LAB|P[0-9]+)( |$)") | ///
        regexm(`core_title', "(^| )(RESEARCH|TRAINING|EDUCATION|PILOT|DEVELOPMENT|PROTEOMICS) CORES?( |$)") | ///
        regexm(upper(project_title), "(^|[^A-Z0-9])CORES? *[-:/(),&]") | ///
        regexm(`core_title', "(^| )(ADMINISTRATIVE|ADMINSTRATIVE|ADMINITRATIVE|ADMIN)( |$)") | ///
        regexm(`core_title', "(^ADMINISTRATION$)|( (CENTER|CENTRE) ADMINISTRATION$)|(^ADMINISTRATION (AND|OF THE (CENTER|CENTRE|PROGRAM))( |$))") | ///
        regexm(`core_title', "(^| )SHARED RESOURCES?( |$)"))
    replace shared_core = 0 if ///
        regexm(`core_title', "^CORE (PROTEIN|PROMOTER|PARTICLE|HISTONE|BINDING|DOMAIN|STRUCTURE|SIGNAL)( |$)") & ///
        !regexm(`core_title', "(^| )CORES?( ([A-Z][0-9]?[0-9]?|[0-9][0-9]?[0-9]?))?$")
    label var shared_core "shared/admin component identified from project title"

    * A parent's TOTAL_COST already contains its component budgets. For each
    * award-fiscal-year, retain components rather than the umbrella record.
    * Use all source rows here, including components outside the activity list.
    * Leave standalone awards intact; never infer a PI budget from the residual.
    tempvar has_subprojects
    egen byte `has_subprojects' = max(!mi(strtrim(subproject_id))), ///
        by(fy core_project_num)
    gen byte multi_project_parent = `has_subprojects' & ///
        mi(strtrim(subproject_id)) & !mi(strtrim(core_project_num)) & !mi(fy)
    label var multi_project_parent "parent excluded: components reported for this core project and FY"

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

    qui count if research
    local n_res = r(N)
    qui count if research & !mi(start_year) & start_year != award_start_year
    di as text "  `r(N)' of `n_res' research rows disagree with their award start"

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
    gen byte new_grant   = res_grant & award_start_year == year

    gen double res_cost   = total_cost    if research
    gen double res_cost_pi = total_cost_pi if research
    gen double train_cost = total_cost    if training
    gen double res_start  = project_start if research
    gen double res_end    = project_end   if research

    gcollapse (sum) n_grants            = res_grant ///
              (sum) n_new_grants        = new_grant ///
              (sum) nih_total_cost      = res_cost ///
              (sum) nih_total_cost_pi   = res_cost_pi ///
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
    label var n_new_grants       "research awards whose AWARD start year is this year"
    label var n_grants           "distinct research awards active this year (supplements incl.)"
    label var nih_total_cost     "total cost, research rows incl. supplements"
    label var nih_total_cost_pi  "research cost divided by all listed PIs, incl. supplements"
    label var n_train_grants     "individual K training awards"
    label var n_r50_grants       "R50 awards (borderline, excluded from n_grants)"
    label var n_grants_all       "all retained grants (research + training + R50)"
    label var nih_total_cost_all "total cost, retained grants"
    label var n_grants_nosupp    "research grants, administrative supplements excluded"
    label var nih_cost_nosupp    "total cost, research grants ex supplements"
    label var n_supp_rows        "administrative supplement rows this year"
    save ../temp/nih_by_athr_year, replace

    save ../output/nih_athr_year, replace
    * Fix baseline resources before any publication-panel/sample restrictions.
    * Sum FY2010-2013 and divide by four, including absent years as zero.
    gen double n_grants_pre = cond(inrange(year, 2010, 2013), n_grants, 0)
    gen double nih_cost_pre = cond(inrange(year, 2010, 2013), nih_total_cost, 0)
    gen double nih_cost_pre_pi = cond(inrange(year, 2010, 2013), nih_total_cost_pi, 0)
    collapse (sum) n_grants_pre nih_cost_pre nih_cost_pre_pi, by(athr_id)
    gen double nih_grants_baseline = n_grants_pre / 4
    gen double nih_funding_baseline = nih_cost_pre / 4
    gen double nih_funding_baseline_pi = nih_cost_pre_pi / 4
    label var n_grants_pre "sum of research award counts, FY2010-2013"
    label var nih_cost_pre "total research funding, FY2010-2013"
    label var nih_grants_baseline "mean annual research award count, FY2010-2013 (zeros included)"
    label var nih_funding_baseline "mean annual research funding, FY2010-2013 (zeros included)"
    label var nih_funding_baseline_pi "mean annual research funding per listed PI, FY2010-2013 (zeros included)"
    save ../output/nih_baseline_by_athr, replace
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
