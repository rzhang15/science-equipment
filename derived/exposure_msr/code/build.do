set more off
clear all
capture log close
program drop _all
set scheme modern
pause on
set seed 8975
set maxvar 120000

program main
    foia_pis
    clean_foia_data
    gen_exposure
end

program foia_pis
    use ../external/foia/foia_athrs, clear
    merge 1:1 athr_id using ../external/ls_samp/list_of_athrs, assert(1 2 3) keep(3) nogen
    save ../output/foia_athrs, replace
end

program clean_foia_data
    use ../external/foia/merged_foias_with_pis, clear
    gen purchase_date = date(date, "YMD")
    gen year = year(purchase_date)
    keep if inrange(year, 2010, 2019)
    drop if mi(athr_id)
    qui count
    local total_obs = r(N)
    qui sum spend, d
    local total_spend : di %16.0f r(sum)
    di "[All purchases EVER] N:  `total_obs' Total Spend:  `total_spend'"
    qui {
        merge m:1 suppliername using ../external/sup/lifescience_supplier_map, assert(1 2 3) keep(3) nogen
        rename (suppliername new_suppliername) (old_suppliername suppliername)
    }
    drop if price <= 0 | qty <= 0 | spend <= 0
    save ../output/cleaned_merged_fois, replace
end

program gen_exposure
    use ../output/cleaned_merged_fois, clear
    replace spend = price * qty if mi(spend)
    drop if mi(spend)
    keep if year <= 2013
    gen lab_spend = spend if category != "Non-Lab" 
    replace lab_spend = 0 if mi(lab_spend)
    merge m:1 category using ../external/ml/categories_tfidf, assert(1 2 3)  keep(1 3) nogen
    gcollapse (sum) spend lab_spend (mean) keep, by(athr_id category year)
    gcollapse (mean) spend lab_spend keep, by(athr_id category)
    bys athr_id: egen tot_spend = total(spend)
    bys athr_id: egen tot_lab_spend = total(lab_spend)
    gen lab_spend_shr = tot_lab_spend / tot_spend
    keep if keep == 1
    drop tot_lab_spend
    bys athr_id: egen tot_lab_spend = total(lab_spend)
    gen mkt_spend_shr = spend / tot_lab_spend
    // align slash → hyphen so the two betas in did_coefs merge
    replace category = "acrylamide-bis solution" if category == "acrylamide/bis solution"
    replace category = "dmem-f-12" if category == "dmem/f-12"
    merge m:1 category using ../external/betas/did_coefs, assert(1 3) keep(1 3)
    rename _merge has_beta
    replace has_beta = 0 if has_beta == 1
    replace has_beta = 1 if has_beta == 3
    gen exposure = b*lab_spend_shr*mkt_spend_shr
   * gen exposure = b*mkt_spend_shr
    gen treated_spend = spend if treated == 1
    collapse (sum) exposure treated_spend (mean) lab_spend_shr tot_lab_spend tot_spend, by(athr_id)
    drop if treated_spend == 0
    drop if mi(exposure)
    save ../output/athr_exposure, replace
    preserve
    contract athr_id
    drop _freq
    save ../output/athr_exposure_list, replace
    restore
end


main
