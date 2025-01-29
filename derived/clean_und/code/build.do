set more off
clear all
capture log close
program drop _all
set scheme modern
version 18
global raw "$sci_equip/raw"
global derived_output "$sci_equip/derived_output"

program main   
	import_data
    split_product_data
end

program import_data 
	foreach years in "2009-2011" "2012-2014" "2015-2017" "2018-2020" {
		import excel using "$raw/FOIA/und_2005_2023.xlsx", sheet("`years'") firstrow case(lower) clear
		
		if "`years'" == "2009-2011" {
			save ../temp/und_2010_2019.dta, replace 
		}
		else {
			append using ../output/und_2010_2019.dta
			save ../temp/und_2010_2019.dta, replace 
		}
	}
	
	gen year = year(podate)
	keep if year >= 2010 & year <= 2019
	
	ren (description supplier vendorname) (product_desc supplier_id suppliername)
	
	drop if mi(product_desc)
    collapse (firstnm)  suppliername (min) year , by(product_desc supplier_id)
	order supplier_id suppliername product_desc year 
    export delimited ../output/und_products.csv, replace
end 

program split_product_data

	import delimited ../output/und_products.csv, clear
	sort supplier_id product_desc
	gen row = _n 
	
	// Split randomly in half 
	gen random_num = runiform() 
	gen data_group = ((random_num > 0.5) + 1)
	drop random_num 
	export excel using "$derived_output/und_products/und_products_group1.xlsx" if data_group == 1, replace firstrow(variables)
	export excel using "$derived_output/und_products/und_products_group2.xlsx" if data_group == 2, replace firstrow(variables)

end

main

