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
    keep agencyname product_desc clean_desc supplier price qty spend purchase_id date prediction_source similarity_score category  nonlab_bucket
    save ../temp/govspend_`embed', replace
    
    // dallas+oregon+michigan
    import delimited  ../external/samp/umich_merged_clean_classified_with_`embed'.csv,clear 
    drop predicted_market
    keep product_desc clean_desc supplier price qty spend purchase_id date prediction_source similarity_score category nonlab_bucket
    cap tostring purchase_id, replace force
    gen agencyname = "university of michigan at ann arbor"
    save ../temp/umich_`embed', replace

    import delimited  ../external/samp/utdallas_merged_clean_classified_with_`embed'.csv,clear 
    drop predicted_market
    keep product_desc clean_desc supplier price qty spend purchase_id date prediction_source similarity_score category nonlab_bucket
    gen agencyname = "university of texas at dallas"
    cap tostring purchase_id, replace force
    save ../temp/utdallas_`embed', replace
    
    import delimited  ../external/samp/oregonstate_2010_2019_standardized_clean_classified_with_`embed'.csv,clear 
    rename predicted_market category
    keep product_desc clean_desc supplier price qty spend purchase_id date prediction_source similarity_score category nonlab_bucket
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

    replace category = "centrifuge tubes" if category == "centrifuge conical tubes"
    replace category = "funnels" if inlist(category, ///
        "filtering funnels", "filling funnels", "separatory funnels", ///
        "addition funnels", "funnel stems")
    replace category = "metabolism assay kits" if category == "cellular metabolism assay kits"
    replace category = "cell lines" if inlist(category, ///
        "human cell lines", "mouse cell lines", "mice cell lines", ///
        "rat cell line", "insect cell lines")
    replace category = "lab-grade water" if inlist(category, ///
        "dnase/rnase-free & molecular-biology-grade water", ///
        "general-lab & specialty water", ///
        "cell culture grade life science water - distilled")
    replace category = "disposable pipettes" if inlist(category, ///
        "pasteur pipettes", "transfer pipettes", "aspirating pipettes", ///
        "mohr pipettes", "volumetric pipettes")
    replace category = "manual pipettors" if inlist(category, ///
        "manual single channel pipettes", "manual multichannel pipettes", ///
        "electronic multichannel pipettes", "pipette kits", "pipettors", ///
        "positive displacement pipettes")
    replace category = "beakers" if inlist(category, ///
        "glass beakers", "plastic beakers", "steel beakers", "stainless steel beakers")
    replace category = "graduated cylinders" if inlist(category, ///
        "glass graduated cylinders", "plastic graduated cylinders")
    replace category = "other flasks" if inlist(category, ///
        "fernbach flasks", "volumetric flasks", "recovery flasks", ///
        "freeze drying flasks", "kjeldahl flasks", "distilling flasks", ///
        "stainless steel flasks", "serum bottles")
    replace category = "specialty gloves" if inlist(category, ///
        "heat resistant gloves", "cold resistant gloves", "neoprene gloves", ///
        "cotton gloves", "chemical resistant gloves", "glove box gloves", ///
        "cut resistant gloves", "vinyl gloves", "rubber gloves")
    replace category = "specialty gloves" if inlist(category, ///
        "glove liners", "chloroprene gloves", "gloves")
    replace category = "specialty membrane filters" if inlist(category, ///
        "nylon membrane filters", "polycarbonate membrane filters", ///
        "pes membrane filters", "mce membrane filters", "membrane filters", ///
        "ptfe membrane filters", "cellulose acetate membrane filters")
    replace category = "specialty needles" if inlist(category, ///
        "dispensing needles", "needles", "blood collection needles", ///
        "pipetting needles", "double-tipped needles")
    replace category = "pcr tube accessories" if inlist(category, ///
        "caps and closures - pcr tube strips", "pcr strip tubes", ///
        "pcr tube strip caps", "caps and closures - pcr tubes")
    replace category = "caps and closures - vials" if inlist(category, ///
        "caps and closures - cryovial", "autosampler vial caps")
    replace category = "cuvettes" if inlist(category, ///
        "spectrophotometer cuvettes", "fluorescence cuvettes", "electroporation cuvettes")
    replace category = "primary antibodies" if inlist(category, ///
        "polyclonal primary antibodies", "monoclonal primary antibodies", ///
        "polyclonal primary antibody", "monoclonal primary antibody", ///
        "other-host primary antibody")
    replace category = "recombinant proteins" if inlist(category, ///
        "recombinant human protein", "recombinant mouse protein", ///
        "recombinant human/mouse/rat protein", "recombinant human/mouse protein", ///
        "recombinant human/murine/rat protein", "recombinant cas9 protein")
    replace category = "expression plasmids" if inlist(category, ///
        "synthetic mammalian expression plasmids", ///
        "synthetic bacterial expression plasmids", ///
        "synthetic plasmids", "aav plasmids", "non-viral expression plasmids")
    replace category = "synthetic dna oligonucleotide - desalted" ///
        if category == "synthetic dna oligonucleotide - purified"
    replace category = "pcr tube strips" if category == "pcr tubes"
    replace category = "nucleotides" if category == "radiolabeled nucleotides"
    replace category = "small molecule inhibitors" if category == "drug - other"
    replace category = "vials" if inlist(category, ///
        "sample vials", "scintillation vials", "autosampler vials", ///
        "drosophila vials", "screw cap vials")
    save ../temp/merged_price_data_`embed', replace

    import delimited ../external/samp/nonlab_bucket_assignments.csv, varnames(1) stringcols(_all) clear
    save ../temp/nl_map, replace 

    use ../temp/merged_price_data_`embed', clear
    merge m:1 category using ../temp/nl_map, assert(1 2 3) keep(1 3)
    rename _merge has_nl_bucket
    replace has_nl_bucket = 1 if has_nl_bucket == 3
    replace category = "Non-Lab" if inlist("university of michigan at ann arbor", "university of texas at dallas") & has_nl_bucket == 1
    replace nonlab_bucket = bucket if inlist("university of michigan at ann arbor", "university of texas at dallas") & has_nl_bucket == 1
    drop has_nl_bucket bucket
    save ../output/first_stage_data_`embed', replace

end

main
