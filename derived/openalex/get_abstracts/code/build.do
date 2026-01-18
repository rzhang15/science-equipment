set more off
clear all
capture log close
program drop _all
set scheme modern
pause on
set seed 8975
set maxvar 120000

program main
*    check_foia_pis
    append_ppr_ids
end

program check_foia_pis 
    use ../external/foia/foia_athrs, clear
    merge 1:1 athr_id using ../external/samp/list_of_athrs, assert(1 2 3) keep(2 3) nogen
    use ../external/samp/list_of_athrs, clear
end

program append_ppr_ids
    use ../external/ls_samp/list_of_works, clear
    append using ../external/samp/list_of_works_all
    gduplicates drop
    save ../output/all_works, replace 
end


main
