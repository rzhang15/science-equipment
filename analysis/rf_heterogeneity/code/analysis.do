set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17
set maxvar 20000

global EXPOSURE_VERSION "hc_all3"
global EXPOSURE_FILTER  "_cf_k3"
global FE_MODE "author"
* FIG_MODES : pres | paper | both
global FIG_MODES "both"
if "$FIG_MODES" == "both" global FIG_MODES "pres paper"
global HET_RUN_OLS 0
global DEBUG_YVAR "ppr_cnt"
global HET_INCLUDE_INSTWTD 0
global HET_RUN_QUARTILES 0
global HET_IC_FULL 0
global HET_AGE_NBINS 10
* LAB_CLOCK : athr_age | panel
global LAB_CLOCK "panel"
global HET_HORSERACE_ONLY 0
if "`1'" == "horserace" global HET_HORSERACE_ONLY 1
global HET_COEFPLOTS_ONLY 0
if "`1'" == "coefplots" global HET_COEFPLOTS_ONLY 1

program main
    if $HET_COEFPLOTS_ONLY == 1 {
        define_group_labels
        ppml_het_coefplot, samp(all_jrnls) r1r2(1) public(0)
        ppml_het_coefplot, samp(all_jrnls) r1r2(1) public(1)
        exit
    }
    gather_inst_chars
    define_group_labels
    local s all_jrnls
    cap mkdir "../output/figures/`s'"
    if $HET_HORSERACE_ONLY == 1 {
        cap mkdir ../temp
        cap confirm file ../temp/es_`s'_r1_r2.dta
        if _rc add_het_splits, samp(`s') r1r2(1) public(0)
        cap confirm file ../temp/es_`s'_r1_r2_public.dta
        if _rc add_het_splits, samp(`s') r1r2(1) public(1)
        desc_exposure_by_age, samp(`s') r1r2(1) public(0)
        desc_exposure_by_age, samp(`s') r1r2(1) public(1)
    }
    if $HET_HORSERACE_ONLY == 0 {
        add_het_splits, samp(`s') r1r2(1) public(0)
        desc_pre_output_by_age, samp(`s') r1r2(1) public(0)
        desc_exposure_by_age, samp(`s') r1r2(1) public(0)
        event_study_het, samp(`s') r1r2(1) public(0)
        ppml_age_gradient, samp(`s') r1r2(1) public(0)
    }
    horse_race_nih, samp(`s') r1r2(1) public(0)
    output_het_tables, samp(`s') r1r2(1) public(0)
    output_split_diff_tables, samp(`s') r1r2(1) public(0)

    if $HET_HORSERACE_ONLY == 0 {
        add_het_splits, samp(all_jrnls) r1r2(1) public(1)
        desc_pre_output_by_age, samp(all_jrnls) r1r2(1) public(1)
        desc_exposure_by_age, samp(all_jrnls) r1r2(1) public(1)
        event_study_het, samp(all_jrnls) r1r2(1) public(1)
        ppml_age_gradient, samp(all_jrnls) r1r2(1) public(1)
    }
    horse_race_nih, samp(all_jrnls) r1r2(1) public(1)
    output_het_tables, samp(all_jrnls) r1r2(1) public(1)
    output_split_diff_tables, samp(all_jrnls) r1r2(1) public(1)
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

global IC_ALIASES tfnd lsf endow
if $HET_IC_FULL == 1 {
    global IC_ALIASES contr fdlsb fdls fdlsh gntsf hhlsb hhls hhlsh nflsb nfls nflsh subrf busf fedf tfnd instf nonpf statf lsf hsf biof applx apfx basx bfx clinx devx lscx medx endow
}
global PI_Q_BASES pre_ppr nihg nihd

program define_group_labels
    global LBL_young        "Early-Career PIs"
    global LBL_old          "Late-Career PIs"
    global LBL_young_ns     "Early-Career PIs (Excl. Solo)"
    global LBL_old_ns       "Late-Career PIs (Excl. Solo)"
    global LBL_young_any    "Early-Career PIs (First Pub Ever)"
    global LBL_old_any      "Late-Career PIs (First Pub Ever)"
    global LBL_lab_lt10     "Early-Career PIs (<10 Yrs)"
    global LBL_lab_10_20    "Mid-Career PIs (10-20 Yrs)"
    global LBL_lab_20p      "Late-Career PIs (20+ Yrs)"
    global LBL_q1_labage    "Q1 Lab Age (Newest Labs)"
    global LBL_q2_labage    "Q2 Lab Age"
    global LBL_q3_labage    "Q3 Lab Age"
    global LBL_q4_labage    "Q4 Lab Age (Most Established)"
    global LBL_r1           "R1"
    global LBL_r2           "R2"
    global LBL_pub_inst     "Public Institutions"
    global LBL_priv_inst    "Private Institutions"
    global LBL_high_pre_ppr "More Productive at Baseline"
    global LBL_low_pre_ppr  "Less Productive at Baseline"
    global LBL_high_nihg    "More NIH Grants at Baseline"
    global LBL_low_nihg     "Fewer NIH Grants at Baseline"
    global LBL_high_nihd    "More NIH Funding at Baseline"
    global LBL_low_nihd     "Less NIH Funding at Baseline"
    global LBL_young_nih    "Early-Career PIs (NIH-Matched)"
    global LBL_old_nih      "Late-Career PIs (NIH-Matched)"
    global LBL_yhigh_nihd   "Early-Career, More NIH (Young Median)"
    global LBL_ylow_nihd    "Early-Career, Less NIH (Young Median)"
    global LBL_yq4_nihd     "Early-Career, Q4 NIH (Young Quartiles)"
    global LBL_yq1_nihd     "Early-Career, Q1 NIH (Young Quartiles)"
    global LBL_new_lab      "Newer Labs"
    global LBL_est_lab      "Established Labs"
    global LBL_big_msa      "Larger MSAs"
    global LBL_small_msa    "Smaller MSAs"

    global LBL_q1_pre_ppr   "Q1 Baseline Productivity"
    global LBL_q4_pre_ppr   "Q4 Baseline Productivity"
    global LBL_q1_nihg      "Q1 Baseline NIH Grants"
    global LBL_q4_nihg      "Q4 Baseline NIH Grants"
    global LBL_q1_nihd      "Q1 Baseline NIH Funding"
    global LBL_q4_nihd      "Q4 Baseline NIH Funding"

    local ic_lbl_contr "Total Contract Funding"
    local ic_lbl_fdlsb "Federal Life-Sci Biology Funding"
    local ic_lbl_fdls  "Federal Life-Sci Funding"
    local ic_lbl_fdlsh "Federal Life-Sci Health-Sci Funding"
    local ic_lbl_gntsf "Grants Funding"
    local ic_lbl_hhlsb "HHS Life-Sci Biology Funding"
    local ic_lbl_hhls  "HHS Life-Sci Funding"
    local ic_lbl_hhlsh "HHS Life-Sci Health-Sci Funding"
    local ic_lbl_nflsb "Non-Federal Life-Sci Biology Funding"
    local ic_lbl_nfls  "Non-Federal Life-Sci Funding"
    local ic_lbl_nflsh "Non-Federal Life-Sci Health-Sci Funding"
    local ic_lbl_subrf "Subrecipient Funding"
    local ic_lbl_busf  "Business Funding"
    local ic_lbl_fedf  "Total Federal Funding"
    local ic_lbl_tfnd  "Institutional R&D Funding"
    local ic_lbl_instf "Institutional Funding"
    local ic_lbl_nonpf "Non-Profit Funding"
    local ic_lbl_statf "State Funding"
    local ic_lbl_lsf   "Institutional Life-Sci Funding"
    local ic_lbl_hsf   "Health-Sci Funding"
    local ic_lbl_biof  "Biology Funding"
    local ic_lbl_applx "Applied Research Expenditures"
    local ic_lbl_apfx  "Federal Applied Research Expenditures"
    local ic_lbl_basx  "Basic Research Expenditures"
    local ic_lbl_bfx   "Federal Basic Research Expenditures"
    local ic_lbl_clinx "Clinical Trial Expenditures"
    local ic_lbl_devx  "Development Expenditures"
    local ic_lbl_lscx  "Life-Sci Capital Expenditures"
    local ic_lbl_medx  "Medical School Expenditures"
    local ic_lbl_endow "Institutional Endowment"
    local ic_lbl_nihd  "NIH Funding at Baseline"
    global LBL_ic_nihd "`ic_lbl_nihd'"
    global JOINT_AE_CHARS ${IC_ALIASES} nihd
    foreach a of global IC_ALIASES {
        global LBL_ic_`a'   "`ic_lbl_`a''"
        global LBL_hi_`a'   "High `ic_lbl_`a''"
        global LBL_lo_`a'   "Low `ic_lbl_`a''"
        global LBL_q1_`a'   "Q1 `ic_lbl_`a''"
        global LBL_q4_`a'   "Q4 `ic_lbl_`a''"
        global LBL_mid_`a'  "Mid `ic_lbl_`a''"
        global LBL_hiw_`a'  "High `ic_lbl_`a''"
        global LBL_low_`a'  "Low `ic_lbl_`a''"
        global LBL_q1w_`a'  "Q1 `ic_lbl_`a''"
        global LBL_q4w_`a'  "Q4 `ic_lbl_`a''"
        global LBL_midw_`a' "Mid `ic_lbl_`a''"
        global LBL_y_hi_`a' "Early-Career x Hi `ic_lbl_`a''"
        global LBL_y_lo_`a' "Early-Career x Lo `ic_lbl_`a''"
        global LBL_o_hi_`a' "Late-Career x Hi `ic_lbl_`a''"
        global LBL_o_lo_`a' "Late-Career x Lo `ic_lbl_`a''"
    }

    global IC_PAIRS_MED
    global IC_PAIRS_MED_PW
    global IC_PAIRS_Q
    global IC_PAIRS_Q_PW
    foreach a of global IC_ALIASES {
        global IC_PAIRS_MED    `"${IC_PAIRS_MED} "hi_`a' lo_`a'" "'
        global IC_PAIRS_MED_PW `"${IC_PAIRS_MED_PW} "hiw_`a' low_`a'" "'
        global IC_PAIRS_Q      `"${IC_PAIRS_Q} "q4_`a' q1_`a'" "'
        global IC_PAIRS_Q_PW   `"${IC_PAIRS_Q_PW} "q4w_`a' q1w_`a'" "'
    }
    global PI_PAIRS_Q
    foreach b of global PI_Q_BASES {
        global PI_PAIRS_Q `"${PI_PAIRS_Q} "q4_`b' q1_`b'" "'
    }
    global COEFPLOT_PI_PAIRS `" "young old" "r1 r2" "pub_inst priv_inst" "high_pre_ppr low_pre_ppr" "high_nihd low_nihd" "'
end

program add_het_splits
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"

    use ../external/prepped_samples/es_`samp'`suf', clear

    cap drop athr_indicator
    bys athr_id : gen athr_indicator = _n == 1

    if "$LAB_CLOCK" == "athr_age" {
        merge m:1 athr_id using ../external/athr_age/athr_age, ///
            keep(1 3) keepusing(first_last) nogen
        cap confirm variable min_year_nonsolo
        if !_rc replace min_year = min(first_last, min_year_nonsolo)
        else {
            di as error "add_het_splits `samp'`suf': min_year_nonsolo not in panel -- lab clock = first_last only"
            replace min_year = first_last
        }
        qui count if athr_indicator == 1 & mi(min_year)
        di as text "add_het_splits `samp'`suf': lab clock = min(athr_age first_last, min_year_nonsolo); " ///
            r(N) " PIs with neither drop from lab-age splits"
        drop first_last
    }

    qui sum pre_ppr_cnt_sum if athr_indicator == 1, d
    local ppr_cut = r(p50)
    gen high_pre_ppr = pre_ppr_cnt_sum >= `ppr_cut' if !mi(pre_ppr_cnt_sum)
    gen low_pre_ppr  = pre_ppr_cnt_sum <  `ppr_cut' if !mi(pre_ppr_cnt_sum)

    qui sum min_year if athr_indicator == 1, d
    local lastyr_med = r(p50)
    di as text "add_het_splits `samp'`suf' min_year (first last-author yr) median = `lastyr_med'"
    gen young = min_year >  `lastyr_med' if !mi(min_year)
    gen old   = min_year <= `lastyr_med' if !mi(min_year)

    cap confirm variable min_year_nonsolo
    if !_rc {
        qui sum min_year_nonsolo if athr_indicator == 1, d
        local nsyr_med = r(p50)
        qui count if athr_indicator == 1 & mi(min_year_nonsolo)
        di as text "add_het_splits `samp'`suf' min_year_nonsolo median = `nsyr_med'; " r(N) " PIs with no non-solo last-author paper"
        gen byte young_ns = min_year_nonsolo >  `nsyr_med' if !mi(min_year_nonsolo)
        gen byte old_ns   = min_year_nonsolo <= `nsyr_med' if !mi(min_year_nonsolo)
        gen lab_age_ns_2014 = 2014 - min_year_nonsolo
    }
    else di as error "add_het_splits `samp'`suf': min_year_nonsolo not in panel -- young_ns/old_ns SKIPPED (rerun reduced_form/code/analysis.do)."

    cap confirm variable min_year_any
    if !_rc {
        qui sum min_year_any if athr_indicator == 1, d
        local anyyr_med = r(p50)
        di as text "add_het_splits `samp'`suf' min_year_any (first pub ever) median = `anyyr_med'"
        gen byte young_any = min_year_any >  `anyyr_med' if !mi(min_year_any)
        gen byte old_any   = min_year_any <= `anyyr_med' if !mi(min_year_any)
    }
    else di as error "add_het_splits `samp'`suf': min_year_any not in panel -- young_any/old_any SKIPPED."

    gen r1 = type == "r1" if !mi(type)
    gen r2 = type == "r2" if !mi(type)
    gen byte pub_inst  = public == 1 if !mi(public)
    gen byte priv_inst = public == 0 if !mi(public)

    local nih_src   n_grants nih_total_cost
    local nih_alias nihg     nihd
    forvalues i = 1/2 {
        local src : word `i' of `nih_src'
        local alias : word `i' of `nih_alias'
        cap confirm variable `src'
        if _rc {
            di as error "add_het_splits `samp'`suf': `src' not in panel -- `alias' split SKIPPED (rerun reduced_form/restrict_samp)."
            continue
        }
        gen pre_`alias'_yr = `src' if year < 2014
        bys athr_id: egen pre_`alias' = mean(pre_`alias'_yr)
        drop pre_`alias'_yr
        local src pre_`alias'
        qui sum `src' if athr_indicator == 1, d
        local nih_n = r(N)
        local nih_p50 = r(p50)
        di as text "add_het_splits `samp'`suf' `alias' N_pi=`nih_n' p50=`nih_p50'"
        gen byte high_`alias' = `src' >= `nih_p50' if !mi(`src')
        gen byte low_`alias'  = `src' <  `nih_p50' if !mi(`src')
    }

    cap confirm variable pre_nihd
    if !_rc {
        qui sum pre_nihd if athr_indicator == 1 & young == 1, d
        local ynih_n = r(N)
        local ynih_med = r(p50)
        local ynih_p25 = r(p25)
        local ynih_p75 = r(p75)
        di as text "add_het_splits `samp'`suf' young-only nihd N_pi=`ynih_n' p25=`ynih_p25' p50=`ynih_med' p75=`ynih_p75'"
        gen byte yhigh_nihd = pre_nihd >= `ynih_med' if !mi(pre_nihd) & young == 1
        gen byte ylow_nihd  = pre_nihd <  `ynih_med' if !mi(pre_nihd) & young == 1
        gen byte yq4_nihd = pre_nihd >= `ynih_p75' if !mi(pre_nihd) & young == 1 ///
                            & (pre_nihd >= `ynih_p75' | pre_nihd <= `ynih_p25')
        gen byte yq1_nihd = 1 - yq4_nihd
    }

    cap drop nih_pi
    cap confirm variable nih_matched
    if !_rc {
        bys athr_id: egen byte nih_pi = max(nih_matched == 1)
    }
    else {
        cap confirm variable n_grants
        if !_rc bys athr_id: egen byte nih_pi = max(!mi(n_grants))
    }
    cap confirm variable nih_pi
    if !_rc {
        qui count if nih_pi == 1 & athr_indicator == 1
        di as text "add_het_splits `samp'`suf' NIH-matched PIs = " r(N)
        gen byte young_nih = young if nih_pi == 1 & !mi(young)
        gen byte old_nih   = old   if nih_pi == 1 & !mi(old)
    }
    else di as error "add_het_splits `samp'`suf': no NIH match flag in panel -- young_nih/old_nih SKIPPED."

    cap confirm variable msa_size
    if !_rc {
        gen msa_size_2014 = msa_size if year == 2014
        bys athr_id: egen msa_size_at = max(msa_size_2014)
        drop msa_size_2014
    }

    merge m:1 inst_id using ../temp/inst_chars_pre, keep(1 3) nogen
    cap drop inst_indicator
    bys inst_id : gen inst_indicator = _n == 1
    foreach a of global IC_ALIASES {
        cap confirm variable ic_`a'
        if _rc continue
        qui sum ic_`a' if inst_indicator == 1, d
        local ic_n = r(N)
        local ic_p50 = r(p50)
        local ic_p25 = r(p25)
        local ic_p75 = r(p75)
        di as text "add_het_splits `samp'`suf' ic_`a' inst-wtd N_inst=`ic_n' p25=`ic_p25' p50=`ic_p50' p75=`ic_p75'"
        gen byte hi_`a'  = ic_`a' >= `ic_p50' if !mi(ic_`a')
        gen byte lo_`a'  = ic_`a' <  `ic_p50' if !mi(ic_`a')
        gen byte q1_`a'  = ic_`a' <= `ic_p25' if !mi(ic_`a')
        gen byte q4_`a'  = ic_`a' >= `ic_p75' if !mi(ic_`a')
        gen byte mid_`a' = (ic_`a' > `ic_p25' & ic_`a' < `ic_p75') if !mi(ic_`a')
        qui sum ic_`a' if athr_indicator == 1, d
        local ic_p25w = r(p25)
        local ic_p50w = r(p50)
        local ic_p75w = r(p75)
        di as text "add_het_splits `samp'`suf' ic_`a' pi-wtd N_pi=" r(N) " p25=`ic_p25w' p50=`ic_p50w' p75=`ic_p75w'"
        gen byte hiw_`a'  = ic_`a' >= `ic_p50w' if !mi(ic_`a')
        gen byte low_`a'  = ic_`a' <  `ic_p50w' if !mi(ic_`a')
        gen byte q1w_`a'  = ic_`a' <= `ic_p25w' if !mi(ic_`a')
        gen byte q4w_`a'  = ic_`a' >= `ic_p75w' if !mi(ic_`a')
        gen byte midw_`a' = (ic_`a' > `ic_p25w' & ic_`a' < `ic_p75w') if !mi(ic_`a')
    }

    local pi_q_source pre_ppr_cnt_sum pre_nihg pre_nihd
    local pi_q_alias  pre_ppr        nihg     nihd
    local nq : word count `pi_q_alias'
    forvalues i = 1/`nq' {
        local src : word `i' of `pi_q_source'
        local alias : word `i' of `pi_q_alias'
        cap confirm variable `src'
        if _rc {
            di as error "add_het_splits `samp'`suf': `src' unavailable -- `alias' quartiles SKIPPED."
            continue
        }
        qui sum `src' if athr_indicator == 1, d
        local p25 = r(p25)
        local p75 = r(p75)
        di as text "add_het_splits `samp'`suf' `alias' p25=`p25' p75=`p75'"
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

    cap confirm variable min_year
    if !_rc {
        gen lab_age_2014 = 2014 - min_year
        qui sum lab_age_2014 if athr_indicator == 1, d
        local lab_med = r(p50)
        di as text "add_het_splits `samp'`suf' lab_age median = `lab_med'"
        gen byte new_lab = lab_age_2014 <  `lab_med' if !mi(lab_age_2014)
        gen byte est_lab = lab_age_2014 >= `lab_med' if !mi(lab_age_2014)
        gen byte lab_lt10  = lab_age_2014 < 10             if !mi(lab_age_2014)
        gen byte lab_10_20 = inrange(lab_age_2014, 10, 19) if !mi(lab_age_2014)
        gen byte lab_20p   = lab_age_2014 >= 20            if !mi(lab_age_2014)
        qui sum lab_age_2014 if athr_indicator == 1, d
        di as text "add_het_splits `samp'`suf' lab_age quartile cuts: p25=" r(p25) " p50=" r(p50) " p75=" r(p75)
        xtile _labq_pi = lab_age_2014 if athr_indicator == 1, nq(4)
        bys athr_id: egen _labq = max(_labq_pi)
        forval q = 1/4 {
            gen byte q`q'_labage = _labq == `q' if !mi(_labq)
        }
        drop _labq_pi _labq
    }
    cap confirm variable msa_size_at
    if !_rc {
        qui sum msa_size_at if athr_indicator == 1, d
        local msa_med = r(p50)
        gen byte big_msa   = msa_size_at >= `msa_med' if !mi(msa_size_at)
        gen byte small_msa = msa_size_at <  `msa_med' if !mi(msa_size_at)
    }

    compress
    save ../temp/es_`samp'`suf', replace
end

program event_study_het
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local fes athr_id year
    local vce_cl athr_id
    if "$FE_MODE" == "inst_cluster" {
        local fes inst_id cluster_30 year
        local vce_cl inst_id
    }
    if "$FE_MODE" == "inst_cluster_fldyr" {
        local fes inst_id i.cluster_30#i.year
        local vce_cl inst_id
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    use ../temp/es_`samp'`suf', clear

    gen rel = year - 2014
    qui sum rel, d
    local abs_lag = abs(r(max))
    local abs_lead = abs(r(min))
    forval i = 1/`abs_lead' {
        gen int_lead`i'  = exposure      if rel == -`i'
        gen mshr_lead`i' = mkt_spend_shr if rel == -`i'
    }
    forval i = 0/`abs_lag' {
        gen int_lag`i'  = exposure      if rel == `i'
        gen mshr_lag`i' = mkt_spend_shr if rel == `i'
    }
    ds int_lead* int_lag* mshr_lead* mshr_lag*
    foreach var in `r(varlist)' {
        replace `var' = 0 if mi(`var')
    }
    local int_leads
    local mshr_leads
    local int_lags
    local mshr_lags
    forval i = 2/`abs_lead' {
        local int_leads int_lead`i' `int_leads'
        local mshr_leads mshr_lead`i' `mshr_leads'
    }
    forval i = 0/`abs_lag' {
        local int_lags `int_lags' int_lag`i'
        local mshr_lags `mshr_lags' mshr_lag`i'
    }
    foreach v in ppr_cnt cite_affl_wt {
        gen ln_`v' = ln(1+`v')
    }

    local het_groups young old young_ns old_ns young_any old_any r1 r2 pub_inst priv_inst ///
                     high_pre_ppr low_pre_ppr high_nihg low_nihg high_nihd low_nihd ///
                     young_nih old_nih new_lab est_lab big_msa small_msa ///
                     yhigh_nihd ylow_nihd yq4_nihd yq1_nihd ///
                     lab_lt10 lab_10_20 lab_20p ///
                     q1_labage q2_labage q3_labage q4_labage
    foreach a of global IC_ALIASES {
        local het_groups `het_groups' hiw_`a' low_`a'
        if "$HET_INCLUDE_INSTWTD" == "1" local het_groups `het_groups' hi_`a' lo_`a'
        if "$HET_RUN_QUARTILES" == "1" {
            local het_groups `het_groups' q1w_`a' midw_`a' q4w_`a'
            if "$HET_INCLUDE_INSTWTD" == "1" local het_groups `het_groups' q1_`a' mid_`a' q4_`a'
        }
    }
    if "$HET_RUN_QUARTILES" == "1" {
        foreach b of global PI_Q_BASES {
            local het_groups `het_groups' q1_`b' mid_`b' q4_`b'
        }
    }
    global HET_GROUPS_ACTIVE
    foreach grp of local het_groups {
        cap confirm variable `grp'
        if _rc {
            di as text "event_study_het `samp'`suf': dummy `grp' not built -- skipping."
            continue
        }
        qui sum `grp'
        if r(N) == 0 | r(min) == r(max) {
            di as text "event_study_het `samp'`suf': dummy `grp' degenerate -- skipping."
            continue
        }
        foreach v of local int_leads {
            gen `v'_`grp' = `v' * `grp'
        }
        foreach v of local int_lags {
            gen `v'_`grp' = `v' * `grp'
        }
        gen int_lead1_`grp' = int_lead1 * `grp'
        foreach v of local mshr_leads {
            gen `v'_`grp' = `v' * `grp'
        }
        foreach v of local mshr_lags {
            gen `v'_`grp' = `v' * `grp'
        }
        local leads_`grp'
        local lags_`grp'
        local mleads_`grp'
        local mlags_`grp'
        foreach v of local int_leads {
            local leads_`grp' `leads_`grp'' `v'_`grp'
        }
        foreach v of local int_lags {
            local lags_`grp' `lags_`grp'' `v'_`grp'
        }
        foreach v of local mshr_leads {
            local mleads_`grp' `mleads_`grp'' `v'_`grp'
        }
        foreach v of local mshr_lags {
            local mlags_`grp' `mlags_`grp'' `v'_`grp'
        }
        global HET_GROUPS_ACTIVE `"${HET_GROUPS_ACTIVE} `grp'"'
    }

    if "$POSITION_OUTCOMES_AVAIL" == "" {
        cap confirm variable n_first_ppr
        global POSITION_OUTCOMES_AVAIL = cond(_rc == 0, 1, 0)
    }
    local position_outcomes ""
    if "$POSITION_OUTCOMES_AVAIL" == "1" {
        local position_outcomes n_middle_ppr avg_position avg_team_size_last avg_team_size_notlast
    }

    cap drop post Z_it Z_share_it
    gen post       = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post

    local pi_pairs `" "young old" "young_ns old_ns" "young_any old_any" "young_nih old_nih" "r1 r2" "pub_inst priv_inst" "high_pre_ppr low_pre_ppr" "high_nihg low_nihg" "high_nihd low_nihd" "new_lab est_lab" "big_msa small_msa" "yhigh_nihd ylow_nihd" "yq4_nihd yq1_nihd" "'
    global DUMMY_PAIRS_MED    `" `pi_pairs' ${IC_PAIRS_MED} "'
    global DUMMY_PAIRS_MED_PW `" `pi_pairs' ${IC_PAIRS_MED_PW} "'

    local ppml_het_skip avg_position avg_team_size_last avg_team_size_notlast

    mat drop _all
    local yvar_list ppr_cnt ppr_cnt_nonsolo cite_affl_wt avg_num_coathrs ///
                    n_grants n_new_grants nih_total_cost ///
                    `position_outcomes'
    if "$DEBUG_YVAR" != "" {
        local yvar_list $DEBUG_YVAR
        di as text "DEBUG_YVAR set -- restricting yvar loop to: $DEBUG_YVAR"
    }

    foreach yvar of local yvar_list {
        tempname ph_handle
        postfile `ph_handle' str30 yvar str24 grp str12 spec str20 split_type ///
            double(post_b post_se pre_b pre_se N r2_p) ///
            using "../temp/phet_results_`samp'`suf'_`yvar'", replace
        local gap 0.5
        if regexm("`yvar'", "^cite_affl_wt") local gap 1
        local ppml_ytit "Output-Cost Elasticity"
        if "`yvar'" == "n_grants"       local ppml_ytit "{&Delta} Log Expected Active NIH Research Grants"
        if "`yvar'" == "n_new_grants"   local ppml_ytit "{&Delta} Log Expected New NIH Research Grants"
        if "`yvar'" == "nih_total_cost" local ppml_ytit "{&Delta} Log Expected NIH Award Dollars"

        if "$HET_RUN_OLS" == "1" & inlist("`yvar'", "ppr_cnt", "cite_affl_wt") {
            foreach pair of global DUMMY_PAIRS_MED {
                local g1: word 1 of `pair'
                local g2: word 2 of `pair'
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `g1' ") == 0 continue
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `g2' ") == 0 continue
                local g1_label = "${LBL_`g1'}"
                if "`g1_label'" == "" local g1_label "`g1'"
                local mshr_ctrls `mshr_leads' `mshr_lags' `mleads_`g1'' `mlags_`g1''
                local plot_suf "_mshrctrl"
                cap drop PT_`g1'
                gen PT_`g1' = post * `g1'
                cap noi reghdfe `yvar' `int_leads' `int_lags' ///
                               `leads_`g1'' `lags_`g1'' ///
                               `mshr_ctrls' PT_`g1', ///
                               absorb(`fes') vce(cluster `vce_cl')
                local rc = _rc
                if `rc' {
                    di as error "event_study_het `samp'`suf' `yvar' `g1' failed (rc=`rc'); skipping."
                    continue
                }
                gunique athr_id if e(sample) & `g1' == 1
                local num_athrs = r(unique)
                gunique inst_id if e(sample) & `g1' == 1
                local num_insts = r(unique)
                sum `yvar' if rel <= -1 & e(sample) & `g1' == 1, d
                local pre_mean : dis %4.3f r(mean)
                preserve
                cap mat drop es
                foreach var in `leads_`g1'' `lags_`g1'' int_lead1_`g1' {
                    if "`var'" == "int_lead1_`g1'" {
                        mat row = 0,0
                    }
                    else {
                        mat row = _b[`var'], _se[`var']
                    }
                    mat es = nullmat(es) \ row
                }
                svmat es
                keep es1 es2
                drop if mi(es1)
                rename (es1 es2) (b se)
                gen ub = b + 1.96*se
                sum ub, d
                local ymax = round(r(max),`gap')
                gen lb = b - 1.96*se
                sum lb, d
                local ymin = round(r(min),`gap')
                if `ymin' > 0 local ymin = 0
                gen rel = -`abs_lead' if _n == 1
                replace rel = rel[_n-1]+1 if _n > 1
                replace rel = rel + 1 if rel >= -1
                replace rel = -1 if rel == `abs_lag' + 1
                gen year = rel + 2014
                hashsort rel
                local stats_leg `"legend(on order(- "Num. PIs: `num_athrs'" "Num. Insts: `num_insts'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(3) bmargin(zero) size(small))"'
                local fdir ../output/figures/`samp'
                foreach fmode of global FIG_MODES {
                    if "`fmode'" == "paper" {
                        local stats_leg legend(off)
                        local fdir ../output/figures/`samp'/paper
                        cap mkdir "`fdir'"
                    }
                    tw rcap ub lb year if year != 2013 , lcolor(ebblue%70) msize(vsmall) || ///
                      scatter b year, mcolor(ebblue) || ///
                    scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                      xlab(2010(1)2019, labsize(small)) xtitle("Year") ///
                      ytitle("Exposure x Post") ysc(titlegap(-6) outergap(0)) ylab(`ymin'(`gap')`ymax') ///
                      `stats_leg' ///
                      yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
                    graph export `fdir'/es_`yvar'`suf'_`g1'`plot_suf'.pdf, replace
                }
                save ../temp/es_`yvar'`suf'_`g1'`plot_suf', replace
                restore
            }

        }

        if strpos(" `ppml_het_skip' ", " `yvar' ") == 0 {
            cap mkdir "../output/figures/`samp'/es_ppml"
            local mmethods pw
            if "$HET_INCLUDE_INSTWTD" == "1" local mmethods inst pw
            foreach mmethod of local mmethods {
            local pairs_current
            if "`mmethod'" == "inst" {
                foreach pair of global DUMMY_PAIRS_MED {
                    local pairs_current `"`pairs_current' `"`pair'"' "'
                }
                local st_tag "med"
                local mplot_suf "_ppml_mshrctrl"
            }
            else {
                foreach pair of global DUMMY_PAIRS_MED_PW {
                    local pairs_current `"`pairs_current' `"`pair'"' "'
                }
                local st_tag "med_pi"
                local mplot_suf "_ppml_medpi_mshrctrl"
            }
            foreach pair of local pairs_current {
                local g1: word 1 of `pair'
                local g2: word 2 of `pair'
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `g1' ") == 0 continue
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `g2' ") == 0 continue

                cap drop Z_`g1' Z_`g2' S_`g1' S_`g2' PT_`g1'
                gen Z_`g1' = Z_it       * `g1'
                gen Z_`g2' = Z_it       * `g2'
                gen S_`g1' = Z_share_it * `g1'
                gen S_`g2' = Z_share_it * `g2'
                gen PT_`g1' = post * `g1'
                cap noi ppmlhdfe `yvar' Z_`g1' Z_`g2' S_`g1' S_`g2' PT_`g1', ///
                               absorb(`fes') vce(cluster `vce_cl')
                local rc = _rc
                if `rc' {
                    di as error "event_study_het `samp'`suf' `yvar' `g1'/`g2' `st_tag' pooled-DiD int ppml failed (rc=`rc'); skipping pair."
                    continue
                }
                local Nppml = e(N)
                local r2ppml = e(r2_p)
                foreach grp in `g1' `g2' {
                    gunique athr_id if e(sample) & `grp' == 1
                    local num_athrs = r(unique)
                    gunique inst_id if e(sample) & `grp' == 1
                    local num_insts = r(unique)
                    local b_post  = _b[Z_`grp']
                    local se_post = _se[Z_`grp']
                    di as text "pooled-DiD int PPML `samp'`suf' `yvar' `grp' `st_tag': b=" %8.4f `b_post' ///
                        " (se=" %8.4f `se_post' ")   N=" %9.0f `Nppml' " PIs=`num_athrs' Insts=`num_insts'"
                    post `ph_handle' ("`yvar'") ("`grp'") ("mshrctrl") ("`st_tag'") ///
                        (`b_post') (`se_post') (.) (.) (`Nppml') (`r2ppml')
                }

                cap noi lincom Z_`g1' - Z_`g2'
                if !_rc {
                    local b_diff  = r(estimate)
                    local se_diff = r(se)
                    local p_diff  = r(p)
                    di as text "pooled-DiD int PPML DIFF `samp'`suf' `yvar' `g1'-`g2' `st_tag': b=" %8.4f `b_diff' ///
                        " (se=" %8.4f `se_diff' ") p=" %6.4f `p_diff'
                    post `ph_handle' ("`yvar'") ("`g1'_diff") ("mshrctrl") ("`st_tag'_diff") ///
                        (`b_diff') (`se_diff') (`p_diff') (.) (`Nppml') (`r2ppml')
                }

                local mshr_ctrls `mleads_`g1'' `mlags_`g1'' `mleads_`g2'' `mlags_`g2''
                local plot_suf "`mplot_suf'"
                cap noi ppmlhdfe `yvar' `leads_`g1'' `lags_`g1'' `leads_`g2'' `lags_`g2'' ///
                               `mshr_ctrls' PT_`g1', ///
                               absorb(`fes') vce(cluster `vce_cl')
                if _rc {
                    di as error "event_study_het `samp'`suf' `yvar' `g1'/`g2' `st_tag' joint ES for PDFs failed; skipping ES plots."
                    continue
                }
                foreach grp in `g1' `g2' {
                    local grp_label = "${LBL_`grp'}"
                    if "`grp_label'" == "" local grp_label "`grp'"
                    gunique athr_id if e(sample) & `grp' == 1
                    local num_athrs = r(unique)
                    gunique inst_id if e(sample) & `grp' == 1
                    local num_insts = r(unique)
                    sum `yvar' if rel <= -1 & e(sample) & `grp' == 1, d
                    local pre_mean : dis %4.3f r(mean)
                    preserve
                    cap mat drop es
                    foreach var in `leads_`grp'' `lags_`grp'' int_lead1_`grp' {
                        if "`var'" == "int_lead1_`grp'" {
                            mat row = 0,0
                        }
                        else {
                            mat row = _b[`var'], _se[`var']
                        }
                        mat es = nullmat(es) \ row
                    }
                    svmat es
                    keep es1 es2
                    drop if mi(es1)
                    rename (es1 es2) (b se)
                    local pgap 0.2
                    gen ub = b + 1.96*se
                    gen lb = b - 1.96*se
                    local ymax = 1.2
                    local ymin = -2.2
                    gen rel = -`abs_lead' if _n == 1
                    replace rel = rel[_n-1]+1 if _n > 1
                    replace rel = rel + 1 if rel >= -1
                    replace rel = -1 if rel == `abs_lag' + 1
                    gen year = rel + 2014
                    hashsort rel
                    local stats_leg `"legend(on order(- "Num. PIs: `num_athrs'" "Num. Insts: `num_insts'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(3) bmargin(zero) size(small))"'
                    local fdir ../output/figures/`samp'/es_ppml
                    foreach fmode of global FIG_MODES {
                        if "`fmode'" == "paper" {
                            local stats_leg legend(off)
                            local fdir ../output/figures/`samp'/es_ppml/paper
                            cap mkdir "`fdir'"
                        }
                        tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
                          scatter b year, mcolor(ebblue) || ///
                        scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                          xlab(2010(1)2019, labsize(small)) xtitle("Year") ///
                          ytitle("`ppml_ytit'") ysc(titlegap(-6) outergap(0)) ylab(`ymin'(`pgap')`ymax') ytick(`ymin'(0.2)`ymax') ///
                          `stats_leg' ///
                          yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
                        graph export `fdir'/es_`yvar'`suf'_`grp'`plot_suf'.pdf, replace
                    }
                    save ../temp/es_`yvar'`suf'_`grp'`plot_suf', replace
                    restore
                }
                if "`g1'" == "young" & "`g2'" == "old" {
                    preserve
                    use ../temp/es_`yvar'`suf'_young`plot_suf', clear
                    gen grp = 1
                    append using ../temp/es_`yvar'`suf'_old`plot_suf'
                    replace grp = 2 if mi(grp)
                    replace year = year - 0.1 if grp == 1
                    replace year = year + 0.1 if grp == 2
                    local ymax = 1.2
                    local ymin = -2.2
                    local pgap 0.2
                    local fdir ../output/figures/`samp'/es_ppml
                    foreach fmode of global FIG_MODES {
                        if "`fmode'" == "paper" {
                            local fdir ../output/figures/`samp'/es_ppml/paper
                            cap mkdir "`fdir'"
                        }
                        foreach hide in 0 1 {
                            local ocol dkorange
                            local ocol_ci dkorange%70
                            local olbl "${LBL_old}"
                            local fsuf young_old
                            if `hide' {
                                local ocol none
                                local ocol_ci none
                                local olbl " "
                                local fsuf young_old_hideold
                            }
                            tw rcap ub lb year if rel != -1 & grp == 1, lcolor(ebblue%70) msize(vsmall) || ///
                              scatter b year if grp == 1, mcolor(ebblue) || ///
                              rcap ub lb year if rel != -1 & grp == 2, lcolor(`ocol_ci') msize(vsmall) || ///
                              scatter b year if grp == 2, mcolor(`ocol') || ///
                            scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                              xlab(2010(1)2019, labsize(small)) xtitle("Year") ///
                              ytitle("`ppml_ytit'") ysc(titlegap(-6) outergap(0)) ylab(`ymin'(`pgap')`ymax') ytick(`ymin'(0.2)`ymax') ///
                              legend(on order(2 "${LBL_young}" 4 "`olbl'") pos(6) ring(1) rows(1) size(small)) ///
                              yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
                            graph export `fdir'/es_`yvar'`suf'_`fsuf'`plot_suf'.pdf, replace
                        }
                    }
                    restore
                }
            }
            }

            foreach aspec in age3 ageq4 {
                if "`aspec'" == "age3"  local agrps lab_lt10 lab_10_20 lab_20p
                if "`aspec'" == "ageq4" local agrps q1_labage q2_labage q3_labage q4_labage
                local aok 1
                foreach grp of local agrps {
                    if strpos(" ${HET_GROUPS_ACTIVE} ", " `grp' ") == 0 local aok 0
                }
                if `aok' {
                local nb : word count `agrps'
                local abase : word `nb' of `agrps'
                local Zs
                local Ss
                local PTs
                foreach grp of local agrps {
                    cap drop Z_`grp'
                    cap drop S_`grp'
                    cap drop PT_`grp'
                    gen Z_`grp' = Z_it       * `grp'
                    gen S_`grp' = Z_share_it * `grp'
                    local Zs `Zs' Z_`grp'
                    local Ss `Ss' S_`grp'
                    if "`grp'" != "`abase'" {
                        gen PT_`grp' = post * `grp'
                        local PTs `PTs' PT_`grp'
                    }
                }
                cap noi ppmlhdfe `yvar' `Zs' `Ss' `PTs', ///
                               absorb(`fes') vce(cluster `vce_cl')
                local rc = _rc
                if `rc' {
                    di as error "event_study_het `samp'`suf' `yvar' `aspec' pooled-DiD int ppml failed (rc=`rc'); skipping."
                }
                else {
                    local Nppml = e(N)
                    local r2ppml = e(r2_p)
                    foreach grp of local agrps {
                        gunique athr_id if e(sample) & `grp' == 1
                        local num_athrs = r(unique)
                        gunique inst_id if e(sample) & `grp' == 1
                        local num_insts = r(unique)
                        local b_post  = _b[Z_`grp']
                        local se_post = _se[Z_`grp']
                        di as text "pooled-DiD int PPML `samp'`suf' `yvar' `grp' `aspec': b=" %8.4f `b_post' ///
                            " (se=" %8.4f `se_post' ")   N=" %9.0f `Nppml' " PIs=`num_athrs' Insts=`num_insts'"
                        post `ph_handle' ("`yvar'") ("`grp'") ("mshrctrl") ("`aspec'") ///
                            (`b_post') (`se_post') (.) (.) (`Nppml') (`r2ppml')
                    }

                    local all_leads
                    local all_lags
                    local all_mshr
                    foreach grp of local agrps {
                        local all_leads `all_leads' `leads_`grp''
                        local all_lags  `all_lags'  `lags_`grp''
                        local all_mshr  `all_mshr'  `mleads_`grp'' `mlags_`grp''
                    }
                    local plot_suf "_ppml_`aspec'_mshrctrl"
                    cap noi ppmlhdfe `yvar' `all_leads' `all_lags' ///
                                            `all_mshr' `PTs', ///
                                            absorb(`fes') vce(cluster `vce_cl')
                    if _rc {
                        di as error "event_study_het `samp'`suf' `yvar' `aspec' joint ES for PDFs failed; skipping ES plots."
                    }
                    else {
                        foreach grp of local agrps {
                            local grp_label = "${LBL_`grp'}"
                            if "`grp_label'" == "" local grp_label "`grp'"
                            gunique athr_id if e(sample) & `grp' == 1
                            local num_athrs = r(unique)
                            gunique inst_id if e(sample) & `grp' == 1
                            local num_insts = r(unique)
                            sum `yvar' if rel <= -1 & e(sample) & `grp' == 1, d
                            local pre_mean : dis %4.3f r(mean)
                            preserve
                            cap mat drop es
                            foreach var in `leads_`grp'' `lags_`grp'' int_lead1_`grp' {
                                if "`var'" == "int_lead1_`grp'" {
                                    mat row = 0,0
                                }
                                else {
                                    mat row = _b[`var'], _se[`var']
                                }
                                mat es = nullmat(es) \ row
                            }
                            svmat es
                            keep es1 es2
                            drop if mi(es1)
                            rename (es1 es2) (b se)
                            gen ub = b + 1.96*se
                            gen lb = b - 1.96*se
                            local ymax = 1.2
                            local ymin = -2.2
                            local pgap 0.2
                            gen rel = -`abs_lead' if _n == 1
                            replace rel = rel[_n-1]+1 if _n > 1
                            replace rel = rel + 1 if rel >= -1
                            replace rel = -1 if rel == `abs_lag' + 1
                            gen year = rel + 2014
                            hashsort rel
                            local stats_leg `"legend(on order(- "Num. PIs: `num_athrs'" "Num. Insts: `num_insts'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(3) bmargin(zero) size(small))"'
                            local fdir ../output/figures/`samp'/es_ppml
                            foreach fmode of global FIG_MODES {
                                if "`fmode'" == "paper" {
                                    local stats_leg legend(off)
                                    local fdir ../output/figures/`samp'/es_ppml/paper
                                    cap mkdir "`fdir'"
                                }
                                tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
                                  scatter b year, mcolor(ebblue) || ///
                                scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                                  xlab(2010(1)2019, labsize(small)) xtitle("Year") ///
                                  ytitle("`ppml_ytit'") ysc(titlegap(-6) outergap(0)) ylab(`ymin'(`pgap')`ymax') ytick(`ymin'(0.2)`ymax') ///
                                  `stats_leg' ///
                                  yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
                                graph export `fdir'/es_`yvar'`suf'_`grp'`plot_suf'.pdf, replace
                            }
                            save ../temp/es_`yvar'`suf'_`grp'`plot_suf', replace
                            restore
                        }
                    }
                }
                }
            }

            local qmethods
            if "$HET_RUN_QUARTILES" == "1" local qmethods pw
            if "$HET_RUN_QUARTILES" == "1" & "$HET_INCLUDE_INSTWTD" == "1" local qmethods inst pw
            foreach qmethod of local qmethods {
            local quart_all
            if "`qmethod'" == "inst" {
                foreach pair of global IC_PAIRS_Q {
                    local quart_all `"`quart_all' `"`pair'"' "'
                }
                local st_tag "quart"
                local qplot_suf "_ppml_q_mshrctrl"
            }
            else {
                foreach pair of global IC_PAIRS_Q_PW {
                    local quart_all `"`quart_all' `"`pair'"' "'
                }
                local st_tag "quart_pi"
                local qplot_suf "_ppml_qpi_mshrctrl"
            }
            foreach pair of global PI_PAIRS_Q {
                local quart_all `"`quart_all' `"`pair'"' "'
            }
            foreach pair of local quart_all {
                local g1: word 1 of `pair'
                local g2: word 2 of `pair'
                if substr("`g1'", 1, 4) == "q4w_" {
                    local base = substr("`g1'", 5, .)
                    local gm "midw_`base'"
                }
                else {
                    local base = substr("`g1'", 4, .)
                    local gm "mid_`base'"
                }
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `g1' ") == 0 continue
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `g2' ") == 0 continue
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `gm' ") == 0 continue

                cap drop Z_`g1' Z_`g2' Z_`gm' S_`g1' S_`g2' S_`gm' PT_`g1' PT_`gm'
                gen Z_`g1' = Z_it       * `g1'
                gen Z_`g2' = Z_it       * `g2'
                gen Z_`gm' = Z_it       * `gm'
                gen S_`g1' = Z_share_it * `g1'
                gen S_`g2' = Z_share_it * `g2'
                gen S_`gm' = Z_share_it * `gm'
                gen PT_`g1' = post * `g1'
                gen PT_`gm' = post * `gm'
                cap noi ppmlhdfe `yvar' Z_`g1' Z_`g2' Z_`gm' S_`g1' S_`g2' S_`gm' PT_`g1' PT_`gm', ///
                                        absorb(`fes') vce(cluster `vce_cl')
                local rc = _rc
                if `rc' {
                    di as error "event_study_het `samp'`suf' `yvar' `g1'/`g2' `st_tag' pooled-DiD int ppml failed (rc=`rc'); skipping pair."
                    continue
                }
                local Nppml = e(N)
                local r2ppml = e(r2_p)
                foreach grp in `g1' `g2' {
                    gunique athr_id if e(sample) & `grp' == 1
                    local num_athrs = r(unique)
                    gunique inst_id if e(sample) & `grp' == 1
                    local num_insts = r(unique)
                    local b_post  = _b[Z_`grp']
                    local se_post = _se[Z_`grp']
                    di as text "pooled-DiD int PPML `samp'`suf' `yvar' `grp' `st_tag': b=" %8.4f `b_post' ///
                        " (se=" %8.4f `se_post' ")   N=" %9.0f `Nppml' " PIs=`num_athrs' Insts=`num_insts'"
                    post `ph_handle' ("`yvar'") ("`grp'") ("mshrctrl") ("`st_tag'") ///
                        (`b_post') (`se_post') (.) (.) (`Nppml') (`r2ppml')
                }

                local mshr_ctrls `mleads_`g1'' `mlags_`g1'' ///
                                 `mleads_`g2'' `mlags_`g2'' ///
                                 `mleads_`gm'' `mlags_`gm''
                local plot_suf "`qplot_suf'"
                cap noi ppmlhdfe `yvar' `leads_`g1'' `lags_`g1'' ///
                                        `leads_`g2'' `lags_`g2'' ///
                                        `leads_`gm'' `lags_`gm'' ///
                                        `mshr_ctrls' PT_`g1' PT_`gm', ///
                                        absorb(`fes') vce(cluster `vce_cl')
                if _rc {
                    di as error "event_study_het `samp'`suf' `yvar' `g1'/`g2' `st_tag' joint ES for PDFs failed; skipping ES plots."
                    continue
                }
                foreach grp in `g1' `g2' {
                    local grp_label = "${LBL_`grp'}"
                    if "`grp_label'" == "" local grp_label "`grp'"
                    gunique athr_id if e(sample) & `grp' == 1
                    local num_athrs = r(unique)
                    gunique inst_id if e(sample) & `grp' == 1
                    local num_insts = r(unique)
                    sum `yvar' if rel <= -1 & e(sample) & `grp' == 1, d
                    local pre_mean : dis %4.3f r(mean)
                    preserve
                    cap mat drop es
                    foreach var in `leads_`grp'' `lags_`grp'' int_lead1_`grp' {
                        if "`var'" == "int_lead1_`grp'" {
                            mat row = 0,0
                        }
                        else {
                            mat row = _b[`var'], _se[`var']
                        }
                        mat es = nullmat(es) \ row
                    }
                    svmat es
                    keep es1 es2
                    drop if mi(es1)
                    rename (es1 es2) (b se)
                    gen ub = b + 1.96*se
                    gen lb = b - 1.96*se
                    local ymax = 1.2
                    local ymin = -2.2
                    local pgap 0.2
                    gen rel = -`abs_lead' if _n == 1
                    replace rel = rel[_n-1]+1 if _n > 1
                    replace rel = rel + 1 if rel >= -1
                    replace rel = -1 if rel == `abs_lag' + 1
                    gen year = rel + 2014
                    hashsort rel
                    local stats_leg `"legend(on order(- "Num. PIs: `num_athrs'" "Num. Insts: `num_insts'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(3) bmargin(zero) size(small))"'
                    local fdir ../output/figures/`samp'/es_ppml
                    foreach fmode of global FIG_MODES {
                        if "`fmode'" == "paper" {
                            local stats_leg legend(off)
                            local fdir ../output/figures/`samp'/es_ppml/paper
                            cap mkdir "`fdir'"
                        }
                        tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
                          scatter b year, mcolor(ebblue) || ///
                        scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                          xlab(2010(1)2019, labsize(small)) xtitle("Year") ///
                          ytitle("`ppml_ytit'") ysc(titlegap(-6) outergap(0)) ylab(`ymin'(`pgap')`ymax') ytick(`ymin'(0.2)`ymax') ///
                          `stats_leg' ///
                          yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
                        graph export `fdir'/es_`yvar'`suf'_`grp'`plot_suf'.pdf, replace
                    }
                    save ../temp/es_`yvar'`suf'_`grp'`plot_suf', replace
                    restore
                }
            }
            }

            foreach a of global JOINT_AE_CHARS {
                cap confirm variable y_hi_`a'
                if _rc continue
                foreach grp in y_hi_`a' y_lo_`a' o_hi_`a' o_lo_`a' {
                    cap drop Z_`grp' S_`grp' PT_`grp'
                    gen Z_`grp' = Z_it       * `grp'
                    gen S_`grp' = Z_share_it * `grp'
                    gen PT_`grp' = post * `grp'
                }
                cap noi ppmlhdfe `yvar' Z_y_hi_`a' Z_y_lo_`a' Z_o_hi_`a' Z_o_lo_`a' ///
                                        S_y_hi_`a' S_y_lo_`a' S_o_hi_`a' S_o_lo_`a' ///
                                        PT_y_hi_`a' PT_y_lo_`a' PT_o_hi_`a', ///
                                        absorb(`fes') vce(cluster `vce_cl')
                if _rc {
                    di as error "event_study_het `samp'`suf' `yvar' joint-ae `a' ppml failed; skipping."
                    continue
                }
                local Nppml = e(N)
                local r2ppml = e(r2_p)
                foreach grp in y_hi_`a' y_lo_`a' o_hi_`a' o_lo_`a' {
                    gunique athr_id if e(sample) & `grp' == 1
                    local num_athrs = r(unique)
                    gunique inst_id if e(sample) & `grp' == 1
                    local num_insts = r(unique)
                    local b_post  = _b[Z_`grp']
                    local se_post = _se[Z_`grp']
                    di as text "joint-ae PPML `samp'`suf' `yvar' `grp': b=" %8.4f `b_post' ///
                        " (se=" %8.4f `se_post' ")   N=" %9.0f `Nppml' " PIs=`num_athrs' Insts=`num_insts'"
                    post `ph_handle' ("`yvar'") ("`grp'") ("mshrctrl") ("joint_ae") ///
                        (`b_post') (`se_post') (.) (.) (`Nppml') (`r2ppml')
                }
                foreach age in y o {
                    cap noi lincom Z_`age'_hi_`a' - Z_`age'_lo_`a'
                    if _rc continue
                    local b_diff  = r(estimate)
                    local se_diff = r(se)
                    local p_diff  = r(p)
                    di as text "joint-ae DIFF `samp'`suf' `yvar' `age'_`a': b=" %8.4f `b_diff' ///
                        " (se=" %8.4f `se_diff' ") p=" %6.4f `p_diff'
                    post `ph_handle' ("`yvar'") ("`age'_diff_`a'") ("mshrctrl") ("joint_ae_diff") ///
                        (`b_diff') (`se_diff') (`p_diff') (.) (`Nppml') (`r2ppml')
                }
                foreach hl in hi lo {
                    cap noi lincom Z_o_`hl'_`a' - Z_y_`hl'_`a'
                    if _rc continue
                    local b_gap  = r(estimate)
                    local se_gap = r(se)
                    local p_gap  = r(p)
                    di as text "joint-ae GAP `samp'`suf' `yvar' `hl'_`a' (late - early): b=" %8.4f `b_gap' ///
                        " (se=" %8.4f `se_gap' ") p=" %6.4f `p_gap'
                    post `ph_handle' ("`yvar'") ("`hl'_gap_`a'") ("mshrctrl") ("joint_ae_gap") ///
                        (`b_gap') (`se_gap') (`p_gap') (.) (`Nppml') (`r2ppml')
                }
            }

        }
        postclose `ph_handle'

        if strpos(" `ppml_het_skip' ", " `yvar' ") == 0 {
            cap noi ppml_pdid_het_binscatter, samp(`samp') r1r2(`r1r2') public(`public') r1_only(`r1_only') yvar(`yvar')
        }
        cap noi ppml_het_coefplot, samp(`samp') r1r2(`r1r2') public(`public') r1_only(`r1_only') yvar(`yvar')
    }

    preserve
    clear
    foreach yvar of local yvar_list {
        cap append using ../temp/phet_results_`samp'`suf'_`yvar'
    }
    save ../temp/phet_results_`samp'`suf', replace
    restore
