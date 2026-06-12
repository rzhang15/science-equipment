set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main
    use ../external/panel/cleaned_all_jrnls.dta, clear
    contract pmid athr_id year
    drop _freq
    save ../temp/pi_ppr, replace
    merge 1:m pmid using ../external/pubmed/grants, assert(1 2 3) keep(1 3)
    tab _merge
    drop n _merge
    contract athr_id year grant_id acronym agency country
    drop _freq
    drop if mi(grant_id)
    save ../output/pi_grants, replace
end
**
main
