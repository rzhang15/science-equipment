set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main  
    use ../external/panel/cleaned_all_jrnls.dta, clear
    contract id athr_id year
    drop _freq
    save ../temp/pi_ppr, replace
    merge 1:m id using ../external/openalex/grants_all_jrnls_merged, assert(1 2 3) keep(1 3) 
    tab _merge
    drop n _merge
    contract athr_id year funder_id funder_name award_id
    drop _freq
    drop if mi(award_id)
    save ../output/pi_grants, replace
end
**
main
