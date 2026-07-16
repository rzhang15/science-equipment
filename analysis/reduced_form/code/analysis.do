set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

* ============================================================
*  ONE PLACE TO SWITCH EXPOSURE MEASURE
*  EXPOSURE_VERSION : hc | all | treated_hc
*      -> picks both  ../external/exposure/final_imputed_exposure_${VER}${FLT}.csv
*                and  ../external/real_exposure/athr_exposure_${VER}.dta
*  EXPOSURE_FILTER  : ""  |  "_cf"  |  "_cf2"  |  "_cf5"
*      -> only affects the imputed CSV (post-imputation cluster filter)
* ============================================================
global EXPOSURE_VERSION "hc"
global EXPOSURE_FILTER  "_cf"

* ============================================================
*  ONE PLACE TO SWITCH FIXED EFFECTS
*  FE_MODE : "author"             (default) -> absorb(athr_id year) vce(cluster athr_id)
*            "inst_cluster"                  -> absorb(inst_id cluster_30 year) vce(cluster inst_id)
*            "inst_cluster_fldyr"            -> absorb(inst_id i.cluster_30#i.year) vce(cluster inst_id)
*  Event studies still use rel = -1 as the omitted reference regardless of mode:
*  int_lead1 (and its heterogeneity variants) is left out of the regressor list
*  explicitly, so the reference year is preserved even when there is no athr_id FE
*  to force collinearity dropping of int_lead1.
*  Honored by: event_study, pooled_did, ppml_specs, placebo_treatment, trim_top, robustness.
*  The "inst_cluster_fldyr" mode drops year main effects and replaces them with
*  cluster-by-year interacted FEs, so identification comes off within-field-year
*  variation. Any pure exposure * year shock common to a research field is
*  absorbed; β is the differential response across fields.
* ============================================================
global FE_MODE "author"

* ============================================================
*  MAX-SIM WEIGHTING SWITCH
*  WEIGHT_MSIM : 0 (default) -> unweighted regressions
*                1           -> [pw=max_sim] on every reghdfe / ppmlhdfe call.
*                               Output figures / matrices / .dta files get a
*                               "_msimwt" suffix so the two versions coexist.
*  max_sim comes from match_diagnostics_restricted.dta (best cosine similarity
*  between the universe PI and any FOIA PI). For observed-exposure FOIA PIs
*  max_sim is set to 1 (they anchor their own exposure); imputed PIs use the
*  merged value; unmatched (rare) get max_sim = 0 so they drop out of the
*  weighted regression.
*  main() runs the full pipeline twice — once at WEIGHT_MSIM=0, once at
*  WEIGHT_MSIM=1 — so a single execution produces both flavors.
* ============================================================
global WEIGHT_MSIM 1

program main
    gather_external_data
    gather_inst_chars
    define_group_labels
    foreach s in all_jrnls top_jrnls {
        cap mkdir "../output/figures/`s'"
        // restrict_samp is weight-mode-agnostic — max_sim is saved as a column
        // in ../temp/es_`s'`suf' so the same dataset feeds both weighted and
        // unweighted runs of the estimation programs.
        restrict_samp, samp(`s') r1r2(1) public(1)
        foreach wmode in 0 1 {
            global WEIGHT_MSIM `wmode'
            di as text _newline "=========================================="
            di as text "  RUNNING sample=`s' WEIGHT_MSIM=`wmode'"
            di as text "=========================================="
            // Clear stale matrices from the prior mode so output_tables only
            // dumps matrices from programs actually run in this iteration.
            mat drop _all
            // event_study produces the OLS heterogeneity coefplots (highest
            // iteration priority) — kept first in the chain so its PDFs land
            // before anything downstream can abort the do file.
            event_study, samp(`s') r1r2(1) public(1)
            pooled_did, samp(`s') r1r2(1) public(1)
            ppml_specs, samp(`s') r1r2(1) public(1)
            // ppml_pdid_het_binscatter has been observed to abort with a Mata
            // r(3301) ("no observations for one of the fit lines") on some
            // (sample, spec) combos. Wrap in `cap noi` so a crash there does
            // not skip the remaining wmode / sample iterations.
            cap noi ppml_pdid_het_binscatter, samp(`s') r1r2(1) public(1)
            if _rc {
                di as error "main: ppml_pdid_het_binscatter failed for `s' wmode=`wmode' (rc=`_rc'); continuing."
            }
            // Diagnostics / robustness / age-split combine only run under the
            // default unweighted spec — no weighted twin needed for pre-trend
            // or trim/attrition sanity checks.
            if `wmode' == 0 {
                placebo_treatment, samp(`s') r1r2(1) public(1)
                trim_top, samp(`s') r1r2(1) public(1)
                combine_es_graphs, samp(`s')
                robustness, samp(`s') r1r2(1) public(1)
            }
            output_tables, samp(`s') r1r2(1) public(1)
        }
        // Reset to default so any downstream reads use the unweighted flavor.
        global WEIGHT_MSIM 0
    }
    joint_outcome_test, samp(all_jrnls) r1r2(1) public(1)
    joint_sample_test, r1r2(1) public(1)

    // ---- R1-only pass (all_jrnls, public=1). Same estimation chain as
    // above, but restrict_samp filters to type=="r1" so all splits /
    // regressions run on R1 authors only. Outputs get "_r1_public" suffix.
    restrict_samp, samp(all_jrnls) r1r2(1) public(1) r1_only(1)
    foreach wmode in 0 1 {
        global WEIGHT_MSIM `wmode'
        di as text _newline "=========================================="
        di as text "  RUNNING sample=all_jrnls WEIGHT_MSIM=`wmode' (R1-only)"
        di as text "=========================================="
        mat drop _all
        event_study, samp(all_jrnls) r1r2(1) public(1) r1_only(1)
        pooled_did,  samp(all_jrnls) r1r2(1) public(1) r1_only(1)
        ppml_specs,  samp(all_jrnls) r1r2(1) public(1) r1_only(1)
        cap noi ppml_pdid_het_binscatter, samp(all_jrnls) r1r2(1) public(1) r1_only(1)
        if _rc {
            di as error "main: ppml_pdid_het_binscatter r1_only failed wmode=`wmode' (rc=`_rc'); continuing."
        }
        if `wmode' == 0 {
            placebo_treatment, samp(all_jrnls) r1r2(1) public(1) r1_only(1)
            trim_top,          samp(all_jrnls) r1r2(1) public(1) r1_only(1)
            combine_es_graphs, samp(all_jrnls)
            robustness,        samp(all_jrnls) r1r2(1) public(1) r1_only(1)
        }
        output_tables, samp(all_jrnls) r1r2(1) public(1) r1_only(1)
    }
    global WEIGHT_MSIM 0
end

program gather_external_data
    import delimited ../external/exposure/final_imputed_shift_share_${EXPOSURE_VERSION}${EXPOSURE_FILTER}, clear
    rename exposure_ss imputed
    rename sum_imputed_shares imputed_mkt_spend_shr
    save ../temp/exposure, replace

    use ../external/grants/pi_grants_clean, clear
    bys athr_id year: gen num_grants = _N
    contract athr_id year num_grants
    drop _freq
    save ../temp/athr_yr_grnt_cnt, replace

    use ../external/foias/merged_foias_with_pis,  clear
    drop if mi(athr_id)
    gen year = year(date(date, "YMD"))
    merge m:1 category using ../external/categories/categories_tfidf, assert(1 2 3) keep(1 3)
    gen nonlab = 1 if _merge == 1
    replace nonlab = 0 if mi(nonlab)
    drop if nonlab == 0
    gcollapse (sum) spend, by(athr_id uni year)
    save ../temp/foia_spend, replace

    // author -> us_cluster_fields 30-cluster assignment (used when FE_MODE = "inst_cluster" or "inst_cluster_fldyr")
    cap confirm file ../temp/athr_cluster30.dta
    if _rc {
        import delimited ../external/cluster/author_static_clusters_30.csv, clear varnames(1)
        cap tostring athr_id, replace
        rename cluster_label cluster_30
        save ../temp/athr_cluster30, replace
    }

    // Universe PI match-quality diagnostics (max_sim = best cosine similarity
    // between the universe PI and any FOIA PI). Keyed on athr_id; keeps
    // athr_id + max_sim only. Real FOIA PIs are handled in restrict_samp
    // where max_sim is forced to 1 (they anchor themselves).
    use athr_id max_sim using ../external/exposure/match_diagnostics_restricted, clear
    save ../temp/match_diag, replace

end

program gather_inst_chars
    // Build ../temp/inst_chars_pre.dta keyed by OpenAlex inst_id, holding 30
    // pre-period university characteristics (funding buckets + expenditures +
    // endowment). Source: derived/inst_chars/output/combined_pre.dta (keyed on
    // ipeds_id) merged onto the netscratch ipeds<->openalex crosswalk.
    // Vars are renamed to short (`ic_<alias>`, <=8 char) aliases so downstream
    // interaction names like `mshr_lead4_q4_<alias>` stay under Stata's 32-char
    // variable-name limit.
    import delimited "/n/netscratch/pakes_lab/Lab/sci_eq/college/ipeds_openalex.csv", ///
        clear varn(1) stringcols(_all)
    keep ipeds_id inst_id
    drop if inst_id == "" | ipeds_id == ""
    destring ipeds_id, replace
    duplicates drop
    tempfile xw
    save `xw'

    use "/n/holylabs/pakes_lab/Lab/sci_eq/derived/inst_chars/output/combined_pre.dta", clear
    merge 1:1 ipeds_id using `xw', keep(3) nogen
    drop ipeds_id

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
    rename endownment          ic_endow

    order inst_id
    compress
    save ../temp/inst_chars_pre, replace
end

// -- Shared name lists driving the inst-char + quartile heterogeneity blocks.
// $IC_ALIASES : 30 short-alias inst-char variables in ../temp/inst_chars_pre
//               (each stored as ic_<alias> after gather_inst_chars).
// $PI_Q_BASES : 5 PI-level continuous vars (built in restrict_samp) that get
//               a quartile split on top of their existing median split.
// $IC_PAIRS_MED / $IC_PAIRS_Q / $PI_PAIRS_Q are the pair lists the estimation
// programs iterate over. Kept as globals so event_study,
// ppml_pdid_het_binscatter, and ppml_het_coefplot see the same lists.
global IC_ALIASES contr fdlsb fdls fdlsh gntsf hhlsb hhls hhlsh nflsb nfls nflsh ///
    subrf busf fedf tfnd instf nonpf statf lsf hsf biof applx apfx basx bfx clinx ///
    devx lscx medx endow
global PI_Q_BASES pre_ppr grants team coauth msa

program define_group_labels
    // Sets $LBL_<groupname> for every dummy used in a heterogeneity spec.
    // Called once at the top of main so all plot-labeling code can look up
    // human-readable labels via ${LBL_<grp>} without repeating chains of
    // if-`grp'=="X" checks.
    // Existing PI-level splits (median).
    global LBL_young        "Young"
    global LBL_old          "Old"
    global LBL_r1           "R1"
    global LBL_r2           "R2"
    global LBL_high_pre_ppr "More Productive at Baseline"
    global LBL_low_pre_ppr  "Less Productive at Baseline"
    global LBL_high_grants  "More Grants per Paper at Baseline"
    global LBL_low_grants   "Fewer Grants per Paper at Baseline"
    global LBL_big_team     "Larger Team Size"
    global LBL_small_team   "Smaller Team Size"
    global LBL_many_coauth  "More Coauthors"
    global LBL_few_coauth   "Fewer Coauthors"
    global LBL_big_msa      "Larger MSA"
    global LBL_small_msa    "Smaller MSA"

    // PI-level continuous chars, Q1 vs Q4 (mid = Q2 U Q3, plotted as nuisance).
    global LBL_q1_pre_ppr   "Q1 Pre-Period Productivity"
    global LBL_q4_pre_ppr   "Q4 Pre-Period Productivity"
    global LBL_mid_pre_ppr  "Mid Pre-Period Productivity"
    global LBL_q1_grants    "Q1 Grants per Paper"
    global LBL_q4_grants    "Q4 Grants per Paper"
    global LBL_mid_grants   "Mid Grants per Paper"
    global LBL_q1_team      "Q1 Team Size"
    global LBL_q4_team      "Q4 Team Size"
    global LBL_mid_team     "Mid Team Size"
    global LBL_q1_coauth    "Q1 Coauthors"
    global LBL_q4_coauth    "Q4 Coauthors"
    global LBL_mid_coauth   "Mid Coauthors"
    global LBL_q1_msa       "Q1 MSA Size"
    global LBL_q4_msa       "Q4 MSA Size"
    global LBL_mid_msa      "Mid MSA Size"

    // Inst-char labels (source: HERD funding buckets + expenditures + endowment).
    // Keyed on the same short alias used in the dummy names.
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
    local ic_lbl_tfnd  "Total R&D Funding"
    local ic_lbl_instf "Institutional Funding"
    local ic_lbl_nonpf "Non-Profit Funding"
    local ic_lbl_statf "State Funding"
    local ic_lbl_lsf   "Life-Sci Funding"
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
    local ic_lbl_endow "Endowment"
    foreach a of global IC_ALIASES {
        global LBL_hi_`a'  "High `ic_lbl_`a''"
        global LBL_lo_`a'  "Low `ic_lbl_`a''"
        global LBL_q1_`a'  "Q1 `ic_lbl_`a''"
        global LBL_q4_`a'  "Q4 `ic_lbl_`a''"
        global LBL_mid_`a' "Mid `ic_lbl_`a''"
    }

    // Pair lists (see IC_ALIASES / PI_Q_BASES globals above).
    // Convention (matches the existing PI-level median pairs high_/low_):
    //   pair = "focal_group  base_group"
    //   Median:   "hi_<x>  lo_<x>"    -> base absorbs low, β_g1 = High-Low diff
    //   Quartile: "q4_<x>  q1_<x>"    -> base absorbs Q1,  β_g1 = Q4-Q1 diff
    // For the three-group PPML quartile fit, mid_<x> is added as a nuisance
    // interaction alongside the pair; both q1 and q4 level β's are extracted.
    global IC_PAIRS_MED
    global IC_PAIRS_Q
    foreach a of global IC_ALIASES {
        global IC_PAIRS_MED `"${IC_PAIRS_MED} "hi_`a' lo_`a'" "'
        global IC_PAIRS_Q   `"${IC_PAIRS_Q} "q4_`a' q1_`a'" "'
    }
    global PI_PAIRS_Q
    foreach b of global PI_Q_BASES {
        global PI_PAIRS_Q `"${PI_PAIRS_Q} "q4_`b' q1_`b'" "'
    }
end

program restrict_samp
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"

    // input_suf identifies the upstream panel file to load. There's no
    // "_r1" panel file — R1-only is done by loading the R1+R2 panel and
    // filtering to type=="r1" here. So under r1_only=1 the input file
    // reads with the r1_r2[_public] suffix; only the OUTPUT files (es_,
    // exposure_dist, ...) carry the `_r1[_public]` suffix.
    local input_suf ""
    if (`r1r2' == 1 & `public' == 0) local input_suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1) local input_suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local input_suf "_r1_r2"
    if (`r1_only' == 1 & `public' == 1) local input_suf "_r1_r2_public"

    // all-authors counterpart: same file name minus the "last_" token.
    // Contains ppr_cnt / cite_affl_wt / affl_wt counting papers where the PI
    // appears in ANY authorship position (not just last). Also carries paper-
    // position metrics (avg_position, avg_position_rat, n_first/middle/last_ppr,
    // avg_team_size_(last|notlast)) once make_athr_yr_panel/build.do has been
    // rerun — the load is wrapped in cap so the pipeline still works with the
    // pre-position-metrics build; a global flag toggles whether position
    // outcomes are added downstream.
    preserve
        cap use athr_id year ppr_cnt cite_affl_wt affl_wt ///
                avg_position avg_position_rat ///
                n_first_ppr n_middle_ppr n_last_ppr ///
                avg_team_size_last avg_team_size_notlast ///
                using ../external/samp/athr_panel_full_year_`samp'`input_suf', clear
        local _pos_rc = _rc
        if `_pos_rc' {
            di as text "restrict_samp `samp'`suf': position vars not in panel yet — falling back to base _any outcomes. Rerun make_athr_yr_panel/code/build.do to enable them."
            use athr_id year ppr_cnt cite_affl_wt affl_wt ///
                using ../external/samp/athr_panel_full_year_`samp'`input_suf', clear
        }
        global POSITION_OUTCOMES_AVAIL = cond(`_pos_rc' == 0, 1, 0)
        rename (ppr_cnt cite_affl_wt affl_wt) (ppr_cnt_any cite_affl_wt_any affl_wt_any)
        save ../temp/athr_any_`samp'`input_suf', replace

        // Per-PI min year across ALL authorship positions -- used below to
        // build age_2014. Under the last-author panel's min_year, a PI who
        // published as first/middle author for years before their first
        // last-author paper looked spuriously young.
        bys athr_id: egen min_year_any = min(year)
        keep athr_id min_year_any
        duplicates drop
        save ../temp/athr_min_year_any_`samp'`input_suf', replace
    restore

    use ../external/samp/athr_panel_full_year_last_`samp'`input_suf',clear
    // R1-only filter: the upstream panel is R1+R2; keep type=="r1" so all
    // downstream medians / quartiles / regressions run on R1 authors only.
    if `r1_only' == 1 {
        keep if type == "r1"
        di as text "restrict_samp `samp'`suf' (r1_only=1): kept N=" _N " R1-only rows"
    }
*    bys athr_id: egen tot_pprs = total(ppr_cnt)
    bys athr_id: egen max_year = max(year)
    bys athr_id: egen min_year = min(year)
    keep if min_year <= 2013
    keep if max_year >= 2015
    keep if inrange(year, 2010, 2019)
    merge m:1 athr_id using ../temp/exposure, assert(1 2 3) keep(3) nogen
    merge m:1 athr_id using ../external/real_exposure/athr_exposure_${EXPOSURE_VERSION}, assert(1 2 3) keep(1 3) nogen
    merge m:1 athr_id using ../temp/athr_cluster30, keep(1 3) nogen
    merge m:1 athr_id using ../temp/athr_min_year_any_`samp'`input_suf', keep(1 3) nogen
    // Safety fallback: if a PI is somehow missing from the all-authors panel,
    // reuse the last-author min_year so age_2014 isn't left missing.
    replace min_year_any = min_year if mi(min_year_any)
    gen foia_athr = 1 if !mi(exposure)
    // Merge max_sim (universe match confidence). Real FOIA PIs get max_sim = 1
    // — they contribute observed exposure so imputation confidence isn't
    // meaningful. Imputed PIs keep their similarity to the nearest FOIA PI.
    // If unmatched (rare), max_sim stays missing and is set to 0 below so the
    // PI drops out of any [pw=max_sim] regression cleanly.
    merge m:1 athr_id using ../temp/match_diag, keep(1 3) nogen
    replace max_sim = 1 if foia_athr == 1
    replace max_sim = 0 if mi(max_sim)
    bys athr_id : gen athr_indicator = _n == 1
    sum exposure if athr_indicator == 1, d
    local mean : di %4.3f r(mean)
    local sd   : di %4.3f r(sd)
    sum imputed if athr_indicator == 1, d
    local imputed_mean : di %4.3f r(mean)
    local imputed_sd   : di %4.3f r(sd)
    sum mkt_spend_shr if athr_indicator == 1, d
    local mshr_mean : di %4.3f r(mean)
    local mshr_sd   : di %4.3f r(sd)
    sum imputed_mkt_spend_shr if athr_indicator == 1, d
    local imshr_mean : di %4.3f r(mean)
    local imshr_sd   : di %4.3f r(sd)
    tw kdensity exposure if athr_indicator == 1   || kdensity imputed if athr_indicator == 1  , xtitle("Exposure Measure") ytitle("Density") ///
        xlab(#15) ///
        legend(on label(1 "FOIA PI Observed Exposure (mean = `mean', sd = `sd')") label(2 "Imputed Exposure (mean = `imputed_mean', sd = `imputed_sd')") pos(7) ring(1) size(small))
    graph export ../output/figures/`samp'/exposure_dist`suf'.pdf, replace
    tw kdensity mkt_spend_shr if athr_indicator == 1  || kdensity imputed_mkt_spend_shr if athr_indicator == 1, xtitle("Market Spend Share") ytitle("Density") ///
        xlab(#15) ///
        legend(on label(1 "FOIA PI Observed (mean = `mshr_mean', sd = `mshr_sd')") label(2 "Imputed (mean = `imshr_mean', sd = `imshr_sd')") pos(7) ring(1) size(small))
    graph export ../output/figures/`samp'/mkt_spend_shr_dist`suf'.pdf, replace
    replace imputed = exposure if !mi(exposure)
    replace imputed_mkt_spend_shr = mkt_spend_shr if !mi(mkt_spend_shr)
    drop exposure
    rename imputed exposure
    drop mkt_spend_shr
    rename imputed_mkt_spend_shr mkt_spend_shr
    bys athr_id: egen num_yrs_pre = total(year < 2014)
    bys athr_id: gen tot_yrs = _N 
    bys athr_id inst_id: gen plc_cntr = _n == 1
    bys athr_id : egen num_place = total(plc_cntr)
    drop if num_yrs <= 2
*    drop if tot_yrs <= 4
    keep if num_place==1
    gegen athr = group(athr_id)
    preserve
    contract athr num_place athr_id exposure inst_id inst msa_comb msa_c_world min_year min_year_any type mkt_spend_shr cluster_30 max_sim foia_athr
    drop _freq
    save ../temp/athr_xw, replace
    restore
    xtset athr year
    tsfill, full
    drop athr_id exposure inst_id inst msa_comb msa_c_world min_year min_year_any type mkt_spend_shr cluster_30 max_sim foia_athr
    merge m:1 athr using ../temp/athr_xw, assert(3) keep(3) nogen
    // The last-author panel *also* carries position vars (build.do computes them
    // for both branches). Under Stata's merge default, master-side variables
    // override same-named using-side variables silently — so if we don't drop
    // these first, the athr_any values would be discarded and we'd keep the
    // degenerate last-author-panel copies (where which_athr == num_athrs
    // makes n_first_ppr into a solo-only count, n_middle_ppr uniformly zero, etc.).
    foreach v in n_first_ppr n_middle_ppr n_last_ppr n_solo_ppr ///
                 avg_position avg_position_rat ///
                 avg_team_size_last avg_team_size_notlast {
        cap drop `v'
    }
    // Merge in all-authors counts (any authorship position) as parallel outcomes.
    // Kept on the same tsfilled PI x year grid; missings after tsfill mean "no
    // papers that year in the all-authors panel either" → filled to 0 below.
    merge 1:1 athr_id year using ../temp/athr_any_`samp'`input_suf', keep(1 3) nogen
    foreach var in ppr_cnt cite_affl_wt affl_wt ppr_cnt_any cite_affl_wt_any affl_wt_any {
        replace `var' = 0 if mi(`var')
    }
    // Position-metric outcomes (from all-authors panel via athr_any merge):
    //   counts: zero-fill (mi means the PI had no papers of that role that year)
    //   means : leave missing when PI publishes nothing that year, so β on the
    //           mean-based outcomes is intensive-margin only (same convention
    //           as avg_num_coathrs).
    if "$POSITION_OUTCOMES_AVAIL" == "1" {
        foreach v in n_first_ppr n_middle_ppr n_last_ppr {
            replace `v' = 0 if mi(`v')
        }
        // Retro-fix for double-counted solo-author papers: in the build.do
        // preceding the 2026-07-10 fix, solo papers had paper_is_first == 1
        // AND paper_is_last == 1. The excess (which_first + n_middle + n_last -
        // ppr_cnt_any) equals n_solo, so we subtract it from n_first to keep
        // the "last/senior" convention consistent. Post-rebuild this line is a
        // no-op (the sum already matches ppr_cnt_any).
        cap confirm variable n_solo_ppr
        if _rc {
            gen n_solo_ppr = n_first_ppr + n_middle_ppr + n_last_ppr - ppr_cnt_any
            replace n_solo_ppr = 0 if n_solo_ppr < 0
            replace n_first_ppr = n_first_ppr - n_solo_ppr
            replace n_first_ppr = 0 if n_first_ppr < 0
        }
        // avg_position, avg_position_rat, avg_team_size_last, avg_team_size_notlast
        // remain missing when no papers of the relevant type exist that year.
    }
    // _notlast = _any - _last is deferred to AFTER the winsorization block
    // below so the diff uses the same p99-capped components that flow into
    // the base and _any regressions. Computing before winsorization would
    // leave the diff carrying raw mega-cite tails while the components are
    // capped — asymmetric outcomes.
    gen pre_ppr_cnt = ppr_cnt if year < 2014
    bys athr_id: egen pre_ppr_cnt_sum = sum(pre_ppr_cnt)
    bys athr_id: egen pre_ppr_cnt_avg = mean(pre_ppr_cnt)
    qui sum pre_ppr_cnt_avg if athr_indicator == 1, d
    drop if pre_ppr_cnt_avg <= r(p5)
    // Median split at PI level (one row per athr_id); save cut into a local
    // because `drop if` below clears r(), which silently made high_pre_ppr = 0
    // for everyone (`x >= .` is FALSE, so all obs became "low").
    qui sum pre_ppr_cnt_sum if athr_indicator == 1, d
    local ppr_cut = r(p50)
    drop if pre_ppr_cnt_sum <= r(p5)
    gen high_pre_ppr = pre_ppr_cnt_sum >= `ppr_cut'
    gen low_pre_ppr  = pre_ppr_cnt_sum <  `ppr_cut'
    // Career age proxy: first year in the all-authors panel (any position),
    // not just first year as last author -- see restrict_samp preserve block.
    gen age_2014 = 2014 - min_year_any + 30
    sum age_2014, d
    local med = r(p50)
    gen young = age_2014 < `med'
    gen old = age_2014 >= `med'
    gen r1 = type == "r1" 
    gen r2 = type == "r2" 
    drop if mi(exposure)  
    drop if mi(mkt_spend_shr) | mkt_spend_shr <= 0
    sum exposure if athr_indicator == 1, d
    gen median = exposure >= r(p50)
    merge 1:1 athr_id year using ../external/coathrs/avg_coathrs, keep(1 3) assert(1 2 3) nogen
    replace avg_num_coathrs = 0 if mi(avg_num_coathrs)
    // Intensive-margin only: team size is undefined in years the PI publishes
    // nothing. Setting to missing means reghdfe/ppmlhdfe drop those rows and
    // β on Z_it is "conditional on publishing, does exposure shift team size,"
    // not confounded by the extensive margin. Report N alongside β so any
    // sample composition shift is visible.
    replace avg_num_coathrs = . if ppr_cnt == 0
    merge 1:1 athr_id year using ../temp/athr_yr_grnt_cnt, keep(1 3) assert(1 2 3) nogen
    replace num_grants = 0 if mi(num_grants)

    // Derived grants outcomes — both sidestep the num_grants mechanical
    // confounding by paper counts flagged in the audit.
    //   grants_per_paper : distinct grants cited per paper in the year;
    //     intensive-margin — β tells you whether each paper cites fewer grants
    //     (e.g. PIs pushed toward unfunded work). Undefined when ppr_cnt == 0.
    //   grant_density    : num_grants scaled by the PI's *pre-period* mean
    //     ppr_cnt (constant per PI). Denominator is fixed pre-2014 so post-
    //     period changes in ppr_cnt do not mechanically move it — β isolates
    //     "given typical output rate, how many grants are now cited."
    gen grants_per_paper = num_grants / ppr_cnt         if ppr_cnt > 0
    gen grant_density    = num_grants / pre_ppr_cnt_avg if pre_ppr_cnt_avg > 0

    gen pre_grants_cnt = num_grants if year < 2014
    bys athr_id: egen pre_grants_sum = total(pre_grants_cnt)
    drop pre_grants_cnt
    // Split on pre-period grants PER PAPER (ratio of totals — robust to years
    // with ppr_cnt == 0). pre_ppr_cnt_sum >= 5 for all remaining PIs after
    // the p5 drop above, so denominator is safe.
    gen pre_gpp = pre_grants_sum / pre_ppr_cnt_sum
    qui sum pre_gpp if athr_indicator == 1, d
    local g_cut = r(p50)
    di as text "restrict_samp `samp'`suf' pre-gpp median = `g_cut'"
    gen high_grants = pre_gpp >= `g_cut'
    gen low_grants  = pre_gpp <  `g_cut'

    // Additional pre-period heterogeneity splits (median splits)
    //   big_team  / small_team    : mean pre-period avg_team_size
    //   many_coauth / few_coauth  : mean pre-period n_coauthors_yr
    //   big_msa   / small_msa     : msa_size at 2014 (metro scientific mass)
    gen pre_team_yr = avg_team_size if year < 2014
    bys athr_id: egen pre_team_avg = mean(pre_team_yr)
    drop pre_team_yr
    qui sum pre_team_avg if athr_indicator == 1, d
    di as text "restrict_samp `samp'`suf' pre-team median = " r(p50)
    gen big_team   = pre_team_avg >= r(p50)
    gen small_team = pre_team_avg <  r(p50)

    gen pre_coauth_yr = n_coauthors_yr if year < 2014
    bys athr_id: egen pre_coauth_avg = mean(pre_coauth_yr)
    drop pre_coauth_yr
    qui sum pre_coauth_avg if athr_indicator == 1, d
    di as text "restrict_samp `samp'`suf' pre-n-coauth median = " r(p50)
    gen many_coauth = pre_coauth_avg >= r(p50)
    gen few_coauth  = pre_coauth_avg <  r(p50)

    gen msa_size_2014 = msa_size if year == 2014
    bys athr_id: egen msa_size_at = max(msa_size_2014)
    drop msa_size_2014
    qui sum msa_size_at if athr_indicator == 1, d
    di as text "restrict_samp `samp'`suf' msa_size median = " r(p50)
    gen big_msa   = msa_size_at >= r(p50)
    gen small_msa = msa_size_at <  r(p50)

    // Winsorize cite_affl_wt / affl_wt at pooled p99 to cap mega-cite outliers
    // (e.g. A5001670387 hit cite_affl_wt=1092 in 2016 vs a p99 ~25).
    // Same treatment for the _any counterparts so the two versions of each
    // outcome are affected symmetrically.
    foreach v in cite_affl_wt affl_wt cite_affl_wt_any affl_wt_any {
        qui sum `v', d
        local p99_`v' = r(p99)
        replace `v' = `p99_`v'' if `v' > `p99_`v'' & !mi(`v')
        di as text "restrict_samp `samp'`suf' winsorized `v' at p99=`p99_`v''"
    }

    // _notlast = _any - _last, computed on the winsorized components so all
    // three flavors (last / any / notlast) sit on the same scale.
    // Interpretation: β on _notlast tells you whether the PI's collaboration
    // participation moved; a big drop in _last with flat _notlast says the PI
    // is losing senior-role papers but not the ones they contribute to as a
    // middle author.
    gen ppr_cnt_notlast      = ppr_cnt_any      - ppr_cnt
    gen cite_affl_wt_notlast = cite_affl_wt_any - cite_affl_wt
    gen affl_wt_notlast      = affl_wt_any      - affl_wt
    // Floor at zero — even after winsorization the diff can go slightly
    // negative when the p99 cap for _any lands below the raw last value.
    foreach v in ppr_cnt_notlast cite_affl_wt_notlast affl_wt_notlast {
        replace `v' = 0 if `v' < 0
    }
    // p99-cap the diff for symmetry with the base and _any outcomes.
    foreach v in cite_affl_wt_notlast affl_wt_notlast {
        qui sum `v', d
        local p99_`v' = r(p99)
        replace `v' = `p99_`v'' if `v' > `p99_`v'' & !mi(`v')
        di as text "restrict_samp `samp'`suf' winsorized `v' at p99=`p99_`v''"
    }

    // -- Institutional-characteristic heterogeneity ---------------------------
    // Merge 30 pre-period university characteristics (HERD funding buckets +
    // expenditures + endowment) keyed on OpenAlex inst_id. inst_id is constant
    // per PI in this panel, so m:1 is safe and each ic_ variable is PI-constant.
    // Then build both a median split (hi_/lo_) and a quartile split
    // (q1_/mid_/q4_) at the PI level, dropping PIs with missing value only from
    // that dimension (dummies set to missing => obs drop from the fit for that
    // regression, panel-wide N unchanged).
    merge m:1 inst_id using ../temp/inst_chars_pre, keep(1 3) nogen
    foreach a of global IC_ALIASES {
        cap confirm variable ic_`a'
        if _rc continue
        qui sum ic_`a' if athr_indicator == 1, d
        local ic_n = r(N)
        local ic_p50 = r(p50)
        local ic_p25 = r(p25)
        local ic_p75 = r(p75)
        di as text "restrict_samp `samp'`suf' ic_`a' N_pi=`ic_n' p25=`ic_p25' p50=`ic_p50' p75=`ic_p75'"
        gen byte hi_`a'  = ic_`a' >= `ic_p50' if !mi(ic_`a')
        gen byte lo_`a'  = ic_`a' <  `ic_p50' if !mi(ic_`a')
        gen byte q1_`a'  = ic_`a' <= `ic_p25' if !mi(ic_`a')
        gen byte q4_`a'  = ic_`a' >= `ic_p75' if !mi(ic_`a')
        gen byte mid_`a' = (ic_`a' > `ic_p25' & ic_`a' < `ic_p75') if !mi(ic_`a')
    }

    // -- PI-level continuous quartile splits ----------------------------------
    // Same three-group parameterization as inst-char quartile splits.
    // Median counterparts (high_/low_/big_/small_/many_/few_) already exist above.
    // Base var mapping:
    //   pre_ppr <- pre_ppr_cnt_sum   grants <- pre_gpp
    //   team    <- pre_team_avg      coauth <- pre_coauth_avg   msa <- msa_size_at
    local pi_q_source pre_ppr_cnt_sum pre_gpp pre_team_avg pre_coauth_avg msa_size_at
    local pi_q_alias  pre_ppr        grants  team         coauth         msa
    local nq : word count `pi_q_alias'
    forvalues i = 1/`nq' {
        local src : word `i' of `pi_q_source'
        local alias : word `i' of `pi_q_alias'
        qui sum `src' if athr_indicator == 1, d
        local p25 = r(p25)
        local p75 = r(p75)
        di as text "restrict_samp `samp'`suf' `alias' p25=`p25' p75=`p75'"
        gen byte q1_`alias'  = `src' <= `p25' if !mi(`src')
        gen byte q4_`alias'  = `src' >= `p75' if !mi(`src')
        gen byte mid_`alias' = (`src' > `p25' & `src' < `p75') if !mi(`src')
    }

    assert !mi(athr_id)
    assert !mi(exposure)
    assert !mi(mkt_spend_shr)
    save ../temp/es_`samp'`suf', replace
end

program event_study
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    // Fixed-effect choice driven by $FE_MODE. int_lead1 (and heterogeneity variants) is
    // never included in the regressor list — under FE_MODE=author it would be dropped
    // via collinearity with athr_id FE; under FE_MODE=inst_cluster it must be omitted
    // manually so that rel = -1 remains the reference year.
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
    // Max-sim weighting: `wt' goes on every reghdfe/ppmlhdfe call, `wsuf' on
    // every graph export / .dta save so the weighted and unweighted output
    // files coexist.
    local wt ""
    local wsuf ""
    if "$WEIGHT_MSIM" == "1" {
        // Weight-type notes:
        //   `wt' = [pw=max_sim]  — reghdfe/ppmlhdfe accept pw; ppmlhdfe rejects aw
        //   `wt_bin' = [aw=max_sim] — binscatter accepts only aw / fw, not pw
        // WLS coefficients are identical under aw vs pw (SEs are handled by
        // vce(cluster) anyway), so mixing the two doesn't change anything
        // substantively — it just gets past each command's accepted weight type.
        local wt "[pw=max_sim]"
        local wt_bin "[aw=max_sim]"
        local wsuf "_msimwt"
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
    qui sum rel, d
    local abs_lead = abs(r(min))
    local timeframe = max(`abs_lag', `abs_lead')
    forval i = 1/`timeframe' {
        gen int_lag`i' = exposure if rel == `i'
        gen int_lead`i' = exposure if rel == -`i'
        gen lag`i' = 1 if rel == `i'
        gen lead`i' = 1 if rel == -`i'
        gen mshr_lag`i'  = mkt_spend_shr if rel == `i'
        gen mshr_lead`i' = mkt_spend_shr if rel == -`i'
    }
    gen int_lag0 = exposure if rel == 0
    gen lag0 = 1 if rel == 0
    gen mshr_lag0 = mkt_spend_shr if rel == 0
    ds lead* lag* int_lead* int_lag* mshr_lead* mshr_lag*
    foreach var in `r(varlist)' {
        replace `var' = 0 if mi(`var')
    }
    local leads
    local int_leads
    local mshr_leads
    local lags
    local int_lags
    local mshr_lags
    forval i = 2/`abs_lead' {
        local leads lead`i' `leads'
        local int_leads int_lead`i' `int_leads'
        local mshr_leads mshr_lead`i' `mshr_leads'
    }
    forval i = 0/`abs_lag' {
        local lags `lags' lag`i'
        local int_lags `int_lags' int_lag`i'
        local mshr_lags `mshr_lags' mshr_lag`i'
    }
    foreach v in ppr_cnt cite_affl_wt ppr_cnt_any cite_affl_wt_any ///
                 ppr_cnt_notlast cite_affl_wt_notlast {
        gen ln_`v' = ln(1+`v')
    }

    // pre-build group-suffixed event-time interactions for heterogeneity (used in pooled-interaction regressions below).
    // For each group build both exposure-based (int_*) and mkt_spend_shr-based (mshr_*) interactions, so
    // every heterogeneity spec below can be run twice: base and with sum-of-shares controls.
    //
    // $HET_GROUPS is the master list of all group dummies feeding heterogeneity
    // specs. Existing 14 PI-level (median + binary categorical) groups, plus
    // all inst-char and PI-continuous quartile-split groups built in restrict_samp.
    // Groups whose dummy is all-missing or degenerate (all 0 or all 1) are
    // silently skipped — this shields the inst-char specs from ipeds ids that
    // never appear in the panel or that don't have enough non-missing PIs to
    // form a median/quartile split.
    local het_groups young old r1 r2 high_pre_ppr low_pre_ppr high_grants low_grants ///
                     big_team small_team many_coauth few_coauth big_msa small_msa
    foreach a of global IC_ALIASES {
        local het_groups `het_groups' hi_`a' lo_`a' q1_`a' mid_`a' q4_`a'
    }
    foreach b of global PI_Q_BASES {
        local het_groups `het_groups' q1_`b' mid_`b' q4_`b'
    }
    global HET_GROUPS_ACTIVE
    foreach grp of local het_groups {
        cap confirm variable `grp'
        if _rc {
            di as text "restrict_samp `samp'`suf': dummy `grp' not built — skipping interactions."
            continue
        }
        qui sum `grp'
        if r(N) == 0 | r(min) == r(max) {
            di as text "restrict_samp `samp'`suf': dummy `grp' degenerate (N=" r(N) " min=" r(min) " max=" r(max) ") — skipping."
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
        gen mshr_lead1_`grp' = mshr_lead1 * `grp'
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

    local position_outcomes ""
    if "$POSITION_OUTCOMES_AVAIL" == "1" {
        local position_outcomes n_first_ppr n_middle_ppr n_last_ppr ///
            avg_position avg_position_rat avg_team_size_last avg_team_size_notlast
    }

    // PPML heterogeneity results collector: one row per (yvar, grp, spec) written
    // by the PPML het block inside the yvar loop below. Kept as a dta rather
    // than named matrices to avoid Stata's 32-char matrix-name limit
    // (e.g. phet_cite_affl_wt_notlast_high_pre_ppr_mshrctrl = 47 chars).
    // output_tables and ppml_het_coefplot consume ../temp/phet_results_<samp>...dta.
    tempname ph_handle
    postfile `ph_handle' str30 yvar str24 grp str12 spec str8 split_type ///
        double(post_b post_se pre_b pre_se N r2_p) ///
        using "../temp/phet_results_`samp'`suf'`wsuf'", replace

    foreach yvar in ppr_cnt cite_affl_wt ln_ppr_cnt ln_cite_affl_wt ///
                    ppr_cnt_any cite_affl_wt_any ln_ppr_cnt_any ln_cite_affl_wt_any ///
                    ppr_cnt_notlast cite_affl_wt_notlast ln_ppr_cnt_notlast ln_cite_affl_wt_notlast ///
                    avg_num_coathrs num_grants grants_per_paper grant_density ///
                    `position_outcomes' {
        if "`yvar'" == "ln_spend" local var_name = "Log Spending"
        if "`yvar'" == "ln_spend" local gap  0.5
        if "`yvar'" == "cite_affl_wt" local var_name = "Citation Weighted Output"
        if "`yvar'" == "cite_affl_wt" local gap  1
        if "`yvar'" == "ppr_cnt" local var_name = "Publication Count"
        if "`yvar'" == "ppr_cnt" local gap 0.5
        if "`yvar'" == "ln_ppr_cnt"      local var_name = "Log Publication Counts"
        if "`yvar'" == "ln_ppr_cnt"      local gap 0.1
        if "`yvar'" == "ln_cite_affl_wt" local var_name = "Log Citation Weighted Output"
        if "`yvar'" == "ln_cite_affl_wt" local gap 0.1
        if "`yvar'" == "ppr_cnt"      & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "cite_affl_wt" & "`samp'" == "top_jrnls" local gap 2
        // _any = papers where the PI is at any authorship position (not just last).
        // _notlast = _any - _last = papers where PI is first / middle author.
        if "`yvar'" == "ppr_cnt_any"         local var_name = "Publication Count (any position)"
        if "`yvar'" == "ppr_cnt_any"         local gap 0.5
        if "`yvar'" == "cite_affl_wt_any"    local var_name = "Citation Weighted Output (any position)"
        if "`yvar'" == "cite_affl_wt_any"    local gap 1
        if "`yvar'" == "ln_ppr_cnt_any"      local var_name = "Log Publication Counts (any position)"
        if "`yvar'" == "ln_ppr_cnt_any"      local gap 0.1
        if "`yvar'" == "ln_cite_affl_wt_any" local var_name = "Log Citation Weighted Output (any position)"
        if "`yvar'" == "ln_cite_affl_wt_any" local gap 0.1
        if "`yvar'" == "ppr_cnt_any"         & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "cite_affl_wt_any"    & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "ppr_cnt_notlast"         local var_name = "Publication Count (non-last author)"
        if "`yvar'" == "ppr_cnt_notlast"         local gap 0.5
        if "`yvar'" == "cite_affl_wt_notlast"    local var_name = "Citation Weighted Output (non-last author)"
        if "`yvar'" == "cite_affl_wt_notlast"    local gap 1
        if "`yvar'" == "ln_ppr_cnt_notlast"      local var_name = "Log Publication Counts (non-last author)"
        if "`yvar'" == "ln_ppr_cnt_notlast"      local gap 0.1
        if "`yvar'" == "ln_cite_affl_wt_notlast" local var_name = "Log Citation Weighted Output (non-last author)"
        if "`yvar'" == "ln_cite_affl_wt_notlast" local gap 0.1
        if "`yvar'" == "ppr_cnt_notlast"         & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "cite_affl_wt_notlast"    & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "avg_num_coathrs"   local var_name = "Average Team Size"
        if "`yvar'" == "avg_num_coathrs"   local gap 0.5
        if "`yvar'" == "num_grants"        local var_name = "Number of Grants"
        if "`yvar'" == "num_grants"        local gap 0.5
        if "`yvar'" == "grants_per_paper"  local var_name = "Grants per Paper (num_grants / ppr_cnt)"
        if "`yvar'" == "grants_per_paper"  local gap 0.5
        if "`yvar'" == "grant_density"     local var_name = "Grant Density (num_grants / pre-period avg ppr)"
        if "`yvar'" == "grant_density"     local gap 0.5
        // Position-metric labels (only used when POSITION_OUTCOMES_AVAIL == 1)
        if "`yvar'" == "n_first_ppr"           local var_name = "# First-Author Papers"
        if "`yvar'" == "n_first_ppr"           local gap 0.5
        if "`yvar'" == "n_middle_ppr"          local var_name = "# Middle-Author Papers"
        if "`yvar'" == "n_middle_ppr"          local gap 0.5
        if "`yvar'" == "n_last_ppr"            local var_name = "# Last-Author Papers"
        if "`yvar'" == "n_last_ppr"            local gap 0.5
        if "`yvar'" == "avg_position"          local var_name = "Avg Author Position (1=first, N=last)"
        if "`yvar'" == "avg_position"          local gap 0.5
        if "`yvar'" == "avg_position_rat"      local var_name = "Avg Author Position / Team Size (0-1)"
        if "`yvar'" == "avg_position_rat"      local gap 0.05
        if "`yvar'" == "avg_team_size_last"    local var_name = "Team Size (papers where PI is last)"
        if "`yvar'" == "avg_team_size_last"    local gap 0.5
        if "`yvar'" == "avg_team_size_notlast" local var_name = "Team Size (papers where PI is not last)"
        if "`yvar'" == "avg_team_size_notlast" local gap 0.5
        local poisson_name "`var_name'"
        if "`yvar'" == "ppr_cnt"              local poisson_name "Publications"
        if "`yvar'" == "cite_affl_wt"         local poisson_name "Citation-Weighted Output"
        if "`yvar'" == "ppr_cnt_any"          local poisson_name "Publications (any position)"
        if "`yvar'" == "cite_affl_wt_any"     local poisson_name "Citation-Weighted Output (any position)"
        if "`yvar'" == "ppr_cnt_notlast"      local poisson_name "Publications (non-last author)"
        if "`yvar'" == "cite_affl_wt_notlast" local poisson_name "Citation-Weighted Output (non-last author)"
        if "`yvar'" == "avg_num_coathrs"      local poisson_name "Coauthors"
        if "`yvar'" == "num_grants"           local poisson_name "Grants"
        if "`yvar'" == "grants_per_paper"     local poisson_name "Grants per Paper"
        if "`yvar'" == "grant_density"        local poisson_name "Grant Density"

        preserve
        cap mat drop es
        sum `yvar' if rel <= -1 & exposure > 0, d
        local pre_mean : dis %4.3f r(mean)
        gunique athr_id
        local num_athrs = r(unique)
        gunique inst_id
        local num_insts = r(unique)
        cap noi reghdfe `yvar' `int_leads' `int_lags' `wt', absorb(`fes') vce(cluster `vce_cl')
        if _rc {
            di as error "event_study `samp'`suf' `yvar' base failed (rc=`_rc'); skipping this outcome."
            restore
            continue
        }
        foreach var in `int_leads' `int_lags' int_lead1 {
            if "`var'" == "int_lead1" {
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
        local ymax =round(r(max),`gap')
        gen lb = b - 1.96*se
        sum lb, d
        local ymin = min(-2.5,round(r(min),`gap'))
        if inlist("`yvar'", "ln_ppr_cnt", "ln_cite_affl_wt") local ymin = -1
        gen rel = -4 if _n == 1
        replace rel = rel[_n-1]+1 if _n > 1
        replace rel = rel + 1 if rel >= -1
        replace rel = -1 if rel == `abs_lag' + 1
        gen year = rel + 2014
        hashsort rel
        tw rcap ub lb year if year != 2013 , lcolor(ebblue%70) msize(vsmall) || ///
          scatter b year, mcolor(ebblue) || ///
          scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
          xlab(2010(1)2019) xtitle("Year") ///
          ytitle("`var_name'") ylab(`ymin'(`gap')`ymax') ///
          yline(0, lcolor(gs10) lpattern(solid)) ///
          legend(on order(- "Num. PIs: `num_athrs'" "Num. Institutions: `num_insts'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) plotregion(margin(sides))
        graph export ../output/figures/`samp'/es_`yvar'`suf'`wsuf'.pdf, replace
        save ../temp/es_`yvar'`wsuf', replace
        restore

        // alternative spec: control for mkt_spend_shr x rel-year dummies
        preserve
        cap mat drop es
        cap noi reghdfe `yvar' `int_leads' `int_lags' `mshr_leads' `mshr_lags' `wt', ///
                       absorb(`fes') vce(cluster `vce_cl')
        if _rc {
            di as error "event_study `samp'`suf' `yvar' mshrctrl failed (rc=`_rc'); skipping mshrctrl plot."
            restore
            // Skip only the mshrctrl plot; PPML and heterogeneity blocks below will try independently.
        }
        else {
        foreach var in `int_leads' `int_lags' int_lead1 {
            if "`var'" == "int_lead1" {
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
        local ymin = min(-2.5,round(r(min),`gap'))
        if inlist("`yvar'", "ln_ppr_cnt", "ln_cite_affl_wt") local ymin = -1
        gen rel = -4 if _n == 1
        replace rel = rel[_n-1]+1 if _n > 1
        replace rel = rel + 1 if rel >= -1
        replace rel = -1 if rel == `abs_lag' + 1
        gen year = rel + 2014
        hashsort rel
        tw rcap ub lb year if year != 2013 , lcolor(ebblue%70) msize(vsmall) || ///
          scatter b year, mcolor(ebblue) || ///
          scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
          xlab(2010(1)2019) xtitle("Year") ///
          ytitle("`var_name'") ylab(`ymin'(`gap')`ymax') ///
          yline(0, lcolor(gs10) lpattern(solid)) ///
          legend(on order(- "Num. PIs: `num_athrs'" "Num. Institutions: `num_insts'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) plotregion(margin(sides))
        graph export ../output/figures/`samp'/es_`yvar'`suf'_mshrctrl`wsuf'.pdf, replace
        save ../temp/es_`yvar'`suf'_mshrctrl`wsuf', replace
        restore
        }

        // Poisson (ppmlhdfe) version — skip already-logged outcomes; coefs are semielasticities
        if !regexm("`yvar'", "^ln_") {
            foreach spec in base mshrctrl {
                preserve
                cap mat drop es
                if "`spec'" == "base" {
                    cap noi ppmlhdfe `yvar' `int_leads' `int_lags' `wt', ///
                            absorb(`fes') vce(cluster `vce_cl')
                }
                else {
                    cap noi ppmlhdfe `yvar' `int_leads' `int_lags' ///
                                           `mshr_leads' `mshr_lags' `wt', ///
                            absorb(`fes') vce(cluster `vce_cl')
                }
                if _rc {
                    di as error "ppmlhdfe `yvar' `spec' failed (rc=`_rc'); skipping plot."
                    restore
                    continue
                }
                foreach var in `int_leads' `int_lags' int_lead1 {
                    if "`var'" == "int_lead1" {
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
                gen rel = -4 if _n == 1
                replace rel = rel[_n-1]+1 if _n > 1
                replace rel = rel + 1 if rel >= -1
                replace rel = -1 if rel == `abs_lag' + 1
                gen year = rel + 2014
                hashsort rel
                local plot_suf "_ppml"
                if "`spec'" == "mshrctrl" local plot_suf "_ppml_mshrctrl"
                tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
                  scatter b year, mcolor(ebblue) || ///
                  scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                  xlab(2010(1)2019) xtitle("Year") ///
                  ytitle("{&Delta} Log Expected `poisson_name'") ylab(`ymin'(0.1)`ymax') ///
                  yline(0, lcolor(gs10) lpattern(solid)) ///
                  legend(on order(- "Num. PIs: `num_athrs'" "Num. Institutions: `num_insts'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) plotregion(margin(sides))
                graph export ../output/figures/`samp'/es_`yvar'`suf'`plot_suf'`wsuf'.pdf, replace
                save ../temp/es_`yvar'`suf'`plot_suf'`wsuf', replace
                restore
            }
        }

        // heterogeneity by author & inst characteristics — one regression per dummy pair, split-interaction form.
        // Run twice per pair: base (no mkt-share controls) and mshrctrl (+ mshr x rel-time x group).
        // Three pair-list globals feed the loops below (also used by PPML het):
        //   $DUMMY_PAIRS_MED  : 7 existing PI-level median pairs + 30 IC median pairs
        //   $IC_PAIRS_Q       : 30 inst-char quartile pairs (Q4 vs Q1, mid = nuisance)
        //   $PI_PAIRS_Q       : 5 PI-continuous quartile pairs (same three-group spec)
        // See define_group_labels for construction.
        global DUMMY_PAIRS_MED `" "young old" "r1 r2" "high_pre_ppr low_pre_ppr" "high_grants low_grants" "big_team small_team" "many_coauth few_coauth" "big_msa small_msa" ${IC_PAIRS_MED} "'
        // Runtime saver: OLS heterogeneity runs on the four headline outcomes
        // (publications + citation-weighted output, level and log). PPML het
        // (below) is broader.
        if inlist("`yvar'", "ppr_cnt", "ln_ppr_cnt", "cite_affl_wt", "ln_cite_affl_wt") {
        foreach pair of global DUMMY_PAIRS_MED {
            local g1: word 1 of `pair'
            local g2: word 2 of `pair'
            // Skip pairs whose dummy failed the degeneracy check during the pre-
            // build in restrict_samp (e.g., an ic_ var with no non-missing PIs
            // in this sample). HET_GROUPS_ACTIVE is set in the pre-build loop.
            if strpos(" ${HET_GROUPS_ACTIVE} ", " `g1' ") == 0 continue
            if strpos(" ${HET_GROUPS_ACTIVE} ", " `g2' ") == 0 continue
            // Human-readable label for the g1 (dummy=1) group; used as the
            // plot subtitle so each split PDF is self-describing. Falls back to
            // the group name if no LBL_<g1> global was defined.
            local g1_label = "${LBL_`g1'}"
            if "`g1_label'" == "" local g1_label "`g1'"
            // Base + interaction form: un-interacted int_lead/lag_* absorb the
            // event-time path for the dummy=0 (`g2') group; leads_`g1'/lags_`g1'
            // are the *differential* effect for the dummy=1 group. Only one
            // coefplot per split is saved (the differential), since it already
            // encodes the comparison to the dummy=0 group.
            //
            // For pre-period-baseline splits (high_pre_ppr, high_grants) the
            // median split is mechanically confounded with regression-to-mean.
            // Adding i.year#c.<baseline> lets each year have its own slope on
            // continuous baseline productivity, absorbing the mean-reversion
            // time-path; the surviving `leads_`g1''/`lags_`g1'' is the
            // differential response to treatment net of "big producers
            // naturally fall back."
            local specs base mshrctrl
            local mr_baseline ""
            if "`g1'" == "high_pre_ppr" {
                local specs `specs' mshrctrl_mr
                local mr_baseline pre_ppr_cnt_sum
            }
            if "`g1'" == "high_grants" {
                local specs `specs' mshrctrl_mr
                local mr_baseline pre_gpp
            }
            foreach spec of local specs {
                local mshr_ctrls
                local plot_suf
                local mr_abs
                if "`spec'" == "mshrctrl" | "`spec'" == "mshrctrl_mr" {
                    // un-interacted mshr_lead/lag_* absorbs the base MShr
                    // event-time; mleads_`g1'/mlags_`g1' lets high group have
                    // its own MShr slope
                    local mshr_ctrls `mshr_leads' `mshr_lags' `mleads_`g1'' `mlags_`g1''
                    local plot_suf "_mshrctrl"
                }
                if "`spec'" == "mshrctrl_mr" {
                    local mr_abs i.year#c.`mr_baseline'
                    local plot_suf "_mshrctrl_mr"
                }
                // int_lead1 (rel=-1) omitted for both base and differential —
                // shared reference year.
                cap noi reghdfe `yvar' `int_leads' `int_lags' ///
                               `leads_`g1'' `lags_`g1'' ///
                               `mshr_ctrls' `wt', ///
                               absorb(`fes' `mr_abs') vce(cluster `vce_cl')
                if _rc {
                    di as error "event_study `samp'`suf' `yvar' `g1' `spec' failed (rc=`_rc'); skipping."
                    continue
                }

                // Extract the differential coefficients (only the `g1'-suffixed
                // ones); int_lead1_`g1' is the rel=-1 reference and pinned to 0.
                sum `yvar' if rel <= -1 & exposure > 0 & `g1' == 1, d
                local pre_mean : dis %4.3f r(mean)
                gunique athr_id if exposure > 0 & `g1' == 1
                local num_athrs = r(unique)
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
                if inlist("`yvar'", "ln_ppr_cnt", "ln_cite_affl_wt") local ymin = -1
                gen rel = -4 if _n == 1
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
                  legend(on order(- "Num. PIs: `num_athrs'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) ///
                  yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
                graph export ../output/figures/`samp'/es_`yvar'`suf'_`g1'`plot_suf'`wsuf'.pdf, replace
                save ../temp/es_`yvar'`suf'_`g1'`plot_suf'`wsuf', replace
                restore
            }
        }

        // ---- OLS heterogeneity: quartile split (Q1 vs Q4, mid = Q2 U Q3 as nuisance).
        //   reghdfe y  int_leads int_lags  leads_q4 lags_q4  leads_mid lags_mid  [mshr]
        // Q1 is absorbed by the un-interacted int_leads/int_lags (same "base +
        // interaction" pattern as the median loop); leads_q4 / lags_q4 are the
        // Q4-Q1 differential (what gets plotted); leads_mid / lags_mid are
        // nuisance interactions that keep mid PIs contributing to the FEs
        // without contaminating the Q4-Q1 contrast. Iterates over inst-char
        // quartile pairs (${IC_PAIRS_Q}) + PI-continuous quartile pairs
        // (${PI_PAIRS_Q}). Coefplot suffix "_q4vsq1" distinguishes from the
        // median-split PDFs written above.
        foreach pair of global IC_PAIRS_Q {
            local quart_pairs_all `"`quart_pairs_all' `"`pair'"' "'
        }
        foreach pair of global PI_PAIRS_Q {
            local quart_pairs_all `"`quart_pairs_all' `"`pair'"' "'
        }
        foreach pair of local quart_pairs_all {
            local g1: word 1 of `pair'  // "q4_<x>" — focal / plotted
            local g2: word 2 of `pair'  // "q1_<x>" — base (absorbed by un-interacted int_*)
            // Recover the mid group name from g1 (strip "q4_" and prepend "mid_").
            local base = substr("`g1'", 4, .)
            local gm = "mid_`base'"
            if strpos(" ${HET_GROUPS_ACTIVE} ", " `g1' ") == 0 continue
            if strpos(" ${HET_GROUPS_ACTIVE} ", " `g2' ") == 0 continue
            if strpos(" ${HET_GROUPS_ACTIVE} ", " `gm' ") == 0 continue
            local g1_label = "${LBL_`g1'}"
            if "`g1_label'" == "" local g1_label "`g1'"
            local specs base mshrctrl
            foreach spec of local specs {
                local mshr_ctrls
                local plot_suf "_q4vsq1"
                if "`spec'" == "mshrctrl" {
                    local mshr_ctrls `mshr_leads' `mshr_lags' `mleads_`g1'' `mlags_`g1'' `mleads_`gm'' `mlags_`gm''
                    local plot_suf "_q4vsq1_mshrctrl"
                }
                cap noi reghdfe `yvar' `int_leads' `int_lags' ///
                               `leads_`g1'' `lags_`g1'' ///
                               `leads_`gm'' `lags_`gm'' ///
                               `mshr_ctrls' `wt', ///
                               absorb(`fes') vce(cluster `vce_cl')
                if _rc {
                    di as error "event_study `samp'`suf' `yvar' `g1' quart `spec' failed (rc=`_rc'); skipping."
                    continue
                }
                sum `yvar' if rel <= -1 & exposure > 0 & `g1' == 1, d
                local pre_mean : dis %4.3f r(mean)
                gunique athr_id if exposure > 0 & `g1' == 1
                local num_athrs = r(unique)
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
                if inlist("`yvar'", "ln_ppr_cnt", "ln_cite_affl_wt") local ymin = -1
                gen rel = -4 if _n == 1
                replace rel = rel[_n-1]+1 if _n > 1
                replace rel = rel + 1 if rel >= -1
                replace rel = -1 if rel == `abs_lag' + 1
                gen year = rel + 2014
                hashsort rel
                tw rcap ub lb year if year != 2013 , lcolor(cranberry%70) msize(vsmall) || ///
                  scatter b year, mcolor(cranberry) || ///
                scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                  xlab(2010(1)2019, labsize(small)) xtitle("Year") ///
                  ytitle("Q4-Q1 Diff (Exposure x Post)") ylab(`ymin'(`gap')`ymax') ///
                  subtitle("`g1_label' vs Q1", pos(11) size(small)) ///
                  legend(on order(- "Num. PIs (Q4): `num_athrs'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) ///
                  yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
                graph export ../output/figures/`samp'/es_`yvar'`suf'_`g1'`plot_suf'`wsuf'.pdf, replace
                save ../temp/es_`yvar'`suf'_`g1'`plot_suf'`wsuf', replace
                restore
            }
        }
        local quart_pairs_all
        }  // closes OLS-only inlist gate

        // ---- PPML heterogeneity: split-form spec matching ppml_pdid_het_binscatter.
        //   ppmlhdfe y  leads_g1 lags_g1  leads_g2 lags_g2  [mshr_g1 mshr_g2]
        // Under this parameterization there is no un-interacted base and
        // g1 + g2 = 1 for every observation, so `_b[lags_g1_k]` is the LEVEL
        // of the event-time effect for the g1 subgroup (not a differential
        // vs g2). Post one row per (yvar, g, spec) — g takes both sides of
        // each pair, so the coefplot below can compare g1 and g2 head-to-head.
        //
        // Runs for all PPML-eligible outcomes under mshrctrl; adds `base` for
        // ppr_cnt (backwards-compat with the older single-outcome block).
        // Skipped for already-logged (ln_*) outcomes (PPML on log outcomes is
        // nonsense) and for average-based outcomes (avg_*), which are
        // conditional means, not counts. mshrctrl_mr also skipped —
        // mean-reversion i.year#c.baseline is an OLS-only diagnostic and its
        // interpretation in the Poisson link is opaque.
        // Per-group event-time PDFs only generated for ppr_cnt to keep runtime
        // bounded.
        local ppml_het_skip ln_ppr_cnt ln_cite_affl_wt ln_ppr_cnt_any ln_cite_affl_wt_any ln_ppr_cnt_notlast ln_cite_affl_wt_notlast avg_position avg_position_rat avg_team_size_last avg_team_size_notlast
        if strpos(" `ppml_het_skip' ", " `yvar' ") == 0 {
            foreach pair of global DUMMY_PAIRS_MED {
                local g1: word 1 of `pair'
                local g2: word 2 of `pair'
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `g1' ") == 0 continue
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `g2' ") == 0 continue
                local ppml_specs mshrctrl
                if "`yvar'" == "ppr_cnt" local ppml_specs base mshrctrl
                foreach spec of local ppml_specs {
                    local mshr_ctrls
                    local plot_suf "_ppml"
                    if "`spec'" == "mshrctrl" {
                        local mshr_ctrls `mleads_`g1'' `mlags_`g1'' `mleads_`g2'' `mlags_`g2''
                        local plot_suf "_ppml_mshrctrl"
                    }
                    cap noi ppmlhdfe `yvar' `leads_`g1'' `lags_`g1'' `leads_`g2'' `lags_`g2'' ///
                                   `mshr_ctrls' `wt', ///
                                   absorb(`fes') vce(cluster `vce_cl')
                    if _rc {
                        di as error "event_study `samp'`suf' `yvar' `g1'/`g2' ppml `spec' failed (rc=`_rc'); skipping."
                        continue
                    }
                    local Nppml = e(N)
                    local r2ppml = e(r2_p)

                    foreach grp in `g1' `g2' {
                        // Human-readable label for this group side (used as
                        // subtitle on the per-group event-time PDF below).
                        // Falls back to the group name if no LBL_<grp> was set.
                        local grp_label = "${LBL_`grp'}"
                        if "`grp_label'" == "" local grp_label "`grp'"

                        sum `yvar' if rel <= -1 & exposure > 0 & `grp' == 1, d
                        local pre_mean : dis %4.3f r(mean)
                        gunique athr_id if exposure > 0 & `grp' == 1
                        local num_athrs = r(unique)

                        // Pooled post- and pre-averages of the group's
                        // event-time β via lincom on the fitted model. Post =
                        // mean of int_lag0..lag(abs_lag) coefs for the group;
                        // pre = mean of the included leads (int_lead2..
                        // lead(abs_lead)) since lead1 is the omitted reference.
                        local n_post = `abs_lag' + 1
                        local n_pre  = `abs_lead' - 1
                        local sum_post
                        foreach v of local lags_`grp' {
                            local sum_post `sum_post' + `v'
                        }
                        local sum_post = substr("`sum_post'", 3, .)
                        local sum_pre
                        foreach v of local leads_`grp' {
                            local sum_pre `sum_pre' + `v'
                        }
                        local sum_pre = substr("`sum_pre'", 3, .)

                        local b_post = .
                        local se_post = .
                        local b_pre = .
                        local se_pre = .
                        cap qui lincom (`sum_post') / `n_post'
                        if _rc == 0 {
                            local b_post = r(estimate)
                            local se_post = r(se)
                        }
                        cap qui lincom (`sum_pre') / `n_pre'
                        if _rc == 0 {
                            local b_pre = r(estimate)
                            local se_pre = r(se)
                        }

                        di as text "ppml het `samp'`suf' `yvar' `grp' `spec': post_avg=" %8.4f `b_post' ///
                            " (se=" %8.4f `se_post' ")   pre_avg=" %8.4f `b_pre' ///
                            " (se=" %8.4f `se_pre' ")   N=" %9.0f `Nppml'

                        post `ph_handle' ("`yvar'") ("`grp'") ("`spec'") ("med") ///
                            (`b_post') (`se_post') (`b_pre') (`se_pre') (`Nppml') (`r2ppml')

                        // Per-group event-time PDF only for ppr_cnt (runtime + volume)
                        if "`yvar'" != "ppr_cnt" continue
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
                        gen rel = -4 if _n == 1
                        replace rel = rel[_n-1]+1 if _n > 1
                        replace rel = rel + 1 if rel >= -1
                        replace rel = -1 if rel == `abs_lag' + 1
                        gen year = rel + 2014
                        hashsort rel
                        tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
                          scatter b year, mcolor(ebblue) || ///
                        scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                          xlab(2010(1)2019, labsize(small)) xtitle("Year") ///
                          ytitle("Exposure x Post") ylab(`ymin'(0.1)`ymax') ///
                          subtitle("`grp_label'", pos(11) size(small)) ///
                          legend(on order(- "Num. PIs: `num_athrs'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) ///
                          yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
                        graph export ../output/figures/`samp'/es_`yvar'`suf'_`grp'`plot_suf'`wsuf'.pdf, replace
                        save ../temp/es_`yvar'`suf'_`grp'`plot_suf'`wsuf', replace
                        restore
                    }
                }
            }

            // ---- PPML heterogeneity: quartile split (three-group full-sample
            // interaction). Fit is:
            //   ppmlhdfe y  leads_q1 lags_q1  leads_mid lags_mid  leads_q4 lags_q4  [mshr]
            // Since q1 + mid + q4 = 1 for every observed obs, each side gets its
            // own LEVEL β for that subgroup. We extract q1 and q4 β's (skip mid —
            // nuisance) and post both to phet_results with split_type = "quart".
            // Per-group event-time PDFs written only for ppr_cnt.
            local quart_all
            foreach pair of global IC_PAIRS_Q {
                local quart_all `"`quart_all' `"`pair'"' "'
            }
            foreach pair of global PI_PAIRS_Q {
                local quart_all `"`quart_all' `"`pair'"' "'
            }
            foreach pair of local quart_all {
                local g1: word 1 of `pair'  // "q4_<x>"
                local g2: word 2 of `pair'  // "q1_<x>"
                local base = substr("`g1'", 4, .)
                local gm = "mid_`base'"
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `g1' ") == 0 continue
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `g2' ") == 0 continue
                if strpos(" ${HET_GROUPS_ACTIVE} ", " `gm' ") == 0 continue
                local ppml_specs mshrctrl
                if "`yvar'" == "ppr_cnt" local ppml_specs base mshrctrl
                foreach spec of local ppml_specs {
                    local mshr_ctrls
                    local plot_suf "_ppml_q"
                    if "`spec'" == "mshrctrl" {
                        local mshr_ctrls `mleads_`g1'' `mlags_`g1'' ///
                                         `mleads_`g2'' `mlags_`g2'' ///
                                         `mleads_`gm'' `mlags_`gm''
                        local plot_suf "_ppml_q_mshrctrl"
                    }
                    cap noi ppmlhdfe `yvar' `leads_`g1'' `lags_`g1'' ///
                                            `leads_`g2'' `lags_`g2'' ///
                                            `leads_`gm'' `lags_`gm'' ///
                                            `mshr_ctrls' `wt', ///
                                            absorb(`fes') vce(cluster `vce_cl')
                    if _rc {
                        di as error "event_study `samp'`suf' `yvar' `g1'/`g2' ppml quart `spec' failed (rc=`_rc'); skipping."
                        continue
                    }
                    local Nppml = e(N)
                    local r2ppml = e(r2_p)

                    foreach grp in `g1' `g2' {
                        local grp_label = "${LBL_`grp'}"
                        if "`grp_label'" == "" local grp_label "`grp'"
                        sum `yvar' if rel <= -1 & exposure > 0 & `grp' == 1, d
                        local pre_mean : dis %4.3f r(mean)
                        gunique athr_id if exposure > 0 & `grp' == 1
                        local num_athrs = r(unique)

                        local n_post = `abs_lag' + 1
                        local n_pre  = `abs_lead' - 1
                        local sum_post
                        foreach v of local lags_`grp' {
                            local sum_post `sum_post' + `v'
                        }
                        local sum_post = substr("`sum_post'", 3, .)
                        local sum_pre
                        foreach v of local leads_`grp' {
                            local sum_pre `sum_pre' + `v'
                        }
                        local sum_pre = substr("`sum_pre'", 3, .)

                        local b_post = .
                        local se_post = .
                        local b_pre = .
                        local se_pre = .
                        cap qui lincom (`sum_post') / `n_post'
                        if _rc == 0 {
                            local b_post = r(estimate)
                            local se_post = r(se)
                        }
                        cap qui lincom (`sum_pre') / `n_pre'
                        if _rc == 0 {
                            local b_pre = r(estimate)
                            local se_pre = r(se)
                        }

                        di as text "ppml het `samp'`suf' `yvar' `grp' quart `spec': post_avg=" %8.4f `b_post' ///
                            " (se=" %8.4f `se_post' ")   pre_avg=" %8.4f `b_pre' ///
                            " (se=" %8.4f `se_pre' ")   N=" %9.0f `Nppml'

                        post `ph_handle' ("`yvar'") ("`grp'") ("`spec'") ("quart") ///
                            (`b_post') (`se_post') (`b_pre') (`se_pre') (`Nppml') (`r2ppml')

                        // Per-group event-time PDF only for ppr_cnt.
                        if "`yvar'" != "ppr_cnt" continue
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
                        gen rel = -4 if _n == 1
                        replace rel = rel[_n-1]+1 if _n > 1
                        replace rel = rel + 1 if rel >= -1
                        replace rel = -1 if rel == `abs_lag' + 1
                        gen year = rel + 2014
                        hashsort rel
                        tw rcap ub lb year if year != 2013, lcolor(cranberry%70) msize(vsmall) || ///
                          scatter b year, mcolor(cranberry) || ///
                        scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
                          xlab(2010(1)2019, labsize(small)) xtitle("Year") ///
                          ytitle("Exposure x Post") ylab(`ymin'(0.1)`ymax') ///
                          subtitle("`grp_label'", pos(11) size(small)) ///
                          legend(on order(- "Num. PIs: `num_athrs'" "Pre-Period Avg : `pre_mean'") pos(7) ring(1) rows(2) bmargin(zero) size(small)) ///
                          yline(0, lcolor(gs10) lpattern(solid)) plotregion(margin(sides))
                        graph export ../output/figures/`samp'/es_`yvar'`suf'_`grp'`plot_suf'`wsuf'.pdf, replace
                        save ../temp/es_`yvar'`suf'_`grp'`plot_suf'`wsuf', replace
                        restore
                    }
                }
            }
        }
    }
    postclose `ph_handle'
end

program pooled_did
    // pooled DiD: y_it = a_i + g_t + b*(exposure_i x post_t) + e_it
    // matches event-study sample/FE/cluster; gives a single post-period beta with SE.
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
    local wt ""
    local wsuf ""
    if "$WEIGHT_MSIM" == "1" {
        // Weight-type notes:
        //   `wt' = [pw=max_sim]  — reghdfe/ppmlhdfe accept pw; ppmlhdfe rejects aw
        //   `wt_bin' = [aw=max_sim] — binscatter accepts only aw / fw, not pw
        // WLS coefficients are identical under aw vs pw (SEs are handled by
        // vce(cluster) anyway), so mixing the two doesn't change anything
        // substantively — it just gets past each command's accepted weight type.
        local wt "[pw=max_sim]"
        local wt_bin "[aw=max_sim]"
        local wsuf "_msimwt"
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    use ../temp/es_`samp'`suf', clear

    foreach v in cite_affl_wt ppr_cnt cite_affl_wt_any ppr_cnt_any ///
                 cite_affl_wt_notlast ppr_cnt_notlast {
        cap gen ln_`v' = ln(1+`v')
    }

    gen post       = year >= 2014
    gen Z_it       = exposure              * post
    gen Z_share_it = mkt_spend_shr * post

    local position_outcomes ""
    if "$POSITION_OUTCOMES_AVAIL" == "1" {
        local position_outcomes n_first_ppr n_middle_ppr n_last_ppr ///
            avg_position avg_position_rat avg_team_size_last avg_team_size_notlast
    }
    local outcomes cite_affl_wt ppr_cnt ln_cite_affl_wt ln_ppr_cnt ///
                   cite_affl_wt_any ppr_cnt_any ln_cite_affl_wt_any ln_ppr_cnt_any ///
                   cite_affl_wt_notlast ppr_cnt_notlast ln_cite_affl_wt_notlast ln_ppr_cnt_notlast ///
                   avg_num_coathrs num_grants grants_per_paper grant_density ///
                   `position_outcomes'

    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'

    cap mat drop results
    foreach yvar of local outcomes {
        qui sum `yvar' if year < 2014, d
        local pre_mean = r(mean)

        // base spec — cap noi + skip so sparse outcomes (e.g. n_first_ppr on top_jrnls)
        // that trigger "insufficient observations" (r(2001)) don't halt the pipeline.
        local b_b = .
        local b_se = .
        local b_N = .
        local b_r2 = .
        cap noi qui reghdfe `yvar' Z_it `wt', absorb(`fes') vce(cluster `vce_cl')
        if _rc {
            di as error "pooled_did `samp'`suf' `yvar' base failed (rc=`_rc'); skipping outcome."
            continue
        }
        local b_b   = _b[Z_it]
        local b_se  = _se[Z_it]
        local b_N   = e(N)
        local b_r2  = e(r2)

        // with shares
        local s_bx = .
        local s_sex = .
        local s_bs = .
        local s_ses = .
        local s_N = .
        local s_r2 = .
        cap noi qui reghdfe `yvar' Z_it Z_share_it `wt', absorb(`fes') vce(cluster `vce_cl')
        if _rc {
            di as error "pooled_did `samp'`suf' `yvar' +share failed (rc=`_rc'); using base-only for this outcome."
        }
        else {
            local s_bx  = _b[Z_it]
            local s_sex = _se[Z_it]
            local s_bs  = _b[Z_share_it]
            local s_ses = _se[Z_share_it]
            local s_N   = e(N)
            local s_r2  = e(r2)
        }

        di as text "pooled_did `samp'`suf' `yvar':  base b=" %7.4f `b_b' " se=" %7.4f `b_se' ///
            "    +share b=" %7.4f `s_bx' " se=" %7.4f `s_sex' ///
            "    share_b=" %7.4f `s_bs' " se=" %7.4f `s_ses' ///
            "    pre-mean=" %7.4f `pre_mean'

        cap mat drop pdid_`yvar'
        mat pdid_`yvar' = J(7,2,.)
        mat pdid_`yvar'[1,1] = `b_b'
        mat pdid_`yvar'[2,1] = `b_se'
        mat pdid_`yvar'[5,1] = `pre_mean'
        mat pdid_`yvar'[6,1] = `b_N'
        mat pdid_`yvar'[7,1] = `b_r2'
        mat pdid_`yvar'[1,2] = `s_bx'
        mat pdid_`yvar'[2,2] = `s_sex'
        mat pdid_`yvar'[3,2] = `s_bs'
        mat pdid_`yvar'[4,2] = `s_ses'
        mat pdid_`yvar'[5,2] = `pre_mean'
        mat pdid_`yvar'[6,2] = `s_N'
        mat pdid_`yvar'[7,2] = `s_r2'
        mat rownames pdid_`yvar' = b_exposure se_exposure b_share se_share pre_mean N r2
        mat colnames pdid_`yvar' = base with_share

        // accumulate one row per outcome for the summary dta
        mat row = `b_b', `b_se', `s_bx', `s_sex', `s_bs', `s_ses', `pre_mean'
        mat results = nullmat(results) \ row

        // Frisch-Waugh partial-regression binscatter: pooled DiD analog of ld plot
        local var_name "`yvar'"
        if "`yvar'" == "cite_affl_wt"            local var_name "Citation Weighted Output"
        if "`yvar'" == "ppr_cnt"                 local var_name "Publication Count"
        if "`yvar'" == "ln_cite_affl_wt"         local var_name "Log Citation Weighted Output"
        if "`yvar'" == "ln_ppr_cnt"              local var_name "Log Publication Counts"
        if "`yvar'" == "cite_affl_wt_any"        local var_name "Citation Weighted Output (any position)"
        if "`yvar'" == "ppr_cnt_any"             local var_name "Publication Count (any position)"
        if "`yvar'" == "ln_cite_affl_wt_any"     local var_name "Log Citation Weighted Output (any position)"
        if "`yvar'" == "ln_ppr_cnt_any"          local var_name "Log Publication Counts (any position)"
        if "`yvar'" == "cite_affl_wt_notlast"    local var_name "Citation Weighted Output (non-last author)"
        if "`yvar'" == "ppr_cnt_notlast"         local var_name "Publication Count (non-last author)"
        if "`yvar'" == "ln_cite_affl_wt_notlast" local var_name "Log Citation Weighted Output (non-last author)"
        if "`yvar'" == "ln_ppr_cnt_notlast"      local var_name "Log Publication Counts (non-last author)"
        if "`yvar'" == "avg_num_coathrs"         local var_name "Avg Coauthors"
        if "`yvar'" == "num_grants"              local var_name "Num Grants"
        if "`yvar'" == "grants_per_paper"        local var_name "Grants per Paper"
        if "`yvar'" == "grant_density"           local var_name "Grant Density (num_grants / pre-avg ppr)"
        if "`yvar'" == "n_first_ppr"             local var_name "# First-Author Papers"
        if "`yvar'" == "n_middle_ppr"            local var_name "# Middle-Author Papers"
        if "`yvar'" == "n_last_ppr"              local var_name "# Last-Author Papers"
        if "`yvar'" == "avg_position"            local var_name "Avg Author Position"
        if "`yvar'" == "avg_position_rat"        local var_name "Avg Author Position Ratio"
        if "`yvar'" == "avg_team_size_last"      local var_name "Team Size (last-author papers)"
        if "`yvar'" == "avg_team_size_notlast"   local var_name "Team Size (non-last papers)"

        preserve
            cap noi qui reghdfe `yvar' `wt', absorb(`fes') residuals(_y_r)
            if _rc == 0 cap noi qui reghdfe Z_it `wt', absorb(`fes') residuals(_Z_r)
            if _rc == 0 {
                local pd_b_str  : dis %7.3f `b_b'
                local pd_se_str : dis %7.3f `b_se'
                binscatter _y_r _Z_r `wt_bin', n(30) ///
                    xtitle("Exposure x Post") ytitle("`var_name'") ///
                    xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                    msymbol(O) mcolor(ebblue) ///
                    note("{&beta} = `pd_b_str' (SE: `pd_se_str')") ///
                    plotregion(margin(sides))
                graph export ../output/figures/`samp'/pdid_`yvar'`suf'`wsuf'.pdf, replace
            }
            else di as error "pdid binscatter `yvar' failed; skipping plot."
        restore

        preserve
            cap noi qui reghdfe `yvar' Z_share_it `wt', absorb(`fes') residuals(_y_r)
            if _rc == 0 cap noi qui reghdfe Z_it Z_share_it `wt', absorb(`fes') residuals(_Z_r)
            if _rc == 0 {
                local pds_b_str  : dis %7.3f `s_bx'
                local pds_se_str : dis %7.3f `s_sex'
                binscatter _y_r _Z_r `wt_bin', n(30) ///
                    xtitle("Exposure x Post") ytitle("`var_name'") ///
                    xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                    msymbol(O) mcolor(ebblue) ///
                    note("{&beta} = `pds_b_str' (SE: `pds_se_str')") ///
                    plotregion(margin(sides))
                graph export ../output/figures/`samp'/pdid_`yvar'`suf'_mshrctrl`wsuf'.pdf, replace
            }
            else di as error "pdid mshrctrl binscatter `yvar' failed; skipping plot."
        restore
    }

    // small dta with both specs per outcome for quoting in figure legends or text
    preserve
        clear
        svmat results
        rename (results1 results2 results3 results4 results5 results6 results7) ///
               (b_base se_base b_exp_wshr se_exp_wshr b_shr_wshr se_shr_wshr pre_mean)
        gen outcome = ""
        local i = 1
        foreach yvar of local outcomes {
            replace outcome = "`yvar'" if _n == `i'
            local ++i
        }
        order outcome b_base se_base b_exp_wshr se_exp_wshr b_shr_wshr se_shr_wshr pre_mean
        save ../temp/pooled_did_`samp'`suf'`wsuf', replace
        list, sep(0) noobs abbrev(20)
    restore
end

program ppml_specs
    // Poisson (ppmlhdfe) analog of pooled_did.
    //   ppml_pdid: y_it on Z_it (+ Z_share_it), absorb(FEs from $FE_MODE)
    // Skips ln_ outcomes; ppmlhdfe wrapped in cap noi (may drop separated obs
    // or fail to converge). Matrix ppml_pdid_<yvar> has rows
    // [b_x, se_x, b_share, se_share, pre_mean, N, r2_p] and cols [base, with_share].
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
    local wt ""
    local wsuf ""
    if "$WEIGHT_MSIM" == "1" {
        // Weight-type notes:
        //   `wt' = [pw=max_sim]  — reghdfe/ppmlhdfe accept pw; ppmlhdfe rejects aw
        //   `wt_bin' = [aw=max_sim] — binscatter accepts only aw / fw, not pw
        // WLS coefficients are identical under aw vs pw (SEs are handled by
        // vce(cluster) anyway), so mixing the two doesn't change anything
        // substantively — it just gets past each command's accepted weight type.
        local wt "[pw=max_sim]"
        local wt_bin "[aw=max_sim]"
        local wsuf "_msimwt"
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    use ../temp/es_`samp'`suf', clear

    gen post = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post

    // PPML expects non-negative counts / weights. Position counts (n_first_ppr,
    // n_middle_ppr, n_last_ppr) fit fine; the mean-based position metrics
    // (avg_position, avg_team_size_*) are conditional means and belong in reghdfe/OLS only.
    local position_outcomes ""
    if "$POSITION_OUTCOMES_AVAIL" == "1" {
        local position_outcomes n_first_ppr n_middle_ppr n_last_ppr
    }
    local outcomes cite_affl_wt ppr_cnt affl_wt ///
                   cite_affl_wt_any ppr_cnt_any affl_wt_any ///
                   cite_affl_wt_notlast ppr_cnt_notlast affl_wt_notlast ///
                   avg_num_coathrs num_grants grants_per_paper grant_density ///
                   `position_outcomes'

    foreach yvar of local outcomes {
        qui sum `yvar' if year < 2014, d
        local pre_mean = r(mean)

        local b_b = .
        local b_se = .
        local b_N = .
        local b_r2 = .
        local s_bx = .
        local s_sex = .
        local s_bs = .
        local s_ses = .
        local s_N = .
        local s_r2 = .
        cap noi ppmlhdfe `yvar' Z_it            `wt', absorb(`fes') vce(cluster `vce_cl')
        if _rc == 0 {
            local b_b  = _b[Z_it]
            local b_se = _se[Z_it]
            local b_N  = e(N)
            local b_r2 = e(r2_p)
        }
        else di as error "ppml_pdid `yvar' base failed (rc=`_rc')"
        cap noi ppmlhdfe `yvar' Z_it Z_share_it `wt', absorb(`fes') vce(cluster `vce_cl')
        if _rc == 0 {
            local s_bx  = _b[Z_it]
            local s_sex = _se[Z_it]
            local s_bs  = _b[Z_share_it]
            local s_ses = _se[Z_share_it]
            local s_N   = e(N)
            local s_r2  = e(r2_p)
        }
        else di as error "ppml_pdid `yvar' +share failed (rc=`_rc')"
        cap mat drop ppml_pdid_`yvar'
        mat ppml_pdid_`yvar' = J(7,2,.)
        mat ppml_pdid_`yvar'[1,1] = `b_b'
        mat ppml_pdid_`yvar'[2,1] = `b_se'
        mat ppml_pdid_`yvar'[5,1] = `pre_mean'
        mat ppml_pdid_`yvar'[6,1] = `b_N'
        mat ppml_pdid_`yvar'[7,1] = `b_r2'
        mat ppml_pdid_`yvar'[1,2] = `s_bx'
        mat ppml_pdid_`yvar'[2,2] = `s_sex'
        mat ppml_pdid_`yvar'[3,2] = `s_bs'
        mat ppml_pdid_`yvar'[4,2] = `s_ses'
        mat ppml_pdid_`yvar'[5,2] = `pre_mean'
        mat ppml_pdid_`yvar'[6,2] = `s_N'
        mat ppml_pdid_`yvar'[7,2] = `s_r2'
        mat rownames ppml_pdid_`yvar' = b_exposure se_exposure b_share se_share pre_mean N r2_p
        mat colnames ppml_pdid_`yvar' = base with_share

        di as text "ppml_specs `samp'`suf' `yvar': pdid b=" %7.4f ppml_pdid_`yvar'[1,1] ///
            "  pre_mean=" %7.4f `pre_mean'

        // Figures: PPML-consistent Frisch-Waugh binscatter. Uses the IRLS
        // working response z = xb + (y - mu)/mu with mu-weighted partial-out;
        // slope of the plotted line equals the ppmlhdfe beta by construction.
        local var_name "`yvar'"
        if "`yvar'" == "cite_affl_wt"         local var_name "Citation Weighted Output"
        if "`yvar'" == "ppr_cnt"              local var_name "Publication Count"
        if "`yvar'" == "affl_wt"              local var_name "Affiliation Weighted Output"
        if "`yvar'" == "cite_affl_wt_any"     local var_name "Citation Weighted Output (any position)"
        if "`yvar'" == "ppr_cnt_any"          local var_name "Publication Count (any position)"
        if "`yvar'" == "affl_wt_any"          local var_name "Affiliation Weighted Output (any position)"
        if "`yvar'" == "cite_affl_wt_notlast" local var_name "Citation Weighted Output (non-last author)"
        if "`yvar'" == "ppr_cnt_notlast"      local var_name "Publication Count (non-last author)"
        if "`yvar'" == "affl_wt_notlast"      local var_name "Affiliation Weighted Output (non-last author)"
        if "`yvar'" == "avg_num_coathrs"      local var_name "Avg Coauthors"
        if "`yvar'" == "num_grants"           local var_name "Num Grants"
        if "`yvar'" == "grants_per_paper"     local var_name "Grants per Paper"
        if "`yvar'" == "grant_density"        local var_name "Grant Density"
        if "`yvar'" == "n_first_ppr"          local var_name "# First-Author Papers"
        if "`yvar'" == "n_middle_ppr"         local var_name "# Middle-Author Papers"
        if "`yvar'" == "n_last_ppr"           local var_name "# Last-Author Papers"
        local poisson_name "`var_name'"
        if "`yvar'" == "ppr_cnt"              local poisson_name "Publications"
        if "`yvar'" == "cite_affl_wt"         local poisson_name "Citation-Weighted Output"
        if "`yvar'" == "affl_wt"              local poisson_name "Affiliation-Weighted Output"
        if "`yvar'" == "ppr_cnt_any"          local poisson_name "Publications (any position)"
        if "`yvar'" == "cite_affl_wt_any"     local poisson_name "Citation-Weighted Output (any position)"
        if "`yvar'" == "affl_wt_any"          local poisson_name "Affiliation-Weighted Output (any position)"
        if "`yvar'" == "ppr_cnt_notlast"      local poisson_name "Publications (non-last author)"
        if "`yvar'" == "cite_affl_wt_notlast" local poisson_name "Citation-Weighted Output (non-last author)"
        if "`yvar'" == "affl_wt_notlast"      local poisson_name "Affiliation-Weighted Output (non-last author)"
        if "`yvar'" == "avg_num_coathrs"      local poisson_name "Coauthors"
        if "`yvar'" == "num_grants"           local poisson_name "Grants"
        if "`yvar'" == "grants_per_paper"     local poisson_name "Grants per Paper"
        if "`yvar'" == "grant_density"        local poisson_name "Grant Density"

        // FWL partial-out uses the IRLS working-weight _mu. Under max_sim
        // weighting, the effective analytic weight is _mu * max_sim so the
        // slope of the plotted binscatter still equals the weighted ppmlhdfe β.
        preserve
            cap drop _y_r _Z_r _mu _z_work _dvar _fwlw
            cap noi ppmlhdfe `yvar' Z_it `wt', absorb(`fes') vce(cluster `vce_cl') d(_dvar)
            if _rc == 0 {
                predict double _mu, mu
                keep if !mi(_mu) & _mu > 0
                gen double _z_work = ln(_mu) + (`yvar' - _mu)/_mu
                gen double _fwlw = _mu
                if "$WEIGHT_MSIM" == "1" replace _fwlw = _mu * max_sim
                cap noi qui reghdfe _z_work [pw=_fwlw], absorb(`fes') residuals(_y_r)
                if _rc == 0 cap noi qui reghdfe Z_it [pw=_fwlw], absorb(`fes') residuals(_Z_r)
                if _rc {
                    di as error "ppml FWL `yvar' failed; skipping plot."
                    restore
                    continue
                }
                local pb_str  : dis %7.3f ppml_pdid_`yvar'[1,1]
                local pse_str : dis %7.3f ppml_pdid_`yvar'[2,1]
                binscatter _y_r _Z_r [aw=_fwlw], n(30) ///
                    xtitle("Exposure x Post") ///
                    ytitle("{&Delta} Log Expected `poisson_name'") ///
                    xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                    msymbol(O) mcolor(ebblue) ///
                    note("{&beta} = `pb_str' (SE: `pse_str')", size(small) pos(7) ring(1) justification(left)) ///
                    plotregion(margin(sides))
                graph export ../output/figures/`samp'/ppml_pdid_`yvar'`suf'`wsuf'.pdf, replace
            }
        restore

        preserve
            cap drop _y_r _Z_r _mu _z_work _dvar _fwlw
            cap noi ppmlhdfe `yvar' Z_it Z_share_it `wt', absorb(`fes') vce(cluster `vce_cl') d(_dvar)
            if _rc == 0 {
                predict double _mu, mu
                keep if !mi(_mu) & _mu > 0
                gen double _z_work = ln(_mu) + (`yvar' - _mu)/_mu
                gen double _fwlw = _mu
                if "$WEIGHT_MSIM" == "1" replace _fwlw = _mu * max_sim
                cap noi qui reghdfe _z_work Z_share_it [pw=_fwlw], absorb(`fes') residuals(_y_r)
                if _rc == 0 cap noi qui reghdfe Z_it Z_share_it [pw=_fwlw], absorb(`fes') residuals(_Z_r)
                if _rc {
                    di as error "ppml FWL mshrctrl `yvar' failed; skipping plot."
                    restore
                    continue
                }
                local pbs_str  : dis %7.3f ppml_pdid_`yvar'[1,2]
                local pses_str : dis %7.3f ppml_pdid_`yvar'[2,2]
                binscatter _y_r _Z_r [aw=_fwlw], n(30) ///
                    xtitle("Exposure x Post") ///
                    ytitle("{&Delta} Log Expected `poisson_name'") ///
                    xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                    msymbol(O) mcolor(ebblue) ///
                    note("{&beta} = `pbs_str' (SE: `pses_str')", size(small) pos(7) ring(1) justification(left)) ///
                    plotregion(margin(sides))
                graph export ../output/figures/`samp'/ppml_pdid_`yvar'`suf'_mshrctrl`wsuf'.pdf, replace
            }
        restore
    }
end

program ppml_pdid_het_binscatter
    // Per-group PPML pooled-DiD FWL binscatter of ppr_cnt on Z_it, with
    // Z_share_it (mkt_spend_shr x post) partialled out. One figure per group
    // per heterogeneity dimension -- same 7 dummy pairs as event_study's
    // heterogeneity block.
    //
    // Match to the interacted parameterization: for each pair (g1, g2) we
    // fit ONE PPML on the FULL sample with fully-interacted Z and share:
    //   ppmlhdfe ppr_cnt Z_g1 Z_g2 S_g1 S_g2, absorb(FEs)
    // where Z_g = Z_it * g and S_g = Z_share_it * g. So _b[Z_g1] and
    // _b[Z_g2] are the group-specific β's -- identical to the split-
    // interaction spec in event_study's heterogeneity block (up to
    // reparameterization). This lets institution / cluster FEs pool
    // across g1 and g2 rather than being re-estimated per subgroup, so
    // under FE_MODE = inst_cluster(_fldyr) it recovers the interacted β
    // rather than a subsample β.
    //
    // Binscatter FWL: residualize _z_work and Z_g against the OTHER
    // interactions plus S_g and FEs, then plot on the g==1 rows -- on
    // those rows the "other" interactions are mechanically zero, so the
    // FWL slope of _z_work on Z_g equals _b[Z_g] exactly.
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
    local wt ""
    local wsuf ""
    if "$WEIGHT_MSIM" == "1" {
        local wt "[pw=max_sim]"
        local wsuf "_msimwt"
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    cap mkdir "../output/figures/`samp'/ppml_pdid_het_bs"

    local dummy_pairs `" "young old" "r1 r2" "high_pre_ppr low_pre_ppr" "high_grants low_grants" "big_team small_team" "many_coauth few_coauth" "big_msa small_msa" "'

    foreach pair of local dummy_pairs {
        local g1 : word 1 of `pair'
        local g2 : word 2 of `pair'

        preserve
            use ../temp/es_`samp'`suf', clear
            gen post       = year >= 2014
            gen Z_it       = exposure      * post
            gen Z_share_it = mkt_spend_shr * post
            // Fully-interacted parameterization: one Z per group, one S per group.
            gen Z_`g1' = Z_it       * `g1'
            gen Z_`g2' = Z_it       * `g2'
            gen S_`g1' = Z_share_it * `g1'
            gen S_`g2' = Z_share_it * `g2'

            cap drop _mu _z_work _dvar _fwlw
            cap noi ppmlhdfe ppr_cnt Z_`g1' Z_`g2' S_`g1' S_`g2' `wt', ///
                    absorb(`fes') vce(cluster `vce_cl') d(_dvar)
            if _rc {
                di as error "ppml_pdid_het_bs `samp'`suf' `g1'/`g2' joint failed (rc=`_rc'); skipping pair."
                restore
                continue
            }
            local b_`g1'  = _b[Z_`g1']
            local se_`g1' = _se[Z_`g1']
            local b_`g2'  = _b[Z_`g2']
            local se_`g2' = _se[Z_`g2']

            // IRLS working response + FWL weight, computed once from the joint fit.
            predict double _mu, mu
            keep if !mi(_mu) & _mu > 0
            gen double _z_work = ln(_mu) + (ppr_cnt - _mu)/_mu
            gen double _fwlw = _mu
            if "$WEIGHT_MSIM" == "1" replace _fwlw = _mu * max_sim

            foreach grp in `g1' `g2' {
                // "other" = the sibling group whose Z / S are treated as controls.
                local other = cond("`grp'" == "`g1'", "`g2'", "`g1'")

                cap drop _y_r _Z_r
                cap noi qui reghdfe _z_work Z_`other' S_`g1' S_`g2' [pw=_fwlw], ///
                        absorb(`fes') residuals(_y_r)
                if _rc == 0 cap noi qui reghdfe Z_`grp' Z_`other' S_`g1' S_`g2' [pw=_fwlw], ///
                        absorb(`fes') residuals(_Z_r)
                if _rc {
                    di as error "ppml_pdid_het_bs FWL `grp' (paired with `other') failed; skipping plot."
                    continue
                }
                local b_str  : dis %7.3f `b_`grp''
                local se_str : dis %7.3f `se_`grp''
                binscatter _y_r _Z_r [aw=_fwlw] if `grp' == 1, n(30) ///
                    xtitle("Exposure x Post") ///
                    ytitle("{&Delta} Log Expected Publications") ///
                    xlab(-0.06(0.015)0.06, format(%5.3f)) ///
                    msymbol(O) mcolor(ebblue) ///
                    note("{&beta} = `b_str' (SE: `se_str')", size(small) pos(7) ring(1) justification(left)) ///
                    plotregion(margin(sides))
                graph export ///
                    ../output/figures/`samp'/ppml_pdid_het_bs/ppml_pdid_ppr_cnt_`grp'_mshrctrl`suf'`wsuf'.pdf, ///
                    replace
            }
        restore
    }
end

program placebo_treatment
    // Pre-period-only placebo: restrict panel to year <= 2013 (drops the actual
    // treatment + post period entirely) and assign a fake treatment year.
    // If parallel trends hold, beta on (exposure * placebo_post) should be ~0
    // and statistically insignificant. Runs for placebo years 2011 and 2012.
    // Also runs an event-study version where each pre-2014 year-relative-to-
    // placebo gets its own exposure interaction, so you can visually inspect
    // whether the placebo "effect" shows up at a specific year.
    // All specifications are ppmlhdfe with the mkt_spend_shr sum-of-shares control.
    // Matrices placebo<yr>_<yvar> have rows
    // [b_exp, se_exp, b_share, se_share, pre_mean, N, r2_p] and one column.
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

    local outcomes cite_affl_wt ppr_cnt cite_affl_wt_any ppr_cnt_any ///
                   cite_affl_wt_notlast ppr_cnt_notlast ///
                   avg_num_coathrs num_grants grants_per_paper grant_density

    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'
    cap mkdir ../output/figures/`samp'

    foreach placebo_yr in 2011 2012 {
        use ../temp/es_`samp'`suf', clear
        keep if year <= 2013     // strictly pre-treatment window

        gen placebo_post   = year >= `placebo_yr'
        gen Z_placebo      = exposure      * placebo_post
        gen Z_share_placebo = mkt_spend_shr * placebo_post

        foreach yvar of local outcomes {
            qui sum `yvar' if year < `placebo_yr', d
            local pre_mean = r(mean)

            local b     = .
            local se    = .
            local b_s   = .
            local se_s  = .
            local N     = .
            local r2_p  = .
            cap noi ppmlhdfe `yvar' Z_placebo Z_share_placebo, ///
                    absorb(`fes') vce(cluster `vce_cl')
            if _rc == 0 {
                local b    = _b[Z_placebo]
                local se   = _se[Z_placebo]
                local b_s  = _b[Z_share_placebo]
                local se_s = _se[Z_share_placebo]
                local N    = e(N)
                local r2_p = e(r2_p)
            }
            else di as error "placebo_treatment `yvar' (placebo=`placebo_yr') ppml failed (rc=`_rc')"

            local t = cond(`se' > 0 & !mi(`se'), `b' / `se', .)
            di as text "placebo_treatment `samp'`suf' `yvar' (placebo=`placebo_yr'):" ///
                _newline "    ppmlhdfe (+share)  b=" %8.4f `b'   "  se=" %8.4f `se'   "  t=" %6.2f `t' ///
                "  b_share=" %8.4f `b_s' "  se_share=" %8.4f `se_s' ///
                "  pre_mean=" %8.4f `pre_mean' "  N=" %8.0f `N'

            cap mat drop placebo`placebo_yr'_`yvar'
            mat placebo`placebo_yr'_`yvar' = J(7,1,.)
            mat placebo`placebo_yr'_`yvar'[1,1] = `b'
            mat placebo`placebo_yr'_`yvar'[2,1] = `se'
            mat placebo`placebo_yr'_`yvar'[3,1] = `b_s'
            mat placebo`placebo_yr'_`yvar'[4,1] = `se_s'
            mat placebo`placebo_yr'_`yvar'[5,1] = `pre_mean'
            mat placebo`placebo_yr'_`yvar'[6,1] = `N'
            mat placebo`placebo_yr'_`yvar'[7,1] = `r2_p'
            mat rownames placebo`placebo_yr'_`yvar' = b_exp se_exp b_share se_share pre_mean N r2_p
            mat colnames placebo`placebo_yr'_`yvar' = ppmlhdfe_wshr
        }
    }

    // Placebo event study: re-run the entire event study on the FULL 2010-2019
    // panel but with a fake treatment year as the omitted reference. Pre-placebo
    // years should be ~0 if trends are parallel. Years between the placebo and
    // 2014 should also be ~0 (no real treatment yet). The real effect should
    // begin at 2014 (marked with a dashed vertical line). If the response curve
    // jumps at the placebo year instead of 2014, that's evidence of a pre-trend
    // problem in the real spec. Estimated by ppmlhdfe with mkt_spend_shr
    // sum-of-shares interacted with event time as controls.
    foreach placebo_yr in 2011 2012 {
        // Placebo ES on all four headline outcome flavors so the pre-trend
        // check covers the same outcomes we report on. Position outcomes are
        // omitted here — placebo pre-trends on counts of first/middle papers
        // are covered by the placebo_treatment pooled test above.
        foreach yvar in ppr_cnt cite_affl_wt ppr_cnt_any cite_affl_wt_any ///
                        ppr_cnt_notlast cite_affl_wt_notlast {
            if "`yvar'" == "ppr_cnt"              local poisson_name "Publications"
            if "`yvar'" == "cite_affl_wt"         local poisson_name "Citation-Weighted Output"
            if "`yvar'" == "ppr_cnt_any"          local poisson_name "Publications (any position)"
            if "`yvar'" == "cite_affl_wt_any"     local poisson_name "Citation-Weighted Output (any position)"
            if "`yvar'" == "ppr_cnt_notlast"      local poisson_name "Publications (non-last author)"
            if "`yvar'" == "cite_affl_wt_notlast" local poisson_name "Citation-Weighted Output (non-last author)"

            use ../temp/es_`samp'`suf', clear
            cap drop pl_rel pl_int_lead* pl_int_lag* pl_mshr_lead* pl_mshr_lag*
            gen pl_rel = year - `placebo_yr'
            qui sum pl_rel
            local pl_abs_lag  = abs(r(max))
            local pl_abs_lead = abs(r(min))
            forval i = 1/`pl_abs_lead' {
                gen pl_int_lead`i'  = exposure      if pl_rel == -`i'
                gen pl_mshr_lead`i' = mkt_spend_shr if pl_rel == -`i'
            }
            forval i = 0/`pl_abs_lag' {
                gen pl_int_lag`i'  = exposure      if pl_rel == `i'
                gen pl_mshr_lag`i' = mkt_spend_shr if pl_rel == `i'
            }
            ds pl_int_lead* pl_int_lag* pl_mshr_lead* pl_mshr_lag*
            foreach v in `r(varlist)' {
                replace `v' = 0 if mi(`v')
            }
            local pl_int_leads
            local pl_int_lags
            local pl_mshr_leads
            local pl_mshr_lags
            forval i = 2/`pl_abs_lead' {
                local pl_int_leads  pl_int_lead`i'  `pl_int_leads'
                local pl_mshr_leads pl_mshr_lead`i' `pl_mshr_leads'
            }
            forval i = 0/`pl_abs_lag' {
                local pl_int_lags  `pl_int_lags'  pl_int_lag`i'
                local pl_mshr_lags `pl_mshr_lags' pl_mshr_lag`i'
            }

            // pl_int_lead1 / pl_mshr_lead1 (year `placebo_yr'-1) are the omitted
            // reference for exposure and share interactions — never included in
            // the regressor list, so rel=-1 stays the reference year.
            cap noi ppmlhdfe `yvar' `pl_int_leads' `pl_int_lags' ///
                                    `pl_mshr_leads' `pl_mshr_lags', ///
                    absorb(`fes') vce(cluster `vce_cl')
            if _rc {
                di as error "placebo ES ppmlhdfe `yvar' yr`placebo_yr' failed (rc=`_rc'); skipping."
                continue
            }

            preserve
            cap mat drop es
            foreach var in `pl_int_leads' `pl_int_lags' pl_int_lead1 {
                if "`var'" == "pl_int_lead1" {
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
            // rel mapping mirrors event_study: leads (deepest first), then
            // lags 0..K, then the omitted reference -1 at the end.
            gen rel = -`pl_abs_lead' if _n == 1
            replace rel = rel[_n-1]+1 if _n > 1
            replace rel = rel + 1 if rel >= -1
            replace rel = -1 if rel == `pl_abs_lag' + 1
            gen year = rel + `placebo_yr'
            hashsort rel
            sum ub, d
            local ymax = round(r(max), 0.1)
            sum lb, d
            local ymin = round(r(min), 0.1)
            local ref_yr = `placebo_yr' - 1
            tw rcap ub lb year if year != `ref_yr', lcolor(cranberry%70) msize(vsmall) || ///
              scatter b year, mcolor(cranberry) ///
              , xlab(2010(1)2019) xtitle("Year (placebo treatment at `placebo_yr')") ///
                ytitle("{&Delta} Log Expected `poisson_name'") ///
                ylab(`ymin'(0.1)`ymax') yline(0, lcolor(gs10) lpattern(solid)) ///
                xline(2014, lpattern(dash) lcolor(gs10)) ///
                title("Placebo ES: treatment shifted to `placebo_yr' (real: 2014)", size(small)) ///
                legend(off) plotregion(margin(sides))
            graph export ../output/figures/`samp'/placebo_es_`yvar'_yr`placebo_yr'`suf'.pdf, replace
            save ../temp/placebo_es_`yvar'_yr`placebo_yr'`suf', replace
            restore
        }
    }
end

program trim_top
    // Composition check: drop the top X% of PIs by pre-period publication
    // count (pre_ppr_cnt_sum, computed in restrict_samp), then re-estimate
    // pdid (reghdfe) and ppml_pdid. If the main effect is driven by a few
    // high-baseline outliers, dropping them will collapse the coefficient.
    // Runs at trim levels {1, 5, 10, 25}; writes one matrix per (trim, yvar)
    // for output_tables and a comparison figure per outcome.
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

    local outcomes cite_affl_wt ppr_cnt cite_affl_wt_any ppr_cnt_any ///
                   cite_affl_wt_notlast ppr_cnt_notlast ///
                   avg_num_coathrs num_grants grants_per_paper grant_density
    local trims 1 5 10 25

    cap mkdir ../output/tables/`samp'
    cap mkdir ../output/figures/`samp'

    foreach trim of local trims {
        use ../temp/es_`samp'`suf', clear
        // pre_ppr_cnt_sum is one value per PI; collapse to one row, compute
        // the (100-trim) percentile cut, drop above.
        bys athr_id: gen _one = _n == 1
        qui sum pre_ppr_cnt_sum if _one == 1, d
        local p = 100 - `trim'
        qui _pctile pre_ppr_cnt_sum if _one == 1, p(`p')
        local cut = r(r1)
        qui gunique athr_id
        local n_pre = r(unique)
        drop if pre_ppr_cnt_sum > `cut'
        qui gunique athr_id
        local n_post = r(unique)
        di as text "trim_top `samp'`suf' trim=`trim'%: cut=" %7.2f `cut' ///
            "  PIs dropped " (`n_pre' - `n_post') " / `n_pre' (kept " %7.4f (`n_post' / `n_pre') ")"

        gen post       = year >= 2014
        gen Z_it       = exposure      * post
        gen Z_share_it = mkt_spend_shr * post

        foreach yvar of local outcomes {
            qui sum `yvar' if year < 2014, d
            local pre_mean = r(mean)

            local lb = .
            local lse = .
            local lN = .
            cap noi reghdfe `yvar' Z_it, absorb(`fes') vce(cluster `vce_cl')
            if _rc == 0 {
                local lb  = _b[Z_it]
                local lse = _se[Z_it]
                local lN  = e(N)
            }

            local pb = .
            local pse = .
            local pN = .
            cap noi ppmlhdfe `yvar' Z_it, absorb(`fes') vce(cluster `vce_cl')
            if _rc == 0 {
                local pb  = _b[Z_it]
                local pse = _se[Z_it]
                local pN  = e(N)
            }

            di as text "  trim=`trim'% `yvar': reghdfe b=" %8.4f `lb' "  se=" %8.4f `lse' ///
                "    ppml b=" %8.4f `pb' "  se=" %8.4f `pse' "    pre_mean=" %7.4f `pre_mean'

            cap mat drop trim`trim'_`yvar'
            mat trim`trim'_`yvar' = J(5,2,.)
            mat trim`trim'_`yvar'[1,1] = `lb'
            mat trim`trim'_`yvar'[2,1] = `lse'
            mat trim`trim'_`yvar'[3,1] = `pre_mean'
            mat trim`trim'_`yvar'[4,1] = `lN'
            mat trim`trim'_`yvar'[5,1] = `n_post'
            mat trim`trim'_`yvar'[1,2] = `pb'
            mat trim`trim'_`yvar'[2,2] = `pse'
            mat trim`trim'_`yvar'[3,2] = `pre_mean'
            mat trim`trim'_`yvar'[4,2] = `pN'
            mat trim`trim'_`yvar'[5,2] = `n_post'
            mat rownames trim`trim'_`yvar' = b se pre_mean N n_PIs
            mat colnames trim`trim'_`yvar' = reghdfe ppmlhdfe
        }
        drop _one
    }

    // Comparison figure per key outcome: linear pdid β at each trim level
    foreach yvar in ppr_cnt cite_affl_wt {
        if "`yvar'" == "ppr_cnt"      local var_name "Publication Count"
        if "`yvar'" == "cite_affl_wt" local var_name "Citation Weighted Output"
        local poisson_name "`var_name'"
        if "`yvar'" == "ppr_cnt"      local poisson_name "Publications"
        if "`yvar'" == "cite_affl_wt" local poisson_name "Citation-Weighted Output"

        preserve
        clear
        set obs 5
        gen trim = 0 in 1
        replace trim = 1 in 2
        replace trim = 5 in 3
        replace trim = 10 in 4
        replace trim = 25 in 5
        gen b  = .
        gen se = .
        // trim = 0 uses the main pdid_<yvar> matrix
        cap confirm matrix pdid_`yvar'
        if !_rc {
            replace b  = pdid_`yvar'[1,1] in 1
            replace se = pdid_`yvar'[2,1] in 1
        }
        local i = 2
        foreach t of local trims {
            cap confirm matrix trim`t'_`yvar'
            if !_rc {
                replace b  = trim`t'_`yvar'[1,1] in `i'
                replace se = trim`t'_`yvar'[2,1] in `i'
            }
            local ++i
        }
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        tw rcap ub lb trim, lcolor(ebblue%70) msize(small) || ///
           scatter b trim, mcolor(ebblue) msize(medium) ///
           , xlab(0 "Full sample" 1 "Drop top 1%" 5 "5%" 10 "10%" 25 "25%", labsize(small)) ///
             xtitle("Top-pre-pub PIs dropped") ///
             ytitle("pdid {&beta}: `var_name'") ///
             yline(0, lcolor(gs10) lpattern(solid)) ///
             title("Trim-top sensitivity: `var_name'", size(small)) ///
             legend(off) plotregion(margin(sides))
        graph export ../output/figures/`samp'/trim_top_`yvar'`suf'.pdf, replace
        restore

        // ppml version
        preserve
        clear
        set obs 5
        gen trim = 0 in 1
        replace trim = 1 in 2
        replace trim = 5 in 3
        replace trim = 10 in 4
        replace trim = 25 in 5
        gen b  = .
        gen se = .
        cap confirm matrix ppml_pdid_`yvar'
        if !_rc {
            replace b  = ppml_pdid_`yvar'[1,1] in 1
            replace se = ppml_pdid_`yvar'[2,1] in 1
        }
        local i = 2
        foreach t of local trims {
            cap confirm matrix trim`t'_`yvar'
            if !_rc {
                replace b  = trim`t'_`yvar'[1,2] in `i'
                replace se = trim`t'_`yvar'[2,2] in `i'
            }
            local ++i
        }
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        tw rcap ub lb trim, lcolor(cranberry%70) msize(small) || ///
           scatter b trim, mcolor(cranberry) msize(medium) ///
           , xlab(0 "Full sample" 1 "Drop top 1%" 5 "5%" 10 "10%" 25 "25%", labsize(small)) ///
             xtitle("Top-pre-pub PIs dropped") ///
             ytitle("{&Delta} Log Expected `poisson_name'") ///
             yline(0, lcolor(gs10) lpattern(solid)) ///
             title("Trim-top sensitivity (ppml): `var_name'", size(small)) ///
             legend(off) plotregion(margin(sides))
        graph export ../output/figures/`samp'/trim_top_ppml_`yvar'`suf'.pdf, replace
        restore
    }
end

program joint_outcome_test
    // Three parameterizations of the same H0: exposure-on-papers = exposure-on-cite-weighted-output.
    //   log   : reghdfe on ln(1+y). β interpreted as proportional log response; comparable
    //           because both outcomes are on the same log scale. Existing default.
    //   norm  : reghdfe on y / pre-period mean(y). β is "% of pre-mean per unit exposure",
    //           so ppr and cite are on the same "% change" ruler. Raw levels version of the same test.
    //   ppml  : ppmlhdfe on raw y. β is semi-elasticity per outcome — directly comparable
    //           without the log(1+·) fudge and without the pre-mean normalization.
    // Stacking pattern is identical across the three: outcome dummy + Z x outcome_cite, cluster athr_id.
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    use ../temp/es_`samp'`suf', clear

    foreach v in cite_affl_wt ppr_cnt {
        cap gen ln_`v' = ln(1+`v')
    }

    gen post = year >= 2014
    gen Z_it = exposure * post

    // pre-period means used for the normalized-levels parameterization
    qui sum ppr_cnt      if year < 2014
    local mean_ppr = r(mean)
    qui sum cite_affl_wt if year < 2014
    local mean_cite = r(mean)

    keep athr_id year Z_it ppr_cnt cite_affl_wt ln_ppr_cnt ln_cite_affl_wt

    // Stack: outcome == 0 -> ppr row; outcome == 1 -> cite row. Each row carries
    // all three y-parameterizations (raw for ppml, log, normalized level).
    preserve
        gen outcome = 1
        gen y_raw = cite_affl_wt
        gen y_ln  = ln_cite_affl_wt
        gen y_nrm = cite_affl_wt / `mean_cite'
        keep athr_id year Z_it outcome y_raw y_ln y_nrm
        save ../temp/stack_cite_`samp'`suf', replace
    restore
    gen outcome = 0
    gen y_raw = ppr_cnt
    gen y_ln  = ln_ppr_cnt
    gen y_nrm = ppr_cnt / `mean_ppr'
    keep athr_id year Z_it outcome y_raw y_ln y_nrm
    append using ../temp/stack_cite_`samp'`suf'

    egen athr_outcome = group(athr_id outcome)
    egen year_outcome = group(year outcome)
    gen Z_it_cite = Z_it * (outcome == 1)

    cap mat drop joint_`samp'`suf'
    mat joint_`samp'`suf' = J(8,3,.)
    mat rownames joint_`samp'`suf' = b_ppr se_ppr b_cite se_cite b_diff se_diff Wald_F p_value
    mat colnames joint_`samp'`suf' = log norm_levels ppml

    // --- log parameterization ---
    reghdfe y_ln Z_it Z_it_cite, absorb(athr_outcome year_outcome) vce(cluster athr_id)
    local b_ppr_ln  = _b[Z_it]
    local se_ppr_ln = _se[Z_it]
    local b_diff_ln = _b[Z_it_cite]
    local se_diff_ln = _se[Z_it_cite]
    qui lincom Z_it + Z_it_cite
    local b_cite_ln  = r(estimate)
    local se_cite_ln = r(se)
    qui test Z_it_cite
    local F_ln = r(F)
    local p_ln = r(p)
    mat joint_`samp'`suf'[1,1] = `b_ppr_ln'
    mat joint_`samp'`suf'[2,1] = `se_ppr_ln'
    mat joint_`samp'`suf'[3,1] = `b_cite_ln'
    mat joint_`samp'`suf'[4,1] = `se_cite_ln'
    mat joint_`samp'`suf'[5,1] = `b_diff_ln'
    mat joint_`samp'`suf'[6,1] = `se_diff_ln'
    mat joint_`samp'`suf'[7,1] = `F_ln'
    mat joint_`samp'`suf'[8,1] = `p_ln'

    // --- normalized-levels parameterization ---
    reghdfe y_nrm Z_it Z_it_cite, absorb(athr_outcome year_outcome) vce(cluster athr_id)
    local b_ppr_nr  = _b[Z_it]
    local se_ppr_nr = _se[Z_it]
    local b_diff_nr = _b[Z_it_cite]
    local se_diff_nr = _se[Z_it_cite]
    qui lincom Z_it + Z_it_cite
    local b_cite_nr  = r(estimate)
    local se_cite_nr = r(se)
    qui test Z_it_cite
    local F_nr = r(F)
    local p_nr = r(p)
    mat joint_`samp'`suf'[1,2] = `b_ppr_nr'
    mat joint_`samp'`suf'[2,2] = `se_ppr_nr'
    mat joint_`samp'`suf'[3,2] = `b_cite_nr'
    mat joint_`samp'`suf'[4,2] = `se_cite_nr'
    mat joint_`samp'`suf'[5,2] = `b_diff_nr'
    mat joint_`samp'`suf'[6,2] = `se_diff_nr'
    mat joint_`samp'`suf'[7,2] = `F_nr'
    mat joint_`samp'`suf'[8,2] = `p_nr'

    // --- PPML parameterization (semi-elasticity per outcome, unit-free comparison) ---
    local b_ppr_pp = .
    local se_ppr_pp = .
    local b_cite_pp = .
    local se_cite_pp = .
    local b_diff_pp = .
    local se_diff_pp = .
    local F_pp = .
    local p_pp = .
    cap noi ppmlhdfe y_raw Z_it Z_it_cite, absorb(athr_outcome year_outcome) vce(cluster athr_id)
    if _rc == 0 {
        local b_ppr_pp  = _b[Z_it]
        local se_ppr_pp = _se[Z_it]
        local b_diff_pp = _b[Z_it_cite]
        local se_diff_pp = _se[Z_it_cite]
        qui lincom Z_it + Z_it_cite
        local b_cite_pp  = r(estimate)
        local se_cite_pp = r(se)
        qui test Z_it_cite
        local F_pp = r(F)
        local p_pp = r(p)
    }
    else di as error "joint_outcome_test ppml failed (rc=`_rc'); ppml column left missing."
    mat joint_`samp'`suf'[1,3] = `b_ppr_pp'
    mat joint_`samp'`suf'[2,3] = `se_ppr_pp'
    mat joint_`samp'`suf'[3,3] = `b_cite_pp'
    mat joint_`samp'`suf'[4,3] = `se_cite_pp'
    mat joint_`samp'`suf'[5,3] = `b_diff_pp'
    mat joint_`samp'`suf'[6,3] = `se_diff_pp'
    mat joint_`samp'`suf'[7,3] = `F_pp'
    mat joint_`samp'`suf'[8,3] = `p_pp'

    di as text "joint outcome test `samp'`suf':  H0 beta_ppr = beta_cite (same H0 in three flavors)"
    di as text "  --- log      : β_ln_ppr    = " %9.4f `b_ppr_ln'  "  β_ln_cite    = " %9.4f `b_cite_ln'  "  diff = " %9.4f `b_diff_ln'  "  F = " %9.4f `F_ln'  "  p = " %9.4f `p_ln'
    di as text "  --- norm lvl : β_ppr/mean  = " %9.4f `b_ppr_nr'  "  β_cite/mean  = " %9.4f `b_cite_nr'  "  diff = " %9.4f `b_diff_nr'  "  F = " %9.4f `F_nr'  "  p = " %9.4f `p_nr'
    di as text "  --- ppml     : β_ppr (sel) = " %9.4f `b_ppr_pp'  "  β_cite (sel) = " %9.4f `b_cite_pp'  "  diff = " %9.4f `b_diff_pp'  "  F = " %9.4f `F_pp'  "  p = " %9.4f `p_pp'

    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'
    qui matrix_to_txt, saving("../output/tables/`samp'/joint_outcome_test`suf'.txt") ///
        matrix(joint_`samp'`suf') title(<tab:joint_outcome_test`suf'>) format(%20.4f) replace
end

program joint_sample_test
    // Stacked DiD across the all_jrnls and top_jrnls samples (same outcome:
    // ppr_cnt) so we get the joint covariance of beta_all and beta_top and
    // can Wald-test H0: beta_all = beta_top. Rejecting => the paper-count
    // response in top-tier outlets differs from the response measured across
    // all outlets, i.e. the cut is not tier-uniform.
    syntax, [r1r2(int 0) public(int 0) r1_only(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"

    cap confirm file ../temp/es_all_jrnls`suf'.dta
    if _rc {
        di as error "joint_sample_test: ../temp/es_all_jrnls`suf'.dta missing; skipping."
        exit
    }
    cap confirm file ../temp/es_top_jrnls`suf'.dta
    if _rc {
        di as error "joint_sample_test: ../temp/es_top_jrnls`suf'.dta missing; skipping."
        exit
    }

    use ../temp/es_all_jrnls`suf', clear
    keep athr_id year exposure ppr_cnt
    rename ppr_cnt y
    gen sample = 0     // all_jrnls
    save ../temp/stack_all_jrnls`suf', replace

    use ../temp/es_top_jrnls`suf', clear
    keep athr_id year exposure ppr_cnt
    rename ppr_cnt y
    gen sample = 1     // top_jrnls
    append using ../temp/stack_all_jrnls`suf'

    gen post = year >= 2014
    gen Z_it     = exposure * post
    gen Z_it_top = Z_it * (sample == 1)

    egen athr_sample = group(athr_id sample)
    egen year_sample = group(year sample)

    // Cluster on athr_id so PIs that appear in both samples are not treated
    // as independent across rows.
    reghdfe y Z_it Z_it_top, absorb(athr_sample year_sample) vce(cluster athr_id)

    local b_all   = _b[Z_it]
    local se_all  = _se[Z_it]
    local b_diff  = _b[Z_it_top]
    local se_diff = _se[Z_it_top]
    qui lincom Z_it + Z_it_top
    local b_top   = r(estimate)
    local se_top  = r(se)

    qui test Z_it_top
    local F_w = r(F)
    local p_w = r(p)

    di as text "joint sample test `suf':  H0 beta_all_jrnls = beta_top_jrnls (ppr_cnt)"
    di as text "  beta_all_jrnls   = " %9.4f `b_all'  "   SE = " %9.4f `se_all'
    di as text "  beta_top_jrnls   = " %9.4f `b_top'  "   SE = " %9.4f `se_top'
    di as text "  diff (top - all) = " %9.4f `b_diff' "   SE = " %9.4f `se_diff'
    di as text "  Wald F = " %9.4f `F_w' "   p = " %9.4f `p_w'

    cap mat drop joint_sample`suf'
    mat joint_sample`suf' = J(8,1,.)
    mat joint_sample`suf'[1,1] = `b_all'
    mat joint_sample`suf'[2,1] = `se_all'
    mat joint_sample`suf'[3,1] = `b_top'
    mat joint_sample`suf'[4,1] = `se_top'
    mat joint_sample`suf'[5,1] = `b_diff'
    mat joint_sample`suf'[6,1] = `se_diff'
    mat joint_sample`suf'[7,1] = `F_w'
    mat joint_sample`suf'[8,1] = `p_w'
    mat rownames joint_sample`suf' = b_all se_all b_top se_top b_diff se_diff Wald_F p_value
    mat colnames joint_sample`suf' = stacked

    cap mkdir ../output/tables
    qui matrix_to_txt, saving("../output/tables/joint_sample_test`suf'.txt") ///
        matrix(joint_sample`suf') title(<tab:joint_sample_test`suf'>) format(%20.4f) replace
end

program combine_es_graphs
    syntax, samp(str)
    // Extended outcome list mirrors event_study's outer loop. Position outcomes
    // are attempted; combine_es_graphs already skips outcomes whose young/old
    // .dta files are missing, so pre-position-metrics builds fall through cleanly.
    local position_outcomes n_first_ppr n_middle_ppr n_last_ppr ///
        avg_position avg_position_rat avg_team_size_last avg_team_size_notlast
    foreach yvar in cite_affl_wt ppr_cnt ln_cite_affl_wt ln_ppr_cnt ///
                    cite_affl_wt_any ppr_cnt_any ln_cite_affl_wt_any ln_ppr_cnt_any ///
                    cite_affl_wt_notlast ppr_cnt_notlast ln_cite_affl_wt_notlast ln_ppr_cnt_notlast ///
                    avg_num_coathrs num_grants grants_per_paper grant_density ///
                    `position_outcomes' {
        // Base outcome labels
        if "`yvar'" == "cite_affl_wt"    local var_name = "Citation Weighted Output"
        if "`yvar'" == "cite_affl_wt"    local gap  1
        if "`yvar'" == "ppr_cnt"         local var_name = "Publication Count"
        if "`yvar'" == "ppr_cnt"         local gap 0.5
        if "`yvar'" == "ln_ppr_cnt"      local var_name = "Log Publication Counts"
        if "`yvar'" == "ln_ppr_cnt"      local gap 0.1
        if "`yvar'" == "ln_cite_affl_wt" local var_name = "Log Citation Weighted Output"
        if "`yvar'" == "ln_cite_affl_wt" local gap 0.1
        if "`yvar'" == "ppr_cnt"      & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "cite_affl_wt" & "`samp'" == "top_jrnls" local gap 2
        // _any labels
        if "`yvar'" == "ppr_cnt_any"         local var_name = "Publication Count (any position)"
        if "`yvar'" == "ppr_cnt_any"         local gap 0.5
        if "`yvar'" == "cite_affl_wt_any"    local var_name = "Citation Weighted Output (any position)"
        if "`yvar'" == "cite_affl_wt_any"    local gap 1
        if "`yvar'" == "ln_ppr_cnt_any"      local var_name = "Log Publication Counts (any position)"
        if "`yvar'" == "ln_ppr_cnt_any"      local gap 0.1
        if "`yvar'" == "ln_cite_affl_wt_any" local var_name = "Log Citation Weighted Output (any position)"
        if "`yvar'" == "ln_cite_affl_wt_any" local gap 0.1
        if "`yvar'" == "ppr_cnt_any"      & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "cite_affl_wt_any" & "`samp'" == "top_jrnls" local gap 2
        // _notlast labels
        if "`yvar'" == "ppr_cnt_notlast"         local var_name = "Publication Count (non-last author)"
        if "`yvar'" == "ppr_cnt_notlast"         local gap 0.5
        if "`yvar'" == "cite_affl_wt_notlast"    local var_name = "Citation Weighted Output (non-last author)"
        if "`yvar'" == "cite_affl_wt_notlast"    local gap 1
        if "`yvar'" == "ln_ppr_cnt_notlast"      local var_name = "Log Publication Counts (non-last author)"
        if "`yvar'" == "ln_ppr_cnt_notlast"      local gap 0.1
        if "`yvar'" == "ln_cite_affl_wt_notlast" local var_name = "Log Citation Weighted Output (non-last author)"
        if "`yvar'" == "ln_cite_affl_wt_notlast" local gap 0.1
        if "`yvar'" == "ppr_cnt_notlast"      & "`samp'" == "top_jrnls" local gap 2
        if "`yvar'" == "cite_affl_wt_notlast" & "`samp'" == "top_jrnls" local gap 2
        // Coauthor / grant labels (variable is avg_num_coathrs, not avg_coathrs)
        if "`yvar'" == "avg_num_coathrs" local var_name = "Average Team Size"
        if "`yvar'" == "avg_num_coathrs" local gap 0.5
        if "`yvar'" == "num_grants"        local var_name = "Number of Grants"
        if "`yvar'" == "num_grants"        local gap 0.5
        if "`yvar'" == "grants_per_paper"  local var_name = "Grants per Paper"
        if "`yvar'" == "grants_per_paper"  local gap 0.5
        if "`yvar'" == "grant_density"     local var_name = "Grant Density"
        if "`yvar'" == "grant_density"     local gap 0.5
        // Position labels
        if "`yvar'" == "n_first_ppr"           local var_name = "# First-Author Papers"
        if "`yvar'" == "n_first_ppr"           local gap 0.5
        if "`yvar'" == "n_middle_ppr"          local var_name = "# Middle-Author Papers"
        if "`yvar'" == "n_middle_ppr"          local gap 0.5
        if "`yvar'" == "n_last_ppr"            local var_name = "# Last-Author Papers"
        if "`yvar'" == "n_last_ppr"            local gap 0.5
        if "`yvar'" == "avg_position"          local var_name = "Avg Author Position (1=first, N=last)"
        if "`yvar'" == "avg_position"          local gap 0.5
        if "`yvar'" == "avg_position_rat"      local var_name = "Avg Author Position / Team Size (0-1)"
        if "`yvar'" == "avg_position_rat"      local gap 0.05
        if "`yvar'" == "avg_team_size_last"    local var_name = "Team Size (papers where PI is last)"
        if "`yvar'" == "avg_team_size_last"    local gap 0.5
        if "`yvar'" == "avg_team_size_notlast" local var_name = "Team Size (papers where PI is not last)"
        if "`yvar'" == "avg_team_size_notlast" local gap 0.5
        cap confirm file ../temp/es_`yvar'_r1_r2_public_young.dta
        if _rc {
            di as text "combine_es_graphs: es_`yvar'_r1_r2_public_young.dta missing; skipping."
            continue
        }
        cap confirm file ../temp/es_`yvar'_r1_r2_public_old.dta
        if _rc {
            di as text "combine_es_graphs: es_`yvar'_r1_r2_public_old.dta missing; skipping."
            continue
        }
        use "../temp/es_`yvar'_r1_r2_public_young", clear
        gen group = "young"                                                                             
        replace rel = rel - 0.1                                                                         
        sum b if group == "young" & rel > 0                                                             
        local young_mean : dis %4.3f r(mean)                                                            
        append using ../temp/es_`yvar'_r1_r2_public_old
        replace group = "old" if mi(group)                                                            

        sum b if group == "old" & rel > 0
        local old_mean : dis %4.3f r(mean)
        cap drop year
        gen year = rel + 2014
        tw rcap ub lb year if year != 2012.9 & group == "young",  lcolor(lavender%60) msize(small) || ///
           scatter b year if group == "young", mcolor(lavender%60) msize(small) || ///
           rcap ub lb year if year != 2013   & group == "old",  lcolor(dkorange) msize(small) || ///
           scatter b year if group == "old", mcolor(dkorange) msymbol(smdiamond) msize(small)  ///
           xlab(2010(1)2019) ylab(#8) ///
              yline(0, lcolor(black) lpattern(solid)) ///
              legend(on order(2 "Below Median Age (Post Period Avg: `young_mean')" 4 "Above Median Age (Post Period Avg: `old_mean')" ) pos(7) ring(1) size(small) region(fcolor(none))) xtitle("Year") ytitle("`var_name'") plotregion(margin(sides))
        graph export ../output/figures/`samp'/es_`yvar'_age_split.pdf, replace
    }
end

program robustness
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
    cap mkdir "../output/figures/`samp'/robustness"
    cap mkdir "../output/tables"
    cap mkdir "../output/tables/`samp'"
    cap mkdir "../output/tables/`samp'/robustness"

    // Main (pooled, no-heterogeneity) event study stress tests:
    //     base / + age x year controls / drop late-exit PIs
    // Applied to the same set of headline outcomes we would report in the paper.
    foreach yvar in ppr_cnt cite_affl_wt ppr_cnt_any cite_affl_wt_any ///
                    ppr_cnt_notlast cite_affl_wt_notlast {
        if "`yvar'" == "ppr_cnt"              local var_name "Publication Count"
        if "`yvar'" == "cite_affl_wt"         local var_name "Citation Weighted Output"
        if "`yvar'" == "ppr_cnt_any"          local var_name "Publication Count (any position)"
        if "`yvar'" == "cite_affl_wt_any"     local var_name "Citation Weighted Output (any position)"
        if "`yvar'" == "ppr_cnt_notlast"      local var_name "Publication Count (non-last author)"
        if "`yvar'" == "cite_affl_wt_notlast" local var_name "Citation Weighted Output (non-last author)"
        if regexm("`yvar'", "^ppr_cnt")      local gap 0.5
        if regexm("`yvar'", "^cite_affl_wt") local gap 1
        if regexm("`yvar'", "^ppr_cnt")      & "`samp'" == "top_jrnls" local gap 2
        if regexm("`yvar'", "^cite_affl_wt") & "`samp'" == "top_jrnls" local gap 2

        foreach spec in base ageCtrl noattrit {
            if "`spec'" == "base"     local title "Base (replicates main)"
            if "`spec'" == "ageCtrl"  local title "Age x year controls"
            if "`spec'" == "noattrit" local title "PIs with last real pub year >= 2018"

            use ../temp/es_`samp'`suf', clear
            cap drop rel int_lead* int_lag*
            gen rel = year - 2014
            qui sum rel
            local abs_lag  = abs(r(max))
            local abs_lead = abs(r(min))
            forval i = 1/`abs_lead' {
                gen int_lead`i' = exposure if rel == -`i'
            }
            forval i = 1/`abs_lag' {
                gen int_lag`i'  = exposure if rel == `i'
            }
            gen int_lag0 = exposure if rel == 0
            ds int_lead* int_lag*
            foreach var in `r(varlist)' {
                replace `var' = 0 if mi(`var')
            }
            if "`spec'" == "noattrit" {
                bys athr_id: egen latest_pub = max(cond(ppr_cnt > 0, year, .))
                keep if latest_pub >= 2018
                drop latest_pub
            }
            qui sum rel
            local abs_lag  = abs(r(max))
            local abs_lead = abs(r(min))
            local int_leads
            local int_lags
            forval i = 2/`abs_lead' {
                local int_leads int_lead`i' `int_leads'
            }
            forval i = 0/`abs_lag' {
                local int_lags `int_lags' int_lag`i'
            }
            local addctrl
            if "`spec'" == "ageCtrl" local addctrl c.age_2014#i.year

            cap noi reghdfe `yvar' `int_leads' `int_lags' int_lead1 `addctrl', ///
                    absorb(`fes') vce(cluster `vce_cl')
            if _rc {
                di as error "robustness `samp'`suf' `yvar' `spec' failed (rc=`_rc'); skipping."
                continue
            }
            local ref_b = _b[int_lead1]
            di as text "robustness `yvar' `spec': ref _b[int_lead1] = `ref_b'"
            gunique athr_id
            local n_pi = r(unique)

            preserve
            cap mat drop es
            foreach var in `int_leads' `int_lags' int_lead1 {
                mat row = _b[`var'] - `ref_b', _se[`var']
                if "`var'" == "int_lead1" mat row = 0,0
                mat es = nullmat(es) \ row
            }
            svmat es
            keep es1 es2
            drop if mi(es1)
            rename (es1 es2) (b se)
            gen ub = b + 1.96*se
            gen lb = b - 1.96*se
            gen rel = -4 if _n == 1
            replace rel = rel[_n-1]+1 if _n > 1
            replace rel = rel + 1 if rel >= -1
            replace rel = -1 if rel == `abs_lag' + 1
            gen year = rel + 2014
            hashsort rel
            // persist coefs to .dta so a downstream plot crash doesn't lose results
            save ../temp/robust_es_main_`yvar'_`spec'_`samp'`suf', replace
            sum ub, d
            local ymax = round(r(max),`gap')
            sum lb, d
            local ymin = round(r(min),`gap')
            if inlist("`yvar'", "ln_ppr_cnt", "ln_cite_affl_wt") local ymin = -1
            cap graph drop _all
            cap noi tw rcap ub lb year if year != 2013, lcolor(ebblue%70) msize(vsmall) || ///
              scatter b year, mcolor(ebblue) ///
              , xlab(2010(1)2019) xtitle("Year") ytitle("`var_name'") ///
                ylab(`ymin'(`gap')`ymax') yline(0, lcolor(gs10) lpattern(solid)) ///
                title("Main ES: `title' (N PIs = `n_pi')", size(small)) ///
                legend(off) plotregion(margin(sides))
            cap noi graph export ../output/figures/`samp'/robustness/es_`yvar'_main_`spec'`suf'.pdf, replace
            restore
        }
    }

end

program output_tables
    // dumps the base vs. + market-share DiD matrices built by long_diff,
    // first_diff, and pooled_did. Each matrix has rows = coefs/SEs + N/R2
    // (+ pre_mean for pooled) and cols = base / with_share.
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local wsuf ""
    if "$WEIGHT_MSIM" == "1" local wsuf "_msimwt"
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'
    local position_outcomes ""
    if "$POSITION_OUTCOMES_AVAIL" == "1" {
        local position_outcomes n_first_ppr n_middle_ppr n_last_ppr ///
            avg_position avg_position_rat avg_team_size_last avg_team_size_notlast
    }
    local outcomes cite_affl_wt ppr_cnt ln_cite_affl_wt ln_ppr_cnt ///
                   cite_affl_wt_any ppr_cnt_any ln_cite_affl_wt_any ln_ppr_cnt_any ///
                   cite_affl_wt_notlast ppr_cnt_notlast ln_cite_affl_wt_notlast ln_ppr_cnt_notlast ///
                   avg_num_coathrs num_grants grants_per_paper grant_density ///
                   `position_outcomes'
    // main() clears matrices between weighting modes, so matrices that don't
    // exist in the current run are silently skipped via cap confirm.
    foreach prog in pdid ppml_pdid placebo2011 placebo2012 trim1 trim5 trim10 trim25 {
        foreach yvar of local outcomes {
            cap confirm matrix `prog'_`yvar'
            if !_rc {
                qui matrix_to_txt, saving("../output/tables/`samp'/`prog'_`yvar'`suf'`wsuf'.txt") ///
                    matrix(`prog'_`yvar') title(<tab:`prog'_`yvar'`suf'`wsuf'>) format(%20.4f) replace
            }
        }
    }

    // PPML heterogeneity results collected in ../temp/phet_results_<samp><suf><wsuf>.dta
    // by event_study (long-format: one row per yvar × grp × spec). Dump as a single
    // long-format tab-separated file for easy inspection.
    cap confirm file "../temp/phet_results_`samp'`suf'`wsuf'.dta"
    if !_rc {
        preserve
        use "../temp/phet_results_`samp'`suf'`wsuf'.dta", clear
        export delimited using "../output/tables/`samp'/phet_results`suf'`wsuf'.txt", replace delim(tab)
        restore
    }
    ppml_het_coefplot, samp(`samp') r1r2(`r1r2') public(`public')
end

program ppml_het_coefplot
    // Combined coefficient plot of PPML heterogeneity results (mshrctrl spec).
    // Produces up to three panels per yvar per split_type ({med, quart}):
    //   "pi"      : PI-level groups (age/type/median-productivity/etc.)
    //   "ic_fund" : 21 HERD funding-bucket inst chars
    //   "ic_expx" : 9 expenditure + endowment inst chars
    // Both sides of each pair are plotted (LEVEL β_post under split-form spec),
    // with pair rows visually adjacent (focal side first). Uses ${LBL_<grp>}
    // globals from define_group_labels for y-axis labels; falls back to the
    // group name if no label was defined. Rows whose grp doesn't appear in
    // phet_results are silently skipped (an all-missing or degenerate dummy
    // never got posted upstream).
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    local wsuf ""
    if "$WEIGHT_MSIM" == "1" local wsuf "_msimwt"

    cap confirm file "../temp/phet_results_`samp'`suf'`wsuf'.dta"
    if _rc {
        di as error "ppml_het_coefplot: ../temp/phet_results_`samp'`suf'`wsuf'.dta not found — skipping"
        exit 0
    }

    local ppml_het_yvars ppr_cnt cite_affl_wt ppr_cnt_any cite_affl_wt_any ///
                        ppr_cnt_notlast cite_affl_wt_notlast ///
                        avg_num_coathrs num_grants grants_per_paper grant_density ///
                        n_first_ppr n_middle_ppr n_last_ppr

    // Inst-char category split (used for both med and quart panels).
    // Funding buckets vs. expenditures + endowment.
    local ic_fund_aliases contr fdlsb fdls fdlsh gntsf hhlsb hhls hhlsh ///
        nflsb nfls nflsh subrf busf fedf tfnd instf nonpf statf lsf hsf biof
    local ic_expx_aliases applx apfx basx bfx clinx devx lscx medx endow

    // Iterate split_type -> panel -> yvar. Each combination writes one PDF.
    foreach st in med quart {
        // Build groups list for this split_type × panel.
        // "pi" panel: existing PI-level groups (median) or PI quartile groups.
        // "ic_fund" and "ic_expx" panels: inst-char groups per split type.
        if "`st'" == "med" {
            local groups_pi     young old r1 r2 ///
                                high_pre_ppr low_pre_ppr ///
                                high_grants low_grants ///
                                big_team small_team ///
                                many_coauth few_coauth ///
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
        else {
            // quart
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

        foreach panel in pi ic_fund ic_expx {
            local groups `groups_`panel''
            local n_groups : word count `groups'
            if `n_groups' == 0 continue

            foreach yvar of local ppml_het_yvars {
                preserve
                use "../temp/phet_results_`samp'`suf'`wsuf'.dta", clear
                keep if yvar == "`yvar'" & spec == "mshrctrl" & split_type == "`st'"
                if _N == 0 {
                    restore
                    continue
                }

                // Attach y position by group ordering; build ylabels list from
                // LBL_<grp> globals (with fallback to raw group name).
                gen y = .
                local ylabs ""
                local i = 0
                foreach g of local groups {
                    local ++i
                    local ypos = `n_groups' + 1 - `i'
                    qui replace y = `ypos' if grp == "`g'"
                    local lbl = "${LBL_`g'}"
                    if "`lbl'" == "" local lbl "`g'"
                    // Truncate long labels so the y-axis stays readable.
                    if length("`lbl'") > 40 local lbl = substr("`lbl'", 1, 37) + "..."
                    local ylabs `ylabs' `ypos' `"`"`lbl'"'"'
                }
                drop if mi(y) | mi(post_b)
                if _N == 0 {
                    restore
                    continue
                }
                gen ub = post_b + 1.96*post_se
                gen lb = post_b - 1.96*post_se

                // Bigger canvas for panels with many rows (ic_fund has ~42;
                // ic_expx has ~18; pi has ~10-14).
                local ysize 6
                if `n_groups' > 20 local ysize 10
                if `n_groups' > 40 local ysize 14
                local labsize small
                if `n_groups' > 20 local labsize vsmall

                tw rcap ub lb y, horizontal lcolor(ebblue%70) msize(vsmall) || ///
                   scatter y post_b, mcolor(ebblue) msize(small) ///
                   , xline(0, lcolor(gs10) lpattern(solid)) ///
                     ylabel(`ylabs', angle(0) labsize(`labsize') noticks nogrid) ///
                     ytitle("") xtitle("Exposure x Post", size(small)) ///
                     xlabel(, labsize(small)) ///
                     legend(off) ///
                     ysize(`ysize') xsize(7) ///
                     plotregion(margin(sides))
                graph export ///
                    "../output/figures/`samp'/ppml_het_coefplot_`yvar'_`st'_`panel'`suf'`wsuf'.pdf", ///
                    replace
                di as text "wrote ../output/figures/`samp'/ppml_het_coefplot_`yvar'_`st'_`panel'`suf'`wsuf'.pdf"
                restore
            }
        }
    }
end

**
main
