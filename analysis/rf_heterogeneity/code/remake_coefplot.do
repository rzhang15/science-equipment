global HET_SKIP_MAIN 1
do analysis.do
define_group_labels
ppml_het_coefplot, samp(all_jrnls) r1r2(1) public(0)
ppml_het_coefplot, samp(all_jrnls) r1r2(1) public(1) yvar(ppr_cnt)
