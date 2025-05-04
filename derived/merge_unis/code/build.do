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
*    uni_xws
*    import_data
    merge_data
    *make_panel
end

program uni_xws 
    import excel using "../external/dallas/combined.xlsx", clear firstrow
    drop if mi(suppliername)
    keep supplier_id suppliername product_desc sku prdct_ctgry  category
    replace prdct_ctgry = category if !mi(category) & !inlist(prdct_ctgry, "primary antibody", "secondary antibody")
    replace prdct_ctgry = strlower(prdct_ctgry)
    replace prdct_ctgry = strtrim(prdct_ctgry)
    replace prdct_ctgry = subinstr(prdct_ctgry, "-"," ",.)
    save "../temp/dallas_ctgry_xw", replace
    foreach uni in oregon_state_university ut_austin {
        import excel using "../external/trained/`uni'_classified_unique.xlsx" , clear firstrow
        cap drop if mi(PurchaseLineDescription)
        rename predicted_category prdct_ctgry
        save ../temp/`uni'_ctgry_xw, replace
    }
end
program import_data
    import excel using "../external/foias/oregonstate_2010_2019.xlsx" , clear firstrow
    drop if mi(PurchaseLineDescription)
    merge m:1  PurchaseLineDescription VendorLastName using ../temp/oregon_state_university_ctgry_xw, assert(3) keep(3) nogen
    gen suppliername = VendorFirstName + VendorLastName
    rename (UniquePurchaseIdentifier PurchaseDate PurchaseLineDescription ItemQuantity UnitPrice VendorID) (purchase_id purchase_date product_desc qty price supplier_id)
    replace suppliername = strlower(suppliername)
    keep purchase_id purchase_date product_desc qty price supplier_id suppliername prdct_ctgry
    replace purchase_date = dofc(purchase_date)
    format %td purchase_date
    gen year = year(purchase_date)
    format purchase_date %td
    cap destring qty, replace force
    cap destring price, replace
    gen spend = price * qty
    gen uni = "oregon_state"
    cap tostring supplier_id, replace
    save ../temp/oregon_merged, replace
/*
    import excel using "../external/foias/und_appended_2005_2023.xlsx", clear firstrow 
    fmerge m:1 Description VendorName using ../temp/und_ctgry_xw, assert(3) keep(3) nogen
    rename (PONumber PODate Description POQty POAmount VendorName) (purchase_id purchase_date product_desc qty spend suppliername)
    replace suppliername = strlower(suppliername)
    gegen supplier_id = group(suppliername)
    destring spend, replace
    cap destring qty, replace force
    gen price = spend/qty
    keep purchase_id purchase_date product_desc qty price supplier_id suppliername prdct_ctgry spend
    gen year = year(purchase_date)
    gen uni = "und"
    cap tostring supplier_id, replace
    save ../temp/und_merged, replace*/

    import excel using "../external/foias/utaustin_2012_2019.xlsx", clear firstrow 
    fmerge m:1 ItemDescription1 VendorName using ../temp/ut_austin_ctgry_xw, assert(3) keep(3) nogen
    rename (PurchaseOrder PurchaseOrderDate VendorName ItemDescription1 ItemQuantityRequest ItemSubtotalCost VendorEID) (purchase_id purchase_date suppliername product_desc qty spend supplier_id)
    replace suppliername = strlower(suppliername)
    cap destring qty, replace force
    cap destring spend, replace
    gen price = spend/qty
    keep purchase_id purchase_date product_desc qty price supplier_id suppliername prdct_ctgry spend
    gen year = year(purchase_date)
    gen uni = "ut_austin"
    cap tostring supplier_id, replace
    save ../temp/ut_austin_merged, replace 

    import excel using "../external/foias/utdallas_2011_2024.xlsx", clear firstrow case(lower)
    rename (purchaseorderidentifier purchasedate suppliernumber productdescription projectid skucatalog unitprice quantity) (purchase_id purchase_date supplier_id product_desc project_id sku price qty)
    replace suppliername = strlower(suppliername)
    drop if mi(suppliername)
    drop if mi(sku)
    cap destring qty, replace force
    cap destring spend, replace
    merge m:1 sku supplier_id using "../temp/dallas_ctgry_xw", assert(3) keep(3) 
    keep purchase_id purchase_date product_desc qty price supplier_id suppliername prdct_ctgry
    gen spend = qty*price
    gen year = year(purchase_date)
    cap tostring supplier_id, replace
    gen uni = "ut_dallas"
    save ../temp/dallas_merged, replace
end 
program merge_data
    clear
    foreach uni in dallas  ut_austin oregon {
        append using ../temp/`uni'_merged
    }
    replace suppliername = subinstr(suppliername, "corporation", "corp",.)
    replace suppliername = "fisher" if strpos(suppliername, "fisher sc")>0 | strpos(suppliername, "thermo fish")>0  | strpos(suppliername, "thermo elec") >0 | strpos(suppliername, "possible mission") >0
    replace suppliername = "vwr" if strpos(suppliername, "vwr")>0
    replace  suppliername = "life tech" if strpos(suppliername, "applied biosystems")>0| strpos(suppliername, "invitrogen") > 0 | strpos(suppliername, "life tech") > 0
    foreach str in "inc" "llc" "ltd" "corp" "co" "company" ".com" { 
        replace suppliername = subinstr(suppliername, "`str'", "", .)
    }
    replace suppliername = subinstr(suppliername, "intnl", "international",.)
    replace suppliername = subinstr(suppliername, "amer ", "american",.)
    replace suppliername = subinstr(suppliername, "assn", "assoc",.)
    replace suppliername = subinstr(suppliername, "&", "", .)
    replace suppliername = subinstr(suppliername, "-", " ", .)
    replace suppliername = subinstr(suppliername, "and", "", .)
    replace suppliername = subinstr(suppliername, ",", "", .)
    replace suppliername = subinstr(suppliername, ".", "", .)
    replace suppliername = stritrim(suppliername)
    replace suppliername = strtrim(suppliername)
    replace suppliername = "abclonal" if strpos(suppliername, "abclonal")
    replace suppliername = "amazon" if strpos(suppliername, "amazon")
    replace suppliername = "bh photo video" if strpos(suppliername, "bh foto")
    replace suppliername = "bh photo video" if strpos(suppliername, "bh foto")
    replace suppliername = "best buy" if strpos(suppliername, "best buy")
    replace suppliername = "bio rad" if strpos(suppliername, "bio rad")
    replace suppliername = "cambridge isotope labs" if strpos(suppliername, "cambridge isotope")
    replace suppliername = "bd biosciences" if suppliername == "bd" 
    replace suppliername = "beckman ulter" if suppliername == "beckman ulter genomics" 
    replace suppliername = "carl seizz" if strpos(suppliername, "carl zeiss") 
    replace suppliername = "carolina biological supply" if strpos(suppliername, "carolina biological supply") 
    replace suppliername = "chem impex" if strpos(suppliername, "chem impex") 
    replace suppliername = "chemglass" if strpos(suppliername, "chemglass") 
    replace suppliername = "dell" if strpos(suppliername, "dell ") 
    replace suppliername = "digi key" if strpos(suppliername, "digi key") 
    replace suppliername = "ems" if strpos(suppliername, "electron microspy sciences") 
    replace suppliername = "genscript" if strpos(suppliername, "genscript") 
    replace suppliername = "mcmaster carr supply" if strpos(suppliername, "mcmaster carr") 
    replace suppliername = "mettler toledo" if strpos(suppliername, "mettler toledo") 
    replace suppliername = "nikon" if strpos(suppliername, "nikon") 
    replace suppliername = "qiagen" if strpos(suppliername, "qiagen") 
    replace suppliername = "milliporesigma" if strpos(suppliername, "emd ") | strpos(suppliername, "sigma aldrich") | strpos(suppliername, "millipore")
    replace suppliername = subinstr(suppliername, " ", "_", .)
    drop supplier_id
    gegen supplier_id = group(suppliername)
    gegen sku = group(supplier_id product_desc)
    save ../output/merged_unis, replace
    drop if strpos(prdct_ctgry, "hotplate") > 0
    drop if strpos(prdct_ctgry, "vacuum") > 0
    drop if strpos(prdct_ctgry, "rotary traps") > 0
    drop if strpos(prdct_ctgry, "rotators") > 0
    drop if strpos(prdct_ctgry, "instrument")> 0
    drop if strpos(prdct_ctgry, "thermal cycler")> 0
    drop if strpos(prdct_ctgry, "service")
    drop if strpos(prdct_ctgry, "fee")
    drop if inlist(prdct_ctgry, "shipping", "subaward", "fees", "chemical", "electronics")
    save ../output/merged_unis_consumables, replace
