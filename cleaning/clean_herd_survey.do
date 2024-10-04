clear all

* Data 
global derived "$sci_equip/derived"
global herd "$sci_equip/HERD/raw"
global iris "$sci_equip/IRIS"
global xwalk "$sci_equip/Crosswalks"

* Code
program main 

	merge_herd_survey_years
	clean_herd_variables
	create_herd_survey
	merge_herd_iris

end 

program merge_herd_survey_years

	* Append all years to master dataset
	local master_data "$derived/herd_survey_clean.dta" 
	
	* Creation of dataset from which year to which year 
	local first_year 2000
	local last_year 2022
	
	forval yr = `first_year'/`last_year' {
		
        import delimited "$herd/herd_`yr'.csv", clear

		* Keep funding related expenditures, only available for later HERD years
		if `yr' >= 2010 {
			
			keep if inlist(question, ///
							 "Federal expenditures by field and agency", ///
							 "Nonfederal expenditures by field and source", ///
							 "Capitalized equipment expenditures by field and source")
							 
			keep inst_id year ncses_inst_id ipeds_unitid ///
				inst_name_long inst_city inst_state_code inst_zip ///
				question row column data
				
			ren inst_id fice 
			ren ncses_inst_id ncses_id 
			ren ipeds_unitid ipeds_id
			ren inst_name_long name
			ren inst_city city  
			ren inst_state_code state 
			ren inst_zip zip 
		} 
		else {
			
			keep if inlist(question, ///
							 "Expenditures by S&E field", ///
							 "Equipment expenditures by S&E field")
							 
			keep fice year ///
				inst_name_long inst_city inst_state inst_zip ///
				question row column data	
				
			ren inst_name_long name 
			ren inst_city city 
			ren inst_state state 
			ren inst_zip zip
		}
		
		if `yr' == `first_year' {
			save "`master_data'", replace
		}
		else {
			append using "`master_data'"
			save "`master_data'", replace
		}
	}
	
	* Extend NCSES ID and IPEDS ID 
	bys fice (year): replace ipeds_id = ipeds_id[_N] if missing(ipeds_id)
	bys fice (year): replace ncses_id = ncses_id[_N] if missing(ncses_id)
	
	* Merge to IPEDS ID for those with missing 
	merge m:1 fice using "$xwalk/fice_opeid_ipeds_id_xwalk.dta", ///
			update keepusing(ipeds_id) keep(1 3 4 5) nogen
	
end 

program clean_herd_variables
		
	* Clean location
	replace zip = cond(strpos(zip, "-"), substr(zip, 1, strpos(zip, "-") - 1), zip)
	destring zip, replace force
	
	* Keep only the whole field 
	ren row field 
		drop if field == "All"
		keep if strpos(field, ", all") > 0
		replace field = subinstr(field, ", all", "", .)
		replace field = "Geosciences, atmospheric sciences, and ocean sciences" ///
			if field == "Geosciences, atmospheric sciences and ocean sciences"
	
	* Keep total federal vs. nonfederal spending
	ren column source
		keep if inlist(source, "Federal", "Nonfederal", "Total")
		replace source = "Federal" if question == "Federal expenditures by field and agency" 
		replace source = "Nonfederal" if question == "Nonfederal expenditures by field and source"
		replace source = lower(source)
		
	* Have everything in terms of total vs. capital R&D 
	ren question expenditure
		replace expenditure = "Total R&D" if inlist(expenditure, ///
								"Expenditures by S&E field", ///
								"Nonfederal expenditures by field and source", ///
								"Federal expenditures by field and agency")
								
		replace expenditure = "Equipment" if inlist(expenditure, ///
								"Equipment expenditures by S&E field", ///
								"Capitalized equipment expenditures by field and source")
	
end 

program create_herd_survey 

	isid fice year field expenditure source
	
	* Reshape
	ren data spend_
	reshape wide spend_, i(fice year field expenditure) j(source) string
	
	* Fill in missing fields (depends on year of survey)
	replace spend_federal = 0 if mi(spend_federal)
	
	replace spend_nonfederal = spend_total - spend_federal ///
		if mi(spend_nonfederal) & !mi(spend_total)
	replace spend_nonfederal = 0 if mi(spend_nonfederal) & mi(spend_total)
		
	replace spend_total = spend_federal + spend_nonfederal ///
		if mi(spend_total) & !mi(spend_nonfederal)
		
	assert spend_total == (spend_federal + spend_nonfederal)
		
	* Label variables 
	foreach var in federal nonfederal total {
		label var spend_`var' "`var' spending"
	}
	
	isid fice year field expenditure 
	sort name year field expenditure 
	
	order year fice ipeds_id ncses_id state city zip name field expenditure spend_*
	
	save "$derived/herd_survey_clean", replace
end

program merge_herd_iris

	import delimited "$iris/university_membership_data_with_fice.csv", clear
	
		drop status 
		destring endyear, force replace 
		replace endyear = 2024 if mi(endyear)
		
	save "$derived/iris_members_fice.dta", replace
	
	* Merge to HERD 
	use "$derived/herd_survey_clean", clear 
	
	merge m:1 fice using "$derived/iris_members_fice.dta", ///
		assert(master matched) nogen keepusing(endyear) 
		
		ren endyear iris_lastyear 
		gen iris_flag = !mi(iris_lastyear)
		
	save "$derived/herd_survey_clean", replace 

end 

main 