end

program ppml_pdid_het_binscatter
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) yvar(string)]
    if "`yvar'" == "" local yvar ppr_cnt
    local fes athr_id year
    local vce_cl athr_id
    if "$FE_MODE" == "inst_cluster" {
        local fes inst_id cluster_30 year
        local vce_cl inst_id
    }
    if "$FE_MODE" == "inst_cluster_fldyr" {
        local fes inst_id i.cluster_30#i.year
        local vce_cl inst_id
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    cap mkdir "../output/figures/`samp'/ppml_pdid_het_bs"

    local bs_lbl "`yvar'"
    if "`yvar'" == "ppr_cnt"           local bs_lbl "Publications"
    if "`yvar'" == "cite_affl_wt"      local bs_lbl "Citation-Weighted Output"
    if "`yvar'" == "avg_num_coathrs"   local bs_lbl "Coauthors"
    if "`yvar'" == "n_grants"          local bs_lbl "Active NIH Research Grants"
    if "`yvar'" == "n_new_grants"      local bs_lbl "New NIH Research Grants"
    if "`yvar'" == "nih_total_cost"    local bs_lbl "NIH Award Dollars"
    if "`yvar'" == "n_middle_ppr"      local bs_lbl "Middle-Author Papers"
    if "`yvar'" == "ppr_cnt_nonsolo"   local bs_lbl "Publications (Excl. Solo)"

    local dummy_pairs `" "young old" "young_ns old_ns" "young_any old_any" "young_nih old_nih" "r1 r2" "pub_inst priv_inst" "high_pre_ppr low_pre_ppr" "high_nihg low_nihg" "high_nihd low_nihd" "new_lab est_lab" "big_msa small_msa" "yhigh_nihd ylow_nihd" "yq4_nihd yq1_nihd" ${IC_PAIRS_MED_PW} "'
    if "$HET_INCLUDE_INSTWTD" == "1" local dummy_pairs `" `dummy_pairs' ${IC_PAIRS_MED} "'

    preserve
        use ../temp/es_`samp'`suf', clear
        gen post       = year >= 2014
        gen Z_it       = exposure      * post
        gen Z_share_it = mkt_spend_shr * post

        foreach pair of local dummy_pairs {
            local g1 : word 1 of `pair'
            local g2 : word 2 of `pair'

            if strpos(" ${HET_GROUPS_ACTIVE} ", " `g1' ") == 0 continue
            if strpos(" ${HET_GROUPS_ACTIVE} ", " `g2' ") == 0 continue

            foreach v in Z_`g1' Z_`g2' S_`g1' S_`g2' PT_`g1' _mu _z_work _dvar _fwlw _y_r _Z_r {
                cap drop `v'
            }
            gen Z_`g1' = Z_it       * `g1'
            gen Z_`g2' = Z_it       * `g2'
            gen S_`g1' = Z_share_it * `g1'
            gen S_`g2' = Z_share_it * `g2'
            gen PT_`g1' = post * `g1'

            cap noi ppmlhdfe `yvar' Z_`g1' Z_`g2' S_`g1' S_`g2' PT_`g1', ///
                    absorb(`fes') vce(cluster `vce_cl') d(_dvar)
            local rc = _rc
            if `rc' {
                di as error "ppml_pdid_het_bs `samp'`suf' `yvar' `g1'/`g2' joint failed (rc=`rc'); skipping pair."
                continue
            }
            local b_`g1'  = _b[Z_`g1']
            local se_`g1' = _se[Z_`g1']
            local b_`g2'  = _b[Z_`g2']
            local se_`g2' = _se[Z_`g2']

            predict double _mu, mu
            gen double _z_work = ln(_mu) + (`yvar' - _mu)/_mu if !mi(_mu) & _mu > 0
            gen double _fwlw = _mu if !mi(_mu) & _mu > 0

            foreach grp in `g1' `g2' {
                local other = cond("`grp'" == "`g1'", "`g2'", "`g1'")

                foreach v in _y_r _Z_r {
                    cap drop `v'
                }
                cap noi qui reghdfe _z_work Z_`other' S_`g1' S_`g2' PT_`g1' if !mi(_fwlw) [pw=_fwlw], ///
                        absorb(`fes') residuals(_y_r)
                if _rc == 0 cap noi qui reghdfe Z_`grp' Z_`other' S_`g1' S_`g2' PT_`g1' if !mi(_fwlw) [pw=_fwlw], ///
                        absorb(`fes') residuals(_Z_r)
                if _rc {
                    di as error "ppml_pdid_het_bs FWL `grp' failed; skipping plot."
                    continue
                }
                gunique athr_id if `grp' == 1 & !mi(_y_r) & !mi(_Z_r)
                local n_pis = r(unique)
                gunique inst_id if `grp' == 1 & !mi(_y_r) & !mi(_Z_r)
                local n_insts = r(unique)
                local b_str  : dis %7.3f `b_`grp''
                local se_str : dis %7.3f `se_`grp''
                local bs_note `"note("Num. PIs: `n_pis'   Num. Insts: `n_insts'" "{&beta} = `b_str' (SE: `se_str')", size(small) pos(7) ring(1) justification(left))"'
                local fdir ../output/figures/`samp'/ppml_pdid_het_bs
                foreach fmode of global FIG_MODES {
                    if "`fmode'" == "paper" {
                        local bs_note `"note("{&beta} = `b_str' (SE: `se_str')", size(small) pos(7) ring(1) justification(left))"'
                        local fdir ../output/figures/`samp'/ppml_pdid_het_bs/paper
                        cap mkdir "`fdir'"
                    }
                    binscatter _y_r _Z_r [aw=_fwlw] if `grp' == 1 & !mi(_y_r) & !mi(_Z_r), n(30) ///
                        xtitle("Exposure x Post") ///
                        ytitle("{&Delta} Log Expected `bs_lbl'") ysc(titlegap(0) outergap(0)) ///
                        xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                        msymbol(O) mcolors(gs6) lcolors(ebblue) ///
                        `bs_note' ///
                        plotregion(margin(sides))
                    graph export ///
                        `fdir'/ppml_pdid_`yvar'_`grp'_mshrctrl`suf'.pdf, ///
                        replace
                }
            }
        }

        foreach aspec in age3 ageq4 {
            if "`aspec'" == "age3"  local agrps lab_lt10 lab_10_20 lab_20p
            if "`aspec'" == "ageq4" local agrps q1_labage q2_labage q3_labage q4_labage
            local aok 1
            foreach grp of local agrps {
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `grp' ") == 0 local aok 0
            }
            if `aok' {
            foreach v in _mu _z_work _dvar _fwlw _y_r _Z_r {
                cap drop `v'
            }
            local nb : word count `agrps'
            local abase : word `nb' of `agrps'
            local Zs
            local Ss
            local PTs
            foreach grp of local agrps {
                cap drop Z_`grp'
                cap drop S_`grp'
                cap drop PT_`grp'
                gen Z_`grp' = Z_it       * `grp'
                gen S_`grp' = Z_share_it * `grp'
                local Zs `Zs' Z_`grp'
                local Ss `Ss' S_`grp'
                if "`grp'" != "`abase'" {
                    gen PT_`grp' = post * `grp'
                    local PTs `PTs' PT_`grp'
                }
            }

            cap noi ppmlhdfe `yvar' `Zs' `Ss' `PTs', ///
                    absorb(`fes') vce(cluster `vce_cl') d(_dvar)
            local rc = _rc
            if `rc' {
                di as error "ppml_pdid_het_bs `samp'`suf' `yvar' `aspec' joint failed (rc=`rc'); skipping."
            }
            else {
                foreach grp of local agrps {
                    local b_`grp'  = _b[Z_`grp']
                    local se_`grp' = _se[Z_`grp']
                }

                predict double _mu, mu
                gen double _z_work = ln(_mu) + (`yvar' - _mu)/_mu if !mi(_mu) & _mu > 0
                gen double _fwlw = _mu if !mi(_mu) & _mu > 0

                foreach grp of local agrps {
                    local others
                    foreach o of local agrps {
                        if "`o'" != "`grp'" local others `others' Z_`o'
                    }
                    foreach v in _y_r _Z_r {
                        cap drop `v'
                    }
                    cap noi qui reghdfe _z_work `others' `Ss' `PTs' if !mi(_fwlw) [pw=_fwlw], ///
                            absorb(`fes') residuals(_y_r)
                    if _rc == 0 cap noi qui reghdfe Z_`grp' `others' `Ss' `PTs' if !mi(_fwlw) [pw=_fwlw], ///
                            absorb(`fes') residuals(_Z_r)
                    if _rc {
                        di as error "ppml_pdid_het_bs FWL `grp' failed; skipping plot."
                        continue
                    }
                    gunique athr_id if `grp' == 1 & !mi(_y_r) & !mi(_Z_r)
                    local n_pis = r(unique)
                    gunique inst_id if `grp' == 1 & !mi(_y_r) & !mi(_Z_r)
                    local n_insts = r(unique)
                    local b_str  : dis %7.3f `b_`grp''
                    local se_str : dis %7.3f `se_`grp''
                    local bs_note `"note("Num. PIs: `n_pis'   Num. Insts: `n_insts'" "{&beta} = `b_str' (SE: `se_str')", size(small) pos(7) ring(1) justification(left))"'
                    local fdir ../output/figures/`samp'/ppml_pdid_het_bs
                    foreach fmode of global FIG_MODES {
                        if "`fmode'" == "paper" {
                            local bs_note `"note("{&beta} = `b_str' (SE: `se_str')", size(small) pos(7) ring(1) justification(left))"'
                            local fdir ../output/figures/`samp'/ppml_pdid_het_bs/paper
                            cap mkdir "`fdir'"
                        }
                        binscatter _y_r _Z_r [aw=_fwlw] if `grp' == 1 & !mi(_y_r) & !mi(_Z_r), n(30) ///
                            xtitle("Exposure x Post") ///
                            ytitle("{&Delta} Log Expected `bs_lbl'") ysc(titlegap(0) outergap(0)) ///
                            xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                            msymbol(O) mcolors(gs6) lcolors(ebblue) ///
                            `bs_note' ///
                            plotregion(margin(sides))
                        graph export ///
                            `fdir'/ppml_pdid_`yvar'_`grp'_mshrctrl`suf'.pdf, ///
                            replace
                    }
                }
            }
            }
        }
    restore
