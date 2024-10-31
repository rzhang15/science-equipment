clear all

* Data 
global derived "$sci_equip/derived_output"
global sdc "$sci_equip/raw/SDC Platinum"

* Code
program main 

// 	subset_merger_data_thermo
// 	subset_merger_data_sigma
	subset_merger_data_sic

end 

program subset_merger_data_thermo

	use "$sdc/SDC platinum all mergers since 1965", clear
	
	* Look at target SICs of Thermo Fisher (formerly Thermo Electron)
	keep if (strpos(AMANAMES, "Thermo Electron") > 0 | strpos(AMANAMES, "Thermo Fisher") > 0 | strpos(AMANAMES, "Fisher Scientific") > 0)
	
	sort DATEANN
	drop if TMANAMES == AMANAMES
	
	save "$derived/sdc_mergers_thermo_fisher_1965.dta", replace

end 

program subset_merger_data_sigma

	use "$sdc/SDC platinum all mergers since 1965", clear
	
	* Look at target SICs of Merck's MilliporeSigma (ie Sigma-Aldrich)
	keep if (strpos(AMANAMES, "Sigma Chemical") > 0 | strpos(AMANAMES, "Aldrich Chemical") > 0 | strpos(AMANAMES, "Sigma-Aldrich") > 0 | strpos(AMANAMES, "Merck") > 0 | strpos(AMANAMES, "Millipore") > 0)
	
	sort DATEANN
	drop if TMANAMES == AMANAMES
	
	save "$derived/sdc_mergers_sigma_aldrich_1965.dta", replace

end 

program subset_merger_data_sic

	use "$sdc/SDC platinum all mergers since 1965", clear

	* Keep following SIC codes: 
	keep if inlist(TSICP, "3826", "3841", "3821", "3829", "3823", "2836", "2835", "2834", "8731")
	
	* Did not include but thee are chemical companies: 2899, 2869, 5169
	
	sort DATEANN
	drop if TMANAMES == AMANAMES
	
	save "$derived/sdc_mergers_subset_target_sic.dta", replace
	
end 

main 
