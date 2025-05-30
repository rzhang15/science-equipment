set more off
clear all
capture log close
program drop _all
set scheme modern
version 18
global dropbox_dir "~/dropbox (harvard university)/scientific equipment"

* Ruby's macros 
global dropbox_dir "$sci_equip"
cd "$github/science-equipment/analysis/pi_descs/code"

global raw "${dropbox_dir}/raw"
global derived_output "${dropbox_dir}/derived_output"
global oa_match "$github/science-equipment/derived/match_openalex_utdallas/output"

program main   
	share_spend_acct
	share_spend_pi
	plot_spend_acct
	plot_pi_stats
	plot_agency_stats
end

program merge_pi_grant 

	use "$oa_match/match_grants_foia_openalex_utdallas.dta", clear 
	
		keep if investigate == 1
		replace agency = lower(agency_oa) if mi(agency) 
		keep grantid agency pi_oa num_paper*
		duplicates drop
		
		gsort grantid -num_papers_grant_pi_oa
		by grantid: gen num = _n
		by grantid: gen num_pi = _N
		keep if num == 1 
		drop num_papers* num
		
		ren pi_oa pi
		isid grantid 
		
	merge 1:m grantid using "${derived_output}/ut_dallas_grants/ut_dallas_projectid_to_pi_xwalk.dta", update nogen 
	
	* Hand fill in some of the missing funding 
	replace pi = "sherry, dean" if grantid == "AT-0584"
	replace pi = "balkus, kenneth" if strpos(grantid, "AT-1153") == 1
	replace pi = "stefan, mihaela" if strpos(grantid, "AT-1740") > 0
	replace pi = "xia, tianbing" if strpos(grantid, "AT-1645") == 1
	replace pi = "smaldone, ronald" if strpos(grantid, "61360-ND10") > 0
	replace pi = "smaldone, ronald" if strpos(grantid, "52906-DNI10") > 0
	replace pi = "smaldone, ronald" if strpos(grantid, "W911SR24C0005") > 0
	replace pi = "delk, nikki" if strpos(grantid, "RSG-20-138-01") > 0
	replace pi = "kim, tae hoon" if strpos(grantid, "W81XWH1810439") > 0
	
	replace agency = "welch" if agency == "welch foundation"
	
	save "${derived_output}/ut_dallas_grants/final_projectid_to_pi_xwalk.dta", replace 

end 

program clean_merge_data

	merge_pi_grant

	import excel using "$raw/FOIA/utdallas_2011_2024.xlsx", firstrow case(lower) clear
	
		merge m:1 projectid using "${derived_output}/ut_dallas_grants/final_projectid_to_pi_xwalk.dta", nogen assert(matched)
	
		gen spend = quantity * unitprice 
		drop extendedprice 
		
		gen year = year(purchasedate)
		
		gen matched_pi = !mi(pi)
		
		replace agency = "other" if !inlist(agency, "nih", "nsf", "welch", "cprit")
	
end 

program share_spend_acct

	clean_merge_data
	
	gcollapse (sum) spend, by(year matched_pi)
	
	reshape wide spend, i(year) j(matched_pi)
	gen perc_matched = 100 * spend1 / (spend1 + spend0)
	
	save "../temp/pi_match_perc_by_year.dta", replace

end

program share_spend_pi

	clean_merge_data
	
	keep if matched_pi == 1 
	
	gcollapse (sum) spend, by(year pi agency grantid)
	gen num_grants = 1 
	
	gcollapse (sum) spend num_grants, by(year pi agency)
		
	save "../temp/pi_agency_spend_by_year.dta", replace

	reshape wide spend num_grants, i(year pi) j(agency) string
		
	foreach var of varlist spend* {
		replace `var' = 0 if mi(`var')
	}
	
	egen spend_total = rowtotal(spend*)
	
	foreach var in cprit nih nsf welch other {
		gen mean_p`var' = 100 * spend`var' / spend_total
		gen median_p`var' = mean_p`var'
		gen sd_p`var' = mean_p`var'
	}
	
	gen num_pi = 1
	gcollapse (median) median_* (mean) mean_* (sd) sd_* ///
		(sum) num_pi num_grants* spend*, by(year)
	
	foreach var in cprit nih nsf welch other {
		gen total_perc_`var' = 100 * spend`var' / spend_total
	}
	
	save "../temp/agency_stats_by_year.dta", replace
		
end 

program plot_spend_acct
	
	use "../temp/pi_match_perc_by_year.dta", clear 
	
	drop if year > 2019
	
	tw ///
		(connected perc_matched year, color(lavender)) ///
		, ///
		xtitle("Year", size(small)) ///
		ytitle("Percent of Total Spend Matched to a PI", size(small)) ///
		xlabel(2011(1)2019, nogrid) ylabel(50(10)100, nogrid)
			
		graph export "../output/perc_spend_matched_by_year.png",replace
	