end

program ppml_age_gradient
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local fes athr_id year
    local vce_cl athr_id
    if "$FE_MODE" == "inst_cluster" {
        local fes inst_id cluster_30 year
        local vce_cl inst_id
    }
    if "$FE_MODE" == "inst_cluster_fldyr" {
        local fes inst_id i.cluster_30#i.year
        local vce_cl inst_id
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    cap mkdir "../output/figures/`samp'"

    local yvar_list ppr_cnt cite_affl_wt
    if "$DEBUG_YVAR" != "" local yvar_list $DEBUG_YVAR
    local ppml_skip avg_position avg_team_size_last avg_team_size_notlast

    use ../temp/es_`samp'`suf', clear
    gen post       = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post

    local K = $HET_AGE_NBINS
    foreach agevar in age_2014 lab_age_2014 lab_age_ns_2014 {
    cap confirm variable `agevar'
    if _rc {
        di as error "ppml_age_gradient `samp'`suf': `agevar' not in panel -- skipped."
        continue
    }
    local gpfx agegrad
    local gtmp age_gradient
    local gxtit "Career Age in 2014"
    if "`agevar'" == "lab_age_2014" {
        local gpfx labgrad
        local gtmp lab_gradient
        local gxtit "Years Running Lab in 2014"
    }
    if "`agevar'" == "lab_age_ns_2014" {
        local gpfx labnsgrad
        local gtmp lab_ns_gradient
        local gxtit "Years Running Lab in 2014 (Excl. Solo Papers)"
    }
    cap drop agebin
    xtile _agebin_pi = `agevar' if athr_indicator == 1, n(`K')
    bys athr_id: egen agebin = max(_agebin_pi)
    drop _agebin_pi

    local zvars
    local svars
    local bins_used
    forval k = 1/`K' {
        qui count if agebin == `k' & athr_indicator == 1
        if r(N) == 0 {
            di as error "ppml_age_gradient `samp'`suf': age bin `k' empty -- skipped."
            continue
        }
        cap drop Z_a`k'
        cap drop S_a`k'
        gen Z_a`k' = Z_it       * (agebin == `k')
        gen S_a`k' = Z_share_it * (agebin == `k')
        local zvars `zvars' Z_a`k'
        local svars `svars' S_a`k'
        local bins_used `bins_used' `k'
    }
    local ptvars
    local nb : word count `bins_used'
    forval i = 1/`=`nb'-1' {
        local k : word `i' of `bins_used'
        cap drop PT_a`k'
        gen PT_a`k' = post * (agebin == `k')
        local ptvars `ptvars' PT_a`k'
    }

    foreach yvar of local yvar_list {
        if strpos(" `ppml_skip' ", " `yvar' ") > 0 {
            di as text "ppml_age_gradient: `yvar' not a count outcome -- skipped."
            continue
        }
        local ppml_ytit "Output-Cost Elasticity"
        if "`yvar'" == "n_grants"       local ppml_ytit "{&Delta} Log Expected Active NIH Research Grants"
        if "`yvar'" == "n_new_grants"   local ppml_ytit "{&Delta} Log Expected New NIH Research Grants"
        if "`yvar'" == "nih_total_cost" local ppml_ytit "{&Delta} Log Expected NIH Award Dollars"

        cap noi ppmlhdfe `yvar' `zvars' `svars' `ptvars' if !mi(agebin), ///
            absorb(`fes') vce(cluster `vce_cl')
        local rc = _rc
        if `rc' {
            di as error "ppml_age_gradient `samp'`suf' `yvar' failed (rc=`rc'); skipping."
            continue
        }
        gunique athr_id if e(sample)
        local n_pis = r(unique)
        gunique inst_id if e(sample)
        local n_insts = r(unique)
        cap mat drop AG
        foreach k of local bins_used {
            if _se[Z_a`k'] == 0 {
                di as error "ppml_age_gradient `samp'`suf' `yvar': Z_a`k' dropped/degenerate -- omitted from plot."
                continue
            }
            qui sum `agevar' if athr_indicator == 1 & agebin == `k'
            mat AG = nullmat(AG) \ (`k', r(mean), r(N), _b[Z_a`k'], _se[Z_a`k'])
        }
        preserve
        clear
        svmat AG
        rename (AG1 AG2 AG3 AG4 AG5) (bin age_mean n_pis b se)
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        save ../temp/`gtmp'_`samp'`suf'_`yvar', replace
        local stats_leg `"legend(on order(- "Num. PIs: `n_pis'" "Num. Insts: `n_insts'") pos(7) ring(1) rows(2) bmargin(zero) size(small))"'
        local fdir ../output/figures/`samp'
        foreach fmode of global FIG_MODES {
            if "`fmode'" == "paper" {
                local stats_leg legend(off)
                local fdir ../output/figures/`samp'/paper
                cap mkdir "`fdir'"
            }
            tw rcap ub lb age_mean, lcolor(ebblue%70) msize(vsmall) || ///
               scatter b age_mean, mcolor(ebblue) || ///
               lfit b age_mean [aw=1/(se*se)], lcolor(dkorange) lpattern(dash) ///
               xtitle("`gxtit'") ytitle("`ppml_ytit'") ysc(titlegap(-6) outergap(0)) ///
               yline(0, lcolor(gs10) lpattern(solid)) ///
               `stats_leg' ///
               plotregion(margin(sides))
            graph export `fdir'/`gpfx'_`yvar'`suf'_ppml_mshrctrl.pdf, replace
        }
        restore
    }
    }
