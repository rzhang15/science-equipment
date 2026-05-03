set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main   
   merge_matched
end

program get_coauthors
    use ../external/exposure_wts/athr_exposure_list.dta, clear
    merge 1:m athr_id using ../external/ls_athrs/cleaned_last20yrs_all_jrnls, keep(3) nogen
end
main
