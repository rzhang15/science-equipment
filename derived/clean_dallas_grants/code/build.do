set more off
clear all
capture log close
program drop _all
set scheme modern
version 18
global dropbox_dir "~/dropbox (harvard university)/scientific equipment"

* Ruby's macros 
global dropbox_dir "$sci_equip"
cd "$github/science-equipment/derived/clean_dallas_grants/code"

global derived_output "${dropbox_dir}/derived_output_sci_eq"

program main   

// 	grants_xwalk 
	grants_merge_nih
	grants_merge_nsf
	grants_merge_cprit 
	create_xwalk
	
end

program grants_xwalk
	import excel using "../external/foia/utdallas_2011_2024.xlsx", firstrow case(lower) clear
	local varlist purchaseorderidentifier projectid referenceawardid fain
	forvalues i=1/4 {
		local var = word("`varlist'", `i')
		di "`var'"
		count if mi(`var')
		distinct `var'
		* Check that purchaseorderidentifier < projectid < referenceawardid < fain 
		if "`var'" != "fain" {
			local j = `i' + 1
			local var_next = word("`varlist'", `j')
			preserve 
				keep `var' `var_next' 
				duplicates drop 
				drop if mi(`var')
				bys `var': gen num = _N 
				assert num == 1
			restore 
		}
	}
	gen spend = unitprice * quantity
	collapse (sum) spend, by(projectid referenceawardid fain)
		isid projectid
	* Generate grant ID which we will use to match onto federal data 
	gen grantid = fain 
	replace grantid = referenceawardid if mi(grantid)
	replace grantid = ("PROJ-" + projectid) if mi(grantid) 
	sort grantid
	
	order projectid spend referenceawardid fain grantid 
	export excel using "${derived_output}/ut_dallas_grants/ut_dallas_proj_grants_xwalk_raw.xlsx", firstrow(variables) replace
	
end

program grants_merge_nih

	* Load NIH reporter data and drop subproject cost data
	import excel "${derived_output}/ut_dallas_grants/ut_dallas_nih_grants.xlsx", firstrow clear
    ren (ContactPIProjectLeader ProjectNumber OrganizationName) (pi full_grantid school)
	ren (BudgetStartDate BudgetEndDate FiscalYear) (budget_start budget_end year)
	ren (TotalCost DirectCostIC IndirectCostIC) (total_cost direct_cost indirect_cost)
    gen grantid = substr(full_grantid, 2, 11)
	drop if mi(pi) | mi(grantid) | mi(school) | mi(total_cost) 
	replace pi = subinstr(pi,".","",.)
	replace indirect_cost = 0 if mi(indirect_cost)
	replace total_cost = direct_cost + indirect_cost
    keep pi *grantid school year *_start *_end *_cost* 
    duplicates drop 
	
	* Make everything lower case 
	replace pi = lower(pi)
	replace pi = substr(pi, 1, strlen(pi) - 2) if substr(pi, -2, 1) == " "
	replace pi = substr(pi, 1, strlen(pi) - 2) if substr(pi, -2, 1) == " "
	
	* Keep if school is UT Dallas 
	replace school = lower(school)
	
	* Save at grant PI level 
	isid full_grantid 
	collapse (sum) *_cost (firstnm) school, by(grantid pi)
	isid grantid 
	
    save ../temp/nih_grants, replace
	
end 

program grants_merge_nsf 

	import excel "${derived_output}/ut_dallas_grants/ut_dallas_nsf_grants.xlsx", firstrow clear
	ren (PrincipalInvestigator AwardNumber Organization AwardedAmountToDate) (pi grantid school total_award_amt)
	ren (StartDate LastAmendmentDate EndDate) (start_date amendment_date end_date) 
	
	foreach var in start amendment end {
		replace `var'_date = ustrtrim(`var'_date)
		gen `var'_year = substr(`var'_date, -4, 4)
		destring `var'_year, replace
	}
	
	replace total_award_amt = subinstr(total_award_amt, "$", "", .)
	replace total_award_amt = subinstr(total_award_amt, ",", "", .)
	destring total_award_amt, replace

	keep pi grantid school *date *year *award_amt 
	destring total_award_amt, replace 
	duplicates drop 
	
	replace pi = lower(pi)
	replace school = lower(school)
	replace school = subinstr(school," at "," ",.)
	
	gen lastname = substr(pi, strpos(pi, " ") + 1, .)
	gen firstname = substr(pi, 1, strpos(pi, " ") - 1)
	replace pi = lastname + ", " + firstname
	drop lastname firstname
	
	bys grantid: gen num_pi = _N
	isid grantid
	save ../temp/nsf_grants, replace
end 

program grants_merge_cprit

	import excel "${derived_output}/ut_dallas_grants/ut_dallas_cprit_grants.xlsx", firstrow clear
	ren (PrimaryInvestigatorProgramDir GrantID Organization) (pi grantid school)
	keep pi grantid school 
	duplicates drop 
	
	replace pi = lower(pi)
	replace school = lower(school)
	replace school = subinstr(school," at "," ",.)
	replace school = subinstr(school,"the ","",1)
	
	bys grantid: gen num_pi = _N
	isid grantid
	save ../temp/cprit_grants, replace
	
end

program create_xwalk 

	* Import our main file
	import excel "${derived_output}/ut_dallas_grants/ut_dallas_proj_grants_xwalk_clean.xlsx", clear firstrow
	    
	replace grantid = fain if !mi(fain)
    replace grantid = substr(grantid, 1, strpos(grantid, "-") - 1) if strpos(grantid, "-") > 0 & agency == "nih"
    replace grantid = subinstr(grantid," ","",.) if agency == "nih"
    replace grantid = substr(grantid, 2, 11) if strlen(grantid) > 11 & agency == "nih"
	
	replace grantid = substr(grantid, -7, .) if agency == "nsf"
	
	* Merge in agency data 
    merge m:1 grantid using ../temp/nih_grants, nogen keep(master matched)
	merge m:1 grantid using ../temp/nsf_grants, update nogen keep(1 3 4)
	merge m:1 grantid using ../temp/cprit_grants, update nogen keep(1 3 4)
	
	replace pi = subinstr(pi,"Ó","o",.)
	replace pi = subinstr(pi,"alonso faruck","faruck",.)
	replace pi = "black, bryan" if strpos(pi, "black, bryan") > 0
	replace pi = "palmer, kelli" if strpos(pi, "palmer, kelli") > 0
	replace pi = "draper, rockford" if strpos(pi, "draper, rockford") > 0
	replace pi = "winkler, duane" if strpos(pi, "winkler, duane") > 0
	replace pi = "nisco, nicole" if strpos(pi, "nisco, nicole") > 0
	replace pi = ustrtrim(pi)
	label var num_pi "Number of PIs associated with this grant"
	
	drop spend referenceawardid fain 
	
	isid projectid 
	save "${derived_output}/ut_dallas_grants/ut_dallas_projectid_to_pi_xwalk.dta", replace
end 

main 
