set more off
clear all
capture log close
program drop _all
set scheme modern
pause on
set seed 8975
set maxvar 12000

program append_ppr_ids
    use ../external/ls_samp/list_of_works, clear
    append using ../external/samp/list_of_works_all
    gduplicates drop
    save ../output/all_works, replace 
end

