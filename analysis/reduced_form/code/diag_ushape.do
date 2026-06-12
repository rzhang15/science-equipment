set more off
clear all
capture log close
log using ../temp/diag_ushape.log, replace text

local samp all_jrnls
local suf  _r1_r2_public

di as text "==== (A) raw mean ppr_cnt by year in the FINAL es_*.dta (post tsfill, post all sample filters) ===="
use ../temp/es_`samp'`suf', clear
gunique athr_id
local n_pi = r(unique)
di as text "N PIs in final es file = `n_pi'"
tab year
collapse (mean) ppr_cnt cite_affl_wt (count) any_obs = ppr_cnt, by(year)
list, sep(0) noobs

di as text "==== (B) raw mean ppr_cnt by year in the RAW input panel (pre any restrict_samp filters) ===="
use ../external/samp/athr_panel_full_year_last_`samp'`suf', clear
gunique athr_id
local n_pi_raw = r(unique)
di as text "N PIs in raw input = `n_pi_raw'"
preserve
collapse (mean) ppr_cnt cite_affl_wt (count) any_obs = ppr_cnt, by(year)
list, sep(0) noobs
restore

di as text "==== (C) raw input restricted to 2010-2019 + tot_pprs >= 10 + active by 2014+ ===="
preserve
bys athr_id: egen tot_pprs = total(ppr_cnt)
keep if tot_pprs >= 10
drop tot_pprs
bys athr_id: egen max_year = max(year)
keep if max_year >= 2014
keep if inrange(year, 2010, 2019)
bys athr_id: egen min_year = min(year)
keep if min_year <= 2013
gunique athr_id
di as text "N PIs after restrict (no tsfill) = `r(unique)'"
collapse (mean) ppr_cnt cite_affl_wt (count) n_obs = ppr_cnt, by(year)
list, sep(0) noobs
restore

di as text "==== (D) distribution of last-publishing-year (max_year) among final-sample PIs ===="
use ../temp/es_`samp'`suf', clear
preserve
keep if ppr_cnt > 0
bys athr_id: egen last_real_year = max(year)
bys athr_id: keep if _n == 1
tab last_real_year
restore

di as text "==== (E) drop tsfilled zero-rows, recompute means: removes the panel-balance effect ===="
preserve
keep if ppr_cnt > 0 | year == 2010   // keep only years a PI actually published
collapse (mean) ppr_cnt cite_affl_wt (count) n_obs = ppr_cnt, by(year)
list, sep(0) noobs
restore

di as text "==== (F) for PIs who publish in every year 2010-2019 (truly balanced active panel) ===="
preserve
gen has_pub = ppr_cnt > 0
bys athr_id: egen n_active_yrs = total(has_pub)
keep if n_active_yrs == 10
gunique athr_id
di as text "N PIs always-active 2010-2019 = `r(unique)'"
collapse (mean) ppr_cnt cite_affl_wt, by(year)
list, sep(0) noobs
restore

di as text "==== (G) check 2016 specifically: per-PI ratio 2016/2013 ===="
use ../temp/es_`samp'`suf', clear
preserve
keep if inlist(year, 2013, 2016)
gcollapse (sum) ppr_cnt, by(athr_id year)
greshape wide ppr_cnt, i(athr_id) j(year)
gen ratio_2016_2013 = ppr_cnt2016 / ppr_cnt2013 if ppr_cnt2013 > 0
sum ratio_2016_2013, d
tab1 ppr_cnt2016 if ppr_cnt2013 > 0 & ppr_cnt2016 == 0, mi
count if ppr_cnt2013 > 0 & ppr_cnt2016 == 0
local n_drop2016 = r(N)
count if ppr_cnt2013 > 0
local n_active2013 = r(N)
di as text "Of `n_active2013' PIs publishing in 2013, `n_drop2016' published 0 in 2016"
restore

log close
