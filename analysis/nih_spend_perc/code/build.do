set more off
clear all
capture log close
program drop _all
set scheme modern
version 18
global dropbox_dir "~/dropbox (harvard university)/scientific equipment"

* Ruby's macros 
global dropbox_dir "$sci_equip"
cd "$github/science-equipment/analysis/nih_spend_perc/code"

global derived_output "${dropbox_dir}/derived_output_sci_eq"

program main   

	clean_nih_data
	merge_without_cost
	merge_transaction_grant
	calculate_consumable_stats
	save_transaction_spine
	
end

program clean_nih_data

	* Load NIH reporter data and drop subproject cost data
	import excel "${derived_output}/ut_dallas_grants/ut_dallas_nih_grants.xlsx", firstrow clear
	
    ren (ContactPIProjectLeader ProjectNumber OrganizationName) (pi full_grantid school)
	ren (BudgetStartDate BudgetEndDate FiscalYear) (budget_start budget_end year)
	ren (ProjectStartDate ProjectEndDate) (project_start project_end)
	ren (TotalCost DirectCostIC IndirectCostIC) (total_cost direct_cost indirect_cost)
	
    gen grantid = substr(full_grantid, 2, 14)
	drop if mi(pi) | mi(grantid) | mi(school) | mi(total_cost) 
	replace pi = subinstr(pi,".","",.)
	
	replace indirect_cost = 0 if mi(indirect_cost)
	replace total_cost = direct_cost + indirect_cost
    keep pi *grantid school year *_start *_end *_cost
    duplicates drop 
	
	* Make everything lower case 
	replace pi = lower(pi)
	replace pi = substr(pi, 1, strlen(pi) - 2) if substr(pi, -2, 1) == " "
	replace pi = substr(pi, 1, strlen(pi) - 2) if substr(pi, -2, 1) == " "
	replace school = lower(school)
	
	* Clean PI name
	replace pi = subinstr(pi,"Ó","o",.)
	replace pi = subinstr(pi,"alonso faruck","faruck",.)
	replace pi = "black, bryan" if strpos(pi, "black, bryan") > 0
	replace pi = "palmer, kelli" if strpos(pi, "palmer, kelli") > 0
	replace pi = "draper, rockford" if strpos(pi, "draper, rockford") > 0
	replace pi = "winkler, duane" if strpos(pi, "winkler, duane") > 0
	replace pi = "nisco, nicole" if strpos(pi, "nisco, nicole") > 0
	replace pi = ustrtrim(pi)
	
	isid full_grantid 
	
	* Collapse to remove supplement funding 
	gen not_supplement = !((strlen(full_grantid) >= 17) & (substr(full_grantid, length(full_grantid)-1, 1) == "S"))
	gsort grantid year budget_start budget_end -not_supplement
	assert substr(full_grantid, 1, 1) == "3" if not_supplement == 0
	gen not_supplement_id = sum(not_supplement)
	
	collapse (firstnm) full_grantid pi school grantid (min) year project_start budget_start ///
			(max) budget_end project_end (sum) *_cost, by(not_supplement_id)
	drop not_supplement_id 
	
	* Create indicator for grant funding cycle (either 1 or 2 as the first)
	gen new_cycle = inlist(substr(full_grantid, 1, 1), "1", "2")
	gen cycle_id = sum(new_cycle)
	drop new_cycle
	
	replace grantid = substr(grantid, 1, 11)
	
	gen need_merge = 1 
	isid full_grantid 
    save ../temp/nih_grants_full_date, replace
	
	* Collapse to the grant cycle level 
	gsort grantid year budget_start budget_end
	collapse (firstnm) full_grantid pi school grantid (min) project_start budget_start ///
			(max) budget_end project_end (sum) *_cost, by(cycle_id)
			
	save ../temp/nih_grants_cycle_level, replace
	
end 

program merge_without_cost 

	* Import transaction at the year level 
	import excel using "$raw/FOIA/utdallas_2011_2024.xlsx", firstrow case(lower) clear
		
	* match to product categories 
	ren suppliernumber supplier_id
	ren skucatalog sku 
	merge m:1 sku supplier_id using "$derived_output/make_mkt_panel/ctgry_xw.dta", nogen keepusing(prdct_ctgry)
	
	* Generate a column for antibodies spend 
	gen product = "other"
	replace product = "antibody" if inlist(prdct_ctgry, "primary antibody", "secondary antibody")
	
	* Generate total purchase and antibody 
	gen purchase_ = quantity * unitprice 
	collapse (sum) purchase_, by(purchasedate projectid product)
	
	reshape wide purchase_, i(purchasedate projectid) j(product) string
	replace purchase_antibody = 0 if mi(purchase_antibody) 
	
	gen purchase = purchase_antibody + purchase_other
	drop purchase_other
	
	* Merge to grant ID data 
	merge m:1 projectid using "${derived_output}/ut_dallas_grants/ut_dallas_projectid_to_pi_xwalk.dta", nogen keepusing(grantid agency referenceawardid pi)
		
	* Use substitute purchase date adjusted manually for two grants 
	gen purchasedate_var = purchasedate
	replace purchasedate_var = purchasedate_var - 365 if grantid == "R01HG001696" & purchasedate_var > 19449
	replace purchasedate_var = purchasedate_var + 15 if grantid == "R01AI116610" & purchasedate_var > 21640
	
	isid purchasedate projectid
	save ../temp/transaction_data, replace

