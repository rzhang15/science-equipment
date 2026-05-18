set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main   
    use ../external/samp/merged_foias_with_pis,  clear
    keep if inlist(uni , "utdallas", "umich")
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
end

main
