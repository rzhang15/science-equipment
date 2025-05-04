set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 18
set maxvar 120000, perm 
global dropbox_dir "~/dropbox (harvard university)/rubicon dissertation"
global derived_output "${dropbox_dir}/derived_output_sci_eq"

program main  
    make_panel
end

program make_panel
    use ../external/samp/merged_unis_final, clear
    replace prdct_ctgry = stritrim(prdct_ctgry)
    replace prdct_ctgry = subinstr(prdct_ctgry, "-", " ", .)
     replace prdct_ctgry = "cell lysis reagents" if prdct_ctgry == "cell lysis reagent"
    replace prdct_ctgry = "dehydrated microbacterial media" if prdct_ctgry == "dehydrated microbacterial medium"
    replace prdct_ctgry = "media supplement" if prdct_ctgry == "medium supplement"
    replace prdct_ctgry = "prestained protein standards" if prdct_ctgry == "prestained protein standard"
    replace prdct_ctgry = "high fidelity dna polymerase" if prdct_ctgry == "high fidelity polymerase"
    *keep if uni == "ut_dallas" | uni == "ut_austin"
*    replace prdct_ctgry = "antibodies" if inlist(prdct_ctgry, "primary antibody", "secondary antibody")
    replace prdct_ctgry = "cross linkers" if prdct_ctgry == "cross-linker"
    gegen mkt = group(prdct_ctgry)
    gen treated = inlist(prdct_ctgry, "adding proteases", "affinity chromatography kits", "biotin reagent", "cdna synthesis kits", "cell lysis detergents" , "cell lysis reagents", "chemical modifiers", "chemiluminescent substrate") | inlist(prdct_ctgry, "cloning enzymes", "cloning kits", "column based instruments", "cross linkers", "dye based qpcr kits", "electrophoresis gel boxes", "elisa kits", "fluorescence photometers", "gel stains") | inlist(prdct_ctgry, "high fidelity polymerase", "hot start polymerase", "magnetic bead based instruments", "western blot membranes", "molecular weight standards", "ordinary and flourescent microparticles") | inlist(prdct_ctgry, "other beads", "other specialty polymerase", "pcr kits", "pcr plastic consumables", "power suppliers", "pre cast gels") | inlist(prdct_ctgry, "primary antibody", "primers", "probe based qpcr kits", "probe based rt qpcr kits", "protease", "protein standards", "qpcr instruments", "reactive dyes", "reverse transcriptase enzymes") | inlist(prdct_ctgry, "rt pcr kits", "secondary antibody", "spectrofluorometers", "standard reagents: buffers, dntps, other ancillary reagents", "streptavidin and avidin reagents",  "taq polymerase") | inlist(prdct_ctgry, "thermal cyclers", "transfection reagents", "transfer boxes", "vertical gel boxes", "antibodies", "rt-pcr kits")  //((strpos(prdct_ctgry, "media") > 0 & strpos(prdct_ctgry, "liquid")>0) | (strpos(prdct_ctgry, "media") > 0 & strpos(prdct_ctgry, "dry")>0) | strpos(prdct_ctgry, "serum") | strpos(prdct_ctgry, "polymer-based magnetic beads") > 0  | strpos(prdct_ctgry, "sera")) | inlist(prdct_ctgry, "shrna", "sirna", "mirna")
    replace treated = 1 if strpos(prdct_ctgry, "column-based")
    replace treated = 1 if strpos(prdct_ctgry, "dye-based")
    replace treated = 1 if strpos(prdct_ctgry, "polymerase")
    replace treated = 1 if strpos(prdct_ctgry, "gel & nucleic acid staining")
    replace treated = 1 if strpos(prdct_ctgry, "system")
    replace treated = 1 if strpos(prdct_ctgry, "restriction enzyme")
    replace treated = 1 if strpos(prdct_ctgry, "nucleic acid modifying enzyme")
    replace treated = 1 if strpos(prdct_ctgry, "reverse transcriptase")
    replace treated = 1 if strpos(prdct_ctgry, "ladder")
    replace treated = 1 if strpos(prdct_ctgry, "standard")
    replace treated = 1 if strpos(prdct_ctgry, "column based")
    replace treated = 1 if strpos(prdct_ctgry, "pvdf membrane")
    replace treated = 1 if strpos(prdct_ctgry, "nitrocellulose membrane")
    replace prdct_ctgry = strtrim(prdct_ctgry)
    gen last_letter = substr(prdct_ctgry, -1,.)
    replace prdct_ctgry = substr(prdct_ctgry, 1, strlen(prdct_ctgry) -1) if last_letter ==   "s" 
    drop if inlist(prdct_ctgry, "unclear", "general lab consumables", "general lab equipment", "instrument accessories" , "electronics accessories")
    drop if inlist(prdct_ctgry, "containers & storage", "cleaning supplies & wipes")
    drop if inlist(prdct_ctgry,  "service", "hardware" ,"non chemical item", "no match", "software", "electronic")
    drop if inlist(prdct_ctgry, "office supplies", "mouse", "3d printing", "adapter")
    drop if inlist(prdct_ctgry, "shipping", "subaward", "fees", "chemical", "electronics")
    drop if strpos(prdct_ctgry, "bundle") > 0
    drop if strpos(prdct_ctgry, "instrument") > 0
    drop if strpos(prdct_ctgry, "nan") > 0
    drop if strpos(prdct_ctgry, "unclear") > 0
    drop if strpos(prdct_ctgry, "random") > 0
    drop if strpos(prdct_ctgry, "sequencing") > 0
    drop if strpos(prdct_ctgry, "pipette") > 0
    drop if strpos(prdct_ctgry, "accessorie") > 0
    drop if strpos(prdct_ctgry, "general") > 0
    drop if strpos(prdct_ctgry, "misc") > 0
    drop if strpos(prdct_ctgry, "lamp") > 0
    drop if strpos(prdct_ctgry, "lighting") > 0
    drop if strpos(prdct_ctgry, "hotplate") > 0
    drop if strpos(prdct_ctgry, "vacuum") > 0
    drop if strpos(prdct_ctgry, "rotary traps") > 0
    drop if strpos(prdct_ctgry, "rotators") > 0
