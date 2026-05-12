set more off
use category year product_desc clean_desc price similarity_score ///
    using /n/home02/cxu75/sci_eq/derived/first_stage/make_mkt_panel/output/full_item_level_tfidf.dta if ///
    category == "carbon dioxide", clear
keep if inrange(year, 2010, 2018)
rename price log_price

display "Total carbon dioxide items 2010-2018: " _N

* Flag bone/marrow items
gen lower_desc = lower(product_desc)
gen bone_marrow = strpos(lower_desc, "bone") > 0 | strpos(lower_desc, "marrow") > 0
count if bone_marrow == 1
display "Items containing 'bone' or 'marrow': " r(N)

* Show what these look like
preserve
keep if bone_marrow == 1
bysort product_desc: keep if _n == 1
display _newline "=== UNIQUE BONE/MARROW PRODUCT DESCS IN CARBON DIOXIDE ==="
format similarity_score log_price %5.2f
list similarity_score log_price product_desc, sep(0) noobs string(80)
restore

* BEFORE: full data
preserve
    collapse (mean) avg_lp = log_price (count) n=log_price, by(year)
    sort year
    gen dlp = avg_lp - avg_lp[_n-1]
    summarize dlp
    display "BEFORE drop: sd_dlp = " %5.3f r(sd) ", n_items = " sum(n)
    list year n avg_lp dlp, sep(0) noobs
restore

* AFTER: drop bone/marrow items
preserve
    drop if bone_marrow == 1
    collapse (mean) avg_lp = log_price (count) n=log_price, by(year)
    sort year
    gen dlp = avg_lp - avg_lp[_n-1]
    summarize dlp
    display _newline "AFTER drop bone/marrow: sd_dlp = " %5.3f r(sd)
    list year n avg_lp dlp, sep(0) noobs
restore
