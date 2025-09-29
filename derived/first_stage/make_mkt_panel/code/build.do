set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17
global treated_products `" "fbs" "serum" "sera" "basal media" "proprietary media" "cell culture nutritional supplements" "media supplements"  "pbs" "dpbs" "cell culture dissociation reagents" "cell lysis" "protein quantitation assay kit" "western blot" "loading dye" "dna purification" "running buffer" "gel stain" "rna extraction reagents" "cell culture antibiotic" "cell culture flasks" "cell culture plates" "cell culture dishes" "hbss" "sirna" "shrna" "rnai" "transfection" "synthetic" "plasmid vectors" "vectors" "magnetic beads" "polystyrene beads" "magnetic bead-based" "magnetic-based" "magnetic bacterial" "magnetic ip" "pcr systems" "qpcr systems" "rt-pcr systems" "taq polymerases" "dna polymerase" "reverse transcriptase" "dntps" "pcr tubes" "pcr tube strips" "miniprep" "midiprep" "maxiprep" "column-based" "spin columns" "dna ladder" "agarose" "restriction enzymes" "modifying enzymes" "chemically competent cells" "cloning kits" "polystyrene particles" "ordinary microparticles" "fluorescent particles" "electrophoresis systems" "pre-cast" "ladder" "gel stains" "blotting membrane" "chemiluminescent substrate" "antibody" "antibodies" "crosslinking reagents" "proteases" "biotin" "streptavidin-biotin" "avidin" "elisa kits" "cell lysis detergents" "in vitro protein expression kits" "'

program main 
    import delimited using ../external/sup/supplier_mapping_final, varn(1) clear 
    rename original_suppliername suppliername
    rename canonical_supplier new_suppliername
    save ../temp/supplier_map, replace 
    make_panel, embed(tfidf)
end

program make_panel
   syntax, embed(string)
    import delimited ../external/samp/utdallas_validation_report_gatekeeper_tfidf_expert_`embed', clear
    drop if inlist(category, "macro avg", "weighted avg", "Non-Lab", "accuracry")
    gen treated = 0
    foreach c of global treated_products {
        replace treated = 1 if strpos(category, "`c'") > 0 
    }
    keep if support >= 25 & precision >= 0.75  & recall >= 0.75
    save ../temp/categories_`embed', replace

    import delimited ../external/samp/govspend_panel_classified_gatekeeper_tfidf_expert_`embed', clear
    rename market_prediction category
    merge m:1 category using ../temp/categories_`embed', assert(1 3) keep(3) nogen
    drop num_yrs orgid
    drop if mi(suppliername)
    drop if strpos(suppliername, "n/a")  > 0 
    gen counter = 1
    bys suppliername year: gen supplier_yr = _n == 1
    bys suppliername: egen tot_supplier_obs = total(counter) 
    bys suppliername: gen sup_id = _n == 1
    gegen uni_id = group(agencyname)
    merge m:1 suppliername using ../temp/supplier_map, assert(2 3) keep(3) nogen
    gegen supplier_id = group(new_suppliername)
    gen raw_price = price
    gen raw_qty = qty
    gen raw_spend = spend 
    replace price = log(price)
    replace qty = log(qty)
    replace spend = log(spend)
    bys category year : egen spend99= pctile(raw_spend), p(99)
    bys category year : egen spend1 = pctile(raw_spend), p(1)
    drop if raw_spend < spend1
    drop if raw_spend > spend99
    bys category : gen num_times = _N
    bys supplier_id category year: egen total_spend = total(raw_spend)
    bys category year: egen category_spend = total(raw_spend)
    bys category supplier_id year: gen num_suppliers_id = _n == 1
    bys category year: egen num_suppliers = total(num_suppliers) 
    preserve
    collapse (max) treated (mean) *price num_suppliers (sum) *raw_qty *raw_spend (firstnm) suppliername , by(supplier_id category year)
    save ../output/supplier_category_yr_`embed', replace
    restore

    preserve
    collapse (max) treated (mean) *price num_suppliers (sum) *raw_qty *raw_spend (firstnm) suppliername agencyname , by(uni_id category year)
    save ../output/uni_category_yr_`embed', replace
    restore

    collapse (max) treated (mean) *price num_suppliers (sum) *raw_qty *raw_spend , by(category year)
    rename price avg_log_price
    gen log_avg_price = log(raw_price)
    gen log_tot_qty = log(raw_qty)
    gen log_tot_spend = log(raw_spend)
    save "../output/category_yr_`embed'", replace 
end

**
main
