set more off
local bumpy_str `" "human serum" "crystallizing dishes" "rectangular carboys" "nitrogen" "bacterial selection antibiotics - rifampicin" "storage jars" "potassium acetate" "carbon dioxide" "depc" "sodium sulfate" "colorimetric substrates - onpg" "ammonium sulfate" "paraffin" "thrombin" "colorimetric substrates - dab" "chromatography paper" "flash chromatography columns - silica gel" "cell lysis detergents - digitonin" "cell culture antibiotics - zeocin" "dewar flasks" "drug - anticoagulant" "direct pcr lysis reagents" "lds sample buffer" "'

use category year product_desc clean_desc price qty spend similarity_score prediction_source supplier_id ///
    using /n/home02/cxu75/sci_eq/derived/first_stage/make_mkt_panel/output/full_item_level_tfidf.dta if ///
    inlist(category, "human serum", "crystallizing dishes", "rectangular carboys", "nitrogen", "bacterial selection antibiotics - rifampicin", "storage jars") | ///
    inlist(category, "potassium acetate", "carbon dioxide", "depc", "sodium sulfate", "colorimetric substrates - onpg", "ammonium sulfate") | ///
    inlist(category, "paraffin", "thrombin", "colorimetric substrates - dab", "chromatography paper", "flash chromatography columns - silica gel", "cell lysis detergents - digitonin") | ///
    inlist(category, "cell culture antibiotics - zeocin", "dewar flasks", "drug - anticoagulant", "direct pcr lysis reagents", "lds sample buffer"), clear
keep if inrange(year, 2010, 2018)

* Note: variable "price" here is log price
rename price log_price

* Outlier detection: per-category median and IQR of log_price
bysort category: egen med_lp = median(log_price)
bysort category: egen p25_lp = pctile(log_price), p(25)
bysort category: egen p75_lp = pctile(log_price), p(75)
gen iqr_lp = p75_lp - p25_lp
gen abs_dev = abs(log_price - med_lp)
gen outlier = abs_dev > 2 * iqr_lp & iqr_lp > 0
gen low_sim = similarity_score < 0.30
gen suspect = outlier | low_sim

* === BEFORE: avg log price by category-year, then SD of yoy changes ===
preserve
    collapse (mean) avg_lp = log_price, by(category year)
    sort category year
    by category: gen dlp = avg_lp - avg_lp[_n-1]
    collapse (sd) sd_dlp_before = dlp (count) n_yrs = year, by(category)
    tempfile before
    save `before'
restore

* === AFTER: drop suspect items, then recompute ===
preserve
    drop if suspect == 1
    collapse (mean) avg_lp = log_price (count) n_items = log_price, by(category year)
    sort category year
    by category: gen dlp = avg_lp - avg_lp[_n-1]
    collapse (sd) sd_dlp_after = dlp (sum) total_items = n_items, by(category)
    tempfile after
    save `after'
restore

* === Count suspects per category ===
preserve
    collapse (sum) n_suspect = suspect n_outlier = outlier n_low_sim = low_sim (count) n_total = log_price, by(category)
    gen pct_suspect = 100*n_suspect/n_total
    tempfile counts
    save `counts'
restore

use `before', clear
merge 1:1 category using `after', nogen
merge 1:1 category using `counts', nogen

gen improvement = sd_dlp_before - sd_dlp_after
gen pct_improve = 100*improvement/sd_dlp_before
gsort -sd_dlp_before
format sd_dlp_before sd_dlp_after improvement %5.2f
format pct_improve pct_suspect %5.1f
list category sd_dlp_before sd_dlp_after pct_improve n_total n_suspect pct_suspect, sep(0) noobs
