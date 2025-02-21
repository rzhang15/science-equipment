set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 18
set maxvar 120000, perm 
global dropbox_dir "~/dropbox (harvard university)/scientific equipment"

program main   
    import_data
    raw_plots
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
    save ../output/ctgry_xw, replace
    import excel using "../external/foias/utdallas_2011_2024.xlsx", clear firstrow case(lower)
    rename (purchaseorderidentifier purchasedate suppliernumber productdescription projectid skucatalog unitprice quantity) (purchase_id purchase_date supplier_id product_desc project_id sku price qty)
    gen year = year(purchase_date)
    gen merged_entity = inlist(supplier_id, 27684, 264, 3315, 2810, 264) | supplier_id == 325
    merge m:1 supplier_id sku using ../output/ctgry_xw, assert(1 3) keep(3) nogen
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
    bys sku: egen min_year = min(year)
    bys sku: egen max_year = max(year)
    keep if min_year < 2014 & max_year >  2014
    bys sku year: egen total_spend = total(raw_spend)
    bys sku: egen pre_merger_spend = mean(total_spend) if year < 2014
    hashsort sku pre_merger_spend
    by sku: replace pre_merger_spend = pre_merger_spend[_n-1] if mi(pre_merger_spend)
    collapse (mean) *price *qty *spend (firstnm) prdct_ctgry, by(sku year mkt)
    collapse (mean) *price *qty spend merged_spend rival_spend rival_raw_spend raw_spend merged_raw_spend (firstnm) prdct_ctgry [aw = pre_merger_spend], by(year mkt)
    save ../output/mkt_yr, replace 
end

program raw_plots
    use ../output/mkt_yr, clear
    drop if year >= 2020
    drop if mi(merged_price)
    bys mkt: gen tot_yrs = _N 
    keep if tot_yrs >= 7  
    glevelsof prdct_ctgry, local(categories)
    foreach c in `categories' {
        preserve
        keep if prdct_ctgry == "`c'" 
        qui sum mkt
        local suf = r(mean)
        hashsort mkt year
        foreach var in price qty spend raw_price raw_qty raw_spend {
            // normalize to 2013 
            qui sum merged_`var' if year == 2013
            replace merged_`var' = merged_`var' - r(mean)
            qui sum rival_`var' if year == 2013
            replace rival_`var' = rival_`var' - r(mean)
            qui sum `var' if year == 2013
            replace `var' = `var' - r(mean)
            tw connected merged_`var' year, lcolor(lavender) mcolor(lavender) || connected rival_`var' year, lcolor(dkorange%40) mcolor(dkorange%40) || connected `var' year, lcolor(ebblue%50) mcolor(ebblue%50) legend(on label(1 "Merged entity `var'") label(2 "Rival `var'") label(3 "Overall `var'") ring(1) pos(6) rows(1) size(vsmall)) ytitle("Log `var'", size(small)) ylabel(#6, labsize(small)) xlabel(2011(2)2024, labsize(small)) xtitle("Year", size(small)) title("`c'", size(small))  tline(2014, lpattern(shortdash) lcolor(gs4%80))
            graph export "../output/figures/`var'_trends_mkt`suf'.pdf", replace
        }
        restore
    }
end

**
main
