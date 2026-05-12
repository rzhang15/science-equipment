set more off
local bumpy_str `" "human serum" "crystallizing dishes" "rectangular carboys" "nitrogen" "bacterial selection antibiotics - rifampicin" "storage jars" "potassium acetate" "carbon dioxide" "depc" "sodium sulfate" "colorimetric substrates - onpg" "ammonium sulfate" "paraffin" "thrombin" "colorimetric substrates - dab" "chromatography paper" "flash chromatography columns - silica gel" "cell lysis detergents - digitonin" "cell culture antibiotics - zeocin" "dewar flasks" "drug - anticoagulant" "direct pcr lysis reagents" "lds sample buffer" "'

use category year price similarity_score ///
    using /n/home02/cxu75/sci_eq/derived/first_stage/make_mkt_panel/output/full_item_level_tfidf.dta if ///
    inlist(category, "human serum", "crystallizing dishes", "rectangular carboys", "nitrogen", "bacterial selection antibiotics - rifampicin", "storage jars") | ///
    inlist(category, "potassium acetate", "carbon dioxide", "depc", "sodium sulfate", "colorimetric substrates - onpg", "ammonium sulfate") | ///
    inlist(category, "paraffin", "thrombin", "colorimetric substrates - dab", "chromatography paper", "flash chromatography columns - silica gel", "cell lysis detergents - digitonin") | ///
    inlist(category, "cell culture antibiotics - zeocin", "dewar flasks", "drug - anticoagulant", "direct pcr lysis reagents", "lds sample buffer"), clear
keep if inrange(year, 2010, 2018)
rename price log_price

foreach thr in 0.15 0.20 0.25 0.30 {
    local thrlbl = strofreal(`thr', "%4.2f")
    preserve
        keep if similarity_score >= `thr'
        collapse (mean) avg_lp = log_price (count) n_items = log_price, by(category year)
        sort category year
        by category: gen dlp = avg_lp - avg_lp[_n-1]
        collapse (sd) sd_thr_`=substr("`thrlbl'",3,2)' = dlp (sum) total_items = n_items, by(category)
        rename total_items n_`=substr("`thrlbl'",3,2)'
        tempfile r_`=substr("`thrlbl'",3,2)'
        save `r_`=substr("`thrlbl'",3,2)''
    restore
}

* before (no filter)
preserve
    collapse (mean) avg_lp = log_price (count) n_items = log_price, by(category year)
    sort category year
    by category: gen dlp = avg_lp - avg_lp[_n-1]
    collapse (sd) sd_before = dlp, by(category)
    tempfile before
    save `before'
restore

use `before', clear
foreach t in 15 20 25 30 {
    merge 1:1 category using `r_`t'', nogen
}
gsort -sd_before
format sd_before sd_thr_15 sd_thr_20 sd_thr_25 sd_thr_30 %5.2f
list category sd_before sd_thr_15 sd_thr_20 sd_thr_25 sd_thr_30 n_15 n_20 n_25 n_30, sep(0) noobs
