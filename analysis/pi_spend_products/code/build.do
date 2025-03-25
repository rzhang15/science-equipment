set more off
clear all
capture log close
program drop _all
set scheme modern
version 18
global dropbox_dir "~/dropbox (harvard university)/scientific equipment"

* Ruby's macros 
global dropbox_dir "$sci_equip"
cd "$github/science-equipment/analysis/pi_spend_products/code"

global raw "${dropbox_dir}/raw"
global derived_output "${dropbox_dir}/derived_output_sci_eq"

program main   

	merge_pi_transactions
	pi_spend_antibody
	
end

program merge_pi_transactions

	import excel using "$raw/FOIA/utdallas_2011_2024.xlsx", firstrow case(lower) clear
	
		merge m:1 projectid using "${derived_output}/ut_dallas_grants/final_projectid_to_pi_xwalk.dta", nogen assert(matched)
	
		gen spend = quantity * unitprice 
		drop extendedprice 
		
		gen year = year(purchasedate)
		
		gen matched_pi = !mi(pi)
		
	* match to product categories 
	ren suppliernumber supplier_id
	ren skucatalog sku 
	
	merge m:1 sku supplier_id using "$derived_output/make_mkt_panel/ctgry_xw.dta", nogen
	
	keep year quantity unitprice spend grantid agency pi prdct_ctgry product_desc suppliername sku
	
	save "../temp/transaction_level_match_pi_product_category.dta", replace
	
end 

program pi_spend_antibody

	use "../temp/transaction_level_match_pi_product_category.dta", clear 
	
		keep if !mi(pi) & !mi(prdct_ctgry) & year <= 2019
		replace prdct_ctgry = "antibody" if inlist(prdct_ctgry, "primary antibody", "secondary antibody")
		
		gen min_year = year 
		gen max_year = year 
		
		gcollapse (sum) spend (nunique) num_years = year (min) min_year (max) max_year, by(pi prdct_ctgry)

		by pi: egen total_spend = total(spend)
		gen perc_prdct = 100 * spend / total_spend 
		gen spend_per_year = spend / num_years
		
		keep if prdct_ctgry == "antibody"
		drop prdct_ctgry 
		order pi num_years min_year max_year total_spend spend* perc_prdct
				
		sum spend* perc_prdct, d 
		
		gsort -spend
		
	* Plot distribution
	tw ///
		(kdensity perc_prdct, color(lavender)) ///
		, ///
		xtitle("Share of PI FOIA Spend on Antibodies", size(small)) ///
		ytitle("Probability Density", size(small)) ///
		xlabel(, nogrid) ylabel(, nogrid) 
			
		graph export "../output/pi_share_foia_antibody_pre2020.png",replace

end

main
