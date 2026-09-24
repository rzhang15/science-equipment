set more off
clear all
capture log close
version 17
set scheme modern

local samp all_jrnls
local suf  _r1_r2

program fill_stats
    syntax, mat(name) vars(varlist)
    local nr : word count `vars'
    mat `mat' = J(`nr',9,.)
    local r = 0
    foreach v of local vars {
        local ++r
        qui sum `v' if high == 0
        mat `mat'[`r',1] = r(mean)
        mat `mat'[`r',2] = r(sd)
        local sd_l = r(sd)
        qui sum `v' if high == 1
        mat `mat'[`r',3] = r(mean)
        mat `mat'[`r',4] = r(sd)
        local sd_h = r(sd)
        qui reg `v' high, r
        mat `mat'[`r',5] = _b[high]
        mat `mat'[`r',6] = _se[high]
        mat `mat'[`r',7] = 2 * ttail(e(df_r), abs(_b[high] / _se[high]))
        mat `mat'[`r',8] = _b[high] / sqrt((`sd_l'^2 + `sd_h'^2) / 2)
        mat `mat'[`r',9] = e(N)
    }
    mat rownames `mat' = `vars'
    mat colnames `mat' = mean_low sd_low mean_high sd_high diff se p normdiff N
    mat list `mat', format(%12.4f)
end

use ../output/prepped_samples/es_`samp'`suf', clear
gen nih_cost_k   = nih_total_cost / 1000
gen yrs_lab_2014 = 2014 - min_year
replace foia_athr = 0 if mi(foia_athr)

local out_vars ppr_cnt ppr_cnt_any cite_affl_wt avg_num_coathrs n_grants nih_cost_k
local pi_vars  exposure mkt_spend_shr yrs_lab_2014 public nih_athr foia_athr
foreach v in `pi_vars' cluster_30 {
    qui gegen _chk = sd(`v'), by(athr_id)
    qui count if _chk > 0 & !mi(_chk)
    if r(N) > 0 di as error "`v' varies within athr_id for " r(N) " PI-years"
    drop _chk
}

keep if year < 2014
gcollapse (mean) `out_vars' (first) `pi_vars' cluster_30, by(athr_id)

qui sum exposure, d
local exp_med = r(p50)
gen byte high = exposure > `exp_med'
qui count if high == 0
local n_low = r(N)
qui count if high == 1
local n_high = r(N)
qui count if !mi(n_grants) & high == 0
local n_low_nih = r(N)
qui count if !mi(n_grants) & high == 1
local n_high_nih = r(N)
di as text "exposure median = " %8.4f `exp_med' "; PIs: less-exposed `n_low', more-exposed `n_high'"

recode cluster_30 (2 19 21 = 1) (4 14 = 2) (7 20 = 3) (12 17 18 = 4) (0 1 6 27 = 5) ///
                  (3 5 8 9 10 11 13 15 16 22 23 24 25 26 28 29 = 6), gen(area)
label define area 1 "Molecular and cellular biology" 2 "Materials and bioengineering" ///
                  3 "Biochemistry and chemistry" 4 "Neuroscience and cognition" ///
                  5 "Organismal and environmental biology" 6 "Clinical and disease research"
label values area area
local n_area 6
local clus_vars ""
local clus_labs ""
forval a = 1/`n_area' {
    gen byte area_`a' = area == `a' if !mi(area)
    local clus_vars `clus_vars' area_`a'
    local clus_labs `"`clus_labs' "`: label area `a''""'
}

