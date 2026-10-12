* Diagnose the NIH funding split; run from analysis/rf_heterogeneity/code.
* Uses the current prepped sample; writes separate audit outputs only.
set more off
clear all
capture log close
log using ../output/tables/all_jrnls/nih_funding_sensitivity_audit.log, replace text
use ../temp/es_all_jrnls_r1_r2.dta, clear
keep if !mi(high_nihd)
gen byte post = year >= 2014
gen double Z = exposure * post
gen double S = mkt_spend_shr * post
gen double Zh = Z * high_nihd
gen double Zl = Z * low_nihd
gen double Sh = S * high_nihd
gen double Sl = S * low_nihd
gen double Ph = post * high_nihd
gen double Zy = Z * young
gen double Py = post * young
gen double Sy = S * young
gen double logpub = ln(1 + pre_ppr_cnt_avg)
gen double Zpub = Z * logpub
gen double Ppub = post * logpub
gen double Spub = S * logpub
egen byte tag = tag(athr_id)
_pctile pre_nihd if tag, p(99)
local funding99 = r(r1)
_pctile pre_ppr_cnt_avg if tag, p(99)
local pubs99 = r(r1)
_pctile exposure if tag, p(1 99)
local exp1 = r(r1)
local exp99 = r(r2)
* Number of baseline years with positive research funding.
bys athr_id: egen byte active_years = total(inrange(year,2010,2013) & !mi(nih_total_cost) & nih_total_cost > 0)
egen long inst_year = group(inst_id year)
egen long field_group_year = group(cluster_30 high_nihd year)
gen double Za = Z * active_years
gen double Pa = post * active_years
gen double Sa = S * active_years
gen double Zpublic = Z * pub_inst
gen double Ppublic = post * pub_inst
gen double Spublic = S * pub_inst
tempname results
postfile `results' str24 spec double high se_high low se_low gap se_gap p N using ../temp/nih_funding_sensitivity_audit, replace
foreach spec in baseline age productivity age_productivity group_year field_year inst_year trim_funding trim_productivity trim_exposure pre_placebo field_group_year active_years persistent public cluster_inst {
 preserve
 local controls ""
 local fes "athr_id year"
 local vce athr_id
 if "`spec'" == "cluster_inst" local vce inst_id
 if "`spec'" == "active_years" local controls Za Pa Sa
 if "`spec'" == "public" local controls Zpublic Ppublic Spublic
 if "`spec'" == "persistent" keep if active_years == 4
 if "`spec'" == "field_group_year" local fes "athr_id field_group_year"
 if "`spec'" == "age" local controls Zy Py Sy
 if "`spec'" == "productivity" local controls Zpub Ppub Spub
 if "`spec'" == "age_productivity" local controls Zy Py Sy Zpub Ppub Spub
 if "`spec'" == "group_year" local fes "athr_id high_nihd#year"
 if "`spec'" == "field_year" local fes "athr_id cluster_30#year"
 if "`spec'" == "inst_year" local fes "athr_id inst_year"
 if "`spec'" == "trim_funding" keep if pre_nihd <= `funding99'
 if "`spec'" == "trim_productivity" keep if pre_ppr_cnt_avg <= `pubs99'
 if "`spec'" == "trim_exposure" keep if inrange(exposure, `exp1', `exp99')
 if "`spec'" == "pre_placebo" {
  keep if year <= 2013
  replace post = year >= 2012
  replace Zh = exposure * post * high_nihd
  replace Zl = exposure * post * low_nihd
  replace Sh = mkt_spend_shr * post * high_nihd
  replace Sl = mkt_spend_shr * post * low_nihd
  replace Ph = post * high_nihd
 }
 capture noisily ppmlhdfe ppr_cnt Zh Zl Sh Sl Ph `controls', absorb(`fes') vce(cluster `vce')
 if _rc == 0 {
  local bh = _b[Zh]
  local seh = _se[Zh]
  local bl = _b[Zl]
  local sel = _se[Zl]
  local N = e(N)
  lincom Zh-Zl
  post `results' ("`spec'") (`bh') (`seh') (`bl') (`sel') (r(estimate)) (r(se)) (r(p)) (`N')
 }
 restore
}
postclose `results'
use ../temp/nih_funding_sensitivity_audit, clear
export delimited using ../output/tables/all_jrnls/nih_funding_sensitivity_audit.csv, replace
list, noobs abbreviate(24)
di "NIH_DIAGNOSTICS_COMPLETE"
log close
exit, clear
