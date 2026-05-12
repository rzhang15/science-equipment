set more off
use category year product_desc clean_desc price similarity_score ///
    using /n/home02/cxu75/sci_eq/derived/first_stage/make_mkt_panel/output/full_item_level_tfidf.dta if ///
    inlist(category, "human serum", "crystallizing dishes", "rectangular carboys", "nitrogen", "bacterial selection antibiotics - rifampicin", "storage jars") | ///
    inlist(category, "potassium acetate", "carbon dioxide", "depc", "sodium sulfate", "colorimetric substrates - onpg", "ammonium sulfate") | ///
    inlist(category, "paraffin", "thrombin", "colorimetric substrates - dab", "chromatography paper", "flash chromatography columns - silica gel", "cell lysis detergents - digitonin") | ///
    inlist(category, "cell culture antibiotics - zeocin", "dewar flasks", "drug - anticoagulant", "direct pcr lysis reagents", "lds sample buffer"), clear
keep if inrange(year, 2010, 2018)
rename price log_price
bysort category: egen med_lp = median(log_price)
bysort category: egen p25_lp = pctile(log_price), p(25)
bysort category: egen p75_lp = pctile(log_price), p(75)
gen iqr_lp = p75_lp - p25_lp
gen abs_dev = abs(log_price - med_lp)
gen outlier = abs_dev > 2 * iqr_lp & iqr_lp > 0
gen low_sim = similarity_score < 0.40
gen suspect = outlier | low_sim
keep if suspect == 1

* Deduplicate descriptions per category
bysort category clean_desc: gen freq = _N
bysort category clean_desc: keep if _n == 1

* Use clean_desc for keyword extraction (lowercase, no formatting)
gsort category similarity_score
keep category similarity_score log_price freq clean_desc product_desc
export delimited using /tmp/all_suspects.csv, replace
display "Saved /tmp/all_suspects.csv"
display "Unique suspect descriptions: " _N
