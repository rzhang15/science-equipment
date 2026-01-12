set more off
clear all
capture log close
program drop _all
set scheme modern
pause on
set seed 8975
here, set
set maxvar 120000

program main
    append_files
end
program append_files
    forval i = 1/1 {
        di "`i'"
        qui import delimited using "../output/openalex_authors`i'", stringcols(_all) clear varn(1) bindquotes(strict) maxquotedrows(unlimited) delimiters(",")
        qui describe
        assert r(k) == 19
        qui gcontract inst_id
        qui drop _freq
        qui drop if mi(inst_id)
        qui save ../temp/inst`i', replace
    }
    clear
    forval i = 1/1 {
        append using ../temp/inst`i'
        gduplicates drop
    }
    fmerge 1:1 inst_id using ../external/openalex/list_of_insts, assert(1 3) keep(1) nogen
    save ../output/list_of_insts.dta, replace
end
main