end

program desc_exposure_by_age
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    cap mkdir "../output/figures/`samp'"

    use ../temp/es_`samp'`suf', clear
    cap confirm variable nih_pi
    if _rc gen byte nih_pi = .
    egen long inst_num = group(inst_id)
    gcollapse (firstnm) exposure young nih_pi inst_num, by(athr_id)
    drop if mi(young) | mi(exposure)

    local tag_all ""
    local tag_nih "_nih"
    local cond_all "1"
    local cond_nih "nih_pi == 1"
    foreach s in all nih {
        qui count if `cond_`s'' & young == 1
        local n_y = r(N)
        qui count if `cond_`s'' & young == 0
        local n_o = r(N)
        if `n_y' == 0 | `n_o' == 0 {
            di as error "desc_exposure_by_age `samp'`suf' [`s']: empty group -- SKIPPED."
            continue
        }
        qui sum exposure if `cond_`s'' & young == 1, d
        local mu_y = strtrim(string(r(mean), "%6.3f"))
        local md_y = strtrim(string(r(p50),  "%6.3f"))
        qui sum exposure if `cond_`s'' & young == 0, d
        local mu_o = strtrim(string(r(mean), "%6.3f"))
        local md_o = strtrim(string(r(p50),  "%6.3f"))
        di as text _n "desc_exposure_by_age `samp'`suf' [`s']: N young = `n_y' (mean=`mu_y' p50=`md_y'), N old = `n_o' (mean=`mu_o' p50=`md_o')"
        cap noi ksmirnov exposure if `cond_`s'', by(young)
        qui reg exposure young if `cond_`s'', vce(cluster inst_num)
        di as text "  young-old diff = " %8.4f _b[young] " (se " %8.4f _se[young] ")"

        qui sum exposure if `cond_`s'', d
        local xcap = r(p99)
        cap drop _kx _kd_y _kd_o _kd_c
        gen _kx = `xcap' * (_n - 1) / 199 if _n <= 200
        kdensity exposure if `cond_`s'' & young == 1 & exposure <= `xcap', at(_kx) gen(_kd_y) nograph
        kdensity exposure if `cond_`s'' & young == 0 & exposure <= `xcap', at(_kx) gen(_kd_o) nograph
        gen _kd_c = min(_kd_y, _kd_o)
        local leg_y "Early-Career (N=`n_y'): mean=`mu_y'"
        local leg_o "Late-Career (N=`n_o'): mean=`mu_o'"
        local kd_leg `"legend(order(3 "`leg_y'" 4 "`leg_o'") pos(2) ring(0) rows(2) size(small))"'
        local fdir ../output/figures/`samp'
        foreach fmode of global FIG_MODES {
            if "`fmode'" == "paper" {
                local kd_leg `"legend(order(3 "${LBL_young}" 4 "${LBL_old}") pos(2) ring(0) rows(2) size(small))"'
                local fdir ../output/figures/`samp'/paper
                cap mkdir "`fdir'"
            }
            tw (rarea _kd_c _kd_y _kx, color(ebblue*0.3) lwidth(none)) ///
               (rarea _kd_c _kd_o _kx, color(dkorange*0.3) lwidth(none)) ///
               (line _kd_y _kx, lcolor(ebblue) lwidth(medthick)) ///
               (line _kd_o _kx, lcolor(dkorange) lwidth(medthick)) ///
               , xtitle("Exposure Measure") ytitle("Density") ysc(titlegap(-6) outergap(0)) ///
                 `kd_leg' ///
                 plotregion(margin(sides))
            graph export `fdir'/desc_kd_exposure`tag_`s''`suf'.pdf, replace
        }
        cap drop _kx _kd_y _kd_o _kd_c
    }
