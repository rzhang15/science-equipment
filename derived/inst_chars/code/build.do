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
    endowment
    combine
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

program endowment
    * f1endmft = endowment/FTE, GASB (public); f2endmft = endowment/FTE, FASB (private-nonprofit).
    * Institutions report one or the other; coalesce into a single per-FTE endowment.
    forval y = 2010/2013 {
        import delimited using ../external/ipeds/endowment_`y', clear stringcols(_all)
        rename unitid ipeds_id
        destring ipeds_id f1endmft f2endmft, replace force
        gen endowment = f1endmft
        replace endowment = f2endmft if mi(endowment) & !mi(f2endmft)
        gen byte endow_src = 1 if !mi(f1endmft)
        replace endow_src = 2 if mi(f1endmft) & !mi(f2endmft)
        keep ipeds_id year endowment endow_src
        save ../temp/endowment_`y', replace
    }

    clear
    forval y = 2010/2013 {
        append using ../temp/endowment_`y', force
    }
    save ../temp/endowment_all, replace
    gcollapse (mean) endowment (max) endow_src, by(ipeds_id)
    save ../output/endowment_pre, replace
end

program combine
    use ../output/herd_pre, clear
    merge 1:1 ipeds_id using ../output/endowment_pre, nogen
    drop if mi(ipeds_id)
    save ../output/combined_pre, replace
end
main
