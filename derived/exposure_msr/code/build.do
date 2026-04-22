set more off
clear all
capture log close
program drop _all
set scheme modern
pause on
set seed 8975
set maxvar 120000

program main
   * foia_pis
   * clean_foia_data
    gen_utdallas_exposure
    stop 
    gen_exposure
end

program foia_pis 
    use ../external/foia/foia_athrs, clear
    merge 1:1 athr_id using ../external/ls_samp/list_of_athrs, assert(1 2 3) keep(3) nogen
    save ../output/foia_athrs, replace

    foreach i in 10 { //15 20 25 30 40 50 100 {
        import delimited using ../external/fields/author_static_clusters_`i', clear varnames(1)
        merge 1:1 athr_id using ../output/foia_athrs, assert(1 2 3) keep(3) nogen 
        save ../output/foia_athrs_with_clusters_`i', replace
        tab cluster_label
    }
end

program clean_foia_data
    use ../external/foia/merged_foias_with_pis, clear
    qui {
        gen purchase_date = date(date, "YMD")
        gen year = year(purchase_date)
        keep if inrange(year, 2010, 2019)
        drop if mi(athr_id)
    }
    qui count
    local total_obs = r(N)
    qui sum spend, d
    local total_spend : di %16.0f r(sum)
    di "[All purchases EVER] N:  `total_obs' Total Spend:  `total_spend'"
    qui {
        merge m:1 suppliername using ../external/sup/lifescience_supplier_map, assert(1 2 3) keep(3) nogen
        rename (suppliername new_suppliername) (old_suppliername suppliername)
        drop if mi(suppliername)
        drop if suppliername == "na"
        bys suppliername: gen num_sup_obs = _N
        drop if num_sup_obs == 1
        replace suppliername = "thermo fisher scientific" if suppliername == "possible missions" & strpos(uni, "dallas") > 0
        bys suppliername: gegen tot_sup_spend = total(spend)
        drop if tot_sup_spend  < 0 
    }
    qui count
    local total_obs = r(N)
    qui sum spend, d
    local total_spend : di %16.0f r(sum)
    di "[Supplier Cut]  N: `total_obs' Total Spend: `total_spend'"

    qui {
        replace predicted_market = category if uni == "utdallas"
        drop category
        rename predicted_market category
        replace category = "cryovials" if strpos(clean_desc, "cryo") >0 & strpos(clean_desc, "vial") >0 
        drop if price <= 0 | qty < 1 | spend <= 0
        gen lab = !inlist(category , "Non-Lab", "unclassified")
        foreach v in "animal - " "fees - " "electronics - " "instrument" "office supplies" "lab furniture" "waste disposal" "equipment" "furniture" "software" ///
          "toolkit" "clamp" "tool" "tubing" "random" "unclear" "wire" "towel" "irrelevant chemicals" "oring" "caps" "gas" "first-aid" "first aid" "desk" "chair" "brushes" "trash" "cleaner" ///
          "cotton ball" "bundle of products" "tape" "miscellaneous" "clips" "flint" "accessories" "stands" "batteries" "ear protection" "apron" "pots" "pants" "stoppers" "closures" "rings" ///
          "mortar" "pestle" "support" "trays" "applicators and swabs" "bundle" "sequencing" "tem - " {
            drop if strpos(category, "`v'") > 0
        }
        keep if lab == 1
        replace spend = price * qty  if qty != 1
        replace qty = spend / price if qty == 1
        drop if similarity_score == 0
    }
    qui count
    local total_obs = r(N)
    qui sum spend, d
    local total_spend : di %16.0f r(sum)
    di "[ML Consumables & Negative Orders] N: `total_obs' Total Spend: `total_spend'"
    qui {
    // get rid of negated orders
        drop if (spend > 100000 & !mi(spend)) | price > 100000 & !mi(price) 
        foreach v in "graduate " "table" "library" "reader" "po " "replace" ///
            "thesis" "pay" "delivery" "sequencing" "analysis" "transport" "lease" "order" " ins" "date" ///
            "delivered" "deliver" "wire" "fitting" "lamp" "nasco" "sport" ///
            "screw" "wall" "file" "mesh" "chamber" "analyzer" "oven" ///
            "fume hood" "biosafety cabinet" "wo#" "construction" "flooring" ///
            "lab gases" "glucarpidase" "voraxaze" "supplement issue" ///
            "ajph" "phssr" "capillarys" "analyses" "datalogger" ///
            "professionalism" ".org" "lcmsms" "pre-owned" "enterprise" ///
            "dialysis" "tower" "kelvin" "lithography" "seal" ///
            "array" "adverstise" {
            drop if strpos(clean_desc, "`v'") > 0
        }
        drop if (strpos(clean_desc, "plate") > 0 | strpos(clean_desc, "card")) & category == "synthetic dna oligonucleotide"
        // drop borderline terms only when model confidence is low
        foreach v in "service" "repair" "maintenance" "consulting" "training" ///
            "rental" "subscription" "license" "software" "warranty" "support contract" ///
            "calibration" "installation" "shipping" "freight" "quote" "estimate" ///
            "contract" "agreement" "professional" "labor" "hourly" {
            drop if strpos(clean_desc, "`v'") > 0 & prediction_source == "Expert Model" & similarity_score < 0.20
        } 
        foreach v in "animal - " "fees - " "electronics - " "instrument" "office supplies" "lab furniture" "waste disposal" "equipment" "furniture" "software" ///
          "toolkit" "clamp" "tool" "tubing" "random" "unclear" "wire" "towel" "irrelevant chemicals" "oring" "caps" "gas" "first-aid" "first aid" "desk" "chair" "brushes" "trash" "cleaner" ///
          "cotton ball" "bundle of products" "tape" "miscellaneous" "clips" "flint" "accessories" "stands" "batteries" "ear protection" "apron" "pots" "pants" "stoppers" "closures" "rings" ///
          "mortar" "pestle" "support" "trays" "applicators and swabs" "bundle" "sequencing" "tem - " "nonlab" {
            drop if strpos(category, "`v'") > 0
          }
    }
    count
    local total_obs = r(N)
    qui sum spend, d
    local total_spend : di %16.0f r(sum)
    di "[Remove Possible Non-consumables] N: `total_obs' Total Spend: `total_spend'"
    merge m:1 category using ../external/ml/categories_tfidf, assert(2 3) keep(3) nogen
    drop if similarity_score <= 0.10 & prediction_source == "Expert Model" 
    drop if support < 5
    qui sum spend, d
    local total_spend : di %16.0f r(sum)
    di "[bad ml categories] N: `total_obs' Total Spend: `total_spend'"
     qui sum spend 
    local tot_spend = r(sum)
    qui sum spend if keep == 1
    di "Total spend in matched categories: " r(sum) " out of " `tot_spend' " (" string(r(sum)/`tot_spend'*100) "%)"
    qui sum spend if keep == 1 & tier3 == 0
    di "Total spend in matched categories minus tier3: " r(sum) " out of " `tot_spend' " (" string(r(sum)/`tot_spend'*100) "%)"
    qui count
    local tot_obs = r(N)
    qui count if keep  == 1
    di "Total observations in matched categories: " r(N) " out of " `tot_obs' " (" string(r(N)/`tot_obs'*100) "%)"
    qui count if keep  == 1 & tier3 == 0
    di "Total observations in matched categories minus tier3: " r(N) " out of " `tot_obs' " (" string(r(N)/`tot_obs'*100) "%)"
    save ../output/cleaned_merged_fois, replace
