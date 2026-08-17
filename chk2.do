local cs /n/home02/cxu75/sci_eq/analysis/foia_case_study
use `cs'/external/samp/merged_foias_with_pis, clear
keep if inlist(uni, "utdallas", "umich")
drop if mi(athr_id)
gen year = year(date(date, "YMD"))
drop if year > 2013
merge m:1 category using `cs'/external/categories/categories_tfidf, keep(1 3)
rename _merge nonlab
replace nonlab = 0 if nonlab == 3
replace keep = 2 if keep == .
gen hq = keep == 1 | (bad_control == 1 & support >= 25 & precision >= 0.8 & recall >= 0.8)
gen lab_spend = spend if nonlab == 0
gen hq_labspend = lab_spend if hq == 1
collapse (sum) lab_spend hq_labspend, by(athr_id year)
di _n "=== PI-YEAR level (pooled) ==="
sum lab_spend hq_labspend if lab_spend > 50, sep(0)
sum hq_labspend if hq_labspend > 50
bys athr_id: gen n_yrs = _N
collapse (mean) lab_spend hq_labspend (first) n_yrs, by(athr_id)
di _n "=== PI level (avg across observed years) ==="
sum lab_spend hq_labspend if lab_spend > 50, sep(0)
sum hq_labspend if hq_labspend > 50
di _n "=== years observed vs spend ==="
corr n_yrs lab_spend
tab n_yrs
