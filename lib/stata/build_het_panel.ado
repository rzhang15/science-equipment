program build_het_panel
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
