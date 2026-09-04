set more off
clear all
capture log close
version 17

local samp all_jrnls
local suf  _r1_r2
local hisim_pct 50

use ../output/prepped_samples/es_`samp'`suf', clear
gen post = year >= 2014
gen exposure_rn = cond(mkt_spend_shr > 0, exposure / mkt_spend_shr, 0)
gen Z_it  = exposure      * post
gen Zs_it = mkt_spend_shr * post
gen Z_rn  = exposure_rn   * post

bys athr_id: gen byte _hs_one = _n == 1
qui _pctile max_sim if _hs_one == 1 & foia_athr != 1, p(`=100 - `hisim_pct'')
local hs_cut = r(r1)
gen byte hisim = max_sim >= `hs_cut'
di as text "hisim cutoff (top `hisim_pct'% of imputed PIs): max_sim >= " %6.4f `hs_cut'

mat expvar = J(9,5,.)
local xvar1 Z_it
local svar1 Zs_it
local cond1
local wt1
local xvar2 Z_rn
local svar2
local cond2
local wt2
local xvar3 Z_it
local svar3 Zs_it
local cond3 & exposure > 0
local wt3
local xvar4 Z_it
local svar4 Zs_it
local cond4
local wt4 [pw=max_sim]
local xvar5 Z_it
local svar5 Zs_it
local cond5 & hisim == 1
local wt5

