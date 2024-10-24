clear all

* Data 
global derived "$sci_equip/derived"
global xwalk "$sci_equip/Crosswalks"

global figures "$sci_equip/../Output/Figures"
global tables "$sci_equip/../Output/Tables"

* Code
program main 

	plot_equip_share_rd_over_time
	plot_iris_share_rd_over_time 
	
end 

program create_balanced_panel

	use "$derived/herd_survey_clean", clear
	
	* Only look at life sciences 
	keep if field == "Life sciences"
	
	* See what the distribution looks like for schools which have all years 
	preserve 
	
		gcollapse (nunique) num_year = year (mean) iris_flag, by(fice)
		
			sum num_year, d 
			sum num_year if iris_flag == 1, d
	
	restore 
	
	* We only keep schools which have all years
	bys fice: gegen num_year = nunique(year) 
	
		qui sum num_year 
		keep if num_year == `r(max)'
	
	* Total equipment vs. non-equipment share 	
	keep year fice expenditure spend_total deflator_gdp iris_flag 
	isid year fice expenditure 
	
	* Reshape to calculate total equipment vs non-equipment 
	ren spend_total spend_ 
	replace expenditure = "Total" if expenditure == "Total R&D"
	
	reshape wide spend_, i(year fice) j(expenditure) string
	
	replace spend_Equipment = 0 if mi(spend_Equipment)
	replace spend_Total = 0 if mi(spend_Total)

	assert spend_Total >= spend_Equipment
	
end 

program plot_equip_share_rd_over_time

	create_balanced_panel

	* Collapse and get total over time by year 
	collapse (count) num_uni = fice (sum) spend_* (mean) deflator_gdp, by(year)
	
		sum num_uni
		assert `r(sd)' == 0
		local uni_balance = `r(mean)'
		
	* Deflate to 2019 dollars (and do millions of dollars) 
	local deflate_year = 2019 
	
		sum deflator_gdp if year == `deflate_year'
		local deflator = `r(mean)'
		
	replace spend_Total = (spend_Total / 1000) * (`deflator' / deflator_gdp)
	replace spend_Equipment = (spend_Equipment / 1000) * (`deflator' / deflator_gdp)
	
	* Plot total over time 
	twoway ///
		(area spend_Total year) ///
        (area spend_Equipment year) ///
       , ///
	   title(" ", size(small)) ///
       ylabel(, format(%9.0f)) xtitle("Year") ///
	   ytitle("Expenditure (Millions of Dollars)") ///
	   legend(order(1 "Total R&D" 2 "Capitalized Equipment R&D") ring(0) pos(11)) ///
	   note("This is a balanced panel with `uni_balance' institutions. All expenditures are deflated to `deflate_year' dollars using implicit price deflators for GDP from the BEA.", size(vsmall))
	   
	graph export "$figures/herd_equip_share_life_sci_over_time_balanced.png", replace 

end 

program plot_iris_share_rd_over_time

	create_balanced_panel 
	
		keep if iris_flag == 1 

	* Collapse and get total over time by year 
	collapse (count) num_uni = fice (sum) spend_* (mean) deflator_gdp, by(year)
	
		sum num_uni
		assert `r(sd)' == 0
		local uni_balance = `r(mean)'
		
	* Deflate to 2019 dollars (and do millions of dollars) 
	local deflate_year = 2019 
	
		sum deflator_gdp if year == `deflate_year'
		local deflator = `r(mean)'
		
	replace spend_Total = (spend_Total / 1000) * (`deflator' / deflator_gdp)
	replace spend_Equipment = (spend_Equipment / 1000) * (`deflator' / deflator_gdp)
	
	* Plot total over time 
	twoway ///
		(area spend_Total year) ///
        (area spend_Equipment year) ///
       , ///
	   title(" ", size(small)) ///
       ylabel(, format(%9.0f)) xtitle("Year") ///
	   ytitle("Expenditure (Millions of Dollars)") ///
	   legend(order(1 "Total R&D" 2 "Capitalized Equipment R&D") ring(0) pos(11)) ///
	   note("This is a balanced panel or IRIS members with `uni_balance' institutions. All expenditures are deflated to `deflate_year' dollars using implicit price deflators for GDP from the BEA.", size(vsmall))
	   
	  graph export "$figures/herd_equip_share_life_sci_over_time_balanced_iris.png", replace
	
end 

main 
