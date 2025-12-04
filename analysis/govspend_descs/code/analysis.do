set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17
global treated_products `" "fbs" "serum" "sera" "basal media" "proprietary media" "cell culture nutritional supplements" "media supplements"  "pbs" "dpbs" "cell culture dissociation reagents" "cell lysis" "protein quantitation assay kit" "western blot" "loading dye" "dna purification" "running buffer" "gel stain" "rna extraction reagents" "cell culture antibiotic" "cell culture flasks" "cell culture plates" "cell culture dishes" "hbss" "sirna" "shrna" "rnai" "transfection" "synthetic" "plasmid vectors" "vectors" "magnetic beads" "polystyrene beads" "magnetic bead-based" "magnetic-based" "magnetic bacterial" "magnetic ip" "pcr systems" "qpcr systems" "rt-pcr systems" "taq polymerases" "dna polymerase" "reverse transcriptase" "dntps" "pcr tubes" "pcr tube strips" "miniprep" "midiprep" "maxiprep" "column-based" "spin columns" "dna ladder" "agarose" "restriction enzymes" "modifying enzymes" "chemically competent cells" "cloning kits" "polystyrene particles" "ordinary microparticles" "fluorescent particles" "electrophoresis systems" "pre-cast" "ladder" "gel stains" "blotting membrane" "chemiluminescent substrate" "antibody" "antibodies" "crosslinking reagents" "proteases" "biotin" "streptavidin-biotin" "avidin" "elisa kits" "cell lysis detergents" "in vitro protein expression kits" "'

program main   
    foreach e in tfidf bert {
        prep_data, embed(`e')
        uni_descs, embed(`e')
        supplier_stats, embed(`e')
        product_stats, embed(`e')
        hhi, embed(`e')
    }
end

program analyze_items
    syntax, embed(string)
    use ../external/samp/full_item_level_`embed', clear

end
program uni_descs
    syntax, embed(string)
    use ../external/samp/uni_category_yr_`embed', clear
    tab year
    collapse (sum) spend counter (firstnm) agencyname, by(uni_id year)
    bys uni_id: egen tot_spend = total(spend)
    bys uni_id: egen num_obs= total(counter)
    collapse (mean) avg_spend = spend avg_obs_yr = counter (firstnm) num_obs tot_spend agencyname, by(uni_id)
    sum avg_obs_yr, d
    local mean : di %12.3f r(mean) 
    local sd : di %12.3f r(sd) 
    local min : di %12.3f r(min)
    local max : di %12.3f r(max)
    local p95 : di %12.3f r(p95)
    tw hist  avg_obs_yr if num_obs <= `p95', freq bin(50) xtitle("Average Number of Observations per Year") ///
        ytitle("Number of Universities") title("Histogram of Average Observations per Year") ///
        legend(on order(- "Mean = `mean'" "SD = `sd'" "Min = `min'" "Max = `max'") ring(0) pos(1)) 
    graph export ../output/figures/avg_obs_per_year_per_uni_`embed'.pdf, replace
    hashsort -avg_obs_yr
    li in 1/20
    sum avg_spend, d
    local mean : di %12.3f r(mean) 
    local sd : di %12.3f r(sd) 
    local min : di %12.3f r(min)
    local max : di %12.3f r(max)
    local p95 : di %12.3f r(p95)
    tw hist  avg_spend if avg_spend <= `p95', freq bin(50) xtitle("Average Spend per Year") ///
        ytitle("Number of Universities") title("Histogram of Average Spend per Year") ///
        legend(on order(- "Mean = `mean'" "SD = `sd'" "Min = `min'" "Max = `max'") ring(0) pos(1)) 
    graph export ../output/figures/avg_spend_per_year_per_uni_`embed'.pdf, replace
    hashsort -avg_spend
    li in 1/20
end

program supplier_stats
    syntax, embed(string)
    use ../temp/govspend_panel_`embed', clear   
    collapse (sum) counter spend (firstnm) new_suppliername, by(supplier_id year)
    bys supplier_id: egen tot_spend = total(spend)
    bys supplier_id: egen tot_obs = total(counter)
    collapse (mean) avg_supplier_obs = counter avg_spend = spend (firstnm) new_suppliername tot_spend tot_obs, by(supplier_id)
    sum avg_supplier_obs , d
    local mean : di %12.3f r(mean) 
    local sd : di %12.3f r(sd) 
    local min : di %12.3f r(min)
    local max : di %12.3f r(max)
    local p95 : di %12.3f r(p95)
    tw hist  avg_supplier_obs if avg_supplier_obs <= `p95', freq bin(50) xtitle("Average Number of Observations per Year") ///
        ytitle("Number of Suppliers") title("Histogram of Average Observations per Year") ///
        legend(on order(- "Mean = `mean'" "SD = `sd'" "Min = `min'" "Max = `max'") ring(0) pos(1)) 
    graph export ../output/figures/avg_obs_per_year_per_sup_`embed'.pdf, replace
    tw hist  avg_spend if avg_spend <= `p95', freq bin(50) xtitle("Average Spend per Year") ///
        ytitle("Number of Suppliers") title("Histogram of Average Spend per Year") ///
        legend(on order(- "Mean = `mean'" "SD = `sd'" "Min = `min'" "Max = `max'") ring(0) pos(1)) 
    graph export ../output/figures/avg_spend_per_year_per_sup_`embed'.pdf, replace
    hashsort -avg_spend
    li in 1/20
end
program product_stats 
    syntax, embed(string)
    use ../temp/govspend_panel_`embed', clear   
    collapse (sum) counter spend, by(category year)
    bys category: egen tot_spend = total(spend)
    bys category: egen tot_obs = total(counter)
    collapse (mean) avg_obs = counter avg_spend = spend (firstnm) tot_spend tot_obs, by(category)
    hashsort -avg_spend
    li in 1/20
end

program hhi
    syntax, embed(string)
    use ../temp/govspend_panel_`embed', clear
    gcollapse (sum) spend , by(new_suppliername supplier_id category year)
    keep if inlist(year, 2012,2013,2015, 2016)
    bys category year: egen tot_mkt_spend = total(spend)
    gen pre_merger = year <= 2013
    gen post_merger = year >= 2015
    bys category: egen has_pre_merger = max(pre_merger)
    bys category: egen has_post_merger = max(post_merger)
    bys category year: gen yr_cnt = _n == 1
    bys category: egen num_years = total(yr_cnt)
    gunique category
    keep if has_post_merger == 1 & has_pre_merger == 1
    gunique category
    cap drop pre_merger_spend
    gcollapse (sum) spend, by(new_suppliername supplier_id category pre_merger)
    bys category: egen pre_merger_spend= total(spend) if pre_merger == 1 
    bys category: egen post_merger_spend= total(spend) if pre_merger == 0 
    gen pre_merger_mkt_shr = spend/pre_merger_spend  * 100          
    gen post_merger_mkt_shr = spend/post_merger_spend  * 100
    hashsort supplier_id category pre_merger_mkt_shr
    by supplier_id category: replace pre_merger_mkt_shr = pre_merger_mkt_shr[_n-1] if mi(pre_merger_mkt_shr) & pre_merger_mkt_shr[_n-1] != .
    hashsort supplier_id category post_merger_mkt_shr
    by supplier_id category: replace post_merger_mkt_shr = post_merger_mkt_shr[_n-1] if mi(post_merger_mkt_shr) & post_merger_mkt_shr[_n-1] != .
    gen thermo_mkt_shr = pre_merger_mkt_shr if new_suppliername == "thermo fisher scientific"
    gen lt_mkt_shr = pre_merger_mkt_shr if new_suppliername == "life technologies"
    hashsort category thermo_mkt_shr
    by category: replace thermo_mkt_shr = thermo_mkt_shr[_n-1] if mi(thermo_mkt_shr) & thermo_mkt_shr[_n-1] != . 
    hashsort category lt_mkt_shr
    by category: replace lt_mkt_shr = lt_mkt_shr[_n-1] if mi(lt_mkt_shr) & lt_mkt_shr[_n-1] != . 
    gen sim_hhi = 2 * thermo_mkt_shr  * lt_mkt_shr
    gen mkt_shr = pre_merger_mkt_shr 
    bys category pre_merger: egen hhi = total(mkt_shr * mkt_shr)
    contract category pre_merger hhi sim_hhi
    save ../output/hhi_`embed', replace
    drop if mi(sim_hhi)
    bys category (pre_merger): gen delta_hhi = hhi[_n+1] - hhi
    cap drop _freq
    contract category delta_hhi sim_hhi
    drop if mi(delta_hhi)
    save ../output/delta_hhi_`embed', replace       
    tw scatter delta_hhi sim_hhi, ///
        xtitle("Simulated HHI Change") ytitle("Actual HHI Change") ///
        title("Actual vs. Simulated HHI Change by Product Category") ///
        legend(off)
    graph export ../output/figures/actual_vs_sim_hhi_change_`embed'.pdf, replace
end
main
