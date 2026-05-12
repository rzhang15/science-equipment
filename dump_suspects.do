set more off
use category year product_desc clean_desc price qty similarity_score ///
    using /n/home02/cxu75/sci_eq/derived/first_stage/make_mkt_panel/output/full_item_level_tfidf.dta if ///
    inlist(category, "cell culture antibiotics - zeocin", "direct pcr lysis reagents", "colorimetric substrates - dab") | ///
    inlist(category, "crystallizing dishes", "lds sample buffer", "rectangular carboys", "human serum") | ///
    inlist(category, "storage jars", "carbon dioxide", "potassium acetate"), clear
keep if inrange(year, 2010, 2018)
rename price log_price
bysort category: egen med_lp = median(log_price)
bysort category: egen p25_lp = pctile(log_price), p(25)
bysort category: egen p75_lp = pctile(log_price), p(75)
gen iqr_lp = p75_lp - p25_lp
gen abs_dev = abs(log_price - med_lp)
gen outlier = abs_dev > 2 * iqr_lp & iqr_lp > 0
gen low_sim = similarity_score < 0.30
gen suspect = outlier | low_sim
gen reason = cond(low_sim==1 & outlier==1, "BOTH", cond(low_sim==1, "LOW_SIM", "OUTLIER"))

* Suspect items
preserve
keep if suspect == 1
bysort category product_desc: gen freq = _N
bysort category product_desc: keep if _n == 1
gsort category similarity_score
keep category similarity_score log_price reason product_desc freq
export delimited using /tmp/suspect_items.csv, replace
restore

* Keeper items (median price range, high sim)
preserve
keep if suspect == 0 & similarity_score > 0.80 & abs_dev < 0.5 * iqr_lp & iqr_lp > 0
bysort category product_desc: gen freq = _N
bysort category product_desc: keep if _n == 1
gsort category -freq
keep category similarity_score log_price product_desc freq
export delimited using /tmp/keeper_items.csv, replace
restore
