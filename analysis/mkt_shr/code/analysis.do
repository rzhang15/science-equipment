set more off

clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 18
set maxvar 120000, perm 
global dropbox_dir "~/dropbox (harvard university)/scientific equipment"

program main   
    foreach u in "all" { //"ut_dallas" "ut_austin" "oregon_state" {
        mkt_shr, uni(`u')
    }
end

program mkt_shr 
    syntax, uni(str)
    use ../external/samp/supplier_mkt_yr, clear
    keep if inrange(year, 2013, 2013) |inrange(year, 2016, 2016)
    bys supplier_id mkt year: egen tot_supplier_spend = total(raw_spend)
    bys mkt year: egen tot_mkt_spend = total(raw_spend)
    gen pre_merger = year <= 2013
    gen post_merger = year >= 2015
    bys mkt : egen has_pre_merger = max(pre_merger)
    bys mkt: egen has_post_merger = max(post_merger)
    bys mkt year: gen yr_cnt = _n ==1
    bys mkt: egen num_years = total(yr_cnt)

    gunique mkt 
    keep if has_pre_merger == 1 & has_post_merger == 1
    keep if num_years ==2
    gunique mkt 
    cap drop pre_merger_spend

    bys supplier_id mkt: egen pre_merger_spply_spend= total(raw_spend) if year <= 2013 
    bys mkt: egen pre_merger_spend= total(raw_spend) if year <= 2013 
    bys supplier_id mkt: egen post_merger_spply_spend= total(raw_spend) if year >= 2015 
    bys mkt: egen post_merger_spend= total(raw_spend) if year >= 2015 
    gen pre_merger_mkt_shr = pre_merger_spply_spend/pre_merger_spend  * 100
    gen post_merger_mkt_shr = post_merger_spply_spend/post_merger_spend  * 100
    hashsort supplier_id mkt year pre_merger_mkt_shr
    by supplier_id mkt: replace pre_merger_mkt_shr = pre_merger_mkt_shr[_n-1] if mi(pre_merger_mkt_shr) & pre_merger_mkt_shr[_n-1] != .
    by supplier_id mkt: replace post_merger_mkt_shr = post_merger_mkt_shr[_n-1] if mi(post_merger_mkt_shr) & post_merger_mkt_shr[_n-1] != .
    gen thermo_mkt_shr = pre_merger_mkt_shr if suppliername == "fisher"
    gen lt_mkt_shr = pre_merger_mkt_shr if suppliername == "life_tech"
    hashsort mkt thermo_mkt_shr
    by mkt: replace thermo_mkt_shr = thermo_mkt_shr[_n-1] if mi(thermo_mkt_shr) & thermo_mkt_shr[_n-1] != . 
    hashsort mkt lt_mkt_shr
    by mkt: replace lt_mkt_shr = lt_mkt_shr[_n-1] if mi(lt_mkt_shr) & lt_mkt_shr[_n-1] != . 
    gen sim_hhi = 2 * thermo_mkt_shr  * lt_mkt_shr
    drop if year == 2014
    bys suppliername pre_merger mkt: gen pre_id = _n == 1
    gen mkt_shr = pre_merger_mkt_shr if year<= 2013
    replace mkt_shr = post_merger_mkt_shr if mi(mkt_shr)
    bys mkt pre_merger: egen hhi = total(mkt_shr * mkt_shr * pre_id)
    contract prdct_ctgry mkt post_merger hhi sim_hhi
    save ../output/mkt_hhi_`uni', replace
    drop if mi(sim_hhi)
    bys mkt (post_merger): gen delta_hhi = hhi[_n+1] - hhi
    cap drop _freq
    contract prdct_ctgry mkt delta_hhi sim_hhi
    drop if mi(delta_hhi)
    drop if delta_hhi < -2000
    corr delta_hhi sim_hhi
    local corr: dis %4.3f r(rho)
    gen treated  = 1 if inlist(prdct_ctgry, "cell lysis reagent", "dna ladder" , "gel & nucleic acid staining" , "transfection reagent", "nucleic acid modifying enzyme", "reverse transcriptase", "restriction enzyme", "proteinase k", "us fb")
    replace treated  = 1 if inlist(prdct_ctgry, "liquid basal media, not chemically defined")
    replace treated = 1 if strpos(prdct_ctgry, "column based")
    replace treated = 1 if strpos(prdct_ctgry, "dye-based")
    replace treated = 1 if strpos(prdct_ctgry, "polymerase")
    replace treated = 1 if strpos(prdct_ctgry, "antibody")
    replace treated =0 if mi(treated)
    gen label = prdct_ctgry if treated == 1
*    gen label = prdct_ctgry if inlist(prdct_ctgry, "high fidelity dna polymerase", "nucleic acid modifying enzyme", "gel & nucleic acid staining", "primary antibody", "us fb", "secondary antibody", "dna ladder")
*    replace label = prdct_ctgry if inlist(prdct_ctgry, "transfection reagent" , "cell lysis reagents")
    gen clock = 9 if inlist(prdct_ctgry, "nucleic acid modifying enzyme", "restriction enzyme", "secondary antibody", "primary antibody" )
    replace clock = 2 if  prdct_ctgry == "cell lysis reagents" | prdct_ctgry == "dna ladder"
    replace clock = 4 if   prdct_ctgry == "high fidelity dna polymerase"
    replace clock = 10 if  inlist(prdct_ctgry, "primary antibody" ) 
    tw (scatter delta_hhi sim_hhi if treated == 1, mcolor(ebblue%80) mlabel(label) mlabsize(vsmall) msize(small) mlabvposition(clock)) || (scatter delta_hhi sim_hhi if treated ==  0, mcolor(dkorange%60) msize(small)) || ///
     (function y=x, range(-2000 6000) lcolor(lavender) lpattern(shortdash)),  xtitle("Simulated Change in HHI", size(small)) ytitle("Actual Change in HHI", size(small)) legend(on ring(0) pos(11) label(1 "Treated Markets") label(2 "Control Markets") order(1 2 - "Corr: `corr'") size(small)) xlab(-2000(1000)6000) ylab(-2000(1000)6000)
    graph export ../output/figures/bs_`uni'.pdf, replace
    save ../output/sim_v_delta_`uni', replace
end
main
