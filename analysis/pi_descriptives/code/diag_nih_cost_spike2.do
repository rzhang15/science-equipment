clear all
set more off

use athr_id year grant_key row_key research total_cost activity ///
    using ../external/nih_panel/nih_grants_by_athr_id, clear
keep if inrange(year, 2010, 2019) & research
duplicates drop athr_id year row_key, force
egen byte tag_res = tag(athr_id year grant_key)
keep if tag_res

gen str3 act3 = substr(activity, 1, 3)
encode act3, gen(act_c)
gen byte big = total_cost > 2000000 & !mi(total_cost)
gen byte post = year >= 2015

tab act_c big, row
table act_c post if big, stat(count grant_key) stat(sum total_cost) nformat(%16.0f)

gen byte one = 1
collapse (sum) dollars = total_cost (sum) n = one, by(act_c year)
reshape wide dollars n, i(act_c) j(year)
list, noobs
