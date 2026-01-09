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
    append_pprs
end
program append_pprs
    use ../external/ids/list_of_athrs, clear
    count
    local N = ceil(r(N)/500)
    forval i = 1/`N' {
        import delimited using "../output/works`i'", clear
        cap ds v2
        if _rc ==0 {
            keep v2
            rename v2 id
        }
        if _rc != 0 { 
            keep v1 
            rename v1 id
        }
        drop if mi(id)
        replace id = subinstr(id, "//openalex.org", "", .)
        replace id = subinstr(id, "/", "", .)
        compress, nocoalesce
        save ../temp/works`i', replace
    }
    clear
    forval i = 1/`N' {
       append using ../temp/works`i'
       gduplicates drop
    }
    fmerge 1:1 id using ../external/ids/list_of_works, assert(1 3) keep(1) nogen
    save "../output/list_of_works", replace
end



main
