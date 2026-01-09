set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main    
    clean_pi_id 
end

program clean_pi_id 
    // have utaustin ecu dallas
    import excel using ../external/pis/utaustin_pi, firstrow clear
    rename Account1 purchasera
    save ../output/utaustin_pi, replace

    import excel using ../external/pis/utdallas_pi, firstrow clear
    rename referenceawardid fund_id
    collapse (firstnm) *name, by(fund_id athr_id)
    save ../output/utdallas_pi, replace 

    import excel using ../external/pis/ecu_pi, firstrow clear
    drop G
    rename fed_id fund_id
    save ../output/ecu_pi, replace
end

program merge_ids_foia
    use ../external/foias/merged_foias, clear    
    keep if inlist(uni, "ecu", "utdallas", "utaustin")
    fmerge m:1 purchaser using ../output/utaustin_pi, assert(1 3) keep(1 3) nogen
    merge m:1 fund_id using ../output/utdallas_pi, assert(1 2 3 4) keep(1 3 4) nogen update 
    merge m:1 fund_id using ../output/ecu_pi, assert(1 2 3 4) keep(1 3 4) nogen update
    save ../output/merged_foias_with_pis, replace
    contract athr_id
    drop _freq
    drop if mi(athr_id)
    save ../output/foia_athrs, replace
end


main
