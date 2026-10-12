* Funding-continuity diagnosis; run from analysis/rf_heterogeneity/code.
* cell 1: low intermittent; 2: low persistent; 3: high intermittent; 4: high persistent.
set more off
clear all
log using ../output/tables/all_jrnls/nih_funding_continuity_audit.log, replace text
use ../temp/es_all_jrnls_r1_r2.dta, clear
keep if !mi(high_nihd)
bys athr_id: egen byte active_years = total(inrange(year,2010,2013) & !mi(nih_total_cost) & nih_total_cost > 0)
gen byte post = year >= 2014
gen byte cell = 1 + high_nihd * 2 + (active_years == 4)
forval i = 1/4 {
 gen double Z`i' = exposure * post * (cell == `i')
 gen double S`i' = mkt_spend_shr * post * (cell == `i')
 gen double P`i' = post * (cell == `i')
}
ppmlhdfe ppr_cnt Z1 Z2 Z3 Z4 S1 S2 S3 S4 P1 P2 P3, absorb(athr_id year) vce(cluster athr_id)
lincom Z1-Z2
lincom Z4-Z2
tempname cells
postfile `cells' byte cell double b se using ../temp/nih_funding_continuity_audit, replace
forval i = 1/4 {
 post `cells' (`i') (_b[Z`i']) (_se[Z`i'])
}
postclose `cells'
use ../temp/nih_funding_continuity_audit, clear
export delimited using ../output/tables/all_jrnls/nih_funding_continuity_audit.csv, replace
log close
exit, clear
