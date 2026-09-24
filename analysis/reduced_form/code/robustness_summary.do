set more off
clear all
capture log close
set scheme modern
version 17

local samp      all_jrnls
local suf       _r1_r2
local hisim_pct 50

local specs base noshare clyr hisim precision positive ols olsln
local rows  h_top base ///
            h_ident noshare clyr ///
            h_expo  hisim precision positive ///
            h_form  ols olsln

local lab_h_top     ""
local lab_base      "{bf:Baseline}"
local lab_h_ident   "{bf:Identification}"
local lab_noshare   "No treated-share control"
local lab_clyr      "Research cluster × year FEs"
local lab_h_expo    "{bf:Exposure measurement}"
local lab_hisim     "High-similarity imputations only"
local lab_precision "Weighted by imputation precision"
local lab_positive  "Positive exposure only"
local lab_h_form    "{bf:Functional form}"
local lab_ols       "OLS, levels"
local lab_olsln     "OLS, log(1 + y)"

program prep_panel
    syntax, hisim(integer)
    gen post = year >= 2014
    gen Z_it  = exposure      * post
    gen Zs_it = mkt_spend_shr * post
    gen ln_ppr_cnt = ln(1 + ppr_cnt)
    bys athr_id: gen byte _one = _n == 1
    qui _pctile max_sim if _one == 1 & foia_athr != 1, p(`=100 - `hisim'')
    gen byte hisim = max_sim >= r(r1)
    drop _one
end

