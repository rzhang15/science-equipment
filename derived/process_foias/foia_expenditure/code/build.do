set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main   
    boe
end

program expenditure_by_athr
    use ../external/samp/merged_foias_with_pis,  clear
    keep if inlist(uni , "utdallas", "umich")
    drop if mi(athr_id)
    gen year = year(date(date, "YMD"))
    merge m:1 category using ../external/categories/categories_tfidf, assert(1 2 3) keep(1 3) 
    gen nonlab = 1 if _merge == 1
    replace nonlab = 0 if mi(nonlab)
    drop if nonlab == 1
     sum spend, d
    gcollapse (sum) spend, by(athr_id uni year)
    merge m:1 athr_id using  ../external/real_exposure/athr_exposure, assert(1 2 3) keep(3) nogen
    gen post = year >= 2014
    gen Z_it = exposure*post
    replace spend = ln(spend)
    reghdfe spend Z_it , absorb(athr_id year) vce(cluster athr_id)
    binscatter2 spend Z_it , absorb(athr_id year)
    graph export ../output/bs_spend_by_exposure.pdf, replace
    xtset athr_id year
end


program boe
    use ../external/samp/merged_foias_with_pis,  clear
    keep if inlist(uni , "utdallas", "umich")
    drop if mi(athr_id)
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
    sum spend if keep == 1 & nonlab == 0 | bad_control == 1
    local spend_in_sample = r(sum)
    di "%lab spend classified as high quality= "  `spend_in_sample'/`lab_spend'*100
    replace keep = 2 if keep ==.
    gen nonlab_spend = spend if nonlab == 1 
    gen lab_spend = spend if nonlab == 0
    gen hq = keep == 1 | (bad_control == 1 & support >= 25 & precision >= 0.8 & recall >= 0.8)
    collapse (sum) spend nonlab_spend lab_spend , by(athr_id year hq)
    gen hq_labspend = lab_spend if hq == 1
    gen lq_labspend = lab_spend if hq == 0
    collapse (sum) tot_spend = spend nonlab_spend lab_spend hq_labspend lq_labspend  , by(athr_id year)
    gen perc_lab_spend = lab_spend/tot_spend* 100
    gen perc_nonlab_spend = nonlab_spend/tot_spend* 100
    collapse (mean) tot_spend nonlab_spend lab_spend hq_labspend lq_labspend perc_lab_spend perc_nonlab_spend, by(athr_id)
    graph bar lab_spend nonlab_spend, over(athr_id ,sort((mean) tot_spend) descending) stack bar(1, color(lavender%70)) bar(2, color(dkorange%70)) legend(on order(- "Lab Spend" - "Non-Lab Spend") pos(1) ring(0) size(small) region(fcolor(none))) ytitle("Average Annual Spend ($)") plotregion(margin(sides))
    graph export ../output/figures/avg_spend_by_athr.pdf, replace
    sum lab_spend if lab_spend >0, d
    local mean_lab_spend : di %6.2f r(mean)
    local sd_lab_spend : di %6.2f r(sd)
    local min_lab_spend : di %6.2f r(min)
    local max_lab_spend : di %10.2f r(max)
    local N_lab_spend : di %6.0f r(N)
    local q1_lab_spend : di %6.2f r(p25)
    local q3_lab_spend : di %6.2f r(p75)
    local median_lab_spend : di %6.2f r(p50)
   tw hist lab_spend if lab_spend >0, color(edkblue) frac width(5000) xlab(0(7500)150000, angle(45)) ///
       xtitle("Consumables Expenditure ($)") ytitle("Fraction of PI-Years") legend(on order(- "Mean = `mean_lab_spend'" "SD = `sd_lab_spend'" "Min = `min_lab_spend'" "Q1 = `q1_lab_spend'" "Median = `median_lab_spend'" "Q3 = `q3_lab_spend'" "Max = `max_lab_spend'") pos(1) ring(0) region(fcolor(none)) size(small))
   graph export ../output/figures/lab_spend.pdf, replace
   kdensity perc_lab_spend
   graph export ../output/figures/perc_lab_spend.pdf, replace
   kdensity perc_nonlab_spend
   graph export ../output/figures/perc_nonlab_spend.pdf, replace
   stop 
   gcollapse (mean) perc_lab_spend perc_nonlab_spend tot_spend nonlab_spend lab_spend (count) year, by(athr_id)
   binscatter perc_lab_spend lab_spend 
   graph export ../output/figures/bs_perc_lab_spend_by_lab_spend.pdf, replace
   binscatter perc_lab_spend tot_spend 
   graph export ../output/figures/bs_perc_lab_spend_by_tot_spend.pdf, replace
   binscatter perc_nonlab_spend nonlab_spend 
   graph export ../output/figures/bs_perc_nonlab_spend_by_lab_spend.pdf, replace
   binscatter lab_spend tot_spend 
   graph export ../output/figures/bs_lab_spend_by_tot_spend.pdf, replace
end

main

