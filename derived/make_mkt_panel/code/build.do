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
    replace prdct_ctgry = subinstr(prdct_ctgry, "-"," ",.)
    save ../temp/pt1, replace
    import excel using "../external/dallas/ut_dallas_products_group1_rz.xlsx", clear firstrow
    keep supplier_id suppliername product_desc sku prdct_ctgry 
    replace prdct_ctgry = strlower(prdct_ctgry)
    replace prdct_ctgry = strtrim(prdct_ctgry)
    replace prdct_ctgry = "us fetal bovine serum" if prdct_ctgry == "foetal bovine serum (fbs)"
    replace prdct_ctgry = subinstr(prdct_ctgry, "-"," ",.)
    append using ../temp/pt1
    save "${derived_output}/make_mkt_panel/ctgry_xw", replace
    import excel using "../external/foias/utdallas_2011_2024.xlsx", clear firstrow case(lower)
    rename (purchaseorderidentifier purchasedate suppliernumber productdescription projectid skucatalog unitprice quantity) (purchase_id purchase_date supplier_id product_desc project_id sku price qty)
    drop if mi(sku)
    gen year = year(purchase_date)
    gen merged_entity = inlist(supplier_id, 27684, 264, 3315, 2810, 264) | supplier_id == 325
    gen treated = merged_entity == 1
    gegen unique_sku = group(sku supplier_id)
    merge m:1 supplier_id sku using "${derived_output}/make_mkt_panel/ctgry_xw", assert(3) keep(3) nogen
    drop if prdct_ctgry == "other"
    gegen mkt = group(prdct_ctgry)
    gen raw_price = price
    gen raw_qty = qty
    gen raw_spend = price * qty
    replace price = log(price)
    replace qty = log(qty)
    gen spend = log(raw_spend)
    foreach var in price qty spend raw_price raw_qty raw_spend {
        gen merged_`var' = `var' if merged_entity == 1
        gen rival_`var' = `var' if merged_entity == 0
    }
    bys unique_sku: egen min_year = min(year)
    bys unique_sku: egen max_year = max(year)
    bys unique_sku : gen num_times = _N
    drop if num_times == 1
    bys unique_sku year: egen total_spend = total(raw_spend)
    bys unique_sku: egen pre_merger_spend = mean(total_spend) if year < 2014
    hashsort unique_sku pre_merger_spend
    by unique_sku: replace pre_merger_spend = pre_merger_spend[_n-1] if mi(pre_merger_spend)
    collapse (mean) *price *qty *spend treated (firstnm) prdct_ctgry product_desc suppliername, by(unique_sku year mkt)
    bys mkt treated: gen num_types = _n == 1
    bys mkt : egen total_types = total(num_types)
    keep if  total_types == 2
    collapse (mean) *price *qty spend merged_spend rival_spend rival_raw_spend raw_spend merged_raw_spend (firstnm) prdct_ctgry [aw = pre_merger_spend], by(year mkt)
    save "${derived_output}/make_mkt_panel/mkt_yr", replace 
end

**
main
