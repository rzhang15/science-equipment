set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 18
set maxvar 120000, perm 
global dropbox_dir "~/dropbox (harvard university)/scientific equipment"
global derived_output "${dropbox_dir}/derived_output"

program main   
    import_data
end

program import_data
    import excel using "../external/dallas/ut_dallas_products_group2_cx.xlsx", clear firstrow
    keep supplier_id suppliername product_desc sku prdct_ctgry 
    replace prdct_ctgry = strlower(prdct_ctgry)
    replace prdct_ctgry = strtrim(prdct_ctgry)
    replace prdct_ctgry = "calf sera" if prdct_ctgry == "bovine calf serum"
    replace prdct_ctgry = "chemical modifiers" if prdct_ctgry == "chemical modifers"
    replace prdct_ctgry = "liquid proprietary media, chemically defined" if prdct_ctgry == "liquid proprietary, chemically defined"
    replace prdct_ctgry = subinstr(prdct_ctgry, "-"," ",.)
    save ../temp/pt1, replace
    import excel using "../external/dallas/ut_dallas_products_group1_rz.xlsx", clear firstrow
    keep supplier_id suppliername product_desc sku prdct_ctgry 
    replace prdct_ctgry = strlower(prdct_ctgry)
    replace prdct_ctgry = strtrim(prdct_ctgry)
    replace prdct_ctgry = "liquid proprietary media, chemically defined" if prdct_ctgry == "liquid proprietary, chemically defined"
    replace prdct_ctgry = "us fetal bovine serum" if prdct_ctgry == "foetal bovine serum (fbs)"
    replace prdct_ctgry = subinstr(prdct_ctgry, "-"," ",.)
    append using ../temp/pt1
    save "${derived_output}/make_mkt_panel/ctgry_xw", replace
    export excel using "${derived_output}/make_mkt_panel/ctgry_xw", replace firstrow(var)
    
    import excel using "../external/foias/utdallas_2011_2024.xlsx", clear firstrow case(lower)
    rename (purchaseorderidentifier purchasedate suppliernumber productdescription projectid skucatalog unitprice quantity) (purchase_id purchase_date supplier_id product_desc project_id sku price qty)
    drop extendedprice
    replace suppliername = strlower(suppliername)
    replace suppliername = "fisher" if inlist(supplier_id, 27684, 264, 3315, 2810, 264) 
    replace suppliername = "vwr" if strpos(suppliername, "vwr")>0
    replace  suppliername = "life tech" if suppliername == "applied biosystems" | suppliername == "life technologies corporation"
    drop if mi(sku)
    gen year = year(purchase_date)
    drop if year >=2020
    gen merged_entity = inlist(supplier_id, 27684, 264, 3315, 2810, 264) | supplier_id == 325 | supplier_id == 2821
    gen treated = merged_entity == 1
    gegen unique_sku = group(sku supplier_id)
    merge m:1 supplier_id sku using "${derived_output}/make_mkt_panel/ctgry_xw", assert(2 3) keep(3) nogen
    drop if prdct_ctgry == "other"
    gen broad_ctgry = prdct_ctgry
    replace broad_ctgry = "cell culture sera" if strpos(prdct_ctgry, "sera") > 0 | strpos(prdct_ctgry, "serum")
    replace broad_ctgry = "cell culture media" if strpos(prdct_ctgry, "media") > 0  
    replace broad_ctgry = "gene silencing effectors" if inlist(prdct_ctgry, "sirna", "shrna", "mirna")
    replace broad_ctgry = "magnetic beads" if inlist(prdct_ctgry, "polymer based magnetic beads", "other magnetic beads")
    replace broad_ctgry = "standalone NA amplification reagents" if strpos(prdct_ctgry, "polymerase") >0 | prdct_ctgry == "reverse transcriptase enzymes"
    replace broad_ctgry = "ready to use NA amplification kits" if strpos(prdct_ctgry, "kits") >0 & !inlist(prdct_ctgry, "elisa kits", "cloning kits", "affinity chromatography kits")
    replace broad_ctgry = "antibody production" if strpos(prdct_ctgry, "antibody") | strpos(prdct_ctgry,  "biotin") | prdct_ctgry == "streptavidin and avidin reagents"
    replace broad_ctgry = "protein modification reagents" if inlist(prdct_ctgry, "chemical modifiers", "cross linkers", "adding proteases") 
    replace broad_ctgry = "sds page tools" if inlist(prdct_ctgry, "vertical gel boxes", "power suppliers", "pre cast gels", "protein standards", "gel stains") 
    replace broad_ctgry = "western blots tools" if inlist(prdct_ctgry, "transfer boxes", "membranes", "chemiluminescent substrate") 
    replace broad_ctgry = "fluorometers" if inlist(prdct_ctgry, "spectrofluorometers", "fluorescence photometers") 
    gegen mkt = group(prdct_ctgry)
    gegen broad_mkt = group(broad_ctgry)
    gen raw_price = price
    gen raw_qty = qty
    gen raw_spend = price * qty
    replace price = log(price)
    replace qty = log(qty)
    gen spend = log(raw_spend)
    bys unique_sku : gen num_times = _N
    drop if num_times == 1
    foreach var in price qty spend raw_price raw_qty raw_spend {
        gen merged_`var' = `var' if merged_entity == 1
        gen rival_`var' = `var' if merged_entity == 0
    }
    save "${derived_output}/make_mkt_panel/transaction_cleaned", replace
    foreach v in mkt broad_mkt {
        preserve
        bys `v': egen min_treated_year = min(year) if treated == 1
        bys `v': egen max_treated_year = max(year) if treated == 1
        bys `v': egen min_untreated_year = min(year) if treated == 0
        bys `v': egen max_untreated_year = max(year) if treated == 0
        foreach var in min_treated_year max_treated_year min_untreated_year max_untreated_year {
            hashsort `v' `var' 
            by `v': replace `var' = `var'[_n-1] if mi(`var')
        }
        keep if min_treated_year< 2014  & min_untreated_year < 2014
        keep if max_treated_year > 2014 & max_untreated_year > 2014
        bys unique_sku year: egen total_spend = total(raw_spend)
        bys unique_sku: egen pre_merger_spend = mean(total_spend) if year < 2014
        hashsort unique_sku pre_merger_spend
        by unique_sku: replace pre_merger_spend = pre_merger_spend[_n-1] if mi(pre_merger_spend)
        collapse (mean) *price treated (sum) *raw_qty *raw_spend (firstnm) prdct_ctgry product_desc suppliername broad_ctgry, by(unique_sku year `v')
        bys `v' treated: gen num_types = _n == 1
        bys `v' : egen total_types = total(num_types)
        keep if  total_types == 2
        rename price avg_log_price
        rename merged_price merged_avg_log_price
        rename rival_price rival_avg_log_price
        gen log_avg_price = log(raw_price)
        gen merged_log_avg_price = log(merged_raw_price)
        gen rival_log_avg_price = log(rival_raw_price)
        gen log_tot_qty = log(raw_qty)
        gen merged_log_tot_qty = log(merged_raw_qty)
        gen rival_log_tot_qty = log(rival_raw_qty)
        gen log_tot_spend = log(raw_spend)
        gen merged_log_tot_spend = log(merged_raw_spend)
        gen rival_log_tot_spend = log(rival_raw_spend)
        save "${derived_output}/make_mkt_panel/sku_`v'_yr", replace 
        collapse (mean) *price *qty *spend (firstnm) prdct_ctgry broad_ctgry (sum) treated_sku = treated  , by(year `v')
        save "${derived_output}/make_mkt_panel/`v'_yr", replace 
        restore
    }
end

**
main
