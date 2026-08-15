set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17
set maxvar 20000

global EXPOSURE_VERSION "hc"
global EXPOSURE_FILTER  "_cf"
global FE_MODE "author"
global HET_RUN_OLS 0
global DEBUG_YVAR "ppr_cnt"
global HET_INCLUDE_INSTWTD 0
global HET_RUN_QUARTILES 0
global HET_IC_FULL 0
global HET_AGE_NBINS 10

program main
    gather_inst_chars
    define_group_labels
    local s all_jrnls
    cap mkdir "../output/figures/`s'"
    add_het_splits, samp(`s') r1r2(1) public(0)
    desc_pre_output_by_age, samp(`s') r1r2(1) public(0)
    event_study_het, samp(`s') r1r2(1) public(0)
    ppml_age_gradient, samp(`s') r1r2(1) public(0)
    output_het_tables, samp(`s') r1r2(1) public(0)

    add_het_splits, samp(all_jrnls) r1r2(1) public(1)
    desc_pre_output_by_age, samp(all_jrnls) r1r2(1) public(1)
    event_study_het, samp(all_jrnls) r1r2(1) public(1)
    ppml_age_gradient, samp(all_jrnls) r1r2(1) public(1)
    output_het_tables, samp(all_jrnls) r1r2(1) public(1)
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

* Reduced set: total R&D + total federal + institutional + life-sci + federal life-sci
* (funding); endowment + basic + applied (expenditures).
global IC_ALIASES tfnd lsf endow
if $HET_IC_FULL == 1 {
    global IC_ALIASES contr fdlsb fdls fdlsh gntsf hhlsb hhls hhlsh nflsb nfls nflsh subrf busf fedf tfnd instf nonpf statf lsf hsf biof applx apfx basx bfx clinx devx lscx medx endow
}
global PI_Q_BASES pre_ppr team nihg nihd

* Joint 2x2 axes for PI-split × inst-char paired coefplots. Each axis defines:
*   SRC   -- 0/1 PI-level dummy (1 = "hi" side of the axis)
*   HIPFX -- 2-char subgroup prefix for the "hi" side, used in dummy names
*   LOPFX -- 2-char subgroup prefix for the "lo" side
*   HILEG -- legend label for the "hi" side; LOLEG same for "lo" side
global PI_CHAR_ALIASES   prppr
global PI_CHAR_SRC_prppr   high_pre_ppr
global PI_CHAR_HIPFX_prppr hp
global PI_CHAR_LOPFX_prppr lp
global PI_CHAR_HILEG_prppr "High Baseline Productivity"
global PI_CHAR_LOLEG_prppr "Low Baseline Productivity"
global PI_CHAR_SRC_team    big_team
global PI_CHAR_HIPFX_team  bt
global PI_CHAR_LOPFX_team  sm
global PI_CHAR_HILEG_team  "Larger Team Size"
global PI_CHAR_LOLEG_team  "Smaller Team Size"

program define_group_labels
    global LBL_young        "Early-Career Scientists"
    global LBL_old          "Late-Career Scientists"
    global LBL_r1           "R1"
    global LBL_r2           "R2"
    global LBL_pub_inst     "Public"
    global LBL_priv_inst    "Private"
    global LBL_high_pre_ppr "More Productive at Baseline"
    global LBL_low_pre_ppr  "Less Productive at Baseline"
    global LBL_big_team     "Larger Team Size"
    global LBL_small_team   "Smaller Team Size"
    global LBL_high_nihg    "More NIH Grants at Baseline"
    global LBL_low_nihg     "Fewer NIH Grants at Baseline"
    global LBL_high_nihd    "More NIH Funding at Baseline"
    global LBL_low_nihd     "Less NIH Funding at Baseline"
    global LBL_young_nih    "Early-Career Scientists (NIH-Matched PIs)"
    global LBL_old_nih      "Late-Career Scientists (NIH-Matched PIs)"
    global LBL_yhigh_nihd   "Early-Career, More NIH (Young Median)"
    global LBL_ylow_nihd    "Early-Career, Less NIH (Young Median)"
    global LBL_yq4_nihd     "Early-Career, Q4 NIH (Young Quartiles)"
    global LBL_yq1_nihd     "Early-Career, Q1 NIH (Young Quartiles)"
    global LBL_big_net      "Larger Coauthor Network"
    global LBL_small_net    "Smaller Coauthor Network"
    global LBL_new_lab      "Newer Labs"
    global LBL_est_lab      "Established Labs"
    global LBL_crwd_inst    "More Same-Field PIs at Inst."
    global LBL_sprs_inst    "Fewer Same-Field PIs at Inst."
    global LBL_big_msa      "Larger MSAs"
    global LBL_small_msa    "Smaller MSAs"

    global LBL_q1_pre_ppr   "Q1 Baseline Productivity"
    global LBL_q4_pre_ppr   "Q4 Baseline Productivity"
    global LBL_q1_team      "Q1 Team Size"
    global LBL_q4_team      "Q4 Team Size"
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

    qui sum pre_ppr_cnt_sum if athr_indicator == 1, d
    local ppr_cut = r(p50)
    gen high_pre_ppr = pre_ppr_cnt_sum >= `ppr_cut' if !mi(pre_ppr_cnt_sum)
    gen low_pre_ppr  = pre_ppr_cnt_sum <  `ppr_cut' if !mi(pre_ppr_cnt_sum)

    qui sum age_2014 if athr_indicator == 1, d
    local age_med = r(p50)
    di as text "add_het_splits `samp'`suf' age_2014 median = `age_med'"
    gen young = age_2014 <  `age_med' if !mi(age_2014)
    gen old   = age_2014 >= `age_med' if !mi(age_2014)

    gen r1 = type == "r1" if !mi(type)
    gen r2 = type == "r2" if !mi(type)

    cap confirm variable public
    if !_rc {
        gen pub_inst  = public == 1 if !mi(public)
        gen priv_inst = public == 0 if !mi(public)
    }
    else di as error "add_het_splits `samp'`suf': public not in panel -- pub_inst/priv_inst SKIPPED (rerun reduced_form/restrict_samp to add it)."

    cap confirm variable avg_team_size_last
    if !_rc {
        gen pre_team_yr = avg_team_size_last if year < 2014
        bys athr_id: egen pre_team_avg = mean(pre_team_yr)
        drop pre_team_yr
        qui sum pre_team_avg if athr_indicator == 1, d
        local team_med = r(p50)
        di as text "add_het_splits `samp'`suf' pre-team median = `team_med'"
        gen big_team   = pre_team_avg >= `team_med' if !mi(pre_team_avg)
        gen small_team = pre_team_avg <  `team_med' if !mi(pre_team_avg)
    }
    else di as error "add_het_splits `samp'`suf': avg_team_size_last not in panel -- team split SKIPPED."

    * Baseline NIH scale: pre-2014 means of the derived author-year measures
    * (n_grants, nih_total_cost from derived/nih/match_pi_athr). Both are missing
    * for PIs excluded upstream, so the NIH splits estimate on the NIH sample.
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

    * Young-only NIH funding split: pre_nihd median re-cut WITHIN young
    * NIH-matched PIs. Dummies stay missing for old PIs, so every fit using
    * the pair estimates on the young sample only.
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
        * Q1-vs-Q4 tails of the same young-only distribution; middle 50%
        * left missing so pair fits compare tails only.
        gen byte yq4_nihd = pre_nihd >= `ynih_p75' if !mi(pre_nihd) & young == 1 ///
                            & (pre_nihd >= `ynih_p75' | pre_nihd <= `ynih_p25')
        gen byte yq1_nihd = 1 - yq4_nihd
    }

    * Age split restricted to PIs matched to RePORTER (n_grants non-missing).
    * Dummies stay missing off the NIH sample, so every fit using them drops
    * unmatched PIs rather than pooling them into the base category.
    * nih_matched comes from reduced_form (RePORTER PI-name match). Fall back to
    * an n_grants-based proxy only if the panel predates it.
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

    cap confirm variable avg_num_coathrs
    if !_rc {
        gen pre_coauth_yr = avg_num_coathrs if year < 2014
        bys athr_id: egen pre_coauth_avg = mean(pre_coauth_yr)
        drop pre_coauth_yr
    }

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
        * Inst-weighted cutoffs (each institution counts once).
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
        * PI-weighted cutoffs (each PI counts once; big institutions dominate).
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

    local pi_q_source pre_ppr_cnt_sum pre_team_avg pre_nihg pre_nihd
    local pi_q_alias  pre_ppr        team         nihg     nihd
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

    * Joint young x hiw_<char> 2x2 for every ic char (PI-weighted median cutoff).
    foreach a of global IC_ALIASES {
        cap confirm variable hiw_`a'
        if _rc continue
        gen byte y_hi_`a' = (young == 1 & hiw_`a' == 1) if !mi(young) & !mi(hiw_`a')
        gen byte y_lo_`a' = (young == 1 & hiw_`a' == 0) if !mi(young) & !mi(hiw_`a')
        gen byte o_hi_`a' = (young == 0 & hiw_`a' == 1) if !mi(young) & !mi(hiw_`a')
        gen byte o_lo_`a' = (young == 0 & hiw_`a' == 0) if !mi(young) & !mi(hiw_`a')
    }

    * Joint age x baseline-productivity 2x2 (no inst char). Four subgroups.
    cap confirm variable high_pre_ppr
    if !_rc {
        gen byte y_hp = (young == 1 & high_pre_ppr == 1) if !mi(young) & !mi(high_pre_ppr)
        gen byte y_lp = (young == 1 & high_pre_ppr == 0) if !mi(young) & !mi(high_pre_ppr)
        gen byte o_hp = (young == 0 & high_pre_ppr == 1) if !mi(young) & !mi(high_pre_ppr)
        gen byte o_lp = (young == 0 & high_pre_ppr == 0) if !mi(young) & !mi(high_pre_ppr)
    }

    * Joint age x baseline-NIH-funding 2x2. Cells missing off the NIH-matched
    * sample, so fits using them drop unmatched PIs rather than pooling them
    * into the base category.
    cap confirm variable high_nihd
    if !_rc {
        gen byte y_hn = (young == 1 & high_nihd == 1) if !mi(young) & !mi(high_nihd)
        gen byte y_ln = (young == 1 & high_nihd == 0) if !mi(young) & !mi(high_nihd)
        gen byte o_hn = (young == 0 & high_nihd == 1) if !mi(young) & !mi(high_nihd)
        gen byte o_ln = (young == 0 & high_nihd == 0) if !mi(young) & !mi(high_nihd)
    }

    * Joint baseline-productivity x baseline-NIH-funding 2x2 (NIH-matched
    * sample, same missingness logic as the age x nihd cells).
    cap confirm variable high_pre_ppr
    local rc_pr = _rc
    cap confirm variable high_nihd
    if !`rc_pr' & !_rc {
        gen byte hp_hn = (high_pre_ppr == 1 & high_nihd == 1) if !mi(high_pre_ppr) & !mi(high_nihd)
        gen byte hp_ln = (high_pre_ppr == 1 & high_nihd == 0) if !mi(high_pre_ppr) & !mi(high_nihd)
        gen byte lp_hn = (high_pre_ppr == 0 & high_nihd == 1) if !mi(high_pre_ppr) & !mi(high_nihd)
        gen byte lp_ln = (high_pre_ppr == 0 & high_nihd == 0) if !mi(high_pre_ppr) & !mi(high_nihd)
    }

    * Team-size 2x2 cells: x age, x baseline NIH funding, x baseline
    * productivity.
    cap confirm variable big_team
    if !_rc {
        gen byte y_bt = (young == 1 & big_team == 1) if !mi(young) & !mi(big_team)
        gen byte y_sm = (young == 1 & big_team == 0) if !mi(young) & !mi(big_team)
        gen byte o_bt = (young == 0 & big_team == 1) if !mi(young) & !mi(big_team)
        gen byte o_sm = (young == 0 & big_team == 0) if !mi(young) & !mi(big_team)
        cap confirm variable high_nihd
        if !_rc {
            gen byte bt_hn = (big_team == 1 & high_nihd == 1) if !mi(big_team) & !mi(high_nihd)
            gen byte bt_ln = (big_team == 1 & high_nihd == 0) if !mi(big_team) & !mi(high_nihd)
            gen byte sm_hn = (big_team == 0 & high_nihd == 1) if !mi(big_team) & !mi(high_nihd)
            gen byte sm_ln = (big_team == 0 & high_nihd == 0) if !mi(big_team) & !mi(high_nihd)
        }
        cap confirm variable high_pre_ppr
        if !_rc {
            gen byte bt_hp = (big_team == 1 & high_pre_ppr == 1) if !mi(big_team) & !mi(high_pre_ppr)
            gen byte bt_lp = (big_team == 1 & high_pre_ppr == 0) if !mi(big_team) & !mi(high_pre_ppr)
            gen byte sm_hp = (big_team == 0 & high_pre_ppr == 1) if !mi(big_team) & !mi(high_pre_ppr)
            gen byte sm_lp = (big_team == 0 & high_pre_ppr == 0) if !mi(big_team) & !mi(high_pre_ppr)
        }
    }

    * Non-funding mechanism splits for the young result.
    * (1) Pre-2014 unique-coauthor network (n_coauthors_yr is distinct
    * coauthors per year, self-excluded) -- access to equipment through
    * collaborators.
    cap confirm variable n_coauthors_yr
    if !_rc {
        gen pre_net_yr = n_coauthors_yr if year < 2014
        bys athr_id: egen pre_net_avg = mean(pre_net_yr)
        drop pre_net_yr
        qui sum pre_net_avg if athr_indicator == 1, d
        local net_med = r(p50)
        di as text "add_het_splits `samp'`suf' pre-net median = `net_med'"
        gen byte big_net   = pre_net_avg >= `net_med' if !mi(pre_net_avg)
        gen byte small_net = pre_net_avg <  `net_med' if !mi(pre_net_avg)
    }
    * (2) Lab age: years since first last-authored paper (min_year), distinct
    * from career age (min_year_any, which age_2014 is built on) -- lab
    * capital vintage: recently-started labs have not accumulated equipment.
    cap confirm variable min_year
    if !_rc {
        gen lab_age_2014 = 2014 - min_year
        qui sum lab_age_2014 if athr_indicator == 1, d
        local lab_med = r(p50)
        di as text "add_het_splits `samp'`suf' lab_age median = `lab_med'"
        gen byte new_lab = lab_age_2014 <  `lab_med' if !mi(lab_age_2014)
        gen byte est_lab = lab_age_2014 >= `lab_med' if !mi(lab_age_2014)
    }
    * (3) Same-field PIs at the institution (sample roster, inst x cluster) --
    * shared cores / borrowable equipment down the hall.
    cap confirm variable cluster_30
    if !_rc {
        bys inst_id cluster_30 athr_id: gen byte _fld_tag = _n == 1
        bys inst_id cluster_30: egen fld_pis = total(_fld_tag)
        drop _fld_tag
        qui sum fld_pis if athr_indicator == 1, d
        local fld_med = r(p50)
        di as text "add_het_splits `samp'`suf' fld_pis median = `fld_med'"
        gen byte crwd_inst = fld_pis >= `fld_med' if !mi(fld_pis)
        gen byte sprs_inst = fld_pis <  `fld_med' if !mi(fld_pis)
    }
    * (4) MSA size -- thick local equipment / core-facility market. NOTE
    * msa_size_at is missing for ~27% of PIs (no 2014 MSA row).
    cap confirm variable msa_size_at
    if !_rc {
        qui sum msa_size_at if athr_indicator == 1, d
        local msa_med = r(p50)
        gen byte big_msa   = msa_size_at >= `msa_med' if !mi(msa_size_at)
        gen byte small_msa = msa_size_at <  `msa_med' if !mi(msa_size_at)
    }
    * Age x mechanism cells.
    cap confirm variable big_net
    if !_rc {
        gen byte y_bn = (young == 1 & big_net == 1) if !mi(young) & !mi(big_net)
        gen byte y_sn = (young == 1 & big_net == 0) if !mi(young) & !mi(big_net)
        gen byte o_bn = (young == 0 & big_net == 1) if !mi(young) & !mi(big_net)
        gen byte o_sn = (young == 0 & big_net == 0) if !mi(young) & !mi(big_net)
    }
    cap confirm variable new_lab
    if !_rc {
        gen byte y_nl = (young == 1 & new_lab == 1) if !mi(young) & !mi(new_lab)
        gen byte y_el = (young == 1 & new_lab == 0) if !mi(young) & !mi(new_lab)
        gen byte o_nl = (young == 0 & new_lab == 1) if !mi(young) & !mi(new_lab)
        gen byte o_el = (young == 0 & new_lab == 0) if !mi(young) & !mi(new_lab)
    }
    cap confirm variable crwd_inst
    if !_rc {
        gen byte y_ci = (young == 1 & crwd_inst == 1) if !mi(young) & !mi(crwd_inst)
        gen byte y_si = (young == 1 & crwd_inst == 0) if !mi(young) & !mi(crwd_inst)
        gen byte o_ci = (young == 0 & crwd_inst == 1) if !mi(young) & !mi(crwd_inst)
        gen byte o_si = (young == 0 & crwd_inst == 0) if !mi(young) & !mi(crwd_inst)
    }
    cap confirm variable big_msa
    if !_rc {
        gen byte y_bmsa = (young == 1 & big_msa == 1) if !mi(young) & !mi(big_msa)
        gen byte y_smsa = (young == 1 & big_msa == 0) if !mi(young) & !mi(big_msa)
        gen byte o_bmsa = (young == 0 & big_msa == 1) if !mi(young) & !mi(big_msa)
        gen byte o_smsa = (young == 0 & big_msa == 0) if !mi(young) & !mi(big_msa)
    }

    * Joint PI-split x inst-char 2x2. For each axis (baseline productivity,
    * coauthors), build 4 subgroup dummies per inst char keyed on the PI split
    * and the PI-wtd inst-char hi/lo indicator.
    foreach axis of global PI_CHAR_ALIASES {
        local src "${PI_CHAR_SRC_`axis'}"
        local hp  "${PI_CHAR_HIPFX_`axis'}"
        local lp  "${PI_CHAR_LOPFX_`axis'}"
        cap confirm variable `src'
        if _rc continue
        foreach a of global IC_ALIASES {
            cap confirm variable hiw_`a'
            if _rc continue
            gen byte `hp'_hi_`a' = (`src' == 1 & hiw_`a' == 1) if !mi(`src') & !mi(hiw_`a')
            gen byte `hp'_lo_`a' = (`src' == 1 & hiw_`a' == 0) if !mi(`src') & !mi(hiw_`a')
            gen byte `lp'_hi_`a' = (`src' == 0 & hiw_`a' == 1) if !mi(`src') & !mi(hiw_`a')
            gen byte `lp'_lo_`a' = (`src' == 0 & hiw_`a' == 0) if !mi(`src') & !mi(hiw_`a')
        }
    }

    compress
    save ../temp/es_`samp'`suf', replace
