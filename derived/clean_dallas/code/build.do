set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 18
global dropbox_dir "~/dropbox (harvard university)/scientific equipment"
//global dropbox_dir "$sci_equip"
global derived_output "${dropbox_dir}/derived_output/"

program main   
    import_data
    desc
	split_product_data
end

program import_data
    import excel using "../external/foia/utdallas_2011_2024.xlsx", firstrow case(lower) clear
	//import excel using "$sci_equip/raw/FOIA/utdallas_2011_2024.xlsx", firstrow case(lower) clear
    drop unitpricedate referenceawardid costcenter
    rename (purchaseorderidentifier purchasedate suppliernumber productdescription projectid skucatalog) (purchase_id purchase_date supplier_id product_desc project_id sku)
    gen year = year(purchase_date)
	bys supplier_id: egen first_yr = min(year)
    gen trans = 1 
	gen thermo = inlist(supplier_id, 27684, 264, 3315, 2810)
	gen lifetech = supplier_id == 325
	save ../temp/dallas, replace
	keep if thermo == 1
	drop if mi(sku)
	save ../temp/thermo_trans, replace
end

program desc
    use ../temp/dallas, clear  
    preserve
    collapse (firstnm) suppliername first_yr (sum) num_trans = trans ,  by(supplier_id)
    restore
	gen avg_price = unitprice
    bys sku: egen first_sku_yr = min(year)
    preserve
    collapse (sum) num_trans = trans  (mean) avg_price (firstnm) product_desc suppliername first_sku_yr , by(sku supplier_id year)
    bys sku : egen sd_price = sd(avg_price)
    replace sd_price = 0 if mi(sd_price)
    drop if mi(sku)
    restore
	
	bys project_id year: gen num_projects_yr = _n == 1
    gen thermo_trans = trans if thermo == 1
    preserve
    gcollapse (sum) num_projects_yr thermo_trans trans, by(year)
    gen perc_thermo = thermo_trans/trans
	graph bar num_projects_yr ,over(year, lab(angle(45))) ytitle("Number of Projects Active in Year", size(small)) 
	graph export ../output/figures/num_projects_yr.pdf, replace
	graph bar perc_thermo , over(year, lab(angle(45))) ytitle("% of Transactions bought from ThermoFisher", size(small)) 
	graph export ../output/figures/perc_thermo_trans_yr.pdf, replace
    restore

    //project level analysis
    gcollapse (sum) trans thermo_trans, by(project_id year)
    gen perc_thermo = thermo_trans/trans
    gcollapse (mean) trans thermo_trans perc_thermo, by(year)
	graph bar trans , over(year, label(angle(45))) ytitle("Avg. Number of Transactions per Project", size(small)) 
	graph export ../output/figures/avg_trans_proj_yr.pdf, replace
	graph bar perc_thermo , over(year, lab(angle(45))) ytitle("Avg. % of Transactions bought from ThermoFisher per Project", size(small)) 
	graph export ../output/figures/avg_perc_thermo_trans_proj_yr.pdf, replace
	// thermo analysis
	use ../temp/thermo_trans, clear
    collapse (firstnm)  product_desc (min) year, by(sku)
    export delimited ../output/thermo_skus.csv, replace
    use ../temp/dallas, clear
    drop if mi(sku)
    keep if lifetech == 1
    collapse (firstnm)  product_desc (min) year , by(sku)
    export delimited ../output/lifetech_skus.csv, replace
	
	// all products 
	use ../temp/dallas, clear
    drop if mi(sku)
    collapse (firstnm)  product_desc suppliername (min) year , by(sku supplier_id)
	order supplier_id suppliername product_desc sku year 
    export delimited ../output/dallas_skus.csv, replace
end

program split_product_data

	import delimited ../output/dallas_skus.csv, clear
	sort supplier_id sku
	gen row = _n 
	
	// Split randomly in half 
	gen random_num = runiform() 
	gen data_group = ((random_num > 0.5) + 1)
	drop random_num 
	export excel using "$derived_output/ut_dallas_products/ut_dallas_products_group1.xlsx" if data_group == 1, replace firstrow(variables)
	export excel using "$derived_output/ut_dallas_products/ut_dallas_products_group2.xlsx" if data_group == 2, replace firstrow(variables)

end
**
main