end

program desc_pre_output_by_age
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    cap mkdir "../output/figures/`samp'"

    use ../temp/es_`samp'`suf', clear
    keep if year < 2014
    qui sum year
    local y0 = r(min)
    local y1 = r(max)

    local sum_src   ppr_cnt cite_affl_wt n_first_ppr n_last_ppr
    local sum_alias ppr_tot cite         first       last
    local mean_src   ppr_cnt
    local mean_alias ppr_yr
    local lbl_ppr_tot "Total Papers"
    local lbl_ppr_yr  "Papers per Year"
    local lbl_cite    "Affiliation-Weighted Citations"
    local lbl_first   "First-Authored Papers"
    local lbl_last    "Last-Authored Papers"
    local fmt_ppr_tot %6.1f
    local fmt_ppr_yr  %5.2f
    local fmt_cite    %8.1f
    local fmt_first   %6.1f
    local fmt_last    %6.1f

    local coll_sum
    local coll_mean
    local keep_alias
    foreach stat in sum mean {
        local nsrc : word count ``stat'_src'
        forvalues i = 1/`nsrc' {
            local src : word `i' of ``stat'_src'
            local a   : word `i' of ``stat'_alias'
            cap confirm variable `src'
            if _rc {
                di as error "desc_pre_output_by_age `samp'`suf': `src' not in panel -- `a' density SKIPPED."
                continue
            }
            local coll_`stat' `coll_`stat'' pre_`a'=`src'
            local keep_alias `keep_alias' `a'
        }
    }
    if "`keep_alias'" == "" {
        di as error "desc_pre_output_by_age `samp'`suf': no outcomes available -- nothing plotted."
        exit
    }
    local coll_sum_part = cond("`coll_sum'" == "", "", "(sum) `coll_sum'")
    local coll_mean_part = cond("`coll_mean'" == "", "", "(mean) `coll_mean'")

    egen long inst_num = group(inst_id)
    gcollapse `coll_sum_part' `coll_mean_part' (firstnm) young inst_num, by(athr_id)
    drop if mi(young)

    qui count if young == 1
    local n_y = r(N)
    qui count if young == 0
    local n_o = r(N)
    di as text _n "desc_pre_output_by_age `samp'`suf': pre-period = `y0'-`y1', N young = `n_y', N old = `n_o'"

    foreach a of local keep_alias {
        local f "`fmt_`a''"
        qui sum pre_`a' if young == 1, d
        local mu_y = strtrim(string(r(mean), "`f'"))
        local md_y = strtrim(string(r(p50),  "`f'"))
        qui sum pre_`a' if young == 0, d
        local mu_o = strtrim(string(r(mean), "`f'"))
        local md_o = strtrim(string(r(p50),  "`f'"))
        local leg_y "Early-Career (N=`n_y'): mean=`mu_y'"
        local leg_o "Late-Career (N=`n_o'): mean=`mu_o'"
        di as text "  `a': young mean=`mu_y' p50=`md_y' | old mean=`mu_o' p50=`md_o'"
        cap noi ksmirnov pre_`a', by(young)
        qui reg pre_`a' young, vce(cluster inst_num)
        di as text "  `a': young-old diff = " %8.3f _b[young] " (se " %8.3f _se[young] ")"

        gen double ln_pre_`a' = ln(1 + pre_`a')
        qui sum ln_pre_`a'
        cap drop _kx _kd_y _kd_o _kd_c
        gen _kx = r(min) + (r(max) - r(min)) * (_n - 1) / 199 if _n <= 200
        kdensity ln_pre_`a' if young == 1, at(_kx) gen(_kd_y) nograph
        kdensity ln_pre_`a' if young == 0, at(_kx) gen(_kd_o) nograph
        gen _kd_c = min(_kd_y, _kd_o)
        local kd_leg `"legend(order(3 "`leg_y'" 4 "`leg_o'") pos(2) ring(0) rows(2) size(small))"'
        local fdir ../output/figures/`samp'
        foreach fmode of global FIG_MODES {
            if "`fmode'" == "paper" {
                local kd_leg `"legend(order(3 "${LBL_young}" 4 "${LBL_old}") pos(2) ring(0) rows(2) size(small))"'
                local fdir ../output/figures/`samp'/paper
                cap mkdir "`fdir'"
            }
            tw (rarea _kd_c _kd_y _kx, color(ebblue*0.3) lwidth(none)) ///
               (rarea _kd_c _kd_o _kx, color(dkorange*0.3) lwidth(none)) ///
               (line _kd_y _kx, lcolor(ebblue) lwidth(medthick)) ///
               (line _kd_o _kx, lcolor(dkorange) lwidth(medthick)) ///
               , xtitle("ln(1 + Pre-Period `lbl_`a'', `y0'-`y1')") ytitle("Density") ysc(titlegap(-6) outergap(0)) ///
                 `kd_leg' ///
                 plotregion(margin(sides))
            graph export `fdir'/desc_kd_pre_`a'_ln`suf'.pdf, replace
        }

        qui sum pre_`a', d
        local xcap = r(p95)
        cap drop _kx _kd_y _kd_o _kd_c
        gen _kx = `xcap' * (_n - 1) / 199 if _n <= 200
        kdensity pre_`a' if young == 1 & pre_`a' <= `xcap', at(_kx) gen(_kd_y) nograph
        kdensity pre_`a' if young == 0 & pre_`a' <= `xcap', at(_kx) gen(_kd_o) nograph
        gen _kd_c = min(_kd_y, _kd_o)
        local kd_leg `"legend(order(3 "`leg_y'" 4 "`leg_o'") pos(2) ring(0) rows(2) size(small))"'
        local fdir ../output/figures/`samp'
        foreach fmode of global FIG_MODES {
            if "`fmode'" == "paper" {
                local kd_leg `"legend(order(3 "${LBL_young}" 4 "${LBL_old}") pos(2) ring(0) rows(2) size(small))"'
                local fdir ../output/figures/`samp'/paper
                cap mkdir "`fdir'"
            }
            tw (rarea _kd_c _kd_y _kx, color(ebblue*0.3) lwidth(none)) ///
               (rarea _kd_c _kd_o _kx, color(dkorange*0.3) lwidth(none)) ///
               (line _kd_y _kx, lcolor(ebblue) lwidth(medthick)) ///
               (line _kd_o _kx, lcolor(dkorange) lwidth(medthick)) ///
               , xtitle("Pre-Period `lbl_`a'', `y0'-`y1' (x capped at pooled p95)") ytitle("Density") ysc(titlegap(-6) outergap(0)) ///
                 `kd_leg' ///
                 plotregion(margin(sides))
            graph export `fdir'/desc_kd_pre_`a'_raw`suf'.pdf, replace
        }
        cap drop _kx _kd_y _kd_o _kd_c
    }

    save ../temp/desc_pre_output_`samp'`suf', replace