*    drop if ((strpos(prdct_ctgry, "media") > 0 & strpos(prdct_ctgry, "liquid")>0) | (strpos(prdct_ctgry, "media") > 0 & strpos(prdct_ctgry, "dry")>0) | strpos(prdct_ctgry, "serum") | strpos(prdct_ctgry, "polymer-based magnetic beads") > 0  | strpos(prdct_ctgry, "sera"))
*    drop if inlist(prdct_ctgry, "shrna", "sirna", "mirna")
    drop if year >= 2020
    gen raw_price = price
    gen raw_qty = qty
    gen raw_spend = spend 
    replace price = log(price)
    replace qty = log(qty)
    bys mkt year : egen spend99= pctile(raw_spend), p(99)
    bys mkt year : egen spend1 = pctile(raw_spend), p(1)
    drop if raw_spend < spend1
    drop if raw_spend > spend99
    replace spend = log(raw_spend)
    bys mkt : gen num_times = _N
    bys supplier_id mkt year: egen total_spend = total(raw_spend)
    bys mkt year: egen mkt_spend = total(raw_spend)
    gen spend_shr = total_spend/mkt_spend 
    bys supplier_id mkt: egen pre_merger_shr = mean(spend_shr) if year == 2013
    bys supplier_id mkt: egen pre_merger_spend = mean(total_spend) if year <=2013
    hashsort supplier_id mkt pre_merger_spend
    by supplier_id mkt: replace pre_merger_spend = pre_merger_spend[_n-1] if mi(pre_merger_spend)
    hashsort supplier_id mkt pre_merger_shr 
    by supplier_id mkt: replace pre_merger_shr = pre_merger_shr[_n-1] if mi(pre_merger_shr)
    bys mkt supplier_id year: gen num_suppliers_id = _n == 1
    bys mkt year: egen num_suppliers = total(num_suppliers) 
    bys supplier_id sku : gen num_sku_cnt = _N
    bys supplier_id mkt: gen num_supplier_trans = _N
    bys mkt: egen sd_price = sd(raw_price)
    sum sd_price, d
    drop if sd_price > r(p95) & treated == 0
    save "${derived_output}/make_mkt_panel/transactions", replace
    collapse (max) treated (mean) *price num_suppliers pre_merger* (sum) *raw_qty *raw_spend (firstnm) mkt product_desc suppliername , by(supplier_id prdct_ctgry year)
    save "${derived_output}/make_mkt_panel/supplier_mkt_yr", replace
    save ../output/supplier_mkt_yr, replace
    collapse (max) treated (mean) *price num_suppliers (sum) *raw_qty *raw_spend (firstnm) mkt product_desc  , by(prdct_ctgry year)
    rename price avg_log_price
    gen log_avg_price = log(raw_price)
    gen log_tot_qty = log(raw_qty)
    gen log_tot_spend = log(raw_spend)
    save "${derived_output}/make_mkt_panel/mkt_yr", replace 
    save "../output/mkt_yr", replace 
end

**
main
