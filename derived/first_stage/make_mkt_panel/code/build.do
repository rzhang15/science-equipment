set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17
global cell_culture `" "basal media" "proprietary media" "custom media" "fbs" "serum" "sera" "hepes buffer" "phosphate-buffered saline (pbs) buffer" "dpbs" "hanks' balanced salt solution (hbss) buffer" "tris-buffered salie (tbs) buffer" "tris-acetate-edta (tae) buffer" "tris-glycine-sds (tgs) buffer" "tris-edta (te) buffer" "tbe buffer" "mes (2-(n-morpholino)ethanesulfonic acid) buffer" "mops-sds buffer" "cell culture nutritional supplements" "media supplements" "cell culture antibiotics" "cell culture dissociation reagents" "cell scrapers" "cell strainers" "cryopreservation solution" "serological pipettes" "cell culture flasks" "cell culture plate" "cell culture dishes" "centrifuge conical tubes" "microcentrifuge tubes" "cryovials" "cell line" "'
global mol_bio `" "synthetic" "sirna" "transfection reagents" "taq polymerase" "dna polymerase" "reverse transcriptase" "pcr system" "qpcr system" "rt-qcr" "rt-pcr" "restriction enzymes" "nucleic acid modifying enzymes" "cloning kit" "polystyrene bead" "dna ladder" "rnai" "dna ligase" "expression plasmid" "plasmid vector" "chemically competent cells" "electrocompetent cell" "column-based" "magnetic-bead" "rna ladder" "agarose" "nucleic acid gel stains" "tbe buffer" "tae buffer"  "cell lysis" "cdna" "dntps" "electrophoresis" "laemmli" "'
global protein_bio `" "pre-cast" "pre-stained" "protein gel stains" "acrylamide/bis solution" "blotting membrane" "chemiluminescent substrate" "protease" "crosslinking reagent" "bioconjugate dye" "antibody" "protein molecular-weight ladder" "western blot" "bca protein assay kit" "bradford protein assay kit" "bovine serum albumin" "protease inhibitor cocktails" "reducing agents" "dtt" "elisa" "'
global treated_products  "$cell_culture $mol_bio $protein_bio"

program main 
    import_suppliers
    make_panel, embed(tfidf)
end

program import_suppliers
    import delimited using ../external/sup/supplier_mapping_final, varn(1) clear 
    rename original_suppliername suppliername
    rename canonical_supplier new_suppliername

    foreach k in "sports" "sales" "communications" "printing" "design" "photography" "music" "education" "john" "robert" "graphics" "management" "community" "publishing" "envvironmental" "prouductions" "marketing" "safety" "hour" "hardware" "investments" "entertainment" "promotional" "maintenance" {
        drop if strpos(suppliername, "`k'") > 0
    }
    save ../temp/supplier_map, replace 
end