end

program event_study_het
    * Split-interaction PPML het regressions (+ OLS if HET_RUN_OLS=1).
    * Writes ../temp/phet_results_<samp><suf>.dta.
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
    * [H8] only the observed window; unused time dummies removed
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

    * Skip dummies that are missing or degenerate (all 0 / all 1) so
    * downstream loops don't try to fit collinear specs.
    local het_groups young old r1 r2 pub_inst priv_inst high_pre_ppr low_pre_ppr ///
                     big_team small_team high_nihg low_nihg high_nihd low_nihd ///
                     young_nih old_nih big_net small_net new_lab est_lab ///
                     crwd_inst sprs_inst big_msa small_msa yhigh_nihd ylow_nihd ///
                     yq4_nihd yq1_nihd
    * Only groups the active config actually fits get lead/lag interactions.
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

    * Pooled DiD building blocks (used by the coefplot-feeding fits below).
    cap drop post Z_it Z_share_it
    gen post       = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post

    local pi_pairs `" "young old" "young_nih old_nih" "r1 r2" "pub_inst priv_inst" "high_pre_ppr low_pre_ppr" "big_team small_team" "high_nihg low_nihg" "high_nihd low_nihd" "big_net small_net" "new_lab est_lab" "crwd_inst sprs_inst" "big_msa small_msa" "yhigh_nihd ylow_nihd" "yq4_nihd yq1_nihd" "'
    global DUMMY_PAIRS_MED    `" `pi_pairs' ${IC_PAIRS_MED} "'
    * PI-level splits included in both med and med_pi so PI-char coefplots
    * still emit when HET_INCLUDE_INSTWTD=0 (only PI-weighted median runs).
    global DUMMY_PAIRS_MED_PW `" `pi_pairs' ${IC_PAIRS_MED_PW} "'

    * Skip PPML on avg_* outcomes (conditional means, not counts).
    local ppml_het_skip avg_position avg_team_size_last avg_team_size_notlast

    mat drop _all
    * Write per-yvar phet_results files (postfile has no append option); combine into
    * master ../temp/phet_results_<samp><suf>.dta after the loop.
    local yvar_list ppr_cnt cite_affl_wt avg_num_coathrs ///
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

        * ---- OLS median het (gated by $HET_RUN_OLS, headline outcomes only)
        * leads_g1/lags_g1 are the differential vs the dummy=0 (`g2') group
        * absorbed by un-interacted int_lead/int_lag.
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
                tw rcap ub lb year if year != 2013 , lcolor(ebblue%70) msize(vsmall) || ///
                  scatter b year, mcolor(ebblue) || ///
                scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                  xlab(2010(1)2019, labsize(small)) xtitle("Year") ///
                  ytitle("Exposure x Post") ylab(`ymin'(`gap')`ymax') ///
                  subtitle("`g1_label'", pos(11) size(small)) ///
                  legend(on order(- "Num. PIs: `num_athrs'" "Num. Insts: `num_insts'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(3) bmargin(zero) size(small)) ///
                  yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
                graph export ../output/figures/`samp'/es_`yvar'`suf'_`g1'`plot_suf'.pdf, replace
                save ../temp/es_`yvar'`suf'_`g1'`plot_suf', replace
                restore
            }

        }

        * ---- PPML heterogeneity ----
        * Posts "mshrctrl": joint pooled DiD with fully-interacted Z_it and Z_share_it
        * on the full sample. grp coefficient = _b[Z_grp]; matches ppml_pdid_het_binscatter.
        if strpos(" `ppml_het_skip' ", " `yvar' ") == 0 {
            cap mkdir "../output/figures/`samp'/es_ppml"
            * ---- PPML median split (inst-weighted + PI-weighted variants) ----
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

                * --- Pooled-DiD PPML with fully-interacted Z and share; posted as "mshrctrl" ---
                * [H11] PT_`g1' absorbs the group-level post shift; `g2' x post is the base
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

                * --- Joint event-study PPML for per-group ES PDFs only (not posted) ---
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
                    gen ub = b + 1.96*se
                    sum ub, d
                    local ymax = round(r(max), 0.1)
                    gen lb = b - 1.96*se
                    sum lb, d
                    local ymin = round(r(min), 0.1)
                    if `ymin' > 0 local ymin = 0
                    gen rel = -`abs_lead' if _n == 1
                    replace rel = rel[_n-1]+1 if _n > 1
                    replace rel = rel + 1 if rel >= -1
                    replace rel = -1 if rel == `abs_lag' + 1
                    gen year = rel + 2014
                    hashsort rel
                    tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
                      scatter b year, mcolor(ebblue) || ///
                    scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                      xlab(2010(1)2019, labsize(small)) xtitle("Year") ///
                      ytitle("`ppml_ytit'") ylab(`ymin'(0.1)`ymax') ///
                      subtitle("`grp_label'", pos(11) size(small)) ///
                      legend(on order(- "Num. PIs: `num_athrs'" "Num. Insts: `num_insts'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(3) bmargin(zero) size(small)) ///
                      yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
                    graph export ../output/figures/`samp'/es_ppml/es_`yvar'`suf'_`grp'`plot_suf'.pdf, replace
                    save ../temp/es_`yvar'`suf'_`grp'`plot_suf', replace
                    restore
                }
            }
            }  // close foreach mmethod

            * ---- PPML quartile split (inst-weighted + PI-weighted variants) ----
            * Gated by HET_RUN_QUARTILES; off by default per user request.
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
            * PI-continuous quartiles run under BOTH methods (same dummies
            * either way) so quart and quart_pi coefplots each fill their
            * pi panel — mirrors pi_pairs in DUMMY_PAIRS_MED / _MED_PW.
            foreach pair of global PI_PAIRS_Q {
                local quart_all `"`quart_all' `"`pair'"' "'
            }
            foreach pair of local quart_all {
                local g1: word 1 of `pair'
                local g2: word 2 of `pair'
                * mid-group name: q4w_<char> -> midw_<char>; q4_<base> -> mid_<base>
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

                * --- Pooled-DiD PPML with fully-interacted Z and share (Q4/Mid/Q1); posted as "mshrctrl" ---
                * [H11] Q1 x post is the omitted base
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

                * --- Joint event-study PPML for per-group ES PDFs only (not posted) ---
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
                    sum ub, d
                    local ymax = round(r(max), 0.1)
                    gen lb = b - 1.96*se
                    sum lb, d
                    local ymin = round(r(min), 0.1)
                    if `ymin' > 0 local ymin = 0
                    gen rel = -`abs_lead' if _n == 1
                    replace rel = rel[_n-1]+1 if _n > 1
                    replace rel = rel + 1 if rel >= -1
                    replace rel = -1 if rel == `abs_lag' + 1
                    gen year = rel + 2014
                    hashsort rel
                    tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
                      scatter b year, mcolor(ebblue) || ///
                    scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                      xlab(2010(1)2019, labsize(small)) xtitle("Year") ///
                      ytitle("`ppml_ytit'") ylab(`ymin'(0.1)`ymax') ///
                      subtitle("`grp_label'", pos(11) size(small)) ///
                      legend(on order(- "Num. PIs: `num_athrs'" "Num. Insts: `num_insts'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(3) bmargin(zero) size(small)) ///
                      yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
                    graph export ../output/figures/`samp'/es_ppml/es_`yvar'`suf'_`grp'`plot_suf'.pdf, replace
                    save ../temp/es_`yvar'`suf'_`grp'`plot_suf', replace
                    restore
                }
            }
            }  // close foreach qmethod

            * ---- PPML young x hiw_<char> joint 2x2 for every ic char.
            * One pooled-DiD interaction fit per char; posts 4 rows per char.
            foreach a of global IC_ALIASES {
                cap confirm variable y_hi_`a'
                if _rc continue
                foreach grp in y_hi_`a' y_lo_`a' o_hi_`a' o_lo_`a' {
                    cap drop Z_`grp' S_`grp' PT_`grp'
                    gen Z_`grp' = Z_it       * `grp'
                    gen S_`grp' = Z_share_it * `grp'
                    gen PT_`grp' = post * `grp'
                }
                * [H11] o_lo x post is the omitted base (the four PTs sum to post)
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
                * Hi-vs-Lo differential per age; SEs via lincom use full VCE.
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
            }

            * ---- PPML joint 2x2 for each PI-split axis (baseline productivity,
            * coauthors) crossed with each inst char. One fit per (axis, char).
            foreach axis of global PI_CHAR_ALIASES {
                local hp "${PI_CHAR_HIPFX_`axis'}"
                local lp "${PI_CHAR_LOPFX_`axis'}"
                foreach a of global IC_ALIASES {
                    cap confirm variable `hp'_hi_`a'
                    if _rc continue
                    foreach grp in `hp'_hi_`a' `hp'_lo_`a' `lp'_hi_`a' `lp'_lo_`a' {
                        cap drop Z_`grp' S_`grp' PT_`grp'
                        gen Z_`grp' = Z_it       * `grp'
                        gen S_`grp' = Z_share_it * `grp'
                        gen PT_`grp' = post * `grp'
                    }
                    * [H11] `lp'_lo x post is the omitted base
                    cap noi ppmlhdfe `yvar' ///
                        Z_`hp'_hi_`a' Z_`hp'_lo_`a' Z_`lp'_hi_`a' Z_`lp'_lo_`a' ///
                        S_`hp'_hi_`a' S_`hp'_lo_`a' S_`lp'_hi_`a' S_`lp'_lo_`a' ///
                        PT_`hp'_hi_`a' PT_`hp'_lo_`a' PT_`lp'_hi_`a', ///
                        absorb(`fes') vce(cluster `vce_cl')
                    if _rc {
                        di as error "event_study_het `samp'`suf' `yvar' joint-ae-`axis' `a' ppml failed; skipping."
                        continue
                    }
                    local Nppml = e(N)
                    local r2ppml = e(r2_p)
                    foreach grp in `hp'_hi_`a' `hp'_lo_`a' `lp'_hi_`a' `lp'_lo_`a' {
                        gunique athr_id if e(sample) & `grp' == 1
                        local num_athrs = r(unique)
                        gunique inst_id if e(sample) & `grp' == 1
                        local num_insts = r(unique)
                        local b_post  = _b[Z_`grp']
                        local se_post = _se[Z_`grp']
                        di as text "joint-ae-`axis' PPML `samp'`suf' `yvar' `grp': b=" %8.4f `b_post' ///
                            " (se=" %8.4f `se_post' ")   N=" %9.0f `Nppml' " PIs=`num_athrs' Insts=`num_insts'"
                        post `ph_handle' ("`yvar'") ("`grp'") ("mshrctrl") ("joint_ae_`axis'") ///
                            (`b_post') (`se_post') (.) (.) (`Nppml') (`r2ppml')
                    }
                    * Within-tier hp-vs-lp: low-res row is the thin cell that would carry the reversal claim.
                    foreach side in hi lo {
                        cap noi lincom Z_`hp'_`side'_`a' - Z_`lp'_`side'_`a'
                        if _rc continue
                        local b_diff  = r(estimate)
                        local se_diff = r(se)
                        local t_diff  = cond(`se_diff' > 0, `b_diff'/`se_diff', .)
                        local p_diff  = r(p)
                        local ci_l    = r(lb)
                        local ci_h    = r(ub)
                        di as text "joint-ae-`axis' DIFF `samp'`suf' `yvar' `side'res_`a' (`hp'-`lp'): " ///
                            "b=" %8.4f `b_diff' " se=" %8.4f `se_diff' ///
                            " t=" %6.2f `t_diff' " p=" %6.4f `p_diff' ///
                            " CI95=[" %6.3f `ci_l' "," %6.3f `ci_h' "]"
                        post `ph_handle' ("`yvar'") ("`side'res_diff_`a'") ("mshrctrl") ("joint_ae_`axis'_diff") ///
                            (`b_diff') (`se_diff') (`p_diff') (.) (`Nppml') (`r2ppml')
                    }
                }
            }

            * ---- PI-split x PI-split joint 2x2s. One PPML per spec: four
            * cell coefficients (4th cell x post is the omitted base [H11])
            * posted under split_type = <jt>, plus four lincom contrasts
            * (c1-c2, c3-c4, c1-c3, c2-c4) posted under <jt>_diff. Spec =
            * "<jt> c1 c2 c3 c4 dname1 dname2 dname3 dname4".
            local joint_specs
            local joint_specs `" `joint_specs' "joint_agepr y_hp y_lp o_hp o_lp y_diff_pr o_diff_pr hp_diff_age lp_diff_age" "'
            local joint_specs `" `joint_specs' "joint_agenih y_hn y_ln o_hn o_ln y_diff_nihd o_diff_nihd hi_diff_age lo_diff_age" "'
            local joint_specs `" `joint_specs' "joint_prnih hp_hn hp_ln lp_hn lp_ln hp_diff_nihd lp_diff_nihd hn_diff_pr ln_diff_pr" "'
            local joint_specs `" `joint_specs' "joint_ageteam y_bt y_sm o_bt o_sm y_diff_team o_diff_team bt_diff_age sm_diff_age" "'
            local joint_specs `" `joint_specs' "joint_tmnih bt_hn bt_ln sm_hn sm_ln bt_diff_nihd sm_diff_nihd hn_diff_team ln_diff_team" "'
            local joint_specs `" `joint_specs' "joint_tmpr bt_hp bt_lp sm_hp sm_lp bt_diff_pr sm_diff_pr hp_diff_team lp_diff_team" "'
            local joint_specs `" `joint_specs' "joint_agenet y_bn y_sn o_bn o_sn y_diff_net o_diff_net bn_diff_age sn_diff_age" "'
            local joint_specs `" `joint_specs' "joint_agelab y_nl y_el o_nl o_el y_diff_lab o_diff_lab nl_diff_age el_diff_age" "'
            local joint_specs `" `joint_specs' "joint_agecrwd y_ci y_si o_ci o_si y_diff_crwd o_diff_crwd ci_diff_age si_diff_age" "'
            local joint_specs `" `joint_specs' "joint_agemsa y_bmsa y_smsa o_bmsa o_smsa y_diff_msa o_diff_msa bmsa_diff_age smsa_diff_age" "'
            foreach js of local joint_specs {
                local jt : word 1 of `js'
                forvalues k = 1/4 {
                    local c`k'  : word `=1+`k'' of `js'
                    local dn`k' : word `=5+`k'' of `js'
                }
                * Skip if any cell is missing or empty (e.g. NIH cells off the
                * matched sample, degenerate joint cells).
                local jt_bad 0
                foreach grp in `c1' `c2' `c3' `c4' {
                    cap confirm variable `grp'
                    if _rc {
                        local jt_bad 1
                        continue, break
                    }
                    qui count if `grp' == 1
                    if r(N) == 0 local jt_bad 1
                }
                if `jt_bad' {
                    di as text "event_study_het `samp'`suf' `yvar': `jt' cells missing/empty -- skipping."
                    continue
                }
                foreach grp in `c1' `c2' `c3' `c4' {
                    cap drop Z_`grp' S_`grp' PT_`grp'
                    gen Z_`grp' = Z_it       * `grp'
                    gen S_`grp' = Z_share_it * `grp'
                    gen PT_`grp' = post * `grp'
                }
                cap noi ppmlhdfe `yvar' Z_`c1' Z_`c2' Z_`c3' Z_`c4' ///
                                        S_`c1' S_`c2' S_`c3' S_`c4' ///
                                        PT_`c1' PT_`c2' PT_`c3', ///
                                        absorb(`fes') vce(cluster `vce_cl')
                if _rc {
                    di as error "event_study_het `samp'`suf' `yvar' `jt' ppml failed; skipping."
                    continue
                }
                local Nppml = e(N)
                local r2ppml = e(r2_p)
                foreach grp in `c1' `c2' `c3' `c4' {
                    gunique athr_id if e(sample) & `grp' == 1
                    local num_athrs = r(unique)
                    gunique inst_id if e(sample) & `grp' == 1
                    local num_insts = r(unique)
                    local b_post  = _b[Z_`grp']
                    local se_post = _se[Z_`grp']
                    di as text "`jt' PPML `samp'`suf' `yvar' `grp': b=" %8.4f `b_post' ///
                        " (se=" %8.4f `se_post' ")   N=" %9.0f `Nppml' " PIs=`num_athrs' Insts=`num_insts'"
                    post `ph_handle' ("`yvar'") ("`grp'") ("mshrctrl") ("`jt'") ///
                        (`b_post') (`se_post') (.) (.) (`Nppml') (`r2ppml')
                }
                * Within-first-axis and within-second-axis contrasts; SEs via
                * lincom use the full VCE.
                foreach d in "`dn1' Z_`c1' Z_`c2'" "`dn2' Z_`c3' Z_`c4'" ///
                             "`dn3' Z_`c1' Z_`c3'" "`dn4' Z_`c2' Z_`c4'" {
                    local dname : word 1 of `d'
                    local d1    : word 2 of `d'
                    local d2    : word 3 of `d'
                    cap noi lincom `d1' - `d2'
                    if _rc continue
                    local b_diff  = r(estimate)
                    local se_diff = r(se)
                    local p_diff  = r(p)
                    di as text "`jt' DIFF `samp'`suf' `yvar' `dname': b=" %8.4f `b_diff' ///
                        " (se=" %8.4f `se_diff' ") p=" %6.4f `p_diff'
                    post `ph_handle' ("`yvar'") ("`dname'") ("mshrctrl") ("`jt'_diff") ///
                        (`b_diff') (`se_diff') (`p_diff') (.) (`Nppml') (`r2ppml')
                }
            }

        }
        postclose `ph_handle'

        * pdid binscatter + coefplot for this yvar, so PDFs land continuously
        if strpos(" `ppml_het_skip' ", " `yvar' ") == 0 {
            cap noi ppml_pdid_het_binscatter, samp(`samp') r1r2(`r1r2') public(`public') r1_only(`r1_only') yvar(`yvar')
        }
        cap noi ppml_het_coefplot, samp(`samp') r1r2(`r1r2') public(`public') r1_only(`r1_only') yvar(`yvar')
    }

    * Combine per-yvar phet_results files into master (consumed by output_het_tables).
    preserve
    clear
    foreach yvar of local yvar_list {
        cap append using ../temp/phet_results_`samp'`suf'_`yvar'
    }
    save ../temp/phet_results_`samp'`suf', replace
    restore
end

program ppml_pdid_het_binscatter
    * Joint PPML pooled-DiD FWL binscatter of `yvar' on Z_it, mshr partialled.
    * Fit ppmlhdfe on FULL sample with fully-interacted Z and share, then
    * residualize _z_work and Z_grp against the sibling group + shares + FEs.
    * On grp==1 rows the sibling interactions are 0 so FWL slope = _b[Z_grp].
    * NOTE: residualization runs on the full sample while the plot keeps
    * grp==1 rows, so the binned slope approximates the (exactly displayed)
    * joint-fit coefficient.
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

    * [H9] y-axis label per outcome (was hard-coded "Publications")
    local bs_lbl "`yvar'"
    if "`yvar'" == "ppr_cnt"           local bs_lbl "Publications"
    if "`yvar'" == "cite_affl_wt"      local bs_lbl "Citation-Weighted Output"
    if "`yvar'" == "avg_num_coathrs"   local bs_lbl "Coauthors"
    if "`yvar'" == "n_grants"          local bs_lbl "Active NIH Research Grants"
    if "`yvar'" == "n_new_grants"      local bs_lbl "New NIH Research Grants"
    if "`yvar'" == "nih_total_cost"    local bs_lbl "NIH Award Dollars"
    if "`yvar'" == "n_middle_ppr"      local bs_lbl "Middle-Author Papers"

    local dummy_pairs `" "young old" "young_nih old_nih" "r1 r2" "pub_inst priv_inst" "high_pre_ppr low_pre_ppr" "big_team small_team" "high_nihg low_nihg" "high_nihd low_nihd" "big_net small_net" "new_lab est_lab" "crwd_inst sprs_inst" "big_msa small_msa" "yhigh_nihd ylow_nihd" "yq4_nihd yq1_nihd" ${IC_PAIRS_MED_PW} "'
    if "$HET_INCLUDE_INSTWTD" == "1" local dummy_pairs `" `dummy_pairs' ${IC_PAIRS_MED} "'

    * Load panel once; per-pair vars are cap-dropped and rebuilt in place.
    preserve
        use ../temp/es_`samp'`suf', clear
        gen post       = year >= 2014
        gen Z_it       = exposure      * post
        gen Z_share_it = mkt_spend_shr * post

        foreach pair of local dummy_pairs {
            local g1 : word 1 of `pair'
            local g2 : word 2 of `pair'

            * HET_GROUPS_ACTIVE (set by event_study_het before this is called)
            * screens missing AND degenerate dummies — a no-obs group would
            * crash binscatter and abort the remaining pairs.
            if strpos(" ${HET_GROUPS_ACTIVE} ", " `g1' ") == 0 continue
            if strpos(" ${HET_GROUPS_ACTIVE} ", " `g2' ") == 0 continue

            * one at a time — a `drop' list is all-or-nothing, and a missing
            * Z_<grp> would leave _mu/_dvar alive to crash d() below
            foreach v in Z_`g1' Z_`g2' S_`g1' S_`g2' PT_`g1' _mu _z_work _dvar _fwlw _y_r _Z_r {
                cap drop `v'
            }
            gen Z_`g1' = Z_it       * `g1'
            gen Z_`g2' = Z_it       * `g2'
            gen S_`g1' = Z_share_it * `g1'
            gen S_`g2' = Z_share_it * `g2'
            gen PT_`g1' = post * `g1'

            * [H11] PT matches the posted pooled-DiD spec so displayed beta agrees
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

            * IRLS working response + FWL weight from the joint fit.
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
                binscatter _y_r _Z_r [aw=_fwlw] if `grp' == 1 & !mi(_y_r) & !mi(_Z_r), n(30) ///
                    xtitle("Exposure x Post") ///
                    ytitle("{&Delta} Log Expected `bs_lbl'") ///
                    xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                    msymbol(O) mcolors(gs6) lcolors(ebblue) ///
                    note("Num. PIs: `n_pis'   Num. Insts: `n_insts'" "{&beta} = `b_str' (SE: `se_str')", size(small) pos(7) ring(1) justification(left)) ///
                    plotregion(margin(sides))
                graph export ///
                    ../output/figures/`samp'/ppml_pdid_het_bs/ppml_pdid_`yvar'_`grp'_mshrctrl`suf'.pdf, ///
                    replace
            }
        }
    restore
end

program ppml_age_gradient
    * Age gradient of the pooled-DiD beta: one joint PPML with Z_it and the
    * share control fully interacted with career-age bins (HET_AGE_NBINS
    * PI-level quantiles of age_2014), plotted as each bin's beta vs the bin's
    * mean age. Same spec as the posted "mshrctrl" median splits, K bins
    * instead of 2.
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
    xtile _agebin_pi = age_2014 if athr_indicator == 1, n(`K')
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
        gen Z_a`k' = Z_it       * (agebin == `k')
        gen S_a`k' = Z_share_it * (agebin == `k')
        local zvars `zvars' Z_a`k'
        local svars `svars' S_a`k'
        local bins_used `bins_used' `k'
    }
    * post x bin shifts for all but the last bin: the full set sums to post,
    * collinear with year FE (last bin's post shift is the absorbed base).
    local ptvars
    local nb : word count `bins_used'
    forval i = 1/`=`nb'-1' {
        local k : word `i' of `bins_used'
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
            qui sum age_2014 if athr_indicator == 1 & agebin == `k'
            mat AG = nullmat(AG) \ (`k', r(mean), r(N), _b[Z_a`k'], _se[Z_a`k'])
        }
        preserve
        clear
        svmat AG
        rename (AG1 AG2 AG3 AG4 AG5) (bin age_mean n_pis b se)
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        save ../temp/age_gradient_`samp'`suf'_`yvar', replace
        tw rcap ub lb age_mean, lcolor(ebblue%70) msize(vsmall) || ///
           scatter b age_mean, mcolor(ebblue) || ///
           lfit b age_mean [aw=1/(se*se)], lcolor(dkorange) lpattern(dash) ///
           xtitle("Career Age in 2014") ytitle("`ppml_ytit'") ///
           yline(0, lcolor(gs10) lpattern(solid)) ///
           legend(on order(- "Num. PIs: `n_pis'" "Num. Insts: `n_insts'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) ///
           plotregion(margin(sides))
        graph export ../output/figures/`samp'/agegrad_`yvar'`suf'_ppml_mshrctrl.pdf, replace
        restore
    }
end

program desc_pre_output_by_age
    * PI-level pre-period research-output densities, young vs old.
    * Log-scale and raw (x capped at pooled p95) overlays per outcome.
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

    * Productivity: total pre-period papers and papers per pre-period year.
    * Citations and authorship-position counts ride along as totals.
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
        * both densities on one common x grid so rarea can shade the gap
        qui sum ln_pre_`a'
        cap drop _kx _kd_y _kd_o _kd_c
        gen _kx = r(min) + (r(max) - r(min)) * (_n - 1) / 199 if _n <= 200
        kdensity ln_pre_`a' if young == 1, at(_kx) gen(_kd_y) nograph
        kdensity ln_pre_`a' if young == 0, at(_kx) gen(_kd_o) nograph
        gen _kd_c = min(_kd_y, _kd_o)
        tw (rarea _kd_c _kd_y _kx, color(ebblue*0.3) lwidth(none)) ///
           (rarea _kd_c _kd_o _kx, color(dkorange*0.3) lwidth(none)) ///
           (line _kd_y _kx, lcolor(ebblue) lwidth(medthick)) ///
           (line _kd_o _kx, lcolor(dkorange) lwidth(medthick)) ///
           , xtitle("ln(1 + Pre-Period `lbl_`a'', `y0'-`y1')") ytitle("Density") ///
             legend(order(3 "`leg_y'" 4 "`leg_o'") ///
                    pos(2) ring(0) rows(2) size(small)) ///
             plotregion(margin(sides))
        graph export ../output/figures/`samp'/desc_kd_pre_`a'_ln`suf'.pdf, replace

        qui sum pre_`a', d
        local xcap = r(p95)
        cap drop _kx _kd_y _kd_o _kd_c
        gen _kx = `xcap' * (_n - 1) / 199 if _n <= 200
        kdensity pre_`a' if young == 1 & pre_`a' <= `xcap', at(_kx) gen(_kd_y) nograph
        kdensity pre_`a' if young == 0 & pre_`a' <= `xcap', at(_kx) gen(_kd_o) nograph
        gen _kd_c = min(_kd_y, _kd_o)
        tw (rarea _kd_c _kd_y _kx, color(ebblue*0.3) lwidth(none)) ///
           (rarea _kd_c _kd_o _kx, color(dkorange*0.3) lwidth(none)) ///
           (line _kd_y _kx, lcolor(ebblue) lwidth(medthick)) ///
           (line _kd_o _kx, lcolor(dkorange) lwidth(medthick)) ///
           , xtitle("Pre-Period `lbl_`a'', `y0'-`y1' (x capped at pooled p95)") ytitle("Density") ///
             legend(order(3 "`leg_y'" 4 "`leg_o'") ///
                    pos(2) ring(0) rows(2) size(small)) ///
             plotregion(margin(sides))
        graph export ../output/figures/`samp'/desc_kd_pre_`a'_raw`suf'.pdf, replace
        cap drop _kx _kd_y _kd_o _kd_c
    }

    save ../temp/desc_pre_output_`samp'`suf', replace
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

program ppml_het_coefplot
    * Three panels per yvar (pi / ic_fund / ic_expx).
    * If yvar() is supplied, plot only that outcome; otherwise loop all.
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) yvar(string)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"

    * When called inline per-yvar, read the per-yvar postfile; otherwise the combined master.
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

    local ppml_het_yvars ppr_cnt cite_affl_wt avg_num_coathrs ///
                        n_grants n_new_grants nih_total_cost ///
                        n_middle_ppr
    if "`yvar'" != "" local ppml_het_yvars `yvar'

    local ic_fund_aliases tfnd lsf
    local ic_expx_aliases endow
    if $HET_IC_FULL == 1 {
        local ic_fund_aliases contr fdlsb fdls fdlsh gntsf hhlsb hhls hhlsh nflsb nfls nflsh subrf busf fedf tfnd instf nonpf statf lsf hsf biof
        local ic_expx_aliases applx apfx basx bfx clinx devx lscx medx endow
    }

    * joint_ae_<axis> types track PI_CHAR_ALIASES so dropping an axis there
    * removes its coefplot too.
    local axis_sts
    foreach axis of global PI_CHAR_ALIASES {
        local axis_sts `axis_sts' joint_ae_`axis'
    }
    local st_list med_pi joint_ae `axis_sts' joint_agepr joint_agenih joint_prnih ///
                  joint_ageteam joint_tmnih joint_tmpr ///
                  joint_agenet joint_agelab joint_agecrwd joint_agemsa
    if "$HET_INCLUDE_INSTWTD" == "1" local st_list med `st_list'
    if "$HET_RUN_QUARTILES" == "1" {
        local st_list `st_list' quart_pi
        if "$HET_INCLUDE_INSTWTD" == "1" local st_list `st_list' quart
    }
    foreach st of local st_list {
        if strpos("`st'", "joint_") == 1 {
            * Custom paired rendering used instead of the standard panel loop.
            * Leaving all groups empty causes the standard loop to skip.
            local groups_pi
            local groups_ic_fund
            local groups_ic_expx
        }
        else if "`st'" == "med" {
            local groups_pi     young old r1 r2 pub_inst priv_inst ///
                                high_pre_ppr low_pre_ppr ///
                                high_nihd low_nihd ///
                                big_msa small_msa
            local groups_ic_fund
            foreach a of local ic_fund_aliases {
                local groups_ic_fund `groups_ic_fund' hi_`a' lo_`a'
            }
            local groups_ic_expx
            foreach a of local ic_expx_aliases {
                local groups_ic_expx `groups_ic_expx' hi_`a' lo_`a'
            }
        }
        else if "`st'" == "med_pi" {
            * PI-weighted inst-char medians. PI-level splits are the same
            * variables as under med so they render in the pi panel too.
            local groups_pi     young old r1 r2 pub_inst priv_inst ///
                                high_pre_ppr low_pre_ppr ///
                                high_nihd low_nihd ///
                                big_msa small_msa
            local groups_ic_fund
            foreach a of local ic_fund_aliases {
                local groups_ic_fund `groups_ic_fund' hiw_`a' low_`a'
            }
            local groups_ic_expx
            foreach a of local ic_expx_aliases {
                local groups_ic_expx `groups_ic_expx' hiw_`a' low_`a'
            }
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
            * quart_pi -- PI-weighted quartiles for inst chars, PI-continuous
            * quartiles for PI bases.
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

        * Combined panel stacks pi + ic_fund + ic_expx so the paper can show
        * one coefplot per (yvar, spec, st) instead of three per-panel PDFs.
        local groups_all `groups_pi' `groups_ic_fund' `groups_ic_expx'
        foreach panel in pi ic_fund ic_expx all {
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

                * Groups come in high/low pairs; add a gap between pairs so
                * each pair reads as one block.
                local pair_gap 0.7
                local npairs = ceil(`n_groups'/2)
                gen double y = .
                local ylabs ""
                local i = 0
                foreach g of local groups {
                    local ++i
                    local pair = int((`i'-1)/2)
                    local ypos = (`n_groups' - `i') + (`npairs' - 1 - `pair')*`pair_gap' + 1
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
                local xmin = floor(r(min)/0.5)*0.5
                qui sum ub
                local xmax = ceil(r(max)/0.5)*0.5

                * Adaptive canvas: bigger for more rows. Matches old reduced_form format.
                local ysize 6
                if `n_groups' > 20 local ysize 10
                if `n_groups' > 40 local ysize 14
                * Grow the canvas by the added inter-pair whitespace.
                local ysize = round(`ysize' * (`n_groups' + (`npairs'-1)*`pair_gap')/`n_groups', 0.1)
                local labsize small
                if `n_groups' > 20 local labsize vsmall

                tw rcap ub lb y, horizontal lcolor(ebblue%70) msize(vsmall) || ///
                   scatter y post_b, mcolor(ebblue) msize(small) ///
                   , xline(0, lcolor(gs10) lpattern(solid)) ///
                     ylabel(`ylabs', angle(0) labsize(`labsize') noticks nogrid) ///
                     ytitle("") xtitle("Exposure x Post", size(small)) ///
                     xlabel(`xmin'(0.5)`xmax', labsize(small)) ///
                     legend(off) ///
                     ysize(`ysize') xsize(7) ///
                     yscale(range(0.9 .)) ///
                     plotregion(margin(l=zero r=zero b=zero t=vsmall))
                graph export ///
                    "../output/figures/`samp'/`spec_folder'/ppml_het_coefplot_`yv'_`st'_`panel'`suf'.pdf", ///
                    replace
                di as text "wrote ../output/figures/`samp'/`spec_folder'/ppml_het_coefplot_`yv'_`st'_`panel'`suf'.pdf"
                restore
            }
        }

        * ----- Custom paired coefplot: inst chars on y-axis (High/Low rows),
        *       one blue + one orange marker per row. Splitting axis and
        *       prefix widths depend on `st':
        *         joint_ae         -- age (1-char y/o prefix)
        *         joint_ae_<axis>  -- PI split (2-char hp/lp or mc/fc prefix)
        if "`st'" == "joint_ae" | strpos("`st'", "joint_ae_") == 1 {
            if "`st'" == "joint_ae" {
                local pfx_len   1
                local hi_pfx    y
                local lo_pfx    o
                local hi_leg    "Early-Career"
                local lo_leg    "Late-Career"
                local filename_stem joint_ae_paired
            }
            else {
                local axis : subinstr local st "joint_ae_" "", all
                local pfx_len   2
                local hi_pfx    "${PI_CHAR_HIPFX_`axis'}"
                local lo_pfx    "${PI_CHAR_LOPFX_`axis'}"
                local hi_leg    "${PI_CHAR_HILEG_`axis'}"
                local lo_leg    "${PI_CHAR_LOLEG_`axis'}"
                local filename_stem "joint_ae_`axis'_paired"
            }
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
                * Row layout: within-pair (blue+orange same hi/lo) 0.6;
                * between hi-row and lo-row of same char = 0.8; between
                * chars = 1.2. Base spacing 3.2 per char.
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
        }

        * ----- Age x baseline-productivity 2x2 (no inst char).
        *       Two rows: High Baseline Productivity / Low Baseline Productivity.
        *       Blue = Early-Career, Orange = Late-Career.
        if "`st'" == "joint_agepr" {
            foreach yv of local ppml_het_yvars {
                preserve
                use "`resfile'", clear
                keep if yvar == "`yv'" & split_type == "joint_agepr" & spec == "`spec_tag'"
                if _N == 0 {
                    restore
                    continue
                }
                gen byte is_young = (substr(grp, 1, 1) == "y")
                gen str2 pr_c    = substr(grp, 3, 2)
                gen double y_pos = cond(pr_c == "hp",  2, 1) ///
                                   + cond(is_young == 1,  0.3, -0.3)
                gen ub = post_b + 1.96*post_se
                gen lb = post_b - 1.96*post_se

                local ylabs `"2 "High Baseline Productivity" 1 "Low Baseline Productivity""'

                qui sum lb
                local xmin = floor(r(min)/0.5)*0.5
                qui sum ub
                local xmax = ceil(r(max)/0.5)*0.5

                tw rcap ub lb y_pos if is_young == 1, horizontal lcolor(ebblue%70) msize(vsmall)   || ///
                   scatter y_pos post_b if is_young == 1, mcolor(ebblue) msize(small)              || ///
                   rcap ub lb y_pos if is_young == 0, horizontal lcolor(dkorange%70) msize(vsmall) || ///
                   scatter y_pos post_b if is_young == 0, mcolor(dkorange) msymbol(D) msize(small) ///
                   , xline(0, lcolor(gs10) lpattern(solid)) ///
                     ylabel(`ylabs', angle(0) labsize(small) noticks nogrid) ///
                     ytitle("") xtitle("Exposure x Post", size(small)) ///
                     xlabel(`xmin'(0.5)`xmax', labsize(small)) ///
                     legend(order(2 "Early-Career" 4 "Late-Career") pos(6) ring(1) rows(1) span size(small)) ///
                     ysize(5) xsize(7) ///
                     yscale(range(0.62 .)) ///
                     plotregion(margin(l=zero r=zero b=zero t=vsmall))
                graph export ///
                    "../output/figures/`samp'/`spec_folder'/ppml_het_coefplot_`yv'_joint_agepr`suf'.pdf", ///
                    replace
                di as text "wrote joint_agepr coefplot for `yv' `spec_tag'"
                restore
            }
        }

        * ----- Generic 4-cell joint coefplots (PI-split x PI-split): one row
        *       per cell, first-axis pairs blocked. Cells ordered hi-hi,
        *       hi-lo, lo-hi, lo-lo; lab1/lab2 = first axis, lab3/lab4 =
        *       second axis.
        local generic_jts joint_agenih joint_prnih joint_ageteam joint_tmnih joint_tmpr ///
                          joint_agenet joint_agelab joint_agecrwd joint_agemsa
        if strpos(" `generic_jts' ", " `st' ") > 0 {
            if "`st'" == "joint_agenih" {
                local cells y_hn y_ln o_hn o_ln
                local lab1 "Early-Career Scientists"
                local lab2 "Late-Career Scientists"
                local lab3 "More NIH Funding at Baseline"
                local lab4 "Less NIH Funding at Baseline"
            }
            if "`st'" == "joint_agenet" {
                local cells y_bn y_sn o_bn o_sn
                local lab1 "Early-Career Scientists"
                local lab2 "Late-Career Scientists"
                local lab3 "Larger Coauthor Network"
                local lab4 "Smaller Coauthor Network"
            }
            if "`st'" == "joint_agelab" {
                local cells y_nl y_el o_nl o_el
                local lab1 "Early-Career Scientists"
                local lab2 "Late-Career Scientists"
                local lab3 "Newer Labs"
                local lab4 "Established Labs"
            }
            if "`st'" == "joint_agecrwd" {
                local cells y_ci y_si o_ci o_si
                local lab1 "Early-Career Scientists"
                local lab2 "Late-Career Scientists"
                local lab3 "More Same-Field PIs at Inst."
                local lab4 "Fewer Same-Field PIs at Inst."
            }
            if "`st'" == "joint_agemsa" {
                local cells y_bmsa y_smsa o_bmsa o_smsa
                local lab1 "Early-Career Scientists"
                local lab2 "Late-Career Scientists"
                local lab3 "Larger MSAs"
                local lab4 "Smaller MSAs"
            }
            if "`st'" == "joint_prnih" {
                local cells hp_hn hp_ln lp_hn lp_ln
                local lab1 "More Productive at Baseline"
                local lab2 "Less Productive at Baseline"
                local lab3 "More NIH Funding at Baseline"
                local lab4 "Less NIH Funding at Baseline"
            }
            if "`st'" == "joint_ageteam" {
                local cells y_bt y_sm o_bt o_sm
                local lab1 "Early-Career Scientists"
                local lab2 "Late-Career Scientists"
                local lab3 "Larger Team Size"
                local lab4 "Smaller Team Size"
            }
            if "`st'" == "joint_tmnih" {
                local cells bt_hn bt_ln sm_hn sm_ln
                local lab1 "Larger Team Size"
                local lab2 "Smaller Team Size"
                local lab3 "More NIH Funding at Baseline"
                local lab4 "Less NIH Funding at Baseline"
            }
            if "`st'" == "joint_tmpr" {
                local cells bt_hp bt_lp sm_hp sm_lp
                local lab1 "Larger Team Size"
                local lab2 "Smaller Team Size"
                local lab3 "More Productive at Baseline"
                local lab4 "Less Productive at Baseline"
            }
            foreach yv of local ppml_het_yvars {
                preserve
                use "`resfile'", clear
                keep if yvar == "`yv'" & split_type == "`st'" & spec == "`spec_tag'"
                if _N == 0 {
                    restore
                    continue
                }
                gen double y_pos = .
                replace y_pos = 4.7 if grp == word("`cells'", 1)
                replace y_pos = 3.7 if grp == word("`cells'", 2)
                replace y_pos = 2   if grp == word("`cells'", 3)
                replace y_pos = 1   if grp == word("`cells'", 4)
                drop if mi(y_pos) | mi(post_b)
                if _N == 0 {
                    restore
                    continue
                }
                gen ub = post_b + 1.96*post_se
                gen lb = post_b - 1.96*post_se

                qui sum lb
                local xmin = floor(r(min)/0.5)*0.5
                qui sum ub
                local xmax = ceil(r(max)/0.5)*0.5

                tw rcap ub lb y_pos, horizontal lcolor(ebblue%70) msize(vsmall) || ///
                   scatter y_pos post_b, mcolor(ebblue) msize(small) ///
                   , xline(0, lcolor(gs10) lpattern(solid)) ///
                     ylabel(4.7 `""`lab1'" "`lab3'""' ///
                            3.7 `""`lab1'" "`lab4'""' ///
                            2   `""`lab2'" "`lab3'""' ///
                            1   `""`lab2'" "`lab4'""', ///
                            angle(0) labsize(small) noticks nogrid) ///
                     ytitle("") xtitle("Exposure x Post", size(small)) ///
                     xlabel(`xmin'(0.5)`xmax', labsize(small)) ///
                     legend(off) ///
                     ysize(5) xsize(7) ///
                     yscale(range(0.9 .)) ///
                     plotregion(margin(l=zero r=zero b=zero t=vsmall))
                graph export ///
                    "../output/figures/`samp'/`spec_folder'/ppml_het_coefplot_`yv'_`st'`suf'.pdf", ///
                    replace
                di as text "wrote `st' coefplot for `yv' `spec_tag'"
                restore
            }
        }
        }  // close foreach spec_tag
    }
end

**
main