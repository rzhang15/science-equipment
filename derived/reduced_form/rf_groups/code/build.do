set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries, loadglob(../external/lib/globals.txt)
adopath ++ "../external/lib/stata"
version 17
set maxvar 20000

* NIH_BASELINE_MEASURE: pi = equal shares across listed PIs; full = full credit (stata-mp -b do build.do full)
global NIH_BASELINE_MEASURE "pi"
if "`1'" != "" global NIH_BASELINE_MEASURE "`1'"
if !inlist("$NIH_BASELINE_MEASURE", "pi", "full") {
    di as error "NIH_BASELINE_MEASURE must be pi or full"
    exit 198
}
* LAB_CLOCK : panel | athr_age
global LAB_CLOCK "panel"
global HET_IC_FULL 0
if $HET_IC_FULL == 1 {
    global IC_ALIASES contr fdlsb fdls fdlsh gntsf hhlsb hhls hhlsh nflsb nfls nflsh subrf busf fedf tfnd instf nonpf statf lsf hsf biof applx apfx basx bfx clinx devx lscx medx endow
}

program main
    gather_inst_chars
    nih_name_matches
    foreach suf in _r1_r2 _r1_r2_public _r1 _r1_public {
        build_nih_outcomes, samp(all_jrnls) suf(`suf')
        build_groups, samp(all_jrnls) suf(`suf')
    }
end

program nih_name_matches
    import delimited ../external/nih/pi_athr_crosswalk.csv, clear varnames(1) stringcols(_all)
    keep athr_id
    drop if mi(athr_id)
    duplicates drop athr_id, force
    gen byte nih_name_matched = 1
    save ../temp/nih_name_matches, replace
end

program build_nih_outcomes
    syntax, samp(string) suf(string)
    use athr_id year using ../external/prepped_samples/es_`samp'`suf', clear
    merge m:1 athr_id using ../temp/nih_name_matches, keep(1 3) nogen
    replace nih_name_matched = 0 if mi(nih_name_matched)
    merge 1:1 athr_id year using ../external/nih/nih_athr_year, ///
        keep(1 3) keepusing(nih_total_cost n_grants n_new_grants) nogen
    foreach v in nih_total_cost n_grants n_new_grants {
        replace `v' = 0 if mi(`v') & nih_name_matched == 1
        replace `v' = . if nih_name_matched != 1
    }
    gen byte has_nih = n_grants > 0 if nih_name_matched == 1
    keep athr_id year nih_total_cost n_grants n_new_grants has_nih
    compress
    save ../output/nih_outcomes`suf', replace
end

program build_groups
    syntax, samp(string) suf(string)
    use ../external/prepped_samples/es_`samp'`suf', clear
    cap confirm variable msa_size
    if !_rc {
        gen msa_size_2014 = msa_size if year == 2014
        bys athr_id: egen msa_size_at = max(msa_size_2014)
        drop msa_size_2014
    }
    bys athr_id (year): keep if _n == 1
    local keep athr_id inst_id type public min_year pre_ppr_cnt_sum
    foreach v in min_year_nonsolo min_year_any msa_size_at nih_grants_baseline nih_funding_baseline {
        cap confirm variable `v'
        if !_rc local keep `keep' `v'
    }
    keep `keep'

    merge 1:1 athr_id using ../temp/nih_name_matches, keep(1 3) nogen
    replace nih_name_matched = 0 if mi(nih_name_matched)

    if "$LAB_CLOCK" == "athr_age" {
        merge 1:1 athr_id using ../external/athr_age/athr_age, keep(1 3) keepusing(first_last) nogen
        cap confirm variable min_year_nonsolo
        if !_rc replace min_year = min(first_last, min_year_nonsolo)
        else {
            di as error "build_groups `samp'`suf': min_year_nonsolo not in panel -- lab clock = first_last only"
            replace min_year = first_last
        }
        qui count if mi(min_year)
        di as text "build_groups `samp'`suf': lab clock = min(athr_age first_last, min_year_nonsolo); " ///
            r(N) " PIs with neither drop from lab-age splits"
        drop first_last
    }
    gen lab_clock_min_year = min_year

    qui sum min_year, d
    local lastyr_med = r(p50)
    di as text "build_groups `samp'`suf' min_year (first last-author yr) median = `lastyr_med'"
    gen young = min_year >  `lastyr_med' if !mi(min_year)
    gen old   = min_year <= `lastyr_med' if !mi(min_year)

    cap confirm variable min_year_nonsolo
    if !_rc {
        qui sum min_year_nonsolo, d
        local nsyr_med = r(p50)
        qui count if mi(min_year_nonsolo)
        di as text "build_groups `samp'`suf' min_year_nonsolo median = `nsyr_med'; " r(N) " PIs with no non-solo last-author paper"
        gen byte young_ns = min_year_nonsolo >  `nsyr_med' if !mi(min_year_nonsolo)
        gen byte old_ns   = min_year_nonsolo <= `nsyr_med' if !mi(min_year_nonsolo)
        gen lab_age_ns_2014 = 2014 - min_year_nonsolo
    }
    else di as error "build_groups `samp'`suf': min_year_nonsolo not in panel -- young_ns/old_ns SKIPPED."

    cap confirm variable min_year_any
    if !_rc {
        qui sum min_year_any, d
        local anyyr_med = r(p50)
        di as text "build_groups `samp'`suf' min_year_any (first pub ever) median = `anyyr_med'"
        gen byte young_any = min_year_any >  `anyyr_med' if !mi(min_year_any)
        gen byte old_any   = min_year_any <= `anyyr_med' if !mi(min_year_any)
        gen lab_age_any_2014 = 2014 - min_year_any
    }
    else di as error "build_groups `samp'`suf': min_year_any not in panel -- young_any/old_any SKIPPED."

    gen r1 = type == "r1" if !mi(type)
    gen r2 = type == "r2" if !mi(type)
    gen byte pub_inst  = public == 1 if !mi(public)
    gen byte priv_inst = public == 0 if !mi(public)

    foreach v in nih_grants_baseline nih_funding_baseline nih_funding_baseline_pi {
        cap drop `v'
    }
    merge 1:1 athr_id using ../external/nih/nih_baseline_by_athr, ///
        keep(1 3) keepusing(nih_grants_baseline nih_funding_baseline nih_funding_baseline_pi) nogen
    local funding_src nih_funding_baseline
    if "$NIH_BASELINE_MEASURE" == "pi" local funding_src nih_funding_baseline_pi
    gen str4 nih_baseline_measure = "$NIH_BASELINE_MEASURE"
    di as text "NIH funding groups use `funding_src' ($NIH_BASELINE_MEASURE)"
    local nih_src   nih_grants_baseline `funding_src'
    local nih_alias nihg     nihd
    forvalues i = 1/2 {
        local src : word `i' of `nih_src'
        local alias : word `i' of `nih_alias'
        cap confirm variable `src'
        if _rc {
            di as error "build_groups `samp'`suf': `src' missing -- rebuild NIH and rf_sample."
            exit 111
        }
        gen double pre_`alias' = `src' if nih_name_matched == 1 & !mi(`src') & `src' > 0
        local src pre_`alias'
        qui sum `src', d
        local nih_n = r(N)
        local nih_p50 = r(p50)
        di as text "build_groups `samp'`suf' `alias' N_pi=`nih_n' p50=`nih_p50'"
        gen byte high_`alias' = `src' >= `nih_p50' if !mi(`src')
        gen byte low_`alias'  = `src' <  `nih_p50' if !mi(`src')
        replace high_`alias' = 0 if mi(pre_`alias') & nih_name_matched == 1
        replace low_`alias' = 1 if mi(pre_`alias') & nih_name_matched == 1
        assert high_`alias' + low_`alias' == 1 if nih_name_matched == 1
        assert mi(high_`alias') & mi(low_`alias') if nih_name_matched != 1
        qui count if low_`alias' == 1
        di as text "build_groups `samp'`suf' `alias' low (name-matched, includes no baseline awards): " r(N) " PIs"
    }

    cap confirm variable pre_nihd
    if !_rc {
        qui sum pre_nihd if young == 1, d
        local ynih_n = r(N)
        local ynih_med = r(p50)
        local ynih_p25 = r(p25)
        local ynih_p75 = r(p75)
        di as text "build_groups `samp'`suf' young-only nihd N_pi=`ynih_n' p25=`ynih_p25' p50=`ynih_med' p75=`ynih_p75'"
        gen byte yhigh_nihd = pre_nihd >= `ynih_med' if !mi(pre_nihd) & young == 1
        gen byte ylow_nihd  = pre_nihd <  `ynih_med' if !mi(pre_nihd) & young == 1
        replace yhigh_nihd = 0 if mi(pre_nihd) & young == 1 & nih_name_matched == 1
        replace ylow_nihd = 1 if mi(pre_nihd) & young == 1 & nih_name_matched == 1
        gen byte yq4_nihd = pre_nihd >= `ynih_p75' if !mi(pre_nihd) & young == 1 ///
                            & (pre_nihd >= `ynih_p75' | pre_nihd <= `ynih_p25')
        gen byte yq1_nihd = 1 - yq4_nihd
    }

    gen byte nih_pi = nih_name_matched
    qui count if nih_pi == 1
    di as text "build_groups `samp'`suf' NIH name-matched PIs = " r(N)
    gen byte young_nih = young if nih_pi == 1 & !mi(young)
    gen byte old_nih   = old   if nih_pi == 1 & !mi(old)

    cap confirm file ../external/prepped_samples/exit_`samp'`suf'.dta
    if !_rc {
        merge 1:1 athr_id using ../external/prepped_samples/exit_`samp'`suf', keep(1 3) keepusing(exit_2022) nogen
        gen byte surv_samp = (young == 0) | (young == 1 & exit_2022 == 0) if !mi(young) & !mi(exit_2022)
        gen byte young_surv = young if surv_samp == 1
        gen byte old_surv   = old   if surv_samp == 1
        gen byte young_sb   = young if exit_2022 == 0 & !mi(young)
        gen byte old_sb     = old   if exit_2022 == 0 & !mi(old)
        qui count if young == 1 & exit_2022 == 1
        local n_drop = r(N)
        qui count if young_surv == 1
        di as text "build_groups `samp'`suf': survivor split drops `n_drop' early-career PIs with no last-author paper in 2020-22; " ///
            r(N) " early-career survivors kept"
        drop surv_samp
    }
    else di as error "build_groups `samp'`suf': exit_`samp'`suf' not in prepped_samples -- young_surv/old_surv SKIPPED (rerun rf_sample)."

    cap confirm file ../external/athr_age/athr_age.dta
    if !_rc {
        merge 1:1 athr_id using ../external/athr_age/athr_age, keep(1 3) keepusing(first_pub) nogen
        gen train_yrs = min_year - first_pub
        qui count if young == 1 & train_yrs < 0
        local n_neg = r(N)
        replace train_yrs = . if train_yrs < 0
        qui sum train_yrs if young == 1, d
        local train_med = r(p50)
        gen byte y_longtrain  = train_yrs >  `train_med' if young == 1 & !mi(train_yrs)
        gen byte y_shorttrain = train_yrs <= `train_med' if young == 1 & !mi(train_yrs)
        qui count if y_longtrain == 1
        local n_long = r(N)
        qui count if y_shorttrain == 1
        di as text "build_groups `samp'`suf': early-career training split (first OpenAlex article to first last-authored paper) at median `train_med' yrs: " ///
            "`n_long' long, " r(N) " short; `n_neg' early-career PIs with first_pub after min_year set missing"
        drop first_pub
    }
    else di as error "build_groups `samp'`suf': athr_age not in external -- y_longtrain/y_shorttrain SKIPPED."

    merge m:1 inst_id using ../temp/inst_chars_pre, keep(1 3) nogen
    bys inst_id: gen inst_indicator = _n == 1
    foreach a of global IC_ALIASES {
        cap confirm variable ic_`a'
        if _rc continue
        qui sum ic_`a' if inst_indicator == 1, d
        local ic_n = r(N)
        local ic_p50 = r(p50)
        local ic_p25 = r(p25)
        local ic_p75 = r(p75)
        di as text "build_groups `samp'`suf' ic_`a' inst-wtd N_inst=`ic_n' p25=`ic_p25' p50=`ic_p50' p75=`ic_p75'"
        gen byte hi_`a'  = ic_`a' >= `ic_p50' if !mi(ic_`a')
        gen byte lo_`a'  = ic_`a' <  `ic_p50' if !mi(ic_`a')
        gen byte q1_`a'  = ic_`a' <= `ic_p25' if !mi(ic_`a')
        gen byte q4_`a'  = ic_`a' >= `ic_p75' if !mi(ic_`a')
        gen byte mid_`a' = (ic_`a' > `ic_p25' & ic_`a' < `ic_p75') if !mi(ic_`a')
        qui sum ic_`a', d
        local ic_p25w = r(p25)
        local ic_p50w = r(p50)
        local ic_p75w = r(p75)
        di as text "build_groups `samp'`suf' ic_`a' pi-wtd N_pi=" r(N) " p25=`ic_p25w' p50=`ic_p50w' p75=`ic_p75w'"
        gen byte hiw_`a'  = ic_`a' >= `ic_p50w' if !mi(ic_`a')
        gen byte low_`a'  = ic_`a' <  `ic_p50w' if !mi(ic_`a')
        gen byte q1w_`a'  = ic_`a' <= `ic_p25w' if !mi(ic_`a')
        gen byte q4w_`a'  = ic_`a' >= `ic_p75w' if !mi(ic_`a')
        gen byte midw_`a' = (ic_`a' > `ic_p25w' & ic_`a' < `ic_p75w') if !mi(ic_`a')
    }
    drop inst_indicator

    local pi_q_source pre_ppr_cnt_sum pre_nihg pre_nihd
    local pi_q_alias  pre_ppr        nihg     nihd
    local nq : word count `pi_q_alias'
    forvalues i = 1/`nq' {
        local src : word `i' of `pi_q_source'
        local alias : word `i' of `pi_q_alias'
        cap confirm variable `src'
        if _rc {
            di as error "build_groups `samp'`suf': `src' unavailable -- `alias' quartiles SKIPPED."
            continue
        }
        qui sum `src', d
        local p25 = r(p25)
        local p75 = r(p75)
        di as text "build_groups `samp'`suf' `alias' p25=`p25' p75=`p75'"
        gen byte q1_`alias'  = `src' <= `p25' if !mi(`src')
        gen byte q4_`alias'  = `src' >= `p75' if !mi(`src')
        gen byte mid_`alias' = (`src' > `p25' & `src' < `p75') if !mi(`src')
    }

    foreach a of global IC_ALIASES {
        cap confirm variable hiw_`a'
        if _rc continue
        gen byte y_hi_`a' = (young == 1 & hiw_`a' == 1) if !mi(young) & !mi(hiw_`a')
        gen byte y_lo_`a' = (young == 1 & hiw_`a' == 0) if !mi(young) & !mi(hiw_`a')
        gen byte o_hi_`a' = (young == 0 & hiw_`a' == 1) if !mi(young) & !mi(hiw_`a')
        gen byte o_lo_`a' = (young == 0 & hiw_`a' == 0) if !mi(young) & !mi(hiw_`a')
    }
    cap confirm variable high_nihd
    if !_rc {
        gen byte y_hi_nihd = (young == 1 & high_nihd == 1) if !mi(young) & !mi(high_nihd)
        gen byte y_lo_nihd = (young == 1 & high_nihd == 0) if !mi(young) & !mi(high_nihd)
        gen byte o_hi_nihd = (young == 0 & high_nihd == 1) if !mi(young) & !mi(high_nihd)
        gen byte o_lo_nihd = (young == 0 & high_nihd == 0) if !mi(young) & !mi(high_nihd)
    }

    gen lab_age_2014 = 2014 - min_year
    qui sum lab_age_2014, d
    local lab_med = r(p50)
    di as text "build_groups `samp'`suf' lab_age median = `lab_med'"
    gen byte new_lab = lab_age_2014 <  `lab_med' if !mi(lab_age_2014)
    gen byte est_lab = lab_age_2014 >= `lab_med' if !mi(lab_age_2014)
    gen byte lab_lt10  = lab_age_2014 < 10             if !mi(lab_age_2014)
    gen byte lab_10_20 = inrange(lab_age_2014, 10, 19) if !mi(lab_age_2014)
    gen byte lab_20p   = lab_age_2014 >= 20            if !mi(lab_age_2014)
    qui sum lab_age_2014, d
    di as text "build_groups `samp'`suf' lab_age quartile cuts: p25=" r(p25) " p50=" r(p50) " p75=" r(p75)
    xtile _labq = lab_age_2014, nq(4)
    forval q = 1/4 {
        gen byte q`q'_labage = _labq == `q' if !mi(_labq)
    }
    drop _labq

    cap confirm variable msa_size_at
    if !_rc {
        qui sum msa_size_at, d
        local msa_med = r(p50)
        gen byte big_msa   = msa_size_at >= `msa_med' if !mi(msa_size_at)
        gen byte small_msa = msa_size_at <  `msa_med' if !mi(msa_size_at)
    }

    foreach v in inst_id type public min_year min_year_nonsolo min_year_any pre_ppr_cnt_sum {
        cap drop `v'
    }
    compress
    save ../output/pi_groups`suf', replace
end

program gather_inst_chars
    import delimited ../external/college/ipeds_openalex.csv, ///
        clear varn(1) stringcols(_all)
    keep ipeds_id inst_id
    drop if inst_id == "" | ipeds_id == ""
    destring ipeds_id, replace
    duplicates drop
    bys ipeds_id: gen _ndup = _N
    qui count if _ndup > 1
    if r(N) > 0 {
        di as error "gather_inst_chars: " r(N) " rows with duplicate ipeds_id in crosswalk; keeping first inst_id per ipeds_id. VERIFY the crosswalk."
        bys ipeds_id (inst_id): keep if _n == 1
    }
    drop _ndup
    save ../temp/ipeds_openalex_xw, replace

    use ../external/inst_chars/combined_pre, clear
    merge 1:1 ipeds_id using ../temp/ipeds_openalex_xw, keep(3) nogen
    drop ipeds_id
    bys inst_id: gen _ndup = _N
    qui count if _ndup > 1
    if r(N) > 0 {
        di as error "gather_inst_chars: " r(N) " rows with duplicate inst_id after ipeds merge; keeping first row per inst_id. VERIFY the crosswalk."
        bys inst_id: keep if _n == 1
    }
    drop _ndup

    rename contracts_fund      ic_contr
    rename fed_ls_bio_fund     ic_fdlsb
    rename fed_ls_fund         ic_fdls
    rename fed_ls_hs_fund      ic_fdlsh
    rename grants_fund         ic_gntsf
    rename hhs_ls_bio_fund     ic_hhlsb
    rename hhs_ls_fund         ic_hhls
    rename hhs_ls_hs_fund      ic_hhlsh
    rename nonfed_ls_bio_fund  ic_nflsb
    rename nonfed_ls_fund      ic_nfls
    rename nonfed_ls_hs_fund   ic_nflsh
    rename subrecipient_fund   ic_subrf
    rename tot_bus_fund        ic_busf
    rename tot_fed_fund        ic_fedf
    rename tot_fund            ic_tfnd
    rename tot_inst_fund       ic_instf
    rename tot_nonprof_fund    ic_nonpf
    rename tot_state_fund      ic_statf
    rename ls_fund             ic_lsf
    rename hs_fund             ic_hsf
    rename bio_fund            ic_biof
    rename applied_expend      ic_applx
    rename applied_fed_expend  ic_apfx
    rename basic_expend        ic_basx
    rename basic_fed_expend    ic_bfx
    rename clin_trial_expend   ic_clinx
    rename dev_expend          ic_devx
    rename ls_cap_expend       ic_lscx
    rename med_sch_expend      ic_medx
    rename endowment           ic_endow

    order inst_id
    compress
    save ../temp/inst_chars_pre, replace
end

main
