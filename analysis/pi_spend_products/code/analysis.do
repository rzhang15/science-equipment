set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main   
    use ../external/samp/merged_foias_with_pis,  clear
    keep if uni == "utdallas"
    drop if mi(athr_id)
    drop predicted_market
    gen year = year(date(date, "YMD"))
    drop if year > 2013
    merge m:1 category using ../external/categories/categories_tfidf, keep(1 3) 
    rename _merge nonlab
    replace nonlab = 0 if nonlab == 3
    sum spend, d
    local total_spend = r(sum)
    sum spend if nonlab == 0
    local lab_spend = r(sum)
    di "% lab spend = " `lab_spend'/`total_spend'*100
    sum spend if keep == 1 & nonlab == 0
    local spend_in_sample = r(sum)
    di "%lab spend classified as high quality= "  `spend_in_sample'/`lab_spend'*100
    replace keep = 2 if keep ==.
    gen nonlab_spend = spend if keep == 2
    gen lab_spend = spend if keep == 1 | keep == 0
    collapse (sum) spend nonlab_spend lab_spend , by(athr_id year keep treated)
    gen treated_hq = spend if keep == 1 & treated == 1
    gen hq = spend if keep == 1
    gen lq = spend if keep == 0
    gen treated_lq = spend if keep == 0 & treated == 1
    collapse (sum) tot_spend = spend nonlab_spend lab_spend hq lq treated_hq treated_lq, by(athr_id year)
    gen perc_lab_spend = lab_spend/tot_spend* 100
    gen perc_nonlab_spend = nonlab_spend/tot_spend* 100
    gen perc_hq = hq/lab_spend* 100
    gen perc_treated_hq = treated_hq/hq* 100
    gen perc_treated_lq = treated_lq/lq* 100
    bys athr_id: egen tot_athr_spend =total(tot_spend)
    stop
    gcollapse (mean) tot_spend nonlab_spend lab_spend labspend_kept treated_spend perc_treated_kept perc_lab_spend perc_nonlab_spend perc_labspend_kept [aw=tot_athr_spend], by(year)
    tw line tot_spend year || line lab_spend year || line nonlab_spend year, legend(label(1 "Total Spend") label(2 "Lab Spend") label(3 "Non-Lab Spend")) ytitle("Average Spend") xtitle("Year") title("Average Spend by Year")
    graph export ../output/figures/avg_spend_by_year.pdf, replace
    graph hbar (mean) perc_lab_spend perc_nonlab_spend, over(year) stack ///
      legend(label(1 "Perc Lab Spend") label(2 "Perc Non-Lab Spend")) ///
      ytitle("Average Percentage of Spend") ///
      title("Average Percentage of Lab vs Non-Lab Spend by Year")
    graph export ../output/figures/perc_lab_nonlab_spend_by_year.pdf, replace
    tw line perc_labspend_kept year, legend(label(1 "Perc Lab Spend Kept")) ytitle("Average Percentage of Lab Spend Kept") xtitle("Year") title("Average Percentage of Lab Spend Kept by Year")
    graph export ../output/figures/perc_labspend_kept_by_year.pdf,replace 
end

main
