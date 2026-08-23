set more off
clear all
capture log close
version 17

* Numbers for tab:sumstats_pi: summary statistics for the PI research-output
* panel, computed on the prepped sample from the last analysis.do run. Writes
* the filled table to ../output/tables/<samp>/sumstats_pi<suf>.tex; the N
* column and notes keep the paper's \NPIs / \RFObs / \CoauthObs /
* \NNIHMatched / \GrantObs macros, whose current values are displayed below.
local samp all_jrnls
local suf  _r1_r2

use ../output/prepped_samples/es_`samp'`suf', clear
gen nih_cost_k = nih_total_cost / 1000
* years since the PI's first last-author publication, as of 2014
gen yrs_lab_2014 = 2014 - min_year

local vars ppr_cnt ppr_cnt_any cite_affl_wt avg_num_coathrs n_grants ///
           nih_cost_k yrs_lab_2014 exposure mkt_spend_shr
mat sumstats = J(9,8,.)
local r = 0
foreach v of local vars {
    local ++r
    qui sum `v', d
    mat sumstats[`r',1] = r(mean)
    mat sumstats[`r',2] = r(sd)
    mat sumstats[`r',3] = r(min)
    mat sumstats[`r',4] = r(p25)
    mat sumstats[`r',5] = r(p50)
    mat sumstats[`r',6] = r(p75)
    mat sumstats[`r',7] = r(max)
    mat sumstats[`r',8] = r(N)
}
mat rownames sumstats = `vars'
mat colnames sumstats = mean sd min p25 p50 p75 max N
mat list sumstats, format(%12.3f)

qui count
local n_rfobs = r(N)
qui count if !mi(avg_num_coathrs)
local n_coauth = r(N)
qui count if !mi(n_grants)
local n_grant = r(N)
qui count if !mi(nih_cost_k)
local n_cost = r(N)
qui gunique athr_id
local n_pis = r(unique)
qui gunique athr_id if !mi(n_grants)
local n_nih = r(unique)
mat sumstats_counts = `n_pis' \ `n_rfobs' \ `n_coauth' \ `n_nih' \ `n_grant' \ `n_cost'
mat rownames sumstats_counts = NPIs RFObs CoauthObs NNIHMatched GrantObs CostObs
mat colnames sumstats_counts = value
di as text _newline "paper macro values (update the preamble if these moved):"
di as text "  \NPIs        = " %12.0fc `n_pis'
di as text "  \RFObs       = " %12.0fc `n_rfobs'
di as text "  \CoauthObs   = " %12.0fc `n_coauth'
di as text "  \NNIHMatched = " %12.0fc `n_nih'
di as text "  \GrantObs    = " %12.0fc `n_grant'
if `n_cost' != `n_grant' {
    di as error "nih_total_cost is observed for `n_cost' PI-years vs `n_grant' for n_grants; \GrantObs covers both rows"
}

cap mkdir ../output/tables
cap mkdir ../output/tables/`samp'
matrix_to_txt, saving("../output/tables/`samp'/sumstats_pi`suf'.txt") ///
    matrix(sumstats) title(<tab:sumstats_pi`suf'>) format(%20.4f) replace
matrix_to_txt, saving("../output/tables/`samp'/sumstats_pi_counts`suf'.txt") ///
    matrix(sumstats_counts) title(<tab:sumstats_pi_counts`suf'>) format(%20.0f) replace

* two decimals everywhere except years as PI (one) and exposure/share (three);
* NIH dollars get {,} separators past 1,000
local d = char(36)
forval r = 1/9 {
    local fmt %9.2f
    if `r' == 6 local fmt %15.2fc
    if `r' == 7 local fmt %9.1f
    if inlist(`r', 8, 9) local fmt %9.3f
    local cells`r' ""
    forval c = 1/7 {
        local v = sumstats[`r',`c']
        local cell = subinstr(trim(string(abs(`v'), "`fmt'")), ",", "{,}", .)
        if `v' < 0 local cell `d'-`d'`cell'
        local cells`r' "`cells`r'' & `cell'"
    }
}

local out ../output/tables/`samp'/sumstats_pi`suf'.tex
tempname fh
file open `fh' using "`out'", write replace
file write `fh' "\begin{table}[H]" _n
file write `fh' "\centering" _n
file write `fh' "\caption{Summary Statistics for the PI Research-Output Panel}" _n
file write `fh' "\label{tab:sumstats_pi}" _n
file write `fh' "\setstretch{1}" _n
file write `fh' "\setlength{\tabcolsep}{3pt}" _n
file write `fh' "\begin{tabular}{@{}l*{8}{r}@{}}" _n
file write `fh' "\toprule" _n
file write `fh' " & Mean & SD & Min & P25 & Median & P75 & Max & N \\" _n
file write `fh' "\midrule" _n
file write `fh' "\multicolumn{9}{l}{\textit{Panel A: PI-year outcomes}} \\" _n
file write `fh' "\quad Publications (last-author) `cells1' & \RFObs \\" _n
file write `fh' "\quad Publications (any position) `cells2' & \RFObs \\" _n
file write `fh' "\quad Citation-weighted output `cells3' & \RFObs \\" _n
file write `fh' "\quad Coauthors per paper `cells4' & \CoauthObs \\" _n
file write `fh' "\quad Active NIH grants `cells5' & \GrantObs \\" _n
file write `fh' "\quad NIH funding (" _char(92) _char(36) " thousands)`cells6' & \GrantObs \\" _n
file write `fh' "\addlinespace" _n
file write `fh' "\multicolumn{9}{l}{\textit{Panel B: PI characteristics}} \\" _n
file write `fh' "\quad Years as PI in 2014 `cells7' & \RFObs \\" _n
file write `fh' "\quad Exposure measure `cells8' & \RFObs \\" _n
file write `fh' "\quad Treated-market share \$S_i\$`cells9' & \RFObs \\" _n
file write `fh' "\bottomrule" _n
file write `fh' "\end{tabular}" _n
file write `fh' "\floatfoot{\textit{Notes:} The sample is the all-journal PI-year panel of R1 and R2 university PIs, 2010--2019, covering \NPIs\ PIs and \RFObs\ PI-years." _n
file write `fh' "Panel A reports PI-year outcomes, whose mean-median gaps reflect the skewness that motivates the Poisson and log specifications used in the main text." _n
file write `fh' "Publications (last-author) is the outcome in our main analysis, and publications (any position) counts a PI's papers in any authorship position." _n
file write `fh' "Coauthors per paper is an average over a PI's papers in a year and is observed for \CoauthObs\ PI-years, since a per-paper average requires at least one publication." _n
file write `fh' "Active NIH grants and annual NIH funding are observed for the \NNIHMatched\ PIs matched to NIH records, \GrantObs\ PI-years." _n
file write `fh' "Panel B reports PI characteristics. Years as PI is the number of years since a PI's first last-author publication, measured in 2014." _n
file write `fh' "The exposure measure and treated-market share \$S_i\$ are the shift-share cost increase and the pre-merger treated-market spending share defined in Section~\ref{sec:exposure}, observed for FOIA PIs and imputed for the rest.}" _n
file write `fh' "\end{table}" _n
file close `fh'
di as text "wrote `out'"
