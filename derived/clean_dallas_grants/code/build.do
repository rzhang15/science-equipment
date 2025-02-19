set more off
clear all
capture log close
program drop _all
set scheme modern
version 18
//global dropbox_dir "~/dropbox (harvard university)/scientific equipment"
//global derived_output "${dropbox_dir}/derived_output/"
global dropbox_dir "$sci_equip"

program main   
    //grants_xwalk 
	grants_merge_nih
end

program grants_xwalk

	import excel using "$sci_equip/raw/FOIA/utdallas_2011_2024.xlsx", firstrow case(lower) clear
	
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
	
	export excel using "$sci_equip/derived_output/ut_dallas_grants/ut_dallas_proj_grants_xwalk_raw.xlsx", firstrow(variables) replace
	
end

program grants_merge_nih
		
	import excel "$sci_equip/derived_output/ut_dallas_grants/ut_dallas_nih_grants.xlsx", firstrow clear

		ren (ContactPIProjectLeader ProjectNumber) (pi grantid)
		
		gen fain = substr(grantid, 2, 11)
		
		keep fain pi
		duplicates drop 
		
		tempfile nih_grants 
		save "`nih_grants'", replace
		
	* Import our main file
	import excel "$sci_equip/derived_output/ut_dallas_grants/ut_dallas_proj_grants_xwalk_clean.xlsx", clear firstrow
	
		keep if agency == "nih"
		
		replace fain = grantid if mi(fain) 
		replace fain = substr(fain, 1, strpos(fain, "-") - 1) if strpos(fain, "-") > 0
		replace fain = subinstr(fain," ","",.) 
		replace fain = substr(fain, 2, 11) if strlen(fain) > 11
		
		keep fain
		duplicates drop 
		
		merge 1:m fain using "`nih_grants'", nogen assert(matched)
		
		sort fain

end 

main 
