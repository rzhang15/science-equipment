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
    tostring unit, replace
    save ../temp/ecu, replace

    import delimited "../external/samp/ttu_2010_2025_standardized_clean_classified_with_tfidf.csv", clear
    gen uni = "ttu"
    tostring fund_id, replace 
    tostring purchaser, replace 
    tostring supplier_id, replace
    tostring supplier, replace
    tostring purchase_id, replace
    tostring sku, replace
    tostring unit, replace
    cap tostring funder, replace
    save ../temp/ttu, replace

    import delimited "../external/samp/ukansas_2010_2019_standardized_clean_classified_with_tfidf.csv", clear
    gen uni = "ukansas"
    tostring fund_id, replace 
    tostring purchaser, replace 
    tostring supplier_id, replace
    tostring supplier, replace
    tostring purchase_id, replace
    tostring unit, replace
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
    tostring unit, replace
    cap tostring funder, replace
    save ../temp/utaustin, replace

    import delimited "../external/samp/utdallas_merged_clean_classified_with_tfidf.csv", clear
    cap gen uni = "utdallas"
    tostring fund_id, replace 
    tostring purchaser, replace 
    tostring supplier_id, replace
    tostring supplier, replace
    tostring purchase_id, replace
    tostring sku, replace
    tostring unit, replace
    cap tostring funder, replace
    save ../temp/utdallas, replace

    import delimited "../external/samp/umich_merged_clean_classified_with_tfidf.csv", clear
    cap gen uni = "umich"
    tostring fund_id, replace 
    tostring purchaser, replace 
    tostring supplier_id, replace
    tostring supplier, replace
    tostring purchase_id, replace
    tostring sku, replace
    tostring unit, replace
    cap tostring funder, replace
    save ../temp/umich, replace

    clear
    foreach u in utaustin utdallas ecu ttu ukansas umich {
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
    
    import excel using ../external/pis/umich_pi, firstrow clear
    rename sponsoraward fund_id
    collapse (firstnm) *name, by(fund_id athr_id)
    save ../output/umich_pi, replace
end

program merge_ids_foia
    use ../output/merged_foias, clear    
    keep if inlist(uni, "ecu", "utdallas", "utaustin", "ttu", "umich")
    fmerge m:1 purchaser using ../output/utaustin_pi, assert(1 3) keep(1 3) nogen
    merge m:1 purchaser using ../output/ttu_pi, assert(1 2 3 4) keep(1 3 4) nogen update
    merge m:1 fund_id using ../output/utdallas_pi, assert(1 2 3 4) keep(1 3 4) nogen update 
    merge m:1 fund_id using ../output/ecu_pi, assert(1 2 3 4) keep(1 3 4) nogen update
    merge m:1 fund_id using ../output/umich_pi, assert(1 2 3 4) keep(1 3 4) nogen update
    replace category = predicted_market if mi(category)
    drop predicted_market

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
    save ../temp/merged_foias_with_pis, replace
   
    import delimited ../external/samp/nonlab_bucket_assignments.csv, varnames(1) stringcols(_all) clear
    save ../temp/nl_map, replace 

    use ../temp/merged_foias_with_pis, clear
    merge m:1 category using ../temp/nl_map, assert(1 2 3) keep(1 3)
    gen has_nl_bucket = _merge == 3
    drop _merge
    replace category = "Non-Lab" if inlist(uni,"umich", "utdallas") & has_nl_bucket == 1
    replace nonlab_bucket = bucket if inlist(uni,"umich", "utdallas") & has_nl_bucket == 1
    drop has_nl_bucket bucket
    save ../output/merged_foias_with_pis, replace
    
    contract athr_id
    drop _freq
    drop if mi(athr_id)
    save ../output/foia_athrs, replace
end

main