end

program gen_utdallas_exposure
    use ../external/foia/merged_foias_with_pis, clear
    drop if mi(athr_id)
    drop predicted_market
    gen year = year(date(date, "YMD"))
    drop if year > 2013
    keep if uni == "utdallas"
    merge m:1 category using ../external/ml/categories_tfidf, keep(1 3) 
    keep if keep == 1
    gcollapse (sum) spend, by(athr_id category)
    qui sum spend
    local raw_spend = r(sum)
    bys athr_id: egen tot_lab_spend = total(spend)
    gen lab_spend_shr = spend / tot_lab_spend
    merge m:1 category using ../external/betas/did_coefs, assert(1 2 3) keep(1 3) nogen
    gen exposure = b*lab_spend_shr
    gcollapse (sum) exposure, by(athr_id)
end

program gen_exposure
    use ../output/cleaned_merged_fois, clear
    keep if year <= 2013
    keep if keep == 1
    merge m:1 athr_id using ../output/foia_athrs_with_clusters_10, assert(1 2 3) keep(3) nogen
    tab cluster_label
    gcollapse (sum) spend (mean) treated cluster_label, by(athr_id category)
    bys athr_id: egen tot_lab_spend = total(spend)
    gen lab_spend_shr = spend / tot_lab_spend
    merge m:1 category using ../external/betas/did_coefs, assert(1 2 3) keep(1 3)
    rename _merge has_beta
    replace has_beta = 0 if has_beta == 1
    replace has_beta = 1 if has_beta == 3
    qui sum spend
    local total_spend = r(sum)
    qui sum spend if has_beta == 1
    local beta_spend = r(sum)
    gen exposure = b*lab_spend_shr
    sum cluster_label
    local maxcl = r(max)
    tostring cluster_label, replace
    heatplot lab_spend_shr cluster_label category if has_beta==1, keylabels(, range(1))  cuts(0(.05).4) xlabel(, angle(90) labsize(tiny)) ylabel(, angle(0) labsize(vsmall))  colors(Greens)
    graph export ../output/figures/cluster_mkt_heatmap.pdf, replace
    gen annual_spend = spend
    gen treated_spend = spend if treated == 1
    collapse (sum) exposure spend treated_spend (mean) annual_spend (firstnm) tot_lab_spend cluster_label, by(athr_id)

    drop if treated_spend == 0
    count
    count if mi(exposure)
    drop if mi(exposure)
    sum exposure , d
    local mean : di %4.3f r(mean)
    local sd: di %4.3f r(sd)
    local p25: di %4.3f r(p25)
    local p50: di %4.3f r(p50)
    local p75: di %4.3f r(p75)
    local max: di %4.3f  r(max)
    local min: di %4.3f r(min)
    local fes athr_id year

    tw kdensity exposure, xtitle("Imputed Exposure Score", size(small)) ytitle("Density", size(small)) ///
        ylab(, labsize(vsmall)) xlab(#15, labsize(vsmall)) ///
        legend(on order(- "Min: `min'" "Q1 = `p25'" "Median = `p50'" "Mean: `mean'" "SD = `sd'" "Q3 = `p75'" "Max = `max'") pos(1) ring(0) size(vsmall))
    graph export ../output/figures/exposure_density.pdf, replace
    save ../output/athr_exposure, replace
    stop 
    preserve
    contract athr_id
    drop _freq
    save ../output/athr_exposure_list, replace
    restore
    hashsort -exposure
    gcollapse (mean) exposure ,by(cluster_label)
    save ../output/cluster_exposure, replace
end


main