program make_panel
    syntax, embed(string)
    import delimited ../external/samp/utdallas_full_report_gatekeeper_tfidf_expert_non_parametric_`embed', clear
    cap rename v1 category
    drop if inlist(category, "macro avg", "weighted avg", "Non-Lab", "accuracy")
    gen treated = 0
    foreach c of global treated_products {
        replace treated = 1 if strpos(category, "`c'") > 0 
    }
    drop if inlist(category, "recombinant human protein") | strpos(category, "recombinant") > 0 | strpos(category, "growth factor") > 0  | strpos(category, "cell line") > 0 | strpos(category, "small molecule inhibitor") > 0 
    gen keep  = support >= 25 & precision >= 0.8 & recall >= 0.8
    save ../temp/categories_`embed', replace

    import delimited ../external/samp/govspend_panel_classified_tfidf_model_expert_`embed', clear
    rename market_prediction category
    drop if price == 0 | qty == 0 | spend == 0
    drop if spend > 100000 | price > 100000
    foreach v in "hall site" "insurance" "liability" "deductible" "claim" "athletic" "wellness" "recreation" "transit" "advertising" "install" "semester" "guarantee" "ncaa" "newspaper" "conference" "po " "replace" "building" "bobcat" "spectramax" "notification" "journal" "drainage"  {
        drop if strpos(clean_desc, "`v'") > 0
    }
    drop if category == "Non-Lab"
    drop if mi(suppliername)
    drop if strpos(suppliername, "n/a")  > 0 
    bys category year: gen cat_yr = _n == 1
    bys category: egen num_yrs_cat = total(cat_yr)
    keep if num_yrs_cat == 10
    merge m:1 category using ../temp/categories_`embed', assert(1 2 3)  keep(1 3)

    replace category = subinstr(category, "/","-",.)
    // drop inconsistent uni's
    bys orgid year: gen num_uni_obs = _N
    bys orgid year: gen org_yr_id = _n == 1 
    bys orgid: gen orgspend_counter = _n == 1
    bys orgid: egen num_obs_sd = sd(num_uni_obs) if org_yr_id == 1 
    bys orgid: egen num_obs_mean = mean(num_uni_obs) if org_yr_id == 1 
    bys orgid: egen num_obs_min = min(num_uni_obs) if org_yr_id == 1 
    bys orgid: egen num_obs_max = max(num_uni_obs) if org_yr_id == 1 
    hashsort orgid num_obs_sd
    ds num_obs*
    foreach v in `r(varlist)' {
        by orgid: replace `v' = `v'[_n-1] if mi(`v')
    }
    gen out_of_bounds = num_obs_min < num_obs_mean - 1.5*num_obs_sd | num_obs_max > 1.5*num_obs_sd + num_obs_mean
    bys orgid: egen drop = max(out_of_bounds)
    *drop if drop == 1

    sum spend if _merge == 3
    gen raw_price = price
    gen raw_qty = qty
    gen raw_spend = spend 
    replace price = log(price)
    replace qty = log(qty)
    replace spend = log(spend)
    bys category year : egen spend99= pctile(raw_spend), p(99)
    bys category year : egen spend1 = pctile(raw_spend), p(1)
    drop if raw_spend <= spend1
    drop if raw_spend >= spend99
    drop spend1 spend99
    bys category  : egen spend99= pctile(raw_spend), p(99)
    bys category  : egen spend1 = pctile(raw_spend), p(1)
    drop if raw_spend <= spend1
    drop if raw_spend >= spend99
    sum raw_spend
    local tot_spend = r(sum)
    sum raw_spend if keep == 1
    di "Total spend in matched categories: " r(sum) " out of " `tot_spend' " (" string(r(sum)/`tot_spend'*100) "%)"
    count
    local tot_obs = r(N)
    count if keep  == 1
    di "Total observations in matched categories: " r(N) " out of " `tot_obs' " (" string(r(N)/`tot_obs'*100) "%)"
    keep if keep == 1 
    drop num_yrs orgid
    gen counter = 1
    bys suppliername year: gen supplier_yr = _n == 1
    bys suppliername: egen tot_supplier_obs = total(counter) 
    bys suppliername: gen sup_id = _n == 1
    gegen uni_id = group(agencyname)
    merge m:1 suppliername using ../temp/supplier_map, assert(1 2 3) keep(3) nogen
    gegen supplier_id = group(new_suppliername)
    bys category : gen num_times = _N
    bys supplier_id category year: egen total_spend = total(raw_spend)
    bys category year: egen category_spend = total(raw_spend)
    bys category supplier_id year: gen num_suppliers_id = _n == 1
    bys category year: egen num_suppliers = total(num_suppliers) 
    gen obs_cnt = 1
    save ../output/item_level_`embed', replace
    preserve
    collapse (max) treated (mean) *price num_suppliers (sum) obs_cnt *raw_qty *raw_spend (firstnm) new_suppliername , by(supplier_id category year)
    save ../output/supplier_category_yr_`embed', replace
    gen pre_period = year < 2014
    keep if inrange(year, 2012,2013) | inrange(year, 2015, 2016)
    collapse (sum) raw_spend obs_cnt (firstnm) new_suppliername treated , by(supplier_id category pre_period)
    bys category: egen total_spend = total(raw_spend)
    gen mkt_shr = raw_spend/total_spend * 100 
    gen life_tech = mkt_shr if new_suppliername == "life technologies"
    gen thermo = mkt_shr if new_suppliername == "thermo fisher scientific"
    bys category pre_period (life_tech): replace life_tech = life_tech[_n-1] if mi(life_tech) 
    bys category pre_period (thermo): replace thermo = thermo[_n-1] if mi(thermo) 
    gen simulated_hhi = 2 * life_tech * thermo if pre_period == 1
    bys category (simulated_hhi): replace simulated_hhi = simulated_hhi[_n-1] if mi(simulated_hhi) & pre_period == 0
    replace mkt_shr = mkt_shr * mkt_shr
    gcollapse (sum) obs_cnt hhi = mkt_shr (firstnm) simulated_hhi treated, by(category pre_period)
    hashsort category -pre_period
    by category : gen delta_hhi = hhi - hhi[_n-1] if pre_period == 0
    bys category: egen tot_cnt = total(obs_cnt)
    bys category (delta_hhi): replace delta_hhi = delta_hhi[_n-1] if mi(delta_hhi) 
    gcontract category simulated_hhi delta_hhi treated tot_cnt
    drop _freq
    gisid category
    save ../output/category_hhi_`embed', replace    
    restore

    bys category: egen cat_spend = total(raw_spend) 
    bys category: egen tot_obs = total(obs_cnt)
    gen spend_2013 = cat_spend if year == 2013
    hashsort category spend_2013
    bys category : replace spend_2013 = spend_2013[_n-1] if mi(spend_2013)

    preserve
    collapse (max) treated (mean) *price num_suppliers (sum) obs_cnt *raw_qty *raw_spend (firstnm) suppliername agencyname , by(uni_id category year)
    save ../output/uni_category_yr_`embed', replace
    restore
    
    gen avg_log_spend = spend
    gen avg_log_qty = qty 
    gen avg_log_price = price 
    collapse (max) treated (mean) avg_log_price tot_obs avg_log_spend avg_log_qty num_suppliers precision recall spend_2013  (sum) obs_cnt *raw_qty *raw_spend [aw = spend_2013], by(category year)
    save "../output/category_yr_`embed'", replace 
end

**
main
