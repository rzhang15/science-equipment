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
    load_pprs
    append_pprs, samp(6)
    clear 
    forval i = 1/6 {
        append using "../output/list_of_works_`i'"
        gduplicates drop
    }
    compress, nocoalesce
    save ../output/list_of_works_all, replace
end

program load_pprs
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
end

program append_pprs
    syntax, samp(int)
    local start = (`samp'-1)*5000+1
    local end = min(`samp'*5000 , 34158) 
    clear
    forval i = `start'/`end' {
       append using ../temp/works`i'
       gduplicates drop
    }
    fmerge 1:1 id using ../external/ids/list_of_works, assert(1 2 3) keep(1) nogen
    save "../output/list_of_works_`samp'", replace
end



main
