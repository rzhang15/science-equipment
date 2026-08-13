set more off
clear all
capture log close
version 17

* Numbers for tab:rf_funcform: {Poisson, OLS levels, OLS log(1+y)} x
* {author+year FE, university+cluster+year FE}, with and without the S_i
* control, on the prepped sample from the last analysis.do run. Writes the
* filled table to ../output/tables/<samp>/robustness/rf_funcform<suf>.tex;
* column (1) keeps the paper's \RFCoef / \RFObs / \OutputDecline macros.
local samp all_jrnls
local suf  _r1_r2

use ../output/prepped_samples/es_`samp'`suf', clear
gen post       = year >= 2014
gen Z_it       = exposure      * post
gen Z_share_it = mkt_spend_shr * post
gen ln_ppr_cnt = ln(1 + ppr_cnt)

mat funcform = J(9,6,.)
local col 0
foreach est in ppml ols ols_ln {
    local cmd  reghdfe
    local yvar ppr_cnt
    if "`est'" == "ppml"   local cmd  ppmlhdfe
    if "`est'" == "ols_ln" local yvar ln_ppr_cnt
    foreach fe in athr inst {
        local ++col
        local fes    athr_id year
        local vce_cl athr_id
        if "`fe'" == "inst" {
            local fes    inst_id cluster_30 year
            local vce_cl inst_id
        }

        `cmd' `yvar' Z_it Z_share_it, absorb(`fes') vce(cluster `vce_cl')
        mat funcform[1,`col'] = _b[Z_it]
        mat funcform[2,`col'] = _se[Z_it]
        local b = _b[Z_it]
        qui sum exposure if e(sample)
        local xbar = r(mean)
        qui sum ppr_cnt if year < 2014 & e(sample)
        local ymn = r(mean)
        * decline for the average PI as a percent of the pre-period mean count
        if "`est'" == "ppml"   local decl = 100 * (1 - exp(`b'*`xbar'))
        if "`est'" == "ols"    local decl = -100 * `b' * `xbar' / `ymn'
        if "`est'" == "ols_ln" local decl = 100 * (1 - exp(`b'*`xbar')) * (1 + `ymn') / `ymn'
        mat funcform[5,`col'] = `decl'
        mat funcform[6,`col'] = `ymn'
        mat funcform[7,`col'] = e(N)
        mat funcform[8,`col'] = `xbar'

        `cmd' `yvar' Z_it, absorb(`fes') vce(cluster `vce_cl')
        mat funcform[3,`col'] = _b[Z_it]
        mat funcform[4,`col'] = _se[Z_it]
        mat funcform[9,`col'] = e(N)
    }
}
mat rownames funcform = b_wshare se_wshare b_base se_base decline_pct ///
                        pre_mean N_wshare avg_exposure N_base
mat colnames funcform = pois_athr pois_inst ols_athr ols_inst lnols_athr lnols_inst
mat list funcform, format(%9.4f)

cap mkdir ../output/tables
cap mkdir ../output/tables/`samp'
cap mkdir ../output/tables/`samp'/robustness
matrix_to_txt, saving("../output/tables/`samp'/robustness/funcform`suf'.txt") ///
    matrix(funcform) title(<tab:funcform`suf'>) format(%20.4f) replace

forval c = 1/6 {
    foreach p in w n {
        local r  = cond("`p'" == "w", 1, 3)
        local b  = funcform[`r',`c']
        local se = funcform[`r'+1,`c']
        local t  = abs(`b'/`se')
        local st`p'`c' = cond(`t' >= 2.576, "^{***}", cond(`t' >= 1.960, "^{**}", cond(`t' >= 1.645, "^{*}", "")))
        local b`p'`c'  = trim(string(`b', "%6.3f"))
        local se`p'`c' = trim(string(`se', "%6.3f"))
    }
    local dc`c' = trim(string(funcform[5,`c'], "%4.1f"))
    local nn`c' = subinstr(trim(string(funcform[7,`c'], "%12.0fc")), ",", "{,}", .)
}

local out ../output/tables/`samp'/robustness/rf_funcform`suf'.tex
* closing $ via char(36): "\$" fails to escape right after an empty macro
local d = char(36)
tempname fh
file open `fh' using "`out'", write replace
file write `fh' "\begin{table}[H]" _n
file write `fh' "\centering" _n
file write `fh' "\caption{Robustness of the Output Effect to Functional Form and Fixed Effects}" _n
file write `fh' "\label{tab:rf_funcform}" _n
file write `fh' "\begin{tabular}{l cc cc cc}" _n
file write `fh' "\toprule" _n
file write `fh' " & \multicolumn{2}{c}{Poisson} & \multicolumn{2}{c}{OLS Levels} & \multicolumn{2}{c}{OLS Log} \\" _n
file write `fh' "\cmidrule(lr){2-3}\cmidrule(lr){4-5}\cmidrule(lr){6-7}" _n
file write `fh' " & (1) & (2) & (3) & (4) & (5) & (6) \\" _n
file write `fh' "\midrule" _n
file write `fh' "\multicolumn{7}{l}{\textit{Post \$\times\$ Exposure}} \\[2pt]" _n
file write `fh' "\quad With \$S_i\$ control   & \$\RFCoef`stw1'`d' & \$`bw2'`stw2'`d' & \$`bw3'`stw3'`d' & \$`bw4'`stw4'`d' & \$`bw5'`stw5'`d' & \$`bw6'`stw6'`d' \\" _n
file write `fh' "                          & \$(\RFCoefSd)\$ & \$(`sew2')\$ & \$(`sew3')\$ & \$(`sew4')\$ & \$(`sew5')\$ & \$(`sew6')\$ \\" _n
file write `fh' "\quad No \$S_i\$ control     & \$\RFCoefRaw`stn1'`d' & \$`bn2'`stn2'`d' & \$`bn3'`stn3'`d' & \$`bn4'`stn4'`d' & \$`bn5'`stn5'`d' & \$`bn6'`stn6'`d' \\" _n
file write `fh' "                          & \$(\RFCoefRawSd)\$ & \$(`sen2')\$ & \$(`sen3')\$ & \$(`sen4')\$ & \$(`sen5')\$ & \$(`sen6')\$ \\" _n
file write `fh' "\addlinespace" _n
file write `fh' "Implied output decline (\%) & \OutputDecline & `dc2' & `dc3' & `dc4' & `dc5' & `dc6' \\" _n
file write `fh' "\midrule" _n
file write `fh' "Author \$+\$ year FE          & \$\checkmark\$ &              & \$\checkmark\$ &              & \$\checkmark\$ &              \\" _n
file write `fh' "University \$+\$ cluster + year FE    &              & \$\checkmark\$ &              & \$\checkmark\$ &              & \$\checkmark\$ \\" _n
file write `fh' "\midrule" _n
file write `fh' "Pre-period mean             & \PoisMean & \PoisMean & \PoisMean & \PoisMean & \PoisMean & \PoisMean \\" _n
file write `fh' "Observations                & \RFObs & `nn2' & `nn3' & `nn4' & `nn5' & `nn6' \\" _n
file write `fh' "\bottomrule" _n
file write `fh' "\end{tabular}" _n
file write `fh' "\floatfoot{\textit{Notes:} Each column is a separate difference-in-differences regression of annual publication counts on the interaction of post-merger timing with PI exposure, estimated on the panel of \NPIs\ PIs observed 2010--2019\ with PI and year fixed effects." _n
file write `fh' "Columns (1) and (2) estimate a Poisson (PPML) model, columns (3) and (4) ordinary least squares in levels, and columns (5) and (6) ordinary least squares in the log of one plus the count." _n
file write `fh' "Odd columns use author and year fixed effects, even columns replace the author fixed effect with university and cluster fixed effects, as indicated at the foot of the table." _n
file write `fh' "Each specification is reported with and without the treated-market share \$S_i\$ as a control, following \citet{borusyak_quasi-experimental_2022}." _n
file write `fh' "The implied output decline is the reduction for the average PI, at exposure \AvgExposure, implied by the with-\$S_i\$ coefficient and expressed as a percent of the pre-period mean, so that it is comparable across estimators whose coefficients are in different units." _n
file write `fh' "The pre-period mean is the average pre-merger publication count per PI-year on the estimation sample." _n
file write `fh' "Columns (2) through (6) are estimated on the same sample as column (1)." _n
file write `fh' "Column (1) with the share control is the specification reported in Table~\ref{tab:rf_main}." _n
file write `fh' "Standard errors clustered at the PI level in parentheses. Significance: \$^{*}\$ \$p<0.10\$, \$^{**}\$ \$p<0.05\$, \$^{***}\$ \$p<0.01\$.}" _n
file write `fh' "\end{table}" _n
file close `fh'
di as text "wrote `out'"
