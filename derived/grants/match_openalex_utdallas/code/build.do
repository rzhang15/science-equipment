set more off
clear all
capture log close
program drop _all
set scheme modern
version 18
global dropbox_dir "~/dropbox (harvard university)/scientific equipment"

* Ruby's macros 
global dropbox_dir "$sci_equip"
cd "$github/science-equipment/derived/match_openalex_utdallas/code"

global raw "${dropbox_dir}/raw"
global derived_output "${dropbox_dir}/derived_output"

program main 

	merge_openalex_authors
	merge_utdallas_pi
	merge_utdallas_grant

end 

program merge_openalex_authors

	use "$derived_output/pull_openalex/openalex_all_jrnls_merged.dta", clear
	
		* Only keep last author (ie the PI who provides the funding)
		ren n year
		keep if dallas_pi == 1 
		keep if year >= 2010
		
		keep athr_name id cite_count year
		duplicates drop 
				
		isid id
	
	* Merge in grant data 
	merge 1:m id using "$derived_output/pull_openalex/grants_all_jrnls_merged.dta", keep(master matched)
	
	* Clean pi name
	gen last = word(athr_name, -1) // Extract last word (assumes it's the last name)
	gen first_middle = subinstr(athr_name, last, "", .) // Remove last name
	replace first_middle = trim(first_middle) // Trim any extra spaces
	gen pi = last + ", " + first_middle // Concatenate in desired format
	replace pi = lower(subinstr(pi, ".", "", .))
	replace pi = subinstr(pi, "‐", "-", .)
	replace pi = subinstr(pi, "í", "i", .)
	replace pi = subinstr(pi, "ó", "o", .)
	replace pi = subinstr(pi, "é", "e", .)
	replace pi = subinstr(pi, "á", "a", .)
	replace pi = subinstr(pi, uchar(8217), "'", .)
	replace pi = substr(pi, 1, strlen(pi) - 2) if substr(pi, -2, 1) == " "
	replace pi = substr(pi, 1, strlen(pi) - 2) if substr(pi, -2, 1) == " "
	replace pi = subinstr(pi, "Рачинский, Дмитрий", "rachinsky, dmitry", .)
	replace pi = subinstr(pi, ", larry", ", lawrence", .)
	* exception for certain PIs
	replace pi = "nisco, nicole" if strpos(pi, "nisco, nicole") > 0
	replace pi = "zhang, li" if pi == "li, zhang"
	
	* Clean grants data
	gen str80 grantid = award_id
	drop award_id 
	replace grantid = "" if grantid == "NA"
	replace grantid = subinstr(grantid, " ", "", .)
	replace grantid = subinstr(grantid, ".", "", .)
	replace grantid = subinstr(grantid, "#", "", .)
	replace grantid = regexr(grantid, "\(.*\)", "")
	
	* NIH grants
	replace grantid = subinstr(grantid, "RO1", "R01", .)
	replace grantid = subinstr(grantid, "RO3", "R03", .)
	replace grantid = subinstr(grantid, "RF1", "R01", 2)
	replace grantid = subinstr(grantid, "-", "", .) if strpos(grantid, "R37") > 0
	replace grantid = subinstr(grantid, "-", "", .) if strpos(grantid, "R00") > 0
	replace grantid = substr(grantid, strpos(grantid, "R01"), 11) if strpos(grantid, "R01") > 0
	replace grantid = substr(grantid, strpos(grantid, "R21"), 11) if strpos(grantid, "R21") > 0
	replace grantid = substr(grantid, strpos(grantid, "R35"), 11) if strpos(grantid, "R35") > 0
	replace grantid = substr(grantid, strpos(grantid, "R03"), 11) if strpos(grantid, "R03") > 0
	replace grantid = substr(grantid, strpos(grantid, "R15"), 11) if strpos(grantid, "R15") > 0
	replace grantid = substr(grantid, strpos(grantid, "R37"), 11) if strpos(grantid, "R37") > 0
	replace grantid = substr(grantid, strpos(grantid, "R00"), 11) if strpos(grantid, "R00") > 0
	replace grantid = substr(grantid, strpos(grantid, "U54"), 11) if strpos(grantid, "U54") > 0
	
	* NSF grants 
	replace grantid = subinstr(grantid, "DMR-", "", 1)
	replace grantid = subinstr(grantid, "CHE-", "", 1)
	replace grantid = subinstr(grantid, "CMMI-", "", 1)
	replace grantid = subinstr(grantid, "DMS-", "", 1)
	replace grantid = subinstr(grantid, "IIP-", "", 1)
	
	replace grantid = ustrtrim(grantid)

	* Only keep relevant variables
	sort pi year funder_name grantid id
	order pi year funder_name grantid id 
	keep pi year funder_name grantid id 

	save "../temp/openalex_author_grant.dta", replace

