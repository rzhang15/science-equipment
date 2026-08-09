* Quick pass: event study only, no_clin sample (all_jrnls, R1+R2, unweighted)
cap mkdir ../temp
shell sed 's/^main$//' analysis.do > ../temp/analysis_programs.do
do ../temp/analysis_programs.do

global WEIGHT_MSIM 0
global QUICK_TOPJRNL 0
cap mkdir ../output/figures/all_jrnls
gather_external_data
restrict_samp, samp(all_jrnls) r1r2(1) public(0) no_clin(1)
mat drop _all
event_study,   samp(all_jrnls) r1r2(1) public(0) no_clin(1)
