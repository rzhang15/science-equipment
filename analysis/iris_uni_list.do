clear all

* Data 
global derived "$sci_equip/derived_output/clean_herd"
global xwalk "$sci_equip/Crosswalks"

* Code
program main 

	iris_uni_highest_life_sci_rd
	
end 

program iris_uni_highest_life_sci_rd 

	use "$derived/herd_survey_clean", clear
	
	* Only look at life sciences 
	keep if field == "Life sciences" & year == 2022
	
	keep if expenditure == "Total R&D"
	
	isid fice
	
	* Only keep IRIS universities, order by state spending 
	keep if iris_flag == 1 
	
	bys state: egen state_spend = total(spend_total)
	
	gsort -state_spend -spend_total 
	
	* Save variables and save 
	keep fice public state city name spend_total state_spend 
	
	save "$derived/iris_uni_life_sci_2022_spend.dta", replace 

end 

main 