end

program horse_race_nih
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local fes athr_id year
    local vce_cl athr_id
    if "$FE_MODE" == "inst_cluster" {
        local fes inst_id cluster_30 year
        local vce_cl inst_id
    }
    if "$FE_MODE" == "inst_cluster_fldyr" {
        local fes inst_id i.cluster_30#i.year
        local vce_cl inst_id
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"

    cap confirm file "../temp/es_`samp'`suf'.dta"
    if _rc {
        di as error "horse_race_nih `samp'`suf': ../temp/es_`samp'`suf'.dta not found -- run add_het_splits first."
        exit
    }
    use ../temp/es_`samp'`suf', clear
    foreach v in young low_nihd nih_pi {
        cap confirm variable `v'
        if _rc {
            di as error "horse_race_nih `samp'`suf': `v' not in panel -- SKIPPED."
            exit
        }
    }
    keep if nih_pi == 1 & !mi(young) & !mi(low_nihd)
    foreach v in young low_nihd {
        qui sum `v'
        if r(N) == 0 | r(min) == r(max) {
            di as error "horse_race_nih `samp'`suf': `v' degenerate on the NIH-matched sample -- SKIPPED."
            exit
        }
    }

    gen post       = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post
    gen Z_early    = Z_it * young
    gen Z_lownih   = Z_it * low_nihd
    gen PT_early   = post * young
    gen PT_lownih  = post * low_nihd

    local yvar_list ppr_cnt cite_affl_wt
    if "$DEBUG_YVAR" != "" local yvar_list $DEBUG_YVAR
    local nyv : word count `yvar_list'

    mat hrace`suf' = J(22, `nyv', .)
    mat rownames hrace`suf' = b_z_base_career se_z_base_career b_z_early_alone se_z_early_alone ///
                              b_z_base_fund se_z_base_fund b_z_lownih_alone se_z_lownih_alone ///
                              b_z_base se_z_base b_z_early se_z_early b_z_lownih se_z_lownih ///
                              early_shift lownih_shift b_diff se_diff p_eq ///
                              N n_pis n_pis_early
    mat colnames hrace`suf' = `yvar_list'

    local col 0
    foreach yvar of local yvar_list {
        local ++col
        cap drop hr_samp
        cap noi ppmlhdfe `yvar' Z_it Z_early Z_lownih PT_early PT_lownih Z_share_it, ///
            absorb(`fes') vce(cluster `vce_cl')
        local rc = _rc
        if `rc' {
            di as error "horse_race_nih `samp'`suf' `yvar' joint spec failed (rc=`rc'); column left missing."
            continue
        }
        gen byte hr_samp = e(sample)
        local Nppml = e(N)
        local b_base     = _b[Z_it]
        local se_base    = _se[Z_it]
        local b_early    = _b[Z_early]
        local se_early   = _se[Z_early]
        local b_lownih   = _b[Z_lownih]
        local se_lownih  = _se[Z_lownih]
        qui lincom Z_early - Z_lownih
        local b_diff  = r(estimate)
        local se_diff = r(se)
        qui test Z_early = Z_lownih
        local p_eq = r(p)
        gunique athr_id if hr_samp
        local n_pis = r(unique)
        gunique athr_id if hr_samp & young == 1
        local n_early = r(unique)

        cap noi ppmlhdfe `yvar' Z_it Z_early PT_early Z_share_it if hr_samp, ///
            absorb(`fes') vce(cluster `vce_cl')
        local rc = _rc
        if `rc' {
            di as error "horse_race_nih `samp'`suf' `yvar' career-only spec failed (rc=`rc'); column left missing."
            continue
        }
        local b_base_c   = _b[Z_it]
        local se_base_c  = _se[Z_it]
        local b_early_a  = _b[Z_early]
        local se_early_a = _se[Z_early]

        cap noi ppmlhdfe `yvar' Z_it Z_lownih PT_lownih Z_share_it if hr_samp, ///
            absorb(`fes') vce(cluster `vce_cl')
        local rc = _rc
        if `rc' {
            di as error "horse_race_nih `samp'`suf' `yvar' funding-only spec failed (rc=`rc'); column left missing."
            continue
        }
        local b_base_f    = _b[Z_it]
        local se_base_f   = _se[Z_it]
        local b_lownih_a  = _b[Z_lownih]
        local se_lownih_a = _se[Z_lownih]

        mat hrace`suf'[1,`col']  = `b_base_c'
        mat hrace`suf'[2,`col']  = `se_base_c'
        mat hrace`suf'[3,`col']  = `b_early_a'
        mat hrace`suf'[4,`col']  = `se_early_a'
        mat hrace`suf'[5,`col']  = `b_base_f'
        mat hrace`suf'[6,`col']  = `se_base_f'
        mat hrace`suf'[7,`col']  = `b_lownih_a'
        mat hrace`suf'[8,`col']  = `se_lownih_a'
        mat hrace`suf'[9,`col']  = `b_base'
        mat hrace`suf'[10,`col'] = `se_base'
        mat hrace`suf'[11,`col'] = `b_early'
        mat hrace`suf'[12,`col'] = `se_early'
        mat hrace`suf'[13,`col'] = `b_lownih'
        mat hrace`suf'[14,`col'] = `se_lownih'
        mat hrace`suf'[15,`col'] = `b_early' - `b_early_a'
        mat hrace`suf'[16,`col'] = `b_lownih' - `b_lownih_a'
        mat hrace`suf'[17,`col'] = `b_diff'
        mat hrace`suf'[18,`col'] = `se_diff'
        mat hrace`suf'[19,`col'] = `p_eq'
        mat hrace`suf'[20,`col'] = `Nppml'
        mat hrace`suf'[21,`col'] = `n_pis'
        mat hrace`suf'[22,`col'] = `n_early'

        mat hrp_`yvar' = (`b_early_a', `se_early_a' \ `b_lownih_a', `se_lownih_a' \ ///
                          `b_early', `se_early' \ `b_lownih', `se_lownih')

        di as text "horse_race_nih `samp'`suf' `yvar' (NIH-matched sample, N = " %9.0f `Nppml' ", PIs = `n_pis', early = `n_early'):"
        di as text "  career only   : Z x Early     = " %9.4f `b_early_a'  "  (se " %7.4f `se_early_a' ")"
        di as text "  funding only  : Z x LowNIH    = " %9.4f `b_lownih_a' "  (se " %7.4f `se_lownih_a' ")"
        di as text "  horse race    : Z x Early     = " %9.4f `b_early'    "  (se " %7.4f `se_early' ")   shift = " %8.4f `=`b_early' - `b_early_a''
        di as text "                  Z x LowNIH    = " %9.4f `b_lownih'   "  (se " %7.4f `se_lownih' ")   shift = " %8.4f `=`b_lownih' - `b_lownih_a''
        di as text "  early - lownih (joint) = " %9.4f `b_diff' "  (se " %7.4f `se_diff' ")   p(equal) = " %6.4f `p_eq'
    }

    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'
    qui matrix_to_txt, saving("../output/tables/`samp'/horse_race_nih`suf'.txt") ///
        matrix(hrace`suf') title(<tab:horse_race_nih`suf'>) format(%20.4f) replace

    cap mkdir "../output/figures/`samp'/coefplot_evavg"
    clear
    foreach yvar of local yvar_list {
        cap confirm matrix hrp_`yvar'
        if _rc continue
        clear
        svmat double hrp_`yvar', names(col)
        rename (c1 c2) (b se)
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        gen byte career = inlist(_n, 1, 3)
        gen y = cond(_n == 1, 4.7, cond(_n == 2, 3.7, cond(_n == 3, 2, 1)))
        qui sum lb
        local xmin = floor(r(min)/0.5)*0.5
        qui sum ub
        local xmax = ceil(r(max)/0.5)*0.5
        local ylabs `"4.7 "Early-Career {&minus} Late-Career PIs" 3.7 "Below {&minus} Above Median NIH Funding" 2 "Early-Career {&minus} Late-Career PIs, Given Funding" 1 "Below {&minus} Above Median NIH, Given Career Stage""'
        tw rcap ub lb y if career == 1, horizontal lcolor(ebblue%70) msize(vsmall) || ///
           scatter y b if career == 1, mcolor(ebblue) msize(small) || ///
           rcap ub lb y if career == 0, horizontal lcolor(dkorange%70) msize(vsmall) || ///
           scatter y b if career == 0, mcolor(dkorange) msymbol(D) msize(small) ///
           , xline(0, lcolor(gs10) lpattern(solid)) ///
             yline(2.85, lcolor(gs12) lpattern(dash)) ///
             ylabel(`ylabs', angle(0) labsize(small) noticks nogrid) ///
             ytitle("") xtitle("Exposure x Post", size(small)) ///
             xlabel(`xmin'(0.5)`xmax', labsize(small)) ///
             legend(off) ///
             ysize(4) xsize(8) yscale(range(0.6 5.1)) ///
             plotregion(margin(l=zero r=zero b=zero t=vsmall))
        graph export "../output/figures/`samp'/coefplot_evavg/horse_race_nih_coefplot_`yvar'`suf'.pdf", replace
        di as text "wrote ../output/figures/`samp'/coefplot_evavg/horse_race_nih_coefplot_`yvar'`suf'.pdf"
    }
end

program output_het_tables
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'

    cap confirm file "../temp/phet_results_`samp'`suf'.dta"
    if !_rc {
        preserve
        use "../temp/phet_results_`samp'`suf'.dta", clear
        export delimited using "../output/tables/`samp'/phet_results`suf'.txt", replace delim(tab)
        restore
    }
end

program output_split_diff_tables
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    cap confirm file "../temp/phet_results_`samp'`suf'.dta"
    if _rc {
        di as error "output_split_diff_tables `samp'`suf': phet_results not found -- skipping."
        exit 0
    }
    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'

    local pairs `"${COEFPLOT_PI_PAIRS}"'
    foreach a of global IC_ALIASES {
        local pairs `"`pairs' "hiw_`a' low_`a'" "'
    }

    foreach yvar in ppr_cnt cite_affl_wt {
        preserve
        use "../temp/phet_results_`samp'`suf'.dta", clear
        keep if yvar == "`yvar'" & spec == "mshrctrl" & inlist(split_type, "med_pi", "med_pi_diff")
        cap mat drop sdiff
        local rows
        foreach pair of local pairs {
            local g1 : word 1 of `pair'
            local g2 : word 2 of `pair'
            qui count if grp == "`g1'_diff" & split_type == "med_pi_diff"
            if r(N) == 0 continue
            foreach g in `g1' `g2' {
                qui sum post_b  if grp == "`g'" & split_type == "med_pi"
                local b_`g'  = r(mean)
                qui sum post_se if grp == "`g'" & split_type == "med_pi"
                local se_`g' = r(mean)
            }
            qui sum post_b  if grp == "`g1'_diff" & split_type == "med_pi_diff"
            local b_diff = r(mean)
            qui sum post_se if grp == "`g1'_diff" & split_type == "med_pi_diff"
            local se_diff = r(mean)
            qui sum pre_b   if grp == "`g1'_diff" & split_type == "med_pi_diff"
            local p_diff = r(mean)
            qui sum N       if grp == "`g1'_diff" & split_type == "med_pi_diff"
            local Nfit = r(mean)
            mat sdiff = nullmat(sdiff) \ ///
                (`b_`g1'', `se_`g1'', `b_`g2'', `se_`g2'', `b_diff', `se_diff', `p_diff', `Nfit')
            local rows `rows' `g1'
        }
        restore
        if "`rows'" == "" continue
        mat colnames sdiff = b_g1 se_g1 b_g2 se_g2 b_diff se_diff p_diff N
        mat rownames sdiff = `rows'
        di as result _n "== split_diff `samp'`suf' `yvar': g1 - g2 off the joint VCE (rows = g1 of each coefplot pair) =="
        matlist sdiff, format(%9.4f) lines(oneline)
        qui matrix_to_txt, saving("../output/tables/`samp'/split_diff_`yvar'`suf'.txt") ///
            matrix(sdiff) title(<tab:split_diff_`yvar'`suf'>) format(%20.4f) replace
    }
end

program ppml_het_coefplot
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) yvar(string)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"

    if "`yvar'" != "" {
        local resfile "../temp/phet_results_`samp'`suf'_`yvar'.dta"
    }
    else {
        local resfile "../temp/phet_results_`samp'`suf'.dta"
    }
    cap confirm file "`resfile'"
    if _rc {
        di as error "ppml_het_coefplot: `resfile' not found -- skipping"
        exit 0
    }

    local ppml_het_yvars ppr_cnt ppr_cnt_nonsolo cite_affl_wt avg_num_coathrs ///
                        n_grants n_new_grants nih_total_cost ///
                        n_middle_ppr
    if "`yvar'" != "" local ppml_het_yvars `yvar'

    local ic_fund_aliases tfnd lsf
    local ic_expx_aliases endow
    if $HET_IC_FULL == 1 {
        local ic_fund_aliases contr fdlsb fdls fdlsh gntsf hhlsb hhls hhlsh nflsb nfls nflsh subrf busf fedf tfnd instf nonpf statf lsf hsf biof
        local ic_expx_aliases applx apfx basx bfx clinx devx lscx medx endow
    }

    local st_list med_pi joint_ae
    if "$HET_INCLUDE_INSTWTD" == "1" local st_list med `st_list'
    if "$HET_RUN_QUARTILES" == "1" {
        local st_list `st_list' quart_pi
        if "$HET_INCLUDE_INSTWTD" == "1" local st_list `st_list' quart
    }
    foreach st of local st_list {
        local groups_core
        local groups_core_any
        if strpos("`st'", "joint_") == 1 {
            local groups_pi
            local groups_ic_fund
            local groups_ic_expx
        }
        else if "`st'" == "med" {
            local groups_pi
            foreach pair of global COEFPLOT_PI_PAIRS {
                local groups_pi `groups_pi' `pair'
            }
            local groups_ic_fund
            foreach a of local ic_fund_aliases {
                local groups_ic_fund `groups_ic_fund' hi_`a' lo_`a'
            }
            local groups_ic_expx
            foreach a of local ic_expx_aliases {
                local groups_ic_expx `groups_ic_expx' hi_`a' lo_`a'
            }
            local groups_core young old hi_tfnd lo_tfnd hi_endow lo_endow
        }
        else if "`st'" == "med_pi" {
            local groups_pi
            foreach pair of global COEFPLOT_PI_PAIRS {
                local groups_pi `groups_pi' `pair'
            }
            local groups_ic_fund
            foreach a of local ic_fund_aliases {
                local groups_ic_fund `groups_ic_fund' hiw_`a' low_`a'
            }
            local groups_ic_expx
            foreach a of local ic_expx_aliases {
                local groups_ic_expx `groups_ic_expx' hiw_`a' low_`a'
            }
            local groups_core young old hiw_tfnd low_tfnd hiw_endow low_endow
            local groups_core_any young old young_any old_any hiw_tfnd low_tfnd hiw_endow low_endow
        }
        else if "`st'" == "quart" {
            local groups_pi
            foreach b of global PI_Q_BASES {
                local groups_pi `groups_pi' q4_`b' q1_`b'
            }
            local groups_ic_fund
            foreach a of local ic_fund_aliases {
                local groups_ic_fund `groups_ic_fund' q4_`a' q1_`a'
            }
            local groups_ic_expx
            foreach a of local ic_expx_aliases {
                local groups_ic_expx `groups_ic_expx' q4_`a' q1_`a'
            }
        }
        else {
            local groups_pi
            foreach b of global PI_Q_BASES {
                local groups_pi `groups_pi' q4_`b' q1_`b'
            }
            local groups_ic_fund
            foreach a of local ic_fund_aliases {
                local groups_ic_fund `groups_ic_fund' q4w_`a' q1w_`a'
            }
            local groups_ic_expx
            foreach a of local ic_expx_aliases {
                local groups_ic_expx `groups_ic_expx' q4w_`a' q1w_`a'
            }
        }

        foreach spec_tag in mshrctrl {
            local spec_folder = cond($HET_IC_FULL == 1, "coefplot_evavg_full", "coefplot_evavg")
            cap mkdir "../output/figures/`samp'/`spec_folder'"

        local groups_all `groups_pi' `groups_ic_fund' `groups_ic_expx'
        foreach panel in pi ic_fund ic_expx core core_any all {
            local groups `groups_`panel''
            local n_groups : word count `groups'
            if `n_groups' == 0 continue

            foreach yv of local ppml_het_yvars {
                preserve
                use "`resfile'", clear
                keep if yvar == "`yv'" & split_type == "`st'" & spec == "`spec_tag'"
                if _N == 0 {
                    restore
                    continue
                }

                local groups_present
                foreach g of local groups {
                    qui count if grp == "`g'" & !mi(post_b)
                    if r(N) > 0 local groups_present `groups_present' `g'
                }
                local groups `groups_present'
                local n_groups : word count `groups'
                if `n_groups' == 0 {
                    restore
                    continue
                }

                local within 0.6
                local between 1.25
                local npairs = ceil(`n_groups'/2)
                gen double y = .
                local ylabs ""
                local i = 0
                foreach g of local groups {
                    local ++i
                    local pair = int((`i'-1)/2)
                    local ypos = (`n_groups' - `i')*`within' + (`npairs' - 1 - `pair')*(`between' - `within') + 1
                    qui replace y = `ypos' if grp == "`g'"
                    local lbl = "${LBL_`g'}"
                    if "`lbl'" == "" local lbl "`g'"
                    if length("`lbl'") > 40 local lbl = substr("`lbl'", 1, 37) + "..."
                    local ylabs `"`ylabs' `ypos' "`lbl'""'
                }
                drop if mi(y) | mi(post_b)
                if _N == 0 {
                    restore
                    continue
                }
                gen ub = post_b + 1.96*post_se
                gen lb = post_b - 1.96*post_se

                qui sum lb
                local xmin = min(-2, floor(r(min)/0.5)*0.5)
                qui sum ub
                local xmax = max(1, ceil(r(max)/0.5)*0.5)
                local xstep 0.5

                local ysize = round(0.28 * ((`n_groups' - 1)*`within' + (`npairs' - 1)*(`between' - `within') + 1), 0.1)
                local ysize = max(2, min(14, `ysize'))
                local xsize 5
                local tscale = 4 / min(`ysize', `xsize')
                local sz_ylab  = cond(`n_groups' > 20, 2.0833, 2.777) * `tscale'
                local sz_xlab  = 2.777 * `tscale'
                local sz_xtit  = 2.777 * `tscale'
                local sz_mk    = 1.04166 * `tscale'
                local sz_cap   = 0.520833 * `tscale'

                gen byte hl = inlist(grp, "young", "old", "young_any", "old_any") & strpos("`panel'", "core") == 1
                local hl_plots
                qui count if hl == 1
                if r(N) > 0 {
                    local hl_plots `" || rcap ub lb y if hl == 1, horizontal lcolor(dkorange%70) msize(`sz_cap') || scatter y post_b if hl == 1, mcolor(dkorange) msize(`sz_mk')"'
                }

                tw rcap ub lb y if hl == 0, horizontal lcolor(ebblue%70) msize(`sz_cap') || ///
                   scatter y post_b if hl == 0, mcolor(ebblue) msize(`sz_mk') `hl_plots' ///
                   , xline(0, lcolor(gs10) lpattern(solid)) ///
                     ylabel(`ylabs', angle(0) labsize(`sz_ylab') noticks nogrid) ///
                     ytitle("") xtitle("Exposure x Post", size(`sz_xtit')) ///
                     xlabel(`xmin'(`xstep')`xmax', labsize(`sz_xlab')) ///
                     legend(off) ///
                     ysize(`ysize') xsize(`xsize') ///
                     yscale(range(0.9 .)) ///
                     plotregion(margin(l=zero r=zero b=zero t=vsmall))
                graph export ///
                    "../output/figures/`samp'/`spec_folder'/ppml_het_coefplot_`yv'_`st'_`panel'`suf'.pdf", ///
                    replace
                di as text "wrote ../output/figures/`samp'/`spec_folder'/ppml_het_coefplot_`yv'_`st'_`panel'`suf'.pdf"
                restore
            }
        }

        if "`st'" == "joint_ae" {
            local pfx_len   1
            local hi_pfx    y
            local lo_pfx    o
            local hi_leg    "Early-Career"
            local lo_leg    "Late-Career"
            local filename_stem joint_ae_paired
            local hilo_pos = `pfx_len' + 2
            local char_pos = `pfx_len' + 5
            foreach yv of local ppml_het_yvars {
                preserve
                use "`resfile'", clear
                keep if yvar == "`yv'" & split_type == "`st'" & spec == "`spec_tag'"
                if _N == 0 {
                    restore
                    continue
                }
                gen str2  pfx_c  = substr(grp, 1, `pfx_len')
                gen str2  hilo_c = substr(grp, `hilo_pos', 2)
                gen str12 char_c = substr(grp, `char_pos', .)
                gen byte  is_hi_side = (pfx_c == "`hi_pfx'")
                gen char_idx = .
                local ii = 0
                foreach a of global IC_ALIASES {
                    local ++ii
                    qui replace char_idx = `ii' if char_c == "`a'"
                }
                qui drop if mi(char_idx)
                if _N == 0 {
                    restore
                    continue
                }
                qui sum char_idx
                local nchars = r(max)
                gen double y_group = (`nchars' + 1 - char_idx) * 3.2
                gen double y_pos   = y_group ///
                    + cond(hilo_c == "hi" & is_hi_side == 1,  1.0, ///
                      cond(hilo_c == "hi" & is_hi_side == 0,  0.4, ///
                      cond(hilo_c == "lo" & is_hi_side == 1, -0.4, -1.0)))
                gen ub = post_b + 1.96*post_se
                gen lb = post_b - 1.96*post_se

                local ylabs
                forvalues i = 1/`nchars' {
                    qui levelsof char_c if char_idx == `i', local(cname) clean
                    local clbl = "${LBL_ic_`cname'}"
                    if "`clbl'" == "" local clbl "`cname'"
                    local base = (`nchars' + 1 - `i') * 3.2
                    local pos_hi = `base' + 1.0
                    local pos_lo = `base' - 0.4
                    local ylabs `"`ylabs' `pos_hi' "High `clbl'""'
                    local ylabs `"`ylabs' `pos_lo' "Low `clbl'""'
                }

                qui sum lb
                local xmin = floor(r(min)/0.5)*0.5
                qui sum ub
                local xmax = ceil(r(max)/0.5)*0.5

                tw rcap ub lb y_pos if is_hi_side == 1, horizontal lcolor(ebblue%70) msize(vsmall)   || ///
                   scatter y_pos post_b if is_hi_side == 1, mcolor(ebblue) msize(small)              || ///
                   rcap ub lb y_pos if is_hi_side == 0, horizontal lcolor(dkorange%70) msize(vsmall) || ///
                   scatter y_pos post_b if is_hi_side == 0, mcolor(dkorange) msymbol(D) msize(small) ///
                   , xline(0, lcolor(gs10) lpattern(solid)) ///
                     ylabel(`ylabs', angle(0) labsize(small) noticks nogrid) ///
                     ytitle("") xtitle("Exposure x Post", size(small)) ///
                     xlabel(`xmin'(0.5)`xmax', labsize(small)) ///
                     legend(order(2 "`hi_leg'" 4 "`lo_leg'") pos(6) ring(1) rows(1) span size(small)) ///
                     ysize(`=max(8, `nchars'*1.6)') xsize(9) ///
                     yscale(range(2.1 .)) ///
                     plotregion(margin(l=zero r=zero b=zero t=vsmall))
                graph export ///
                    "../output/figures/`samp'/`spec_folder'/ppml_het_coefplot_`yv'_`filename_stem'`suf'.pdf", ///
                    replace
                di as text "wrote `filename_stem' coefplot for `yv' `spec_tag'"
                restore
            }
            joint_ae_panel_coefplot, resfile("`resfile'") yvars(`ppml_het_yvars') samp(`samp') ///
                suf(`suf') spec_folder(`spec_folder') spec_tag(`spec_tag')
        }

        }
    }
end

program joint_ae_panel_coefplot
    syntax, resfile(string) yvars(string) samp(string) spec_folder(string) spec_tag(string) [suf(string)]
    foreach a of global JOINT_AE_CHARS {
        local clbl = "${LBL_ic_`a'}"
        if "`clbl'" == "" local clbl "`a'"
        foreach yv of local yvars {
            preserve
            use "`resfile'", clear
            keep if yvar == "`yv'" & spec == "`spec_tag'" & split_type == "joint_ae"
            keep if inlist(grp, "y_hi_`a'", "o_hi_`a'", "y_lo_`a'", "o_lo_`a'")
            qui count if split_type == "joint_ae" & !mi(post_b)
            if r(N) < 4 {
                restore
                continue
            }
            gen byte early = substr(grp, 1, 1) == "y"
            gen ub = post_b + 1.96*post_se
            gen lb = post_b - 1.96*post_se

            local within 0.6
            local between 1.25
            local rows hdr_hi y_hi_`a' o_hi_`a' hdr_lo y_lo_`a' o_lo_`a'
            local n_rows : word count `rows'
            gen double y = .
            local ylabs ""
            local i = 0
            foreach r of local rows {
                local ++i
                local blk = int((`i'-1)/3)
                local ypos = (`n_rows' - `i')*`within' + (1 - `blk')*(`between' - `within') + 1
                if "`r'" == "hdr_hi" local lbl "{bf:Above-median `clbl'}"
                else if "`r'" == "hdr_lo" local lbl "{bf:Below-median `clbl'}"
                else {
                    local lbl = cond(substr("`r'", 1, 1) == "y", "${LBL_young}", "${LBL_old}")
                    qui replace y = `ypos' if grp == "`r'"
                }
                local ylabs `"`ylabs' `ypos' "`lbl'""'
            }

            qui sum lb
            local xmin = min(-2, floor(r(min)/0.5)*0.5)
            qui sum ub
            local xmax = max(1, ceil(r(max)/0.5)*0.5)
            local xstep 0.5

            local ysize = round(0.28 * ((`n_rows' - 1)*`within' + (`between' - `within') + 1) + 0.3, 0.1)
            local xsize 5
            local tscale = 4 / min(`ysize', `xsize')
            local sz_ylab = 2.777 * `tscale'
            local sz_xlab = 2.777 * `tscale'
            local sz_xtit = 2.777 * `tscale'
            local sz_mk   = 1.04166 * `tscale'
            local sz_cap  = 0.520833 * `tscale'

            tw rcap ub lb y if early == 1, horizontal lcolor(ebblue%70) msize(`sz_cap') || ///
               scatter y post_b if early == 1, mcolor(ebblue) msize(`sz_mk') || ///
               rcap ub lb y if early == 0, horizontal lcolor(dkorange%70) msize(`sz_cap') || ///
               scatter y post_b if early == 0, mcolor(dkorange) msize(`sz_mk') ///
               , xline(0, lcolor(gs10) lpattern(solid)) ///
                 ylabel(`ylabs', angle(0) labsize(`sz_ylab') noticks nogrid) ///
                 ytitle("") xtitle("Exposure x Post", size(`sz_xtit')) ///
                 xlabel(`xmin'(`xstep')`xmax', labsize(`sz_xlab')) ///
                 legend(off) ///
                 ysize(`ysize') xsize(`xsize') ///
                 yscale(range(0.9 .)) ///
                 plotregion(margin(l=zero r=zero b=zero t=vsmall))
            graph export ///
                "../output/figures/`samp'/`spec_folder'/ppml_het_coefplot_`yv'_joint_ae_panel_`a'`suf'.pdf", ///
                replace
            di as text "wrote ../output/figures/`samp'/`spec_folder'/ppml_het_coefplot_`yv'_joint_ae_panel_`a'`suf'.pdf"
            restore
        }
    }
end

if "$HET_SKIP_MAIN" != "1" main
