set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

clear
save ../output/pmids, emptyok replace


foreach f in clinical diseases fundamental therapeutics {
    import delimited using "`f'_results.txt", clear
    append using ../output/pmids
    save ../output/pmids, replace
}

rename v1 pmid
gduplicates drop pmid, force
save ../output/pmids, replace

import delimited using clinical_results.txt, clear
save ../output/clinical_pmids, replace