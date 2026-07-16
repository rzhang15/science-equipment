set more off
clear all
capture log close
program drop _all
set scheme modern
pause on
set seed 8975
set maxvar 120000

program main
    herd
end

program herd
    forval y =  2010/2013 {
        import delimited using ../external/herd/herd_`y', clear
        save ../temp/herd_`y', replace
    }
    clear
    save ../temp/herd_all, replace emptyok
    forval y = 2010/2013 {
        append using ../temp/herd_`y', force
    }
    save ../temp/herd_all, replace

    gcontract inst_id ipeds_unitid
    drop _freq
    rename ipeds_unitid ipeds_id
    save ../temp/ipeds_xw, replace

    use ../external/herd/herd_2010_2022, clear
    keep if inrange(year, 2010,2013)
    merge m:1 inst_id using ../temp/ipeds_xw, keep(3) nogen
    collapse (mean) *fund *expend , by(ipeds_id)
    save ../output/herd_pre , replace
end

program endownment
    forval y = 2010/2013 {
        import delimited using ../external/ipeds/endownment_`y', clear
        rename unitid ipeds_id
        rename f1h01 endownment
        save ../temp/endownment_`y', replace
    }

    clear
    forval y = 2010/2013 {
        append using ../temp/endownment_`y', force
    }
    save ../temp/endownment_all, replace
    gcollapse (mean) endownment, by(ipeds_id)
    save ../output/endownment_pre, replace
end

program combine
    use ../output/herd_pre, clear
    merge 1:1 ipeds_id using ../output/endownment_pre, nogen
    drop if mi(ipeds_id)
    save ../output/combined_pre, replace
end
main
