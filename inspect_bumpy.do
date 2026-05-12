set more off
* Categories to inspect — top ~20 bumpy controls + 2 treated Tier 3
local bumpy `" "human serum" "crystallizing dishes" "rectangular carboys" "nitrogen" "bacterial selection antibiotics - rifampicin" "storage jars" "potassium acetate" "carbon dioxide" "depc" "sodium sulfate" "colorimetric substrates - onpg" "ammonium sulfate" "paraffin" "thrombin" "colorimetric substrates - dab" "chromatography paper" "flash chromatography columns - silica gel" "cell lysis detergents - digitonin" "cell culture antibiotics - zeocin" "dewar flasks" "drug - anticoagulant" "direct pcr lysis reagents" "lds sample buffer" "'

use category year product_desc clean_desc price qty spend similarity_score prediction_source supplier_id ///
    using /n/home02/cxu75/sci_eq/derived/first_stage/make_mkt_panel/output/full_item_level_tfidf.dta if ///
    inlist(category, "human serum", "crystallizing dishes", "rectangular carboys", "nitrogen", "bacterial selection antibiotics - rifampicin", "storage jars") | ///
    inlist(category, "potassium acetate", "carbon dioxide", "depc", "sodium sulfate", "colorimetric substrates - onpg", "ammonium sulfate") | ///
    inlist(category, "paraffin", "thrombin", "colorimetric substrates - dab", "chromatography paper", "flash chromatography columns - silica gel", "cell lysis detergents - digitonin") | ///
    inlist(category, "cell culture antibiotics - zeocin", "dewar flasks", "drug - anticoagulant", "direct pcr lysis reagents", "lds sample buffer"), clear

display "N obs loaded: " _N
* Restrict to merger window
keep if inrange(year, 2010, 2018)
display "After window filter: " _N

* Summary by category
display _newline "=== ITEM COUNTS, SIMILARITY, PRICE SUMMARY BY CATEGORY ==="
bysort category: gen n = _N
gen low_sim = similarity_score < 0.30
bysort category: egen pct_low_sim = mean(low_sim*100)
bysort category: egen med_sim = median(similarity_score)
bysort category: egen p05_price = pctile(price), p(5)
bysort category: egen p95_price = pctile(price), p(95)
bysort category: egen med_price = median(price)
collapse (first) n pct_low_sim med_sim p05_price p95_price med_price, by(category)
gen ratio_p95_p05 = p95_price / p05_price
gsort -ratio_p95_p05
format pct_low_sim med_sim %5.2f
format ratio_p95_p05 %7.1f
format p05_price p95_price med_price %9.2f
list category n med_sim pct_low_sim med_price p05_price p95_price ratio_p95_p05, sep(0) noobs