end 

program plot_pi_stats

	use "../temp/agency_stats_by_year.dta", clear 
	
	drop if year > 2019
	
	tw ///
		(connected num_pi year, color(lavender)) ///
		, ///
		xtitle("Year", size(small)) ///
		ytitle("Number of PIs", size(small)) ///
		xlabel(2011(1)2019, nogrid) ylabel(, nogrid)
			
		graph export "../output/num_pi_by_year.png",replace
	
	tw ///
		(connected mean_pnih year, color(lavender)) ///
		(connected mean_pnsf year, color(dkorange)) ///
		(connected mean_pwelch year, color(ebblue)) ///
		(connected mean_pcprit year, color(emerald)) ///
		(connected mean_pother year, color(cranberry)) ///
		, ///
		xtitle("Year", size(small)) ///
		ytitle("Percentage of Spend from Agencies for Mean PI", size(small)) ///
		legend(order(1 "NIH" 2 "NSF" 3 "Welch" 4 "CPRIT" 5 "Other") pos(11) ring(0) col(1)) ///
		xlabel(2011(1)2019, nogrid) ylabel(0(20)80, nogrid)
			
		graph export "../output/agency_perc_mean_pi_by_year.png",replace
		
end 

program plot_agency_stats
	use "../temp/agency_stats_by_year.dta", clear 
	
	drop if year > 2019
	
	* Total agency spend
	gen spendnihnsf = spendnih + spendnsf
	gen spendnihnsfwelch = spendnih + spendnsf + spendwelch
	gen spendallagency = spendnih + spendnsf + spendwelch + spendcprit
	gen spendtotal = spendnih + spendnsf + spendwelch + spendcprit + spendother
	
	tw ///
		(area spendnih year, color(lavender)) ///
		(rarea spendnih spendnihnsf year, color(dkorange)) ///
		(rarea spendnihnsf spendnihnsfwelch year, color(ebblue)) ///
		(rarea spendnihnsfwelch spendallagency year, color(emerald)) ///
		(rarea spendallagency spendtotal year, color(cranberry)) ///
		, ///
		xtitle("Year", size(small)) ///
		ytitle("Total Spend from Agencies", size(small)) ///
		legend(order(1 "NIH" 2 "NSF" 3 "Welch" 4 "CPRIT" 5 "Other") pos(11) ring(0) col(1)) ///
		xlabel(2011(1)2019, nogrid) ylabel(, nogrid)

		graph export "../output/spend_by_agency_by_year.png",replace
		
	gen total_perc_nihnsf = total_perc_nih + total_perc_nsf 
	gen total_perc_nihnsfwelch = total_perc_nih + total_perc_nsf + total_perc_welch
	gen total_perc_allagency = total_perc_nih + total_perc_nsf + total_perc_welch + total_perc_cprit
	gen total_perc = total_perc_nih + total_perc_nsf + total_perc_welch + total_perc_cprit + total_perc_other
	
	tw ///
		(area total_perc_nih year, color(lavender)) ///
		(rarea total_perc_nih total_perc_nihnsf year, color(dkorange)) ///
		(rarea total_perc_nihnsf total_perc_nihnsfwelch year, color(ebblue)) ///
		(rarea total_perc_nihnsfwelch total_perc_allagency year, color(emerald)) ///
		(rarea total_perc_allagency total_perc year, color(cranberry)) ///
		, ///
		xtitle("Year", size(small)) ///
		ytitle("Total Percent Spend from Agencies", size(small)) ///
		legend(order(1 "NIH" 2 "NSF" 3 "Welch" 4 "CPRIT" 5 "Other") ///
			pos(5) ring(0) col(1) size(vsmall)) ///
		xlabel(2011(1)2019, nogrid) ylabel(, nogrid)

		graph export "../output/perc_spend_by_agency_by_year.png",replace
		
	* Total grants by agency
	tw ///
		(connected num_grantsnih year, color(lavender)) ///
		(connected num_grantsnsf year, color(dkorange)) ///
		(connected num_grantswelch year, color(ebblue)) ///
		(connected num_grantscprit year, color(emerald)) ///
		(connected num_grantsother year, color(cranberry)) ///
		, ///
		xtitle("Year", size(small)) ///
		ytitle("Total Number of Grants by Agency", size(small)) ///
		legend(order(1 "NIH" 2 "NSF" 3 "Welch" 4 "CPRIT" 5 "Other") pos(11) ring(0) col(1)) ///
		xlabel(2011(1)2019, nogrid) ylabel(, nogrid)
			
		graph export "../output/num_grants_by_agency_by_year.png",replace
		
end 

main 