end


program make_panel
    use ../output/merged_unis, clear
    keep if uni == "ut_dallas" | uni == "ut_austin"
    replace prdct_ctgry = "antibodies" if inlist(prdct_ctgry, "primary antibody", "secondary antibody")
    replace prdct_ctgry = "cross linkers" if prdct_ctgry == "cross-linker"
    gegen mkt = group(prdct_ctgry)
    gen treated = inlist(prdct_ctgry, "adding proteases", "affinity chromatography kits", "biotin reagent", "cdna synthesis kits", "cell lysis detergents" , "cell lysis reagents", "chemical modifiers", "chemiluminescent substrate") | inlist(prdct_ctgry, "cloning enzymes", "cloning kits", "column based instruments", "cross linkers", "dye based qpcr kits", "electrophoresis gel boxes", "elisa kits", "fluorescence photometers", "gel stains") | inlist(prdct_ctgry, "high fidelity polymerase", "hot start polymerase", "magnetic bead based instruments", "western blot membranes", "molecular weight standards", "ordinary and flourescent microparticles") | inlist(prdct_ctgry, "other beads", "other specialty polymerase", "pcr kits", "pcr plastic consumables", "power suppliers", "pre cast gels") | inlist(prdct_ctgry, "primary antibody", "primers", "probe based qpcr kits", "probe based rt qpcr kits", "protease", "protein standards", "qpcr instruments", "reactive dyes", "reverse transcriptase enzymes") | inlist(prdct_ctgry, "rt pcr kits", "secondary antibody", "spectrofluorometers", "standard reagents: buffers, dntps, other ancillary reagents", "streptavidin and avidin reagents",  "taq polymerase") | inlist(prdct_ctgry, "thermal cyclers", "transfection reagents", "transfer boxes", "vertical gel boxes", "antibodies", "rt-pcr kits")  //((strpos(prdct_ctgry, "media") > 0 & strpos(prdct_ctgry, "liquid")>0) | (strpos(prdct_ctgry, "media") > 0 & strpos(prdct_ctgry, "dry")>0) | strpos(prdct_ctgry, "serum") | strpos(prdct_ctgry, "polymer-based magnetic beads") > 0  | strpos(prdct_ctgry, "sera")) | inlist(prdct_ctgry, "shrna", "sirna", "mirna")
    replace prdct_ctgry = strtrim(prdct_ctgry)
    gen last_letter = substr(prdct_ctgry, -1,.)
    replace prdct_ctgry = substr(prdct_ctgry, 1, strlen(prdct_ctgry) -1) if last_letter ==   "s" & treated == 0
    drop if inlist(prdct_ctgry, "unclear", "general lab consumables", "general lab equipment", "instrument accessories" , "electronics accessories")
    drop if inlist(prdct_ctgry, "containers & storage", "cleaning supplies & wipes")
    drop if inlist(prdct_ctgry,  "service", "hardware" ,"non chemical item", "no match")
    drop if inlist(prdct_ctgry, "office supplies", "mouse", "3d printing", "adapter")
    drop if inlist(prdct_ctgry, "shipping", "subaward", "fees", "chemical", "electronics")
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
    collapse (mean) *price treated num_suppliers pre_merger* (sum) *raw_qty *raw_spend (firstnm) prdct_ctgry product_desc suppliername [aw = num_sku_cnt], by(supplier_id mkt year)
    save "${derived_output}/make_mkt_panel/supplier_mkt_yr", replace
    collapse (mean) *price treated num_suppliers (sum) *raw_qty *raw_spend (firstnm) prdct_ctgry product_desc  , by(mkt year)
        replace prdct_ctgry = stritrim(prdct_ctgry)
    replace prdct_ctgry = subinstr(prdct_ctgry, "-", " ", .)
     replace prdct_ctgry = "cell lysis reagents" if prdct_ctgry == "cell lysis reagent"
    replace prdct_ctgry = "dehydrated microbacterial media" if prdct_ctgry == "dehydrated microbacterial medium"
    replace prdct_ctgry = "media supplement" if prdct_ctgry == "medium supplement"
    replace prdct_ctgry = "prestained protein standards" if prdct_ctgry == "prestained protein standard"
    replace prdct_ctgry = "high fidelity dna polymerase" if prdct_ctgry == "high fidelity polymerase"
    rename price avg_log_price
    gen log_avg_price = log(raw_price)
    gen log_tot_qty = log(raw_qty)
    gen log_tot_spend = log(raw_spend)
    save "${derived_output}/make_mkt_panel/mkt_yr", replace 
end

**
main
