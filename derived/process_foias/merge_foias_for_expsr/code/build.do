set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main
    merge_foias
end

program merge_foias
    import delimited "../external/samp/ecu_2006_2024_standardized_clean_classified_with_non_parametric_tfidf.csv", clear
    gen uni = "ecu"
    tostring fund_id, replace 
    tostring purchaser, replace 
    tostring supplier_id, replace
    tostring supplier, replace
    tostring purchase_id, replace
    tostring sku, replace
    tostring funder, replace
    save ../temp/ecu, replace

    import delimited "../external/samp/ttu_2010_2025_standardized_clean_classified_with_non_parametric_tfidf.csv", clear
    gen uni = "ttu"
    tostring fund_id, replace 
    tostring purchaser, replace 
    tostring supplier_id, replace
    tostring supplier, replace
    tostring purchase_id, replace
    tostring sku, replace
    cap tostring funder, replace
    save ../temp/ttu, replace

    import delimited "../external/samp/ukansas_2010_2019_standardized_clean_classified_with_non_parametric_tfidf.csv", clear
    gen uni = "ukansas"
    tostring fund_id, replace 
    tostring purchaser, replace 
    tostring supplier_id, replace
    tostring supplier, replace
    tostring purchase_id, replace
    tostring sku, replace
    cap tostring funder, replace
    save ../temp/ukansas, replace

    import delimited "../external/samp/utaustin_2012_2019_standardized_clean_classified_with_non_parametric_tfidf.csv", clear
    gen uni = "utaustin"
    tostring fund_id, replace 
    tostring purchaser, replace 
    tostring supplier_id, replace
    tostring supplier, replace
    tostring purchase_id, replace
    tostring sku, replace
    cap tostring funder, replace
    save ../temp/utaustin, replace

    import delimited "../external/samp/utdallas_merged_clean_classified_with_non_parametric_tfidf.csv", clear
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

main
