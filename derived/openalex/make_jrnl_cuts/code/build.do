set more off
clear all
capture log close
program drop _all
set scheme modern
pause on
set seed 8975
set maxvar 120000

program main
    top_jrnls
end

program top_jrnls
    use ../external/ls_samp/openalex_all_jrnls_merged, clear
    keep if inlist(jrnl, "Science", "Nature", "Cell", "Neuron", "Nature Genetics") | inlist(jrnl, "Nature Medicine", "Nature Biotechnology", "Nature Neuroscience", "Nature Cell Biology", "Nature Chemical Biology") | inlist(jrnl, "Cell stem cell", "PLoS ONE", "Journal of Biological Chemistry", "Oncogene", "The FASEB Journal") | inlist(jrnl, "BMJ", "JAMA" , "New England Journal of Medicine", "The Lancet")
    compress, nocoalesce
    save ../output/openalex_top_jrnls, replace

end

main
