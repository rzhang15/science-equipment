set more off
use category year product_desc clean_desc price similarity_score keep ///
    using /n/home02/cxu75/sci_eq/derived/first_stage/make_mkt_panel/output/full_item_level_tfidf.dta if keep == 1, clear
keep if inrange(year, 2010, 2018)
keep if similarity_score >= 0.30 & similarity_score < 0.40

* Top categories in this band by item count
bysort category: gen n_cat = _N
preserve
bysort category: keep if _n == 1
gsort -n_cat
display "=== TOP CATEGORIES IN sim 0.30-0.40 BAND ==="
list category n_cat in 1/25, sep(0) noobs
restore

* Random sample of 30 items in this band
set seed 42
gen u = runiform()
sort u
display _newline "=== RANDOM SAMPLE OF 30 ITEMS IN sim 0.30-0.40 BAND ==="
format similarity_score %5.2f
list category similarity_score product_desc in 1/30, sep(0) noobs string(75)