forval c = 1/5 {
    local mean1 exposure
    if `c' == 2 local mean1 exposure_rn
    local meanwt ""
    if "`wt`c''" != "" local meanwt [aw=max_sim]

    ppmlhdfe ppr_cnt `xvar`c'' `svar`c'' `wt`c'' if 1 `cond`c'', ///
        absorb(athr_id year) vce(cluster athr_id)
    mat expvar[1,`c'] = _b[`xvar`c'']
    mat expvar[2,`c'] = _se[`xvar`c'']
    local b = _b[`xvar`c'']
    qui sum `mean1' `meanwt' if e(sample)
    local xbar = r(mean)
    qui sum ppr_cnt if year < 2014 & e(sample)
    local ymn = r(mean)
    mat expvar[5,`c'] = 100 * (1 - exp(`b'*`xbar'))
    mat expvar[6,`c'] = `ymn'
    mat expvar[7,`c'] = e(N)
    mat expvar[8,`c'] = `xbar'

    if "`svar`c''" != "" {
        ppmlhdfe ppr_cnt `xvar`c'' `wt`c'' if 1 `cond`c'', ///
            absorb(athr_id year) vce(cluster athr_id)
        mat expvar[3,`c'] = _b[`xvar`c'']
        mat expvar[4,`c'] = _se[`xvar`c'']
        mat expvar[9,`c'] = e(N)
    }
}
mat rownames expvar = b_wshare se_wshare b_base se_base decline_pct ///
                      pre_mean N_wshare avg_exposure N_base
mat colnames expvar = baseline renorm positive precision hisim`hisim_pct'
mat list expvar, format(%9.4f)

cap mkdir ../output/tables
cap mkdir ../output/tables/`samp'
cap mkdir ../output/tables/`samp'/robustness
matrix_to_txt, saving("../output/tables/`samp'/robustness/exposure_variants`suf'.txt") ///
    matrix(expvar) title(<tab:exposure_variants`suf'>) format(%20.4f) replace

forval c = 1/5 {
    foreach p in w n {
        local r  = cond("`p'" == "w", 1, 3)
        local b  = expvar[`r',`c']
        local se = expvar[`r'+1,`c']
        if `b' == . {
            local b`p'`c' ""
            continue
        }
        local t  = abs(`b'/`se')
        local st`p'`c' = cond(`t' >= 2.576, "^{***}", cond(`t' >= 1.960, "^{**}", cond(`t' >= 1.645, "^{*}", "")))
        local b`p'`c'  = trim(string(`b', "%6.3f"))
        local se`p'`c' = trim(string(`se', "%6.3f"))
    }
    local dc`c' = trim(string(expvar[5,`c'], "%4.1f"))
    local pm`c' = trim(string(expvar[6,`c'], "%5.2f"))
    local nn`c' = subinstr(trim(string(expvar[7,`c'], "%12.0fc")), ",", "{,}", .)
}

local out ../output/tables/`samp'/robustness/rf_exposure_variants`suf'.tex
* char(36): "\$" fails to escape right after an empty macro
local d = char(36)
tempname fh
file open `fh' using "`out'", write replace
file write `fh' "\begin{table}[H]" _n
file write `fh' "\centering" _n
file write `fh' "\caption{Robustness of the Output Effect to the Exposure Measure}" _n
file write `fh' "\label{tab:rf_exposure_variants}" _n
file write `fh' "\begin{tabular}{l ccccc}" _n
file write `fh' "\toprule" _n
file write `fh' " & (1) & (2) & (3) & (4) & (5) \\" _n
file write `fh' " & Baseline & Renormalized & Positive & Precision- & High- \\" _n
file write `fh' " &          & shares       & exposure & weighted   & similarity \\" _n
file write `fh' "\midrule" _n
file write `fh' "\multicolumn{6}{l}{\textit{Post \$\times\$ Exposure}} \\[2pt]" _n
file write `fh' "\quad With \$S_i\$ control   & \$\RFCoef`stw1'`d' & \$`bw2'`stw2'`d' & \$`bw3'`stw3'`d' & \$`bw4'`stw4'`d' & \$`bw5'`stw5'`d' \\" _n
file write `fh' "                          & \$(\RFCoefSd)\$ & \$(`sew2')\$ & \$(`sew3')\$ & \$(`sew4')\$ & \$(`sew5')\$ \\" _n
file write `fh' "\quad No \$S_i\$ control     & \$\RFCoefRaw`stn1'`d' & --- & \$`bn3'`stn3'`d' & \$`bn4'`stn4'`d' & \$`bn5'`stn5'`d' \\" _n
file write `fh' "                          & \$(\RFCoefRawSd)\$ &  & \$(`sen3')\$ & \$(`sen4')\$ & \$(`sen5')\$ \\" _n
file write `fh' "\addlinespace" _n
file write `fh' "Implied output decline (\%) & \OutputDecline & `dc2' & `dc3' & `dc4' & `dc5' \\" _n
file write `fh' "\midrule" _n
file write `fh' "Pre-period mean             & \PoisMean & `pm2' & `pm3' & `pm4' & `pm5' \\" _n
file write `fh' "Observations                & \RFObs & `nn2' & `nn3' & `nn4' & `nn5' \\" _n
file write `fh' "\bottomrule" _n
file write `fh' "\end{tabular}" _n
file write `fh' "\floatfoot{\textit{Notes:} Each column is a Poisson (PPML) difference-in-differences regression of annual publication counts on the interaction of post-merger timing with PI exposure, with author and year fixed effects and standard errors clustered at the PI level." _n
file write `fh' "Column (1) is the baseline exposure measure of Table~\ref{tab:rf_main}." _n
file write `fh' "Column (2) renormalizes each PI's market shares to sum to one (exposure divided by the treated-market share \$S_i\$); renormalization is the \citet{borusyak_quasi-experimental_2022} alternative to including \$S_i\$ as a control, so the no-control row does not apply." _n
file write `fh' "Column (3) restricts the panel to PIs with strictly positive exposure." _n
file write `fh' "Column (4) weights each PI by the maximum text similarity of their publications to a FOIA PI, so that precisely imputed exposures receive more weight; the implied decline is evaluated at the similarity-weighted average exposure." _n
file write `fh' "Column (5) restricts to the top `hisim_pct'\% of imputed PIs by maximum similarity (FOIA PIs, whose exposure is observed, are always retained)." _n
file write `fh' "The implied output decline is the reduction for the average PI implied by the with-\$S_i\$ coefficient (for column (2), the renormalized coefficient) at that column's average exposure, expressed as a percent of the pre-period mean." _n
file write `fh' "Significance: \$^{*}\$ \$p<0.10\$, \$^{**}\$ \$p<0.05\$, \$^{***}\$ \$p<0.01\$.}" _n
file write `fh' "\end{table}" _n
file close `fh'
di as text "wrote `out'"
