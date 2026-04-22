set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main
    merge_foias
    clean_pi_id 
    merge_ids_foia
end

program merge_foias
    import delimited "../external/samp/ecu_2006_2024_standardized_clean_classified_with_tfidf.csv", clear
    gen uni = "ecu"
    tostring fund_id, replace 
    tostring purchaser, replace 
    tostring supplier_id, replace
    tostring supplier, replace
    tostring purchase_id, replace
    tostring sku, replace
    tostring funder, replace
    save ../temp/ecu, replace

    import delimited "../external/samp/ttu_2010_2025_standardized_clean_classified_with_tfidf.csv", clear
    gen uni = "ttu"
    tostring fund_id, replace 
    tostring purchaser, replace 
    tostring supplier_id, replace
    tostring supplier, replace
    tostring purchase_id, replace
    tostring sku, replace
    cap tostring funder, replace
    save ../temp/ttu, replace

    import delimited "../external/samp/ukansas_2010_2019_standardized_clean_classified_with_tfidf.csv", clear
    gen uni = "ukansas"
    tostring fund_id, replace 
    tostring purchaser, replace 
    tostring supplier_id, replace
    tostring supplier, replace
    tostring purchase_id, replace
    tostring sku, replace
    cap tostring funder, replace
    save ../temp/ukansas, replace

    import delimited "../external/samp/utaustin_2012_2019_standardized_clean_classified_with_tfidf.csv", clear
    gen uni = "utaustin"
    tostring fund_id, replace 
    tostring purchaser, replace 
    tostring supplier_id, replace
    tostring supplier, replace
    tostring purchase_id, replace
    tostring sku, replace
    cap tostring funder, replace
    save ../temp/utaustin, replace

    import delimited "../external/samp/utdallas_merged_clean_classified_with_tfidf.csv", clear
    gen uni = "utdallas"
    tostring fund_id, replace 
    tostring purchaser, replace 
    tostring supplier_id, replace
    tostring supplier, replace
    tostring purchase_id, replace
    tostring sku, replace
    cap tostring funder, replace
    save ../temp/utdallas, replace

    clear
    foreach u in utaustin utdallas ecu ttu ukansas {
        append using ../temp/`u'
    }
    foreach v in fund_id purchaser supplier_id supplier purchase_id sku funder {
        replace `v' = "" if `v' == "."
    }
    rename supplier suppliername
    replace suppliername = strlower(suppliername)
    save ../output/merged_foias, replace
end

program clean_pi_id 
    // have utaustin ecu dallas
    import excel using ../external/pis/utaustin_pi, firstrow clear
    rename Account1 purchaser
    save ../output/utaustin_pi, replace

    import excel using ../external/pis/utdallas_pi, firstrow clear
    rename referenceawardid fund_id
    collapse (firstnm) *name, by(fund_id athr_id)
    save ../output/utdallas_pi, replace 

    import excel using ../external/pis/ecu_pi, firstrow clear
    drop G
    rename fed_id fund_id
    save ../output/ecu_pi, replace
    
    import excel using ../external/pis/ttu_pi, firstrow clear
    rename PrincipalInvestigator purchaser
    tostring middle_name, force replace
    save ../output/ttu_pi, replace
end

program merge_ids_foia
    use ../output/merged_foias, clear    
    keep if inlist(uni, "ecu", "utdallas", "utaustin", "ttu")
    fmerge m:1 purchaser using ../output/utaustin_pi, assert(1 3) keep(1 3) nogen
    merge m:1 purchaser using ../output/ttu_pi, assert(1 2 3 4) keep(1 3 4) nogen update
    merge m:1 fund_id using ../output/utdallas_pi, assert(1 2 3 4) keep(1 3 4) nogen update 
    merge m:1 fund_id using ../output/ecu_pi, assert(1 2 3 4) keep(1 3 4) nogen update
    save ../output/merged_foias_with_pis, replace
    contract athr_id
    drop _freq
    drop if mi(athr_id)
    save ../output/foia_athrs, replace
end

main
