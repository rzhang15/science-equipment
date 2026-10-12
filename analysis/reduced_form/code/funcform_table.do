set more off
clear all
capture log close
version 17

local samp all_jrnls
local suf  _r1_r2

use ../output/prepped_samples/es_`samp'`suf', clear
gen post       = year >= 2014
gen Z_it       = exposure      * post
gen Z_share_it = mkt_spend_shr * post
gen ln_ppr_cnt = ln(1 + ppr_cnt)

local fe_sets athr clyr inst
local n_fe : word count `fe_sets'
local n_col = 3 * `n_fe'

mat funcform = J(9, `n_col', .)
local col 0
local cnames
foreach est in ppml ols ols_ln {
    local cmd  reghdfe
    local yvar ppr_cnt
    if "`est'" == "ppml"   local cmd  ppmlhdfe
    if "`est'" == "ols_ln" local yvar ln_ppr_cnt
    foreach fe of local fe_sets {
        local ++col
        local cnames `cnames' `est'_`fe'
        local fes    athr_id year
        local vce_cl athr_id
        local mainx  ""
        local mains  ""
        if "`fe'" == "clyr" {
            local fes    athr_id i.cluster_30#i.year
        }
        if "`fe'" == "inst" {
            local fes    inst_id i.cluster_30#i.year
            local vce_cl inst_id
            local mainx  exposure
            local mains  exposure mkt_spend_shr
        }

        `cmd' `yvar' Z_it Z_share_it `mains', absorb(`fes') vce(cluster `vce_cl')
        mat funcform[1,`col'] = _b[Z_it]
        mat funcform[2,`col'] = _se[Z_it]
        local b = _b[Z_it]
        qui sum exposure if e(sample)
        local xbar = r(mean)
        qui sum ppr_cnt if year < 2014 & e(sample)
        local ymn = r(mean)
        if "`est'" == "ppml"   local decl = 100 * (1 - exp(`b'*`xbar'))
        if "`est'" == "ols"    local decl = -100 * `b' * `xbar' / `ymn'
        if "`est'" == "ols_ln" local decl = 100 * (1 - exp(`b'*`xbar')) * (1 + `ymn') / `ymn'
        mat funcform[5,`col'] = `decl'
        mat funcform[6,`col'] = `ymn'
        mat funcform[7,`col'] = e(N)
        mat funcform[8,`col'] = `xbar'

        `cmd' `yvar' Z_it `mainx', absorb(`fes') vce(cluster `vce_cl')
        mat funcform[3,`col'] = _b[Z_it]
        mat funcform[4,`col'] = _se[Z_it]
        mat funcform[9,`col'] = e(N)
    }
}
mat rownames funcform = b_wshare se_wshare b_base se_base decline_pct ///
                        pre_mean N_wshare avg_exposure N_base
mat colnames funcform = `cnames'
mat list funcform, format(%9.4f)

cap mkdir ../output/tables
cap mkdir ../output/tables/`samp'
cap mkdir ../output/tables/`samp'/robustness
matrix_to_txt, saving("../output/tables/`samp'/robustness/funcform`suf'.txt") ///
    matrix(funcform) title(<tab:funcform`suf'>) format(%20.4f) replace

* closing $ via char(36): "\$" fails to escape right after an empty macro
local d = char(36)
local line_bw  "\quad With \$S_i\$ control  "
local line_sw  "                          "
local line_bn  "\quad No \$S_i\$ control    "
local line_sn  "                          "
local line_dc  "Implied output decline (\%)"
local line_nn  "Observations               "
local line_pm  "Pre-period mean            "
local line_num " "
local fe_athr  "Author \$+\$ year FE"
local fe_clyr  "Author \$+\$ cluster \$\times\$ year FE"
local fe_inst  "University \$+\$ cluster \$\times\$ year FE"
foreach fe of local fe_sets {
    local line_fe_`fe' "`fe_`fe''"
}
forval c = 1/`n_col' {
    foreach p in w n {
        local r  = cond("`p'" == "w", 1, 3)
        local b  = funcform[`r',`c']
        local se = funcform[`r'+1,`c']
        local t  = abs(`b'/`se')
        local st = cond(`t' >= 2.576, "^{***}", cond(`t' >= 1.960, "^{**}", cond(`t' >= 1.645, "^{*}", "")))
        local b`p'  = trim(string(`b', "%6.3f"))
        local se`p' = trim(string(`se', "%6.3f"))
        local st`p' "`st'"
    }
    local dc = trim(string(funcform[5,`c'], "%4.1f"))
    local nn = subinstr(trim(string(funcform[7,`c'], "%12.0fc")), ",", "{,}", .)
    if `c' == 1 {
        local line_bw "`line_bw' & \$\RFCoef`stw'`d'"
        local line_sw "`line_sw' & \$(\RFCoefSd)\$"
        local line_bn "`line_bn' & \$\RFCoefRaw`stn'`d'"
        local line_sn "`line_sn' & \$(\RFCoefRawSd)\$"
        local line_dc "`line_dc' & \OutputDecline"
        local line_nn "`line_nn' & \RFObs"
    }
    else {
        local line_bw "`line_bw' & \$`bw'`stw'`d'"
        local line_sw "`line_sw' & \$(`sew')\$"
        local line_bn "`line_bn' & \$`bn'`stn'`d'"
        local line_sn "`line_sn' & \$(`sen')\$"
        local line_dc "`line_dc' & `dc'"
        local line_nn "`line_nn' & `nn'"
    }
    local line_pm  "`line_pm' & \PoisMean"
    local line_num "`line_num' & (`c')"
    local this_fe : word `=mod(`c' - 1, `n_fe') + 1' of `fe_sets'
    foreach fe of local fe_sets {
        local mark = cond("`fe'" == "`this_fe'", "\$\checkmark\$", "")
        local line_fe_`fe' "`line_fe_`fe'' & `mark'"
    }
}

local out ../output/tables/`samp'/robustness/rf_funcform`suf'.tex
tempname fh
file open `fh' using "`out'", write replace
file write `fh' "\begin{table}[H]" _n
file write `fh' "\centering" _n
file write `fh' "\small" _n
file write `fh' "\setlength{\tabcolsep}{4pt}" _n
file write `fh' "\caption{Robustness of the Output Effect to Functional Form and Fixed Effects}" _n
file write `fh' "\label{tab:rf_funcform}" _n
file write `fh' "\begin{tabular}{l ccc ccc ccc}" _n
file write `fh' "\toprule" _n
file write `fh' " & \multicolumn{3}{c}{Poisson} & \multicolumn{3}{c}{OLS Levels} & \multicolumn{3}{c}{OLS Log} \\" _n
file write `fh' "\cmidrule(lr){2-4}\cmidrule(lr){5-7}\cmidrule(lr){8-10}" _n
file write `fh' "`line_num' \\" _n
file write `fh' "\midrule" _n
file write `fh' "\multicolumn{10}{l}{\textit{Post \$\times\$ Exposure}} \\[2pt]" _n
file write `fh' "`line_bw' \\" _n
file write `fh' "`line_sw' \\" _n
file write `fh' "`line_bn' \\" _n
file write `fh' "`line_sn' \\" _n
file write `fh' "\addlinespace" _n
file write `fh' "`line_dc' \\" _n
file write `fh' "\midrule" _n
foreach fe of local fe_sets {
    file write `fh' "`line_fe_`fe'' \\" _n
}
file write `fh' "\midrule" _n
file write `fh' "`line_pm' \\" _n
file write `fh' "`line_nn' \\" _n
file write `fh' "\bottomrule" _n
file write `fh' "\end{tabular}" _n
file write `fh' "\floatfoot{\textit{Notes:} Each column is a separate difference-in-differences regression of annual publication counts on the interaction of post-merger timing with PI exposure, estimated on the panel of \NPIs\ PIs observed 2010--2019." _n
file write `fh' "Columns (1) through (3) estimate a Poisson (PPML) model, columns (4) through (6) ordinary least squares in levels, and columns (7) through (9) ordinary least squares in the log of one plus the count." _n
file write `fh' "Within each estimator, the first column uses author and year fixed effects, the second uses author and research-cluster-by-year fixed effects, and the third replaces the author fixed effects with university fixed effects alongside research-cluster-by-year fixed effects, as indicated at the foot of the table." _n
file write `fh' "The university columns additionally control for the levels of exposure and of the treated-market share, which are absorbed by the author fixed effect in the other columns." _n
file write `fh' "Each specification is reported with and without the treated-market share \$S_i\$ as a control, following \citet{borusyak_quasi-experimental_2022}." _n
file write `fh' "The implied output decline is the reduction for the average PI, at exposure \AvgExposure, implied by the with-\$S_i\$ coefficient and expressed as a percent of the pre-period mean, so that it is comparable across estimators whose coefficients are in different units." _n
file write `fh' "The pre-period mean is the average pre-merger publication count per PI-year on the estimation sample." _n
file write `fh' "Column (1) with the share control is the specification reported in Table~\ref{tab:rf_main}." _n
file write `fh' "Standard errors are clustered at the PI level, or at the university level in the university fixed-effect columns, in parentheses. Significance: \$^{*}\$ \$p<0.10\$, \$^{**}\$ \$p<0.05\$, \$^{***}\$ \$p<0.01\$.}" _n
file write `fh' "\end{table}" _n
file close `fh'
di as text "wrote `out'"
