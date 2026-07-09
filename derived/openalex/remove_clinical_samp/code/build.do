set more off
clear all
capture log close
program drop _all
set scheme modern
pause on
set seed 8975
set maxvar 120000

program main
    filter_samp
end

program filter_samp
    foreach samp in all_jrnls top_jrnls {
        use ../external/samp/cleaned_`samp', clear
        rename pmid v1
        merge m:1 v1 using ../external/clinical/clinical_pmids, assert(1 2 3) keep(1) nogen   
        rename v1 pmid
        save ../output/cleaned_`samp'_no_clin, replace
        
        use ../external/samp/cleaned_last20yrs_`samp', clear
        rename pmid v1
        merge m:1 v1 using ../external/clinical/clinical_pmids, assert(1 2 3) keep(1) nogen   
        rename v1 pmid
        save ../output/cleaned_last20yrs_`samp'_no_clin, replace
    }
end
main

