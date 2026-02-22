set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main
    local embed tfidf
    import delimited ../external/samp/govspend_panel_classified_with_non_parametric_`embed'.csv, clear
    // get rid of negated orders these are returns
    rename predicted_market category
    gduplicates tag poid clean_desc, gen(dup_order)
    bys poid clean_desc: gegen has_neg = max(qty<0)
    drop if has_neg == 1 & dup_order > 0
    rename id purchase_id
    rename suppliername supplier
    rename purchasedate date
    keep agencyname product_desc clean_desc supplier price qty spend purchase_id date prediction_source similarity_score category 
    save ../temp/govspend_`embed', replace
    // dallas+oregon+kansas
    import delimited  ../external/samp/utdallas_merged_clean_classified_with_non_parametric_`embed'.csv,clear 
    drop predicted_market
    gen agencyname = "university of texas at dallas"
    keep product_desc clean_desc supplier price qty spend purchase_id date prediction_source similarity_score category 
    save ../temp/utdallas_`embed', replace
    
    import delimited  ../external/samp/ukansas_2010_2019_standardized_clean_classified_with_non_parametric_`embed'.csv, clear
    rename predicted_market category
    keep product_desc clean_desc supplier price qty spend purchase_id date prediction_source similarity_score category 
    gen agencyname = "university of kansas"
    save ../temp/ukansas_`embed', replace

    import delimited  ../external/samp/oregonstate_2010_2019_standardized_clean_classified_with_non_parametric_`embed'.csv,clear 
    rename predicted_market category
    keep product_desc clean_desc supplier price qty spend purchase_id date prediction_source similarity_score category 
    gen agencyname = "oregon state university"
    save ../temp/oregonstate_`embed', replace

    clear
    save ../output/first_stage_data_`embed', replace emptyok
    foreach f in govspend utdallas ukansas oregonstate {
        append using ../temp/`f'_`embed'
    }
    rename supplier suppliername
    save ../output/first_stage_data_`embed', replace

end

main