local n : word count `specs'
mat rs = J(`n', 8, .)
local i = 0
foreach s of local specs {
    local ++i
    local file es_`samp'`suf'
    local cmd  ppmlhdfe
    local yvar ppr_cnt
    local xvar Z_it
    local ctrl Zs_it
    local cond 1
    local wt   ""
    local fes  athr_id year
    local vce  athr_id
    local form ppml
    if "`s'" == "noshare"   local ctrl ""
    if "`s'" == "clyr"      local fes athr_id i.cluster_30#i.year
    if "`s'" == "hisim"     local cond hisim == 1
    if "`s'" == "precision" local wt [pw=max_sim]
    if "`s'" == "positive"  local cond exposure > 0
    if "`s'" == "ols" {
        local cmd  reghdfe
        local form ols
    }
    if "`s'" == "olsln" {
        local cmd  reghdfe
        local yvar ln_ppr_cnt
        local form olsln
    }

    use ../output/prepped_samples/`file', clear
    prep_panel, hisim(`hisim_pct')
    di as text _newline "robustness_summary `s': `cmd' `yvar' `xvar' `ctrl' if `cond' `wt', absorb(`fes')"
    `cmd' `yvar' `xvar' `ctrl' if `cond' `wt', absorb(`fes') vce(cluster `vce')
    local b  = _b[`xvar']
    local se = _se[`xvar']
    local meanwt = cond("`wt'" != "", "[aw=max_sim]", "")
    qui sum exposure `meanwt' if e(sample)
    local xbar = r(mean)
    qui sum ppr_cnt if year < 2014 & e(sample)
    local ymn = r(mean)
    if "`form'" == "ppml" {
        local scale 1
        local decl = 100 * (1 - exp(`b'*`xbar'))
    }
    if "`form'" == "ols" {
        local scale = 1/`ymn'
        local decl = -100 * `b' * `xbar' / `ymn'
    }
    if "`form'" == "olsln" {
        local scale = (1 + `ymn')/`ymn'
        local decl = 100 * (1 - exp(`b'*`xbar')) * (1 + `ymn') / `ymn'
    }
    mat rs[`i',1] = `b'
    mat rs[`i',2] = `se'
    mat rs[`i',3] = `b'*`scale'
    mat rs[`i',4] = `se'*`scale'
    mat rs[`i',5] = `decl'
    mat rs[`i',6] = `xbar'
    mat rs[`i',7] = `ymn'
    mat rs[`i',8] = e(N)
}
mat rownames rs = `specs'
mat colnames rs = b se elasticity se_elasticity decline_pct avg_exposure pre_mean N
mat list rs, format(%9.4f)

cap mkdir ../output/tables
cap mkdir ../output/tables/`samp'
cap mkdir ../output/tables/`samp'/robustness
matrix_to_txt, saving("../output/tables/`samp'/robustness/robust_summary`suf'.txt") ///
    matrix(rs) title(<tab:robust_summary`suf'>) format(%20.4f) replace

clear
svmat double rs, names(col)
gen spec = ""
forval i = 1/`n' {
    replace spec = "`: word `i' of `specs''" if _n == `i'
}
save ../temp/robust_summary`suf', replace

clear
local nrows : word count `rows'
set obs `nrows'
gen spec = ""
gen double y = .
gen lab = ""
local yy = 0
local i = 0
foreach r of local rows {
    local ++i
    if substr("`r'", 1, 2) == "h_" & "`r'" != "h_top" local yy = `yy' - 0.6
    local yy = `yy' - 1
    replace spec = "`r'" if _n == `i'
    replace y = `yy' if _n == `i'
    replace lab = `"`lab_`r''"' if _n == `i'
}
qui sum y
replace y = y - r(min) + 1
merge 1:1 spec using ../temp/robust_summary`suf', keep(1 3) nogen
sort y
gen ub = elasticity + 1.96*se_elasticity
gen lb = elasticity - 1.96*se_elasticity
gen byte base = spec == "base"
gen decl_s = string(decline_pct, "%3.1f") + "%" if !mi(decline_pct)
replace decl_s = "{bf:Implied output decline}" if spec == "h_top"

local ylabs
local ylabs2
forval i = 1/`=_N' {
    local yy = y[`i']
    local l1 = cond(lab[`i'] == "", " ", lab[`i'])
    local l2 = cond(decl_s[`i'] == "", " ", decl_s[`i'])
    local ylabs  `ylabs'  `yy' `"`l1'"'
    local ylabs2 `ylabs2' `yy' `"`l2'"'
}
qui sum elasticity if base == 1
local b_base = r(mean)
qui sum lb
local xmin = floor(r(min)/0.2)*0.2
qui sum ub
local xmax = ceil(r(max)/0.2)*0.2
if `xmax' < 0.2 local xmax = 0.2
qui sum y
local ylo = r(min) - 0.6
local yhi = r(max) + 0.4

tw rcap ub lb y if base == 0, horizontal lcolor(ebblue%70) msize(vsmall) yaxis(1 2) || ///
   scatter y elasticity if base == 0, mcolor(ebblue) msize(small) || ///
   rcap ub lb y if base == 1, horizontal lcolor(dkorange%70) msize(vsmall) || ///
   scatter y elasticity if base == 1, mcolor(dkorange) msize(small) ///
   , xline(0, lcolor(gs10) lpattern(solid)) ///
     xline(`b_base', lcolor(dkorange) lpattern(dash) lwidth(thin)) ///
     ylabel(`ylabs',  angle(0) labsize(small) noticks nogrid axis(1)) ///
     ylabel(`ylabs2', angle(0) labsize(small) noticks nogrid axis(2)) ///
     yscale(noline range(`ylo' `yhi') axis(1)) ///
     yscale(noline range(`ylo' `yhi') axis(2)) ///
     ytitle("", axis(1)) ytitle("", axis(2)) ///
     xtitle("Output-cost elasticity (95% CI)", size(small)) ///
     xlabel(`xmin'(0.2)`xmax', labsize(small) format(%3.1f)) ///
     legend(off) ysize(4.5) xsize(7) plotregion(margin(l=zero r=zero b=zero t=zero))
cap mkdir ../output/figures
cap mkdir ../output/figures/`samp'
cap mkdir ../output/figures/`samp'/robustness
graph export ../output/figures/`samp'/robustness/robust_summary`suf'.pdf, replace
di as text "wrote ../output/figures/`samp'/robustness/robust_summary`suf'.pdf"