local vars `out_vars' `pi_vars'
local nr : word count `vars'
fill_stats, mat(balance) vars(`vars')
fill_stats, mat(balance_area) vars(`clus_vars')

cap mkdir ../output/tables
cap mkdir ../output/tables/`samp'
matrix_to_txt, saving("../output/tables/`samp'/balance_pi`suf'.txt") ///
    matrix(balance) title(<tab:balance_pi`suf'>) format(%20.4f) replace
matrix_to_txt, saving("../output/tables/`samp'/balance_area`suf'.txt") ///
    matrix(balance_area) title(<tab:balance_area`suf'>) format(%20.4f) replace

local d = char(36)
forval r = 1/`nr' {
    local fmt %9.2f
    if `r' == 6 local fmt %15.2fc
    if `r' == 9 local fmt %9.1f
    if inlist(`r', 7, 8) local fmt %9.3f
    local cells`r' ""
    forval c = 1/7 {
        local v = balance[`r',`c']
        local f `fmt'
        if `c' == 7 local f %9.3f
        local cell = subinstr(trim(string(abs(`v'), "`f'")), ",", "{,}", .)
        if `v' < 0 local cell `d'-`d'`cell'
        if `c' == 6 local cell (`cell')
        local cells`r' "`cells`r'' & `cell'"
    }
}
local pct_low  = string(100 * `n_low'  / (`n_low' + `n_high'), "%4.1f")
local pct_high = string(100 * `n_high' / (`n_low' + `n_high'), "%4.1f")
local n_low_c    = subinstr(string(`n_low',    "%12.0fc"), ",", "{,}", .)
local n_high_c   = subinstr(string(`n_high',   "%12.0fc"), ",", "{,}", .)
local n_low_nihc = subinstr(string(`n_low_nih',  "%12.0fc"), ",", "{,}", .)
local n_high_nihc= subinstr(string(`n_high_nih', "%12.0fc"), ",", "{,}", .)
local exp_med_c  = string(`exp_med', "%9.3f")

local out ../output/tables/`samp'/balance_pi`suf'.tex
tempname fh
file open `fh' using "`out'", write replace
file write `fh' "\begin{table}[H]" _n
file write `fh' "\centering" _n
file write `fh' "\caption{Balance Across More- and Less-Exposed PIs}" _n
file write `fh' "\label{tab:balance_pi}" _n
file write `fh' "\setstretch{1}" _n
file write `fh' "\setlength{\tabcolsep}{3pt}" _n
file write `fh' "\begin{tabular}{@{}l*{7}{r}@{}}" _n
file write `fh' "\toprule" _n
file write `fh' " & \multicolumn{2}{c}{Less exposed} & \multicolumn{2}{c}{More exposed} & \multicolumn{2}{c}{Difference} & \\" _n
file write `fh' "\cmidrule(lr){2-3} \cmidrule(lr){4-5} \cmidrule(lr){6-7}" _n
file write `fh' " & Mean & SD & Mean & SD & Coef. & (SE) & \$p\$-value \\" _n
file write `fh' "\midrule" _n
file write `fh' "\multicolumn{8}{l}{\textit{Panel A: Pre-period (2010--2013) PI averages}} \\" _n
file write `fh' "\quad Publications (last-author) `cells1' \\" _n
file write `fh' "\quad Publications (any position) `cells2' \\" _n
file write `fh' "\quad Citation-weighted output `cells3' \\" _n
file write `fh' "\quad Coauthors per paper `cells4' \\" _n
file write `fh' "\quad Active NIH grants `cells5' \\" _n
file write `fh' "\quad NIH funding (" _char(92) _char(36) " thousands)`cells6' \\" _n
file write `fh' "\addlinespace" _n
file write `fh' "\multicolumn{8}{l}{\textit{Panel B: PI characteristics}} \\" _n
file write `fh' "\quad Exposure measure `cells7' \\" _n
file write `fh' "\quad Treated-market share \$S_i\$`cells8' \\" _n
file write `fh' "\quad Years as PI in 2014 `cells9' \\" _n
file write `fh' "\quad Public university `cells10' \\" _n
file write `fh' "\quad Matched to NIH records `cells11' \\" _n
file write `fh' "\quad FOIA PI (observed exposure) `cells12' \\" _n
file write `fh' "\midrule" _n
file write `fh' "Number of PIs & `n_low_c' & & `n_high_c' & & & & \\" _n
file write `fh' "\bottomrule" _n
file write `fh' "\end{tabular}" _n
file write `fh' "\floatfoot{\textit{Notes:} One observation per PI in the all-journal R1 and R2 panel (\NPIs\ PIs). More-exposed PIs are those whose exposure measure is above its median across PIs (`exp_med_c'); less-exposed PIs are at or below the median." _n
file write `fh' "Panel A averages each outcome over a PI's pre-merger years, 2010--2013. Coauthors per paper is averaged over pre-period years with at least one last-author publication." _n
file write `fh' "Active NIH grants and NIH funding are observed only for PIs matched to NIH records (`n_low_nihc' less-exposed and `n_high_nihc' more-exposed PIs)." _n
file write `fh' "Panel B reports time-invariant PI characteristics. Years as PI is the number of years since a PI's first last-author publication, measured in 2014. Public university, matched to NIH records, and FOIA PI are shares." _n
file write `fh' "The exposure measure and treated-market share \$S_i\$ are the shift-share cost increase and the pre-merger treated-market spending share defined in Section~\ref{sec:exposure}, observed for FOIA PIs and imputed for the rest." _n
file write `fh' "Difference is the more-exposed minus less-exposed mean, with heteroskedasticity-robust standard errors in parentheses and the \$p\$-value of the two-sided test that it equals zero.}" _n
file write `fh' "\end{table}" _n
file close `fh'
di as text "wrote `out'"

local na : word count `clus_vars'
forval r = 1/`na' {
    local acells`r' ""
    forval c = 1/7 {
        local v = balance_area[`r',`c']
        local cell = trim(string(abs(`v'), "%9.3f"))
        if `v' < 0 local cell `d'-`d'`cell'
        if `c' == 6 local cell (`cell')
        local acells`r' "`acells`r'' & `cell'"
    }
}

local out ../output/tables/`samp'/balance_area`suf'.tex
file open `fh' using "`out'", write replace
file write `fh' "\begin{table}[H]" _n
file write `fh' "\centering" _n
file write `fh' "\caption{Research Areas of More- and Less-Exposed PIs}" _n
file write `fh' "\label{tab:balance_area}" _n
file write `fh' "\setstretch{1}" _n
file write `fh' "\setlength{\tabcolsep}{3pt}" _n
file write `fh' "\begin{tabular}{@{}l*{7}{r}@{}}" _n
file write `fh' "\toprule" _n
file write `fh' " & \multicolumn{2}{c}{Less exposed} & \multicolumn{2}{c}{More exposed} & \multicolumn{2}{c}{Difference} & \\" _n
file write `fh' "\cmidrule(lr){2-3} \cmidrule(lr){4-5} \cmidrule(lr){6-7}" _n
file write `fh' " & Share & SD & Share & SD & Coef. & (SE) & \$p\$-value \\" _n
file write `fh' "\midrule" _n
local r = 0
foreach lab of local clus_labs {
    local ++r
    file write `fh' "`lab' `acells`r'' \\" _n
}
file write `fh' "\midrule" _n
file write `fh' "Number of PIs & `n_low_c' & & `n_high_c' & & & & \\" _n
file write `fh' "\bottomrule" _n
file write `fh' "\end{tabular}" _n
file write `fh' "\floatfoot{\textit{Notes:} One observation per PI in the all-journal R1 and R2 panel (\NPIs\ PIs). More-exposed PIs are those whose exposure measure is above its median across PIs (`exp_med_c'); less-exposed PIs are at or below the median." _n
file write `fh' "Each row is the share of PIs whose pre-period publication text falls in one of six research areas, formed by grouping the 30 topical clusters of PI publication text; shares in each column sum to one." _n
file write `fh' "Difference is the more-exposed minus less-exposed share, with heteroskedasticity-robust standard errors in parentheses and the \$p\$-value of the two-sided test that it equals zero.}" _n
file write `fh' "\end{table}" _n
file close `fh'
di as text "wrote `out'"

keep area high
gen one = 1
gcollapse (count) n = one, by(area high)
bys high: egen tot = total(n)
gen share = 100 * n / tot
drop n tot
reshape wide share, i(area) j(high)
gen diff = share1 - share0
gsort -diff
gen pos    = `n_area' + 1 - _n
gen pos_lo = pos + 0.19
gen pos_hi = pos - 0.19
gen lab0 = string(share0, "%4.1f")
gen lab1 = string(share1, "%4.1f")
local ylabs ""
forval i = 1/`n_area' {
    local ylabs `"`ylabs' `=pos[`i']' "`: label area `=area[`i']''""'
}
qui sum share0
local xmax = r(max)
qui sum share1
local xmax = 1.12 * max(`xmax', r(max))
tw (bar share0 pos_lo, horizontal barwidth(0.34) color(ebblue)) ///
   (bar share1 pos_hi, horizontal barwidth(0.34) color(dkorange)) ///
   (scatter pos_lo share0, msymbol(none) mlabel(lab0) mlabpos(3) mlabcolor(black) mlabsize(small)) ///
   (scatter pos_hi share1, msymbol(none) mlabel(lab1) mlabpos(3) mlabcolor(black) mlabsize(small)), ///
    ylabel(`ylabs', angle(0) nogrid labsize(small) notick) ytitle("") yscale(lstyle(none)) ///
    xlabel(none) xtick(none) xscale(range(0 `xmax') lstyle(none)) ///
    xtitle("Share of PIs (%)", color(black)) ///
    legend(order(1 "Less exposed" 2 "More exposed") pos(12) ring(1) rows(1) size(small) region(lstyle(none)))
cap mkdir ../output/figures
cap mkdir ../output/figures/`samp'
graph export ../output/figures/`samp'/balance_area`suf'.pdf, replace
