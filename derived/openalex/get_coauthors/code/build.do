set more off
clear all
capture log close
program drop _all
set scheme modern
pause on
set seed 8975
set maxvar 120000

program main
    get_coauthors
end

program get_coauthors 
    use ../external/foia_athr/athr_exposure_list, clear
    merge 1:m athr_id using ../external/ls_samp/cleaned_last20yrs_all_jrnls, assert(1 2 3) keep(3) nogen
    contract id athr_id
    drop _freq
    save ../temp/relevant_ppr_athrs, replace
    contract id
    drop _freq
    save ../temp/relevant_pprs, replace

    use ../temp/relevant_pprs, clear
    merge 1:m id using ../external/ls_samp/cleaned_last20yrs_all_jrnls, keep(3) nogen
    contract id athr_id athr_pos
    drop _freq
    rename athr_id coauthor_id
    joinby id using ../temp/relevant_ppr_athrs, unmatched(both)
    merge m:1 id using ../temp/relevant_ppr_athrs
    save ../temp/coathrs, replace
    contract athr_id coauthor_id
    drop _freq
    drop if athr_id == coauthor_id
    save ../output/coauthors, replace
end


main
