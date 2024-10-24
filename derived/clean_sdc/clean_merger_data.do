clear all

* Data 
global derived "$sci_equip/derived"
global sdc "$sci_equip/SDC Platinum"

* Code
program main 

	subset_merger_data_thermo
	subset_merger_data_sigma
	//subset_merger_data_sic

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

	// keep SIC starting with 38, 28, 50, 51 
	tab TSICP, sort
	
	* Generate first two digits of the SIC codes 
	gen short_TSIC = substr(TSICP,1,2)
	
	tab short_TSIC, sort
	
	local short_SIC_list 38 28 35 87 36 49 73 37 50 15 32 80 30 34 42 51 62 67 75
	
	* Test avantor (formerly Mallinckrodt), VWR international
	
	* Test Sigma Chemical, Aldrich Chemical, Millipore Corporation, Sigma-Aldrich, MilliporeSigma (2015), (Merck?)

	
end 

main 
