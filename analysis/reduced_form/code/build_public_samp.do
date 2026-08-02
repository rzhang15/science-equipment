* Builds the es_all_jrnls_r1_r2_public prepped sample only.
* Program definitions come from analysis.do with its trailing main call stripped;
* ../temp inputs (exposure, match_diag, athr_cluster30, athr_yr_grnt_cnt) are
* reused from the last full run rather than rebuilt.
run "/tmp/claude-67049/-n-holylabs-pakes-lab-Lab-sci-eq/8c382461-193e-48c0-b03b-5663e34dd516/scratchpad/rf_progs.do"

cap log close _all
log using build_public_samp.log, replace text
restrict_samp, samp(all_jrnls) r1r2(1) public(1)
log close
