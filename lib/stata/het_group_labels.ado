program het_group_labels
    global PI_Q_BASES pre_ppr nihg nihd
    global LBL_young        "Early-career PIs"
    global LBL_old          "Late-career PIs"
    global LBL_young_ns     "Early-career PIs (excl. solo)"
    global LBL_old_ns       "Late-career PIs (excl. solo)"
    global LBL_young_any    "Early-career PIs (first pub ever)"
    global LBL_old_any      "Late-career PIs (first pub ever)"
    global LBL_lab_lt10     "Early-career PIs (<10 yrs)"
    global LBL_lab_10_20    "Mid-career PIs (10-20 yrs)"
    global LBL_lab_20p      "Late-career PIs (20+ yrs)"
    global LBL_q1_labage    "Q1 lab age (newest labs)"
    global LBL_q2_labage    "Q2 lab age"
    global LBL_q3_labage    "Q3 lab age"
    global LBL_q4_labage    "Q4 lab age (most established)"
    global LBL_r1           "R1"
    global LBL_r2           "R2"
    global LBL_pub_inst     "Public institutions"
    global LBL_priv_inst    "Private institutions"
    global LBL_high_nihg    "More NIH grants at baseline"
    global LBL_low_nihg     "Fewer NIH grants at baseline"
    global LBL_high_nihd    "More NIH funding at baseline"
    global LBL_low_nihd     "Less NIH funding at baseline"
    global LBL_young_nih    "Early-career PIs (NIH-matched)"
    global LBL_old_nih      "Late-career PIs (NIH-matched)"
    global LBL_young_surv   "Early-career PIs (publishing in 2020-22)"
    global LBL_old_surv     "Late-career PIs"
    global LBL_young_sb     "Early-career PIs (publishing in 2020-22)"
    global LBL_old_sb       "Late-career PIs (publishing in 2020-22)"
    global LBL_y_longtrain  "Early-career PIs, longer training"
    global LBL_y_shorttrain "Early-career PIs, shorter training"
    global LBL_yhigh_nihd   "Early-career, more NIH (young median)"
    global LBL_ylow_nihd    "Early-career, less NIH (young median)"
    global LBL_yq4_nihd     "Early-career, Q4 NIH (young quartiles)"
    global LBL_yq1_nihd     "Early-career, Q1 NIH (young quartiles)"
    global LBL_new_lab      "Newer labs"
    global LBL_est_lab      "Established labs"
    global LBL_big_msa      "Larger MSAs"
    global LBL_small_msa    "Smaller MSAs"

    global LBL_q1_pre_ppr   "Q1 baseline productivity"
    global LBL_q4_pre_ppr   "Q4 baseline productivity"
    global LBL_q1_nihg      "Q1 baseline NIH grants"
    global LBL_q4_nihg      "Q4 baseline NIH grants"
    global LBL_q1_nihd      "Q1 baseline NIH funding"
    global LBL_q4_nihd      "Q4 baseline NIH funding"

    local ic_lbl_contr "Total contract funding"
    local ic_lbl_fdlsb "Federal life-sci biology funding"
    local ic_lbl_fdls  "Federal life-sci funding"
    local ic_lbl_fdlsh "Federal life-sci health-sci funding"
    local ic_lbl_gntsf "Grants funding"
    local ic_lbl_hhlsb "HHS life-sci biology funding"
    local ic_lbl_hhls  "HHS life-sci funding"
    local ic_lbl_hhlsh "HHS life-sci health-sci funding"
    local ic_lbl_nflsb "Non-federal life-sci biology funding"
    local ic_lbl_nfls  "Non-federal life-sci funding"
    local ic_lbl_nflsh "Non-federal life-sci health-sci funding"
    local ic_lbl_subrf "Subrecipient funding"
    local ic_lbl_busf  "Business funding"
    local ic_lbl_fedf  "Total federal funding"
    local ic_lbl_tfnd  "Institutional R&D funding"
    local ic_lbl_instf "Institutional funding"
    local ic_lbl_nonpf "Non-profit funding"
    local ic_lbl_statf "State funding"
    local ic_lbl_lsf   "Institutional life-sci funding"
    local ic_lbl_hsf   "Health-sci funding"
    local ic_lbl_biof  "Biology funding"
    local ic_lbl_applx "Applied research expenditures"
    local ic_lbl_apfx  "Federal applied research expenditures"
    local ic_lbl_basx  "Basic research expenditures"
    local ic_lbl_bfx   "Federal basic research expenditures"
    local ic_lbl_clinx "Clinical trial expenditures"
    local ic_lbl_devx  "Development expenditures"
    local ic_lbl_lscx  "Life-sci capital expenditures"
    local ic_lbl_medx  "Medical school expenditures"
    local ic_lbl_endow "Institutional endowment"
    local ic_lbl_nihd  "NIH funding at baseline"
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
    global COEFPLOT_PI_PAIRS `" "young old" "r1 r2" "pub_inst priv_inst" "high_nihd low_nihd" "'
end