end

program merge_utdallas_pi

	use "$derived_output/ut_dallas_grants/ut_dallas_projectid_to_pi_xwalk.dta", replace
		
		* Keep only UT dallas professors 
		gen dallas_flag = (school == "university of texas dallas")
		bys pi: egen dallas_pi = max(dallas_flag)
		replace school = "university of texas dallas" if dallas_pi == 1
		
		drop if mi(pi)
		collapse (firstnm) school , by(pi grantid)
		
		gen num_grant_dallas = 1 
		collapse (sum) num_grant (firstnm) school, by(pi)
		
		merge 1:m pi using "../temp/openalex_author_grant.dta" 
		
		egen num_paper_oa = group(id)
		egen num_grant_oa = group(grantid)
		
		replace num_paper_oa = . if id == ""
		replace num_grant_oa = . if grantid == ""
		
		gcollapse (mean) num_grant_dallas _merge (min) min_year_oa = year ///
				(max) max_year_oa = year ///
				(nunique) num_grant_oa num_paper_oa, by(pi school)
		
		replace num_grant_oa = . if mi(min_year) 
		replace num_paper_oa = . if mi(min_year) 
		
		keep if school == "university of texas dallas" | mi(school)
		
		tab _merge 
		
		sort _merge pi
		gen source = "matched" if _merge == 3 
		replace source = "openalex only" if _merge == 2 
		replace source = "foia only" if _merge == 1
		drop _merge 
		
		order pi num_grant* num_paper* *year*
		pwcorr num_grant* num_paper*
		
		isid pi 
		
		save "../temp/match_pi_foia_openalex_utdallas.dta", replace
end 

program merge_utdallas_grant

	use "$derived_output/ut_dallas_grants/ut_dallas_projectid_to_pi_xwalk.dta", clear 

		keep grantid agency pi
		duplicates drop 
		isid grantid 
		
	* Merge in the PIs that are matched 
	merge m:1 pi using "../output/match_pi_foia_openalex_utdallas.dta", nogen keepusing(pi school source)
		ren pi pi_foia
		drop if source == "openalex only"
		
	* Merge in Open Alex data
	merge 1:m grantid using "../temp/openalex_author_grant.dta"
		
		ren pi pi_oa 
		ren funder_name agency_oa 
		
		encode id, gen(paper_id)
		bys grantid pi_oa: gegen num_papers_grant_pi_oa = nunique(paper_id)
		
		drop year id paper_id
		duplicates drop 
		drop if mi(grantid)
		
		sort grantid 
		gen investigate = 1 if mi(pi_foia) & _merge == 3
		
	gsort -investigate -_merge grantid
	
	gen source_grant = "matched" if _merge == 3 
	replace source_grant = "openalex only" if _merge == 2 
	replace source_grant = "foia only" if _merge == 1
	drop _merge 
	
	save "../output/match_grants_foia_openalex_utdallas.dta", replace
	
	* Run some stats 
	keep if source == "matched" & (source_grant == "matched" | source_grant == "foia only")
	
		bys source_grant: distinct grantid 
	
end 

main 
