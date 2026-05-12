set more off
use /n/home02/cxu75/sci_eq/derived/first_stage/make_mkt_panel/output/full_category_yr_tfidf.dta, clear
keep if inrange(year, 2010, 2018)
keep if keep == 1
sort category year
by category: gen dlp = avg_log_price - avg_log_price[_n-1]
collapse (sd) sd_dlp = dlp ///
         (max) max_dlp = dlp (min) min_dlp = dlp ///
         (count) n_yrs = year ///
         (max) treated = treated tier1 = tier1 tier2 = tier2 tier3 = tier3 ///
         (mean) spend = raw_spend, by(category)
gen abs_max = max(abs(max_dlp), abs(min_dlp))
gen treated_any = (treated > 0 & treated < .)
keep if n_yrs >= 6
gen already_excluded = inlist(category, "slide mounting medium", "collagenase", "catalase", "dextrose", "egta solution", "pipes buffers") | inlist(category, "synthetic shrna")
format sd_dlp abs_max %5.3f
gsort -sd_dlp
keep category sd_dlp abs_max n_yrs treated_any tier1 tier2 tier3 already_excluded spend
export delimited using /tmp/volatility_ranked_v2.csv, replace
display "Total kept categories: " _N
