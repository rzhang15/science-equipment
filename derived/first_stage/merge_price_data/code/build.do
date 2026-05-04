set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main
    local embed tfidf
    import delimited ../external/samp/govspend_panel_clean_classified_with_`embed'.csv, clear
    // get rid of negated orders these are returns
    rename predicted_market category
    gduplicates tag poid clean_desc, gen(dup_order)
    bys poid clean_desc: gegen has_neg = max(qty<0)
    drop if has_neg == 1 & dup_order > 0
    drop if agencyname == "university of michigan at ann arbor"
    drop if agencyname == "university of texas at dallas"
    rename id purchase_id
    *rename suppliername supplier
    rename purchasedate date
    keep agencyname product_desc clean_desc supplier price qty spend purchase_id date prediction_source similarity_score category 
    save ../temp/govspend_`embed', replace
    
    // dallas+oregon+michigan
    import delimited  ../external/samp/umich_merged_clean_classified_with_`embed'.csv,clear 
    drop predicted_market
    keep product_desc clean_desc supplier price qty spend purchase_id date prediction_source similarity_score category
    cap tostring purchase_id, replace force
    gen agencyname = "university of michigan at ann arbor"
    save ../temp/umich_`embed', replace

    import delimited  ../external/samp/utdallas_merged_clean_classified_with_`embed'.csv,clear 
    drop predicted_market
    keep product_desc clean_desc supplier price qty spend purchase_id date prediction_source similarity_score category 
    gen agencyname = "university of texas at dallas"
    cap tostring purchase_id, replace force
    save ../temp/utdallas_`embed', replace
    
    import delimited  ../external/samp/oregonstate_2010_2019_standardized_clean_classified_with_`embed'.csv,clear 
    rename predicted_market category
    keep product_desc clean_desc supplier price qty spend purchase_id date prediction_source similarity_score category 
    gen agencyname = "oregon state university"
    replace spend = price * qty
    cap tostring purchase_id, replace force
    save ../temp/oregonstate_`embed', replace

    clear
    save ../output/first_stage_data_`embed', replace emptyok
    foreach f in govspend utdallas oregonstate umich {
        append using ../temp/`f'_`embed'
    }
    rename supplier suppliername

    // === Category consolidation (mirrors prdct_classification step 0 / 1c) ===
    // UMich and UT Dallas use raw vendor categories (kept as ground truth);
    // these passes ensure all four sources end up in a consistent taxonomy
    // and that non-lab labels are dropped before downstream pipelines.

    // Lump all antibody variants into a single "primary antibodies" bucket.
    qui count if strpos(category, "antibod") > 0
    di "Antibody consolidation: collapsing " r(N) " obs to 'primary antibodies'"
    replace category = "primary antibodies" if strpos(category, "antibod") > 0

    // Drop non-lab categories (mirrors NONLAB_PREFIXES in
    // derived/process_foias/prdct_classification/code/config.py).
    // Prefix match: drops "electronics", "electronics - cables", etc.
    foreach v in "fees" "electronics" "instrument" "office" "lab furniture" ///
        "waste disposal" "equipment" "furniture" "software" "animal" ///
        "toolkit" "nonlab" "non-lab" "sequencing" "unclear" {
        qui count if strpos(category, "`v'") == 1
        di "  dropping prefix '`v'': " r(N) " obs"
        drop if strpos(category, "`v'") == 1
    }
    // Whole-word keyword match (mirrors NONLAB_KEYWORDS).
    foreach v in "clamp" "clamps" "tool" "random" "unclear" "tubing" "wire" ///
        "towel" "oring" "caps" "gas" "desk" "chair" "brushes" "trash" ///
        "cleaner" "tape" "miscellaneous" "clips" "flint" "accessories" ///
        "stands" "batteries" "apron" "pots" "pans" "stoppers" "closures" ///
        "rings" "mortar" "pestle" "supports" "trays" {
        qui count if ustrregexm(category, "\b`v'\b")
        di "  dropping keyword '`v'': " r(N) " obs"
        drop if ustrregexm(category, "\b`v'\b")
    }
    // Multi-word non-lab phrases (substring match — no word-boundary issues).
    foreach v in "irrelevant chemicals" "first-aid" "first aid" "cotton ball" ///
        "bundle of products" "ear protection" "applicators and swabs" ///
        "bundle of items" {
        qui count if strpos(category, "`v'") > 0
        di "  dropping phrase '`v'': " r(N) " obs"
        drop if strpos(category, "`v'") > 0
    }

    save ../output/first_stage_data_`embed', replace

end

main
