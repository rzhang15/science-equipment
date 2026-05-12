set more off
use category year similarity_score price keep treated tier1 tier2 tier3 ///
    using /n/home02/cxu75/sci_eq/derived/first_stage/make_mkt_panel/output/full_item_level_tfidf.dta, clear
keep if inrange(year, 2010, 2018)
display "Total items 2010-2018: " _N

display _newline "=== SIMILARITY SCORE DISTRIBUTION ==="
display "ALL items:"
summarize similarity_score, detail

display _newline "Items in keep=1 categories only:"
summarize similarity_score if keep == 1, detail

display _newline "=== FRACTIONS BELOW THRESHOLDS (keep=1 items) ==="
count if keep == 1
local n_total = r(N)
foreach t in 0.10 0.20 0.30 0.40 0.50 0.60 0.70 {
    count if similarity_score < `t' & keep == 1
    local pct = 100 * r(N) / `n_total'
    display "sim < `t': " r(N) " items (" %5.2f `pct' "%)"
}

display _newline "=== ITEM COUNT BY SIM BIN, TREATED vs CONTROL (keep=1) ==="
gen sim_bin = .
replace sim_bin = 1 if similarity_score < 0.10
replace sim_bin = 2 if similarity_score >= 0.10 & similarity_score < 0.20
replace sim_bin = 3 if similarity_score >= 0.20 & similarity_score < 0.30
replace sim_bin = 4 if similarity_score >= 0.30 & similarity_score < 0.40
replace sim_bin = 5 if similarity_score >= 0.40 & similarity_score < 0.50
replace sim_bin = 6 if similarity_score >= 0.50 & similarity_score < 0.60
replace sim_bin = 7 if similarity_score >= 0.60 & similarity_score < 0.70
replace sim_bin = 8 if similarity_score >= 0.70 & similarity_score < 0.80
replace sim_bin = 9 if similarity_score >= 0.80 & similarity_score < 0.90
replace sim_bin = 10 if similarity_score >= 0.90
label define simbin 1 "<0.10" 2 "0.10-.20" 3 "0.20-.30" 4 "0.30-.40" 5 "0.40-.50" 6 "0.50-.60" 7 "0.60-.70" 8 "0.70-.80" 9 "0.80-.90" 10 "0.90+"
label values sim_bin simbin
tabulate sim_bin treated if keep == 1
