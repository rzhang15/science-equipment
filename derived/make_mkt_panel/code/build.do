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
    gcontract supplier_id suppliername
    drop _freq
    save ../temp/pt1, replace
    import excel using "../external/dallas/ut_dallas_products_group1_rz.xlsx", clear firstrow
    gcontract supplier_id suppliername
    drop _freq
    append using ../temp/pt1
    contract supplier_id suppliername
    save ../temp/supplier_xw, replace

    import excel using "../external/dallas/combined.xlsx", clear firstrow
    drop if mi(suppliername)
    keep supplier_id suppliername product_desc sku prdct_ctgry 
    replace prdct_ctgry = strlower(prdct_ctgry)
    replace prdct_ctgry = strtrim(prdct_ctgry)
    replace prdct_ctgry = subinstr(prdct_ctgry, "-"," ",.)
    drop supplier_id
    merge m:1 suppliername using ../temp/supplier_xw, assert(3) nogen
    hashsort suppliername supplier_id
    by suppliername: replace supplier_id = supplier_id[_n-1] if mi(supplier_id)
    save "${derived_output}/make_mkt_panel/ctgry_xw", replace
    export excel using "${derived_output}/make_mkt_panel/ctgry_xw", replace firstrow(var)
    
    import excel using "../external/foias/utdallas_2011_2024.xlsx", clear firstrow case(lower)
    rename (purchaseorderidentifier purchasedate suppliernumber productdescription projectid skucatalog unitprice quantity) (purchase_id purchase_date supplier_id product_desc project_id sku price qty)
    replace suppliername = strlower(suppliername)
    replace suppliername = "fisher" if inlist(supplier_id, 27684, 264, 3315, 2810, 264) 
    replace suppliername = "vwr" if strpos(suppliername, "vwr")>0
    replace  suppliername = "life tech" if suppliername == "applied biosystems" | suppliername == "life technologies corporation"
    gen year = year(purchase_date)
    gen merged_entity = inlist(supplier_id, 27684, 264, 3315, 2810, 264) | supplier_id == 325 | supplier_id == 2821
    gegen unique_sku = group(sku supplier_id)
    drop if mi(sku)
    merge m:1 supplier_id sku using "${derived_output}/make_mkt_panel/ctgry_xw", assert(3) keep(3) nogen
    replace prdct_ctgry = "antibodies" if inlist(prdct_ctgry, "primary antibody", "secondary antibody")
    gegen mkt = group(prdct_ctgry)
    drop extendedprice
    gen treated = inlist(prdct_ctgry, "adding proteases", "affinity chromatography kits", "biotin reagent", "cdna synthesis kits", "cell lysis detergents" , "cell lysis reagents", "chemical modifiers", "chemiluminescent substrate") | inlist(prdct_ctgry, "cloning enzymes", "cloning kits", "column based instruments", "cross linkers", "dye based qpcr kits", "electrophoresis gel boxes", "elisa kits", "fluorescence photometers", "gel stains") | inlist(prdct_ctgry, "high fidelity polymerase", "hot start polymerase", "magnetic bead based instruments", "western blot membranes", "molecular weight standards", "ordinary and flourescent microparticles") | inlist(prdct_ctgry, "other beads", "other specialty polymerase", "pcr kits", "pcr plastic consumables", "power suppliers", "pre cast gels") | inlist(prdct_ctgry, "primary antibody", "primers", "probe based qpcr kits", "probe based rt qpcr kits", "protease", "protein standards", "qpcr instruments", "reactive dyes", "reverse transcriptase enzymes") | inlist(prdct_ctgry, "rt pcr kits", "secondary antibody", "spectrofluorometers", "standard reagents: buffers, dntps, other ancillary reagents", "streptavidin and avidin reagents",  "taq polymerase") | inlist(prdct_ctgry, "thermal cyclers", "transfection reagents", "transfer boxes", "vertical gel boxes", "antibodies") 
    drop if inlist(prdct_ctgry, "unclear", "general lab consumables", "general lab equipment", "instrument accessories" , "electronics accessories")
    drop if inlist(prdct_ctgry, "containers & storage", "cleaning supplies & wipes")
    drop if inlist(prdct_ctgry,  "service", "hardware" ,"non chemical item")
    drop if inlist(prdct_ctgry, "office supplies", "mouse")
    drop if inlist(prdct_ctgry, "shipping", "subaward", "fees", "chemical", "electronics")
    drop if strpos(prdct_ctgry, "general") > 0
    drop if ((strpos(prdct_ctgry, "media") > 0 & strpos(prdct_ctgry, "liquid")>0) | (strpos(prdct_ctgry, "media") > 0 & strpos(prdct_ctgry, "dry")>0) | strpos(prdct_ctgry, "serum") | strpos(prdct_ctgry, "polymer-based magnetic beads") > 0  | strpos(prdct_ctgry, "sera"))
    drop if inlist(prdct_ctgry, "shrna", "sirna", "mirna")
    drop if year >= 2020
    gen raw_price = price
    gen raw_qty = qty
    gen raw_spend = price * qty
    replace price = log(price)
    replace qty = log(qty)
    bys mkt year: egen spend99= pctile(raw_spend), p(99)
    bys mkt year: egen spend1 = pctile(raw_spend), p(1)
    drop if raw_spend <= spend1
    drop if raw_spend >= spend99
    gen spend = log(raw_spend)
    bys supplier_id mkt : gen num_trans = _N
    bys supplier_id mkt year: gen num_trans_yr = _N
    bys mkt : gen num_times = _N
    bys supplier_id mkt year: egen total_spend = total(raw_spend)
    bys mkt year: egen mkt_spend = total(raw_spend)
    gen spend_shr = total_spend/mkt_spend 
    bys supplier_id mkt: egen pre_merger_shr = mean(spend_shr) if year == 2013
    bys supplier_id mkt: egen pre_merger_spend = mean(total_spend) if year <=2013
    hashsort supplier_id mkt pre_merger_spend
    by supplier_id mkt: replace pre_merger_spend = pre_merger_spend[_n-1] if mi(pre_merger_spend)
    hashsort supplier_id mkt pre_merger_shr 
    by supplier_id mkt: replace pre_merger_shr = pre_merger_shr[_n-1] if mi(pre_merger_shr)
    bys mkt supplier_id year: gen num_suppliers_id = _n == 1
    bys mkt year: egen num_suppliers = total(num_suppliers) 
    bys supplier_id sku : gen num_sku_cnt = _N
    bys mkt: egen sd_price = sd(raw_price)
    sum sd_price, d
    drop if sd_price >= r(p95) & treated == 0
    save "${derived_output}/make_mkt_panel/transactions", replace
    collapse (mean) *price treated num_suppliers pre_merger* (sum) *raw_qty *raw_spend (firstnm) prdct_ctgry product_desc suppliername [aw = num_sku_cnt], by(supplier_id mkt year)
    collapse (mean) *price treated num_suppliers (sum) *raw_qty *raw_spend (firstnm) prdct_ctgry product_desc suppliername, by(mkt year)
    rename price avg_log_price
    gen log_avg_price = log(raw_price)
    gen log_tot_qty = log(raw_qty)
    gen log_tot_spend = log(raw_spend)
    save "${derived_output}/make_mkt_panel/mkt_yr", replace 
end

**
main
