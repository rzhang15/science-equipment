set more off
clear all
capture log close
program drop _all
version 17

* Rebuild the es_all_jrnls_r1_r2 author sample using the archived exposure
* file external/exposure/ok (Jul 10 shift-share output), then diff the author
* set against the snapshot saved at ../es_all_jrnls_r1_r2.dta. Mirrors
* restrict_samp in analysis.do (samp=all_jrnls, r1r2=1, EXPOSURE_VERSION=hc);
* graph/NIH/winsorize steps are skipped because they do not change the sample.

program main
    build_inputs
    build_sample_ok
    compare_authors
end

program build_inputs
    copy ../external/exposure/ok ../temp/ok_exposure.csv, replace
    import delimited ../temp/ok_exposure.csv, clear
    rename exposure_ss imputed
    rename sum_imputed_shares imputed_mkt_spend_shr
    save ../temp/exposure_ok, replace

    import delimited ../external/cluster/author_static_clusters_30_ls.csv, clear varnames(1)
    cap tostring athr_id, replace
    rename cluster_label cluster_30
    save ../temp/athr_cluster30_ok, replace

    use athr_id max_sim using ../external/exposure/match_diagnostics, clear
    save ../temp/match_diag_ok, replace

    use athr_id year ppr_cnt cite_affl_wt affl_wt ///
        using ../external/samp/athr_panel_full_year_all_jrnls_r1_r2, clear
    rename (ppr_cnt cite_affl_wt affl_wt) (ppr_cnt_any cite_affl_wt_any affl_wt_any)
    save ../temp/athr_any_ok, replace
    bys athr_id: egen min_year_any = min(year)
    keep athr_id min_year_any
    duplicates drop
    save ../temp/athr_min_year_any_ok, replace
end

program build_sample_ok
    use ../external/samp/athr_panel_full_year_last_all_jrnls_r1_r2, clear
    bys athr_id: egen max_year = max(year)
    bys athr_id: egen min_year = min(year)
    keep if min_year <= 2013
    keep if max_year >= 2015
    keep if inrange(year, 2010, 2019)
    merge m:1 athr_id using ../temp/exposure_ok, keep(1 3) nogen
    merge m:1 athr_id using ../external/real_exposure/athr_exposure_hc, keep(1 3) nogen
    keep if !mi(imputed) | !mi(exposure)
    merge m:1 athr_id using ../temp/athr_cluster30_ok, keep(1 3) nogen
    merge m:1 athr_id using ../temp/athr_min_year_any_ok, keep(1 3) nogen
    replace min_year_any = min_year if mi(min_year_any)
    gen foia_athr = 1 if !mi(exposure)
    merge m:1 athr_id using ../temp/match_diag_ok, keep(1 3) nogen
    replace max_sim = 1 if foia_athr == 1
    replace max_sim = 0 if mi(max_sim)
    bys athr_id : gen athr_indicator = _n == 1
    replace imputed = exposure if !mi(exposure)
    replace imputed_mkt_spend_shr = mkt_spend_shr if !mi(mkt_spend_shr)
    drop exposure
    rename imputed exposure
    drop mkt_spend_shr
    rename imputed_mkt_spend_shr mkt_spend_shr
    bys athr_id: egen num_yrs_pre = total(year < 2014)
    bys athr_id inst_id: gen plc_cntr = _n == 1
    bys athr_id : egen num_place = total(plc_cntr)
    drop if num_yrs_pre <= 2
    keep if num_place==1
    gegen athr = group(athr_id)
    preserve
    contract athr num_place athr_id exposure inst_id inst msa_comb msa_c_world min_year min_year_any type public mkt_spend_shr cluster_30 max_sim foia_athr
    drop _freq
    save ../temp/athr_xw_ok, replace
    restore
    xtset athr year
    tsfill, full
    drop athr_id exposure inst_id inst msa_comb msa_c_world min_year min_year_any type public mkt_spend_shr cluster_30 max_sim foia_athr
    merge m:1 athr using ../temp/athr_xw_ok, assert(3) keep(3) nogen
    merge 1:1 athr_id year using ../temp/athr_any_ok, keep(1 3) nogen
    foreach var in ppr_cnt cite_affl_wt affl_wt ppr_cnt_any cite_affl_wt_any affl_wt_any {
        replace `var' = 0 if mi(`var')
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
    drop if mi(exposure)
    drop if mi(mkt_spend_shr) | mkt_spend_shr <= 0
    keep athr_id inst foia_athr exposure mkt_spend_shr
    bys athr_id: keep if _n == 1
    gunique athr_id
    di as text "ok-based sample: " r(unique) " authors"
    save ../temp/ok_sample_athrs, replace
end

program compare_authors
    use athr_id inst foia_athr exposure mkt_spend_shr using ../es_all_jrnls_r1_r2.dta, clear
    bys athr_id: keep if _n == 1
    rename (inst foia_athr exposure mkt_spend_shr) ///
           (inst_saved foia_saved exposure_saved mkt_spend_shr_saved)
    merge 1:1 athr_id using ../temp/ok_sample_athrs

    qui count if _merge == 3
    di as text _newline "mutual authors:                     " r(N)
    qui count if _merge == 2
    di as text "only in ok-based sample:            " r(N)
    qui count if _merge == 1
    di as text "only in saved es_all_jrnls_r1_r2:   " r(N)

    preserve
    keep if _merge == 1
    keep athr_id inst_saved foia_saved exposure_saved
    export delimited ../temp/athrs_only_in_saved.csv, replace
    qui count
    if r(N) > 0 & r(N) <= 300 list athr_id inst_saved foia_saved, sep(0) noobs
    restore

    preserve
    keep if _merge == 2
    keep athr_id inst foia_athr exposure
    export delimited ../temp/athrs_only_in_ok.csv, replace
    qui count
    if r(N) > 0 & r(N) <= 300 list athr_id inst foia_athr, sep(0) noobs
    restore
end

main
