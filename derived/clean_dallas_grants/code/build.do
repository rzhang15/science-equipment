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

global derived_output "${dropbox_dir}/derived_output"


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

	import excel "${derived_output}/ut_dallas_grants/ut_dallas_nih_grants.xlsx", firstrow clear
    ren (ContactPIProjectLeader ProjectNumber OrganizationName) (pi grantid school)
    replace grantid = substr(grantid, 2, 11)
    keep grantid pi school
	drop if mi(pi) | mi(grantid) | mi(school)
	replace pi = subinstr(pi,".","",.)
    duplicates drop 
	
	* Make everything lower case 
	replace pi = lower(pi)
	replace pi = substr(pi, 1, strlen(pi) - 2) if substr(pi, -2, 1) == " "
	replace pi = substr(pi, 1, strlen(pi) - 2) if substr(pi, -2, 1) == " "
	replace school = lower(school)
	
	* For PI x grant with multiple affiliations, keep UT Dallas if exists 
	gen school_utdallas = (school == "university of texas dallas")
	bys grantid pi: egen dallas_ind = max(school_utdallas)
    drop if dallas_ind == 1 & school_utdallas == 0
	
	* Take the first school 
	bys grantid pi (school): gen num = _n 
	keep if num == 1 
	drop num dallas_ind school_utdallas
	
	* Make note of multi-PI grants
	bys grantid: gen num_pi = _N
	
	* Take the first PI (only two multi-PI grants, and none of them are UT Dallas)
	bys grantid (pi school): gen num = _n 
	keep if num == 1 
	drop num 
	
	isid grantid
    save ../temp/nih_grants, replace
	
end 

program grants_merge_nsf 

	import excel "${derived_output}/ut_dallas_grants/ut_dallas_nsf_grants.xlsx", firstrow clear
	ren (PrincipalInvestigator AwardNumber Organization) (pi grantid school)
	keep pi grantid school 
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
    
	* Merge in data 
    merge m:1 grantid using ../temp/nih_grants, nogen assert(master matched)
	merge m:1 grantid using ../temp/nsf_grants, update nogen keep(1 3 4)
	merge m:1 grantid using ../temp/cprit_grants, update nogen keep(1 3 4)

	replace pi = subinstr(pi,"alonso faruck","faruck",.)
	replace pi = subinstr(pi,"Ó","o",.)
	replace pi = ustrtrim(pi)
	label var num_pi "Number of PIs associated with this grant"
	
	drop spend referenceawardid fain 
	
	isid projectid 
	save "${derived_output}/ut_dallas_grants/ut_dallas_projectid_to_pi_xwalk.dta", replace
end 

main 
