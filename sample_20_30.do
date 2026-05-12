set more off
use category year product_desc clean_desc price similarity_score keep ///
    using /n/home02/cxu75/sci_eq/derived/first_stage/make_mkt_panel/output/full_item_level_tfidf.dta if keep == 1, clear
keep if inrange(year, 2010, 2018)
keep if similarity_score >= 0.20 & similarity_score < 0.30

set seed 42
gen u = runiform()
sort u
display _newline "=== RANDOM SAMPLE OF 30 ITEMS IN sim 0.20-0.30 BAND ==="
format similarity_score %5.2f
list category similarity_score product_desc in 1/30, sep(0) noobs string(75)
