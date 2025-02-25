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


program main   
	share_spend_acct
	share_spend_pi
	plot_spend_acct
	plot_pi_stats
	plot_agency_stats
end

program clean_merge_data

	import excel using "$raw/FOIA/utdallas_2011_2024.xlsx", firstrow case(lower) clear
	
		merge m:1 projectid using "${derived_output}/ut_dallas_grants/ut_dallas_projectid_to_pi_xwalk.dta", nogen assert(matched)
	
		gen spend = quantity * unitprice 
		drop extendedprice 
		
		gen year = year(purchasedate)
		
		gen matched_pi = !mi(pi)
		
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
	
	foreach var in cprit nih nsf {
		gen mean_p`var' = 100 * spend`var' / (spendcprit + spendnih + spendnsf)
		gen median_p`var' = mean_p`var'
		gen sd_p`var' = mean_p`var'
	}
	
	gen num_pi = 1
	gcollapse (median) median_* (mean) mean_* (sd) sd_* ///
		(sum) num_pi num_grants* spend*, by(year)
	
	foreach var in cprit nih nsf {
		gen total_perc_`var' = 100 * spend`var' / (spendcprit + spendnih + spendnsf)
	}
	
	save "../temp/agency_stats_by_year.dta", replace
		
end 

program plot_spend_acct
	
	use "../temp/pi_match_perc_by_year.dta", clear 
	
	drop if year > 2019
	
	tw ///
		(connected perc_matched year) ///
		, ///
		xtitle("Year", size(small)) ///
		ytitle("Percent of Total Spend Matched to a PI", size(small)) ///
		xlabel(2011(1)2019, nogrid) ylabel(30(10)100, nogrid)
			
		graph export "../output/perc_spend_matched_by_year.png",replace
	
end 

program plot_pi_stats

	use "../temp/agency_stats_by_year.dta", clear 
	
	drop if year > 2019
	
	tw ///
		(connected num_pi year) ///
		, ///
		xtitle("Year", size(small)) ///
		ytitle("Number of PIs", size(small)) ///
		xlabel(2011(1)2019, nogrid) ylabel(, nogrid)
			
		graph export "../output/num_pi_by_year.png",replace
	
	tw ///
		(connected median_pnih year) ///
		, ///
		xtitle("Year", size(small)) ///
		ytitle("Percentage of Spend from NIH for Median PI", size(small)) ///
		xlabel(2011(1)2019, nogrid) ylabel(50(10)100, nogrid)
			
		graph export "../output/nih_perc_median_pi_by_year.png",replace
		
	tw ///
		(connected mean_pnih year) ///
		(connected mean_pnsf year) ///
		(connected mean_pcprit year) ///
		, ///
		xtitle("Year", size(small)) ///
		ytitle("Percentage of Spend from Agencies for Mean PI", size(small)) ///
		legend(order(1 "NIH" 2 "NSF" 3 "CPRIT") pos(11) ring(0) col(1)) ///
		xlabel(2011(1)2019, nogrid) ylabel(0(20)80, nogrid)
			
		graph export "../output/agency_perc_mean_pi_by_year.png",replace
		
end 

program plot_agency_stats
	use "../temp/agency_stats_by_year.dta", clear 
	
	drop if year > 2019
	
	* Total agency spend
	gen spendnihnsf = spendnih + spendnsf
	gen spendtotal = spendnih + spendnsf + spendcprit
	
	tw ///
		(area spendnih year) ///
		(rarea spendnih spendnihnsf year) ///
		(rarea spendnihnsf spendtotal year) ///
		, ///
		xtitle("Year", size(small)) ///
		ytitle("Total Spend from Agencies", size(small)) ///
		legend(order(1 "NIH" 2 "NSF" 3 "CPRIT") pos(11) ring(0) col(1)) ///
		xlabel(2011(1)2019, nogrid) ylabel(, nogrid)

		graph export "../output/spend_by_agency_by_year.png",replace
		
	gen total_perc_nihnsf = total_perc_nih + total_perc_nsf 
	gen total_perc = total_perc_nih + total_perc_nsf + total_perc_cprit
	
	tw ///
		(area total_perc_nih year) ///
		(rarea total_perc_nih total_perc_nihnsf year) ///
		(rarea total_perc_nihnsf total_perc year) ///
		, ///
		xtitle("Year", size(small)) ///
		ytitle("Total Percent Spend from Agencies", size(small)) ///
		legend(order(1 "NIH" 2 "NSF" 3 "CPRIT") pos(11) ring(0) col(1)) ///
		xlabel(2011(1)2019, nogrid) ylabel(, nogrid)

		graph export "../output/perc_spend_by_agency_by_year.png",replace
		
	* Total grants by agency
	tw ///
		(connected num_grantsnih year) ///
		(connected num_grantsnsf year) ///
		(connected num_grantscprit year) ///
		, ///
		xtitle("Year", size(small)) ///
		ytitle("Total Number of Grants by Agency", size(small)) ///
		legend(order(1 "NIH" 2 "NSF" 3 "CPRIT") pos(11) ring(0) col(1)) ///
		xlabel(2011(1)2019, nogrid) ylabel(, nogrid)
			
		graph export "../output/num_grants_by_agency_by_year.png",replace
		
	
end 

main 