end 

program merge_transaction_grant

	* Load NIH data
	use "../temp/nih_grants_full_date", clear
	
	* Range merge into NIH data 
	gen low_date = budget_start - 0.5
	gen high_date = budget_end + 0.5
	
	rangejoin purchasedate_var low_date high_date using ../temp/transaction_data, by(grantid)
	keep if !mi(projectid) 
	drop low_date high_date
	
	* Make sure each row just range match on one NIH reporter row
	bys projectid purchasedate (year budget_start): gen num = _N
	sum num if num > 1
	local obs_num = `r(N)'
	local num_val = `r(mean)'
	drop if (year != year(purchasedate)) & (num > 1) 
	local drop_num = `r(N_drop)'
	assert `drop_num' == (1 / `num_val') * `obs_num'
	drop num purchase purchase_antibody referenceawardid need_merge full_grantid
	
	isid projectid purchasedate
		
	* Check that we got all possible transaction x grant matched 
	merge 1:1 purchasedate projectid using ../temp/transaction_data, nogen
	
	* Merge on full award for those unmatched
	gen need_merge = mi(total_cost)
	ren referenceawardid full_grantid 
	merge m:1 full_grantid need_merge using "../temp/nih_grants_full_date", update
	drop if _merge == 2
	drop _merge need_merge purchasedate_var
	
	assert !mi(total_cost) if agency == "nih"
	
	isid projectid purchasedate
	
	* Save output 
	save ../temp/nih_merged_spending.dta, replace 
	
end 

program calculate_consumable_stats

	use ../temp/nih_merged_spending.dta, clear 
	
	* Perform analysis
	gen purchase_year = year(purchase)
	
	* Do pre-2020 
	keep if year <= 2019
		
	drop if mi(pi)
	bys pi: egen total_pi_spend = total(purchase)
	
	keep if agency == "nih"
	
	bys pi: egen total_pi_nih = total(purchase)

	
	collapse (sum) purchase purchase_antibody (first) pi school (mean) total_pi* , by(cycle_id)
	
	* Merge in data about each grant cycle 
	merge 1:1 cycle_id using ../temp/nih_grants_cycle_level, nogen keep(master matched)

	gen pi_nih_share = total_pi_nih / total_pi_spend * 100
	gen consumable_share = purchase / direct_cost * 100 
	gen antibody_share = purchase_antibody / direct_cost * 100 
	gen indirect_rate = indirect_cost / total_cost * 100
	
	* Summary stats 
	sum pi_nih_share, d 
	sum consumable_share if pi_nih_share > 95, d 
	local num_cycles = `r(N)'
	sum antibody_share if pi_nih_share > 95, d 
	sum indirect_rate if pi_nih_share > 95, d
	
	distinct pi 
	distinct pi if pi_nih_share > 95
	local num_pis = `r(ndistinct)'
	
	* Plot shares 
	tw ///
		(kdensity consumable_share, color(lavender)) ///
		, ///
		xtitle("Share of NIH Grant Cycle Funding", size(small)) ///
		ytitle("Probability Density", size(small)) ///
		xlabel(, nogrid) ylabel(, nogrid) ///
		note("Total Grant Cycles: `num_cycles', Total PIs: `num_pis'")
			
		graph export "../output/nih_share_foia_pre2020.png",replace

end 

program save_transaction_spine

	* Import transaction at the year level 
	import excel using "$raw/FOIA/utdallas_2011_2024.xlsx", firstrow case(lower) clear
			
	drop unitpricedate extendedprice costcenter vendoraddress city state fain referenceawardid
	
	* match to product categories 
	ren (suppliernumber purchaseorderidentifier skucatalog productdescription) ///
		(supplier_id ponumber sku product_desc)
		
	merge m:1 sku supplier_id using "$derived_output/make_mkt_panel/ctgry_xw.dta", nogen keepusing(prdct_ctgry)
		
	* Merge in grant data
	merge m:1 projectid purchasedate using ../temp/nih_merged_spending.dta, nogen assert(matched)
	
		drop pi_U purchase_antibody purchase 
		ren full_grantid full_nih_grantid
		label var cycle_id "Unique numeric identifier for which cycle this purchase is a part of"
		
	duplicates drop 
		
	save "$derived_output/ut_dallas_grants/transaction_spine_with_pi_grant.dta", replace

end 

main 
