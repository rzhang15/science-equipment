run "/tmp/claude-67049/-n-holylabs-pakes-lab-Lab-sci-eq/8c382461-193e-48c0-b03b-5663e34dd516/scratchpad/rf_progs.do"

cap log close _all
log using build_public_samp.log, replace text
restrict_samp, samp(all_jrnls) r1r2(1) public(1)
log close
