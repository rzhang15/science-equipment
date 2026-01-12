set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17
global cell_culture `" "basal media" "proprietary media" "custom media" "fbs" "serum" "sera" "hepes buffer" "phosphate-buffered saline (pbs) buffer" "dpbs" "hanks' balanced salt solution (hbss) buffer" "tris-buffered salie (tbs) buffer" "tris-acetate-edta (tae) buffer" "tris-glycine-sds (tgs) buffer" "tris-edta (te) buffer" "tbe buffer" "mes (2-(n-morpholino)ethanesulfonic acid) buffer" "mops-sds buffer" "cell culture nutritional supplements" "media supplements" "cell culture antibiotics" "cell culture dissociation reagents"  "cryopreservation solution" "serological pipettes" "cell line"  "'
global mol_bio `" "synthetic" "sirna" "transfection reagents" "taq polymerase" "dna polymerase" "reverse transcriptase" "pcr system" "qpcr system" "rt-qcr" "rt-pcr" "restriction enzymes" "nucleic acid modifying enzymes" "cloning kit" "polystyrene bead" "dna ladder" "rnai" "dna ligase" "expression plasmid" "plasmid vector" "chemically competent cells" "electrocompetent cell" "column-based" "magnetic-bead" "rna ladder" "agarose" "nucleic acid gel stains" "tbe buffer" "tae buffer"  "cell lysis" "cdna" "dntps" "electrophoresis" "laemmli" "'
global protein_bio `" "pre-cast" "pre-stained" "protein gel stains" "acrylamide/bis solution" "blotting membrane" "chemiluminescent substrate" "protease" "crosslinking reagent" "bioconjugate dye" "antibody" "protein molecular-weight ladder" "western blot" "bca protein assay kit" "bradford protein assay kit" "bovine serum albumin" "protease inhibitor cocktails" "reducing agents" "dtt" "elisa"  "ladder" "'
global treated_products  "$cell_culture $mol_bio $protein_bio"

program main 
    import_suppliers
    foreach t in tfidf {
        select_good_categories, embed(`t')
        clean_raw, embed(`t')
        make_panels, embed(`t')
    }
end

program import_suppliers
    import delimited using ../external/sup/supplier_mapping_final, varn(1) clear 
    rename original_suppliername suppliername
    rename canonical_supplier new_suppliername
    qui {
        foreach k in "xpedx" "rent" "event" "travel" "audio" "xerox"  "acct" "cardinal health 411 inc" ///
            "henry ford health system" "illumina" "sports" "sales" "communications" "printing" ///
            "design" "photography" "music" "education" "john" "robert" "graphics" "management" ///
            "community" "publishing" "environmental" "productions" "marketing" "safety" "hour" "hardware" ///
            "investments" "entertainment" "promotional" "maintenance" "american rock salt" "lowes" "equipment" "mailing" ///
            "fire protection" "price waterhouse coopers" "hp" "radio" "cisco systems" "sanitation strategies" "network solutions" ///
            "college board" "proquest" "hill rom" "painting" "warehouse" "assurance" "blind" "davol" "atricure" "media associates" ///
             "cbord group" "united healthcare" "dimension data" "nwn" "farm" "heating" "drainage" "media" ///
             "aviation" "travel" "airline" "defense" "freight" "lumber" "floor" "clean" "construct" "blackboard" ///
             "oil" "commercial products" "kintetsu" "buhler" "nalco" "truck" "milestone" "eckert and ziegler" "newport"  ///
             "engineering" "spectroglyph"  "backup technology" "gerdau" "datadirect" "network" ///
             "plumbing" "hvac" "seating" "sprinkler" "nortrax" "marine"  "insurance" "campus" ///
             "building" "finance" "fitness" "engineering" "airport" "touring" ///
             "meeting" "commercial" "university" "college" "somanetics" "neurotune" "centerplate" "sport" ///
             "cse" "interiors" "sheraton" "film" "pentax" "fire" "machine" "tko" "brow" "lithographing" ///
            "twitchell" "ibm" "athletic" "lenovo" "immigration" "law enforcement" "school" "hotel" ///
             "publication" "advtsng" "backflow" "lymphedema" "gas" "ferguson enterprise"  "valve" "cargo" ///
            "weld" "flagcraft" "henry schein" "dental" "practicon" "alchip" "semiconductor" ///
            "canyon materials" "photo" "display" "broadcasting" "stevesongs" " press" "bioquell" "gle associates" "medrad" ///
            "psychological association" "mechanical" "3m unitek" "roofing" "print" "repair" "trophies" "trophy" "award" ///
            "cater" "repair" "book" "coffee" "auto" "optical" "beauty" "bldg" "mower" "body shop" "eye supply" "golf"  ///
            "fuel" "cdw government" "lma north america" "hamamatsu" "feed" "techniplast" "percival scientific" "zimmer" ///
            "veterinary" "teleflex" "biomet" "waste" "surgical" "surgery" "anesthesia" "salt" "orfit" "endocare" ///
           "medical" "waterpik" "imaging" "optic" "microscopy" "nurse" "urological" "nano"  "shipment" ///
           "animal" "petroleum" "dermatology" "nano" "environment" "manufacturing" "resort" "uniform" "hospital" ///
           "devices" "architectural" "pools" "use " "packaging" "revenue" "verizon" "art gallery" "team apparel" ///
           "fashion" "gardens" "art suppies" "cellular" "unifirst" "tractor" "toyota" "traffic" "foods"  "deli" "tiger" "thyssenkrupp" "accounting" {
            drop if strpos(new_suppliername, "`k'") > 0
        }
        foreach k in "cem" "na" {
            drop if new_suppliername == "`k'"
        }
    }
    save ../temp/supplier_map, replace 
end

program select_good_categories
    syntax, embed(string)
    import delimited ../external/samp/utdallas_full_report_gatekeeper_tfidf_expert_non_parametric_`embed', clear
    cap rename v1 category
    drop if inlist(category, "macro avg", "weighted avg", "Non-Lab", "accuracy")
    gen treated = 0
    foreach c of global treated_products {
        replace treated = 1 if strpos(category, "`c'") > 0 
    }
    *drop if inlist(category, "recombinant human protein") | strpos(category, "recombinant") > 0 | strpos(category, "growth factor") > 0  | strpos(category, "cell line") > 0 | strpos(category, "small molecule inhibitor") > 0  
    gen keep  = support >= 25 & precision >= 0.8 & recall >= 0.8
    replace keep = 0 if inlist(category, "recombinant human protein") | strpos(category, "recombinant") > 0 | strpos(category, "growth factor") > 0  | strpos(category, "cell line") > 0 | strpos(category, "small molecule inhibitor") > 0  | strpos(category, "thin layer") > 0 | strpos(category, "tem -") > 0  | strpos(category , "syringe")
    save ../temp/categories_`embed', replace
end

program clean_raw
    syntax, embed(string)
    import delimited ../external/samp/govspend_panel_classified_with_non_parametric_`embed'.csv, clear
    merge m:1 agencyname using ../external/unis/final_unis_list, keep(3) nogen
    rename predicted_market category
    replace category = "cryovials" if strpos(clean_desc, "cryo") >0 & strpos(clean_desc, "vial") >0 
    // get rid of negated orders
    gduplicates tag poid clean_desc, gen(dup_order)
    bys poid clean_desc: gegen has_neg = max(qty<0)
    drop if has_neg == 1 & dup_order > 0
    drop if price <= 0 | qty <= 0 | spend <= 0
    drop if category == "Non-Lab"
    drop if category == "unclassified"
    drop if spend > 100000 | price > 100000
    foreach v in "furnace" "vacuum" "lighting" "truck" "pump" "student" ///
        "graduate" "cfx" "table" "library" "appliance" "charger" "dtba1d1" ///
        "gasket"  "reader" "alfalfa" "chemidoc" "rfp" "red cross" ///
        "imaging system" "arena" "dna library" "storm drain" "utilities" ///
        "electricity" "hall site" "insurance" "liability" "deductible" "claim" ///
        "athletic" "wellness" "recreation" "transit" "advertising" "install" ///
        "semester" "guarantee" "ncaa" "newspaper" "conference" "po " "replace" ///
        "building" "bobcat" "spectramax" "notification" "journal" "drainage"  "turnitin" ///
        "thesis" "mail" "credits" "webcard" "s-insert assembly" "messaging" "campus" "pay" "scientist" ///
        "notice" "annual" "firework" "delivery" "upgrade" "bedding" "sequencing" "blanket order" "drain" ///
        "entertainment" "campaign" "textbook" "analysis"  "chair"  "datacenter" "production" "bleacher" ///
        "relocation" "transport" "stainer" "interview" "interviewing" "door" "hardware" "surveY" "program" "expenses" ///
        "health ins" "games" "flights" "game" "residency" "robot" "vehicle" "tournament" "basketball" "ticket" "coordinator" "completion" "lease" ///
        "order" "concrete" "coverslipper" " ins" "for reference" "tractor" "connections" "date" "misc " "course" "review" ///
        "book" "delivered" "deliver" "racquet" "guidewire" "wire" "fitting" "per attached quote" "lamp" "drive" "football" ///
        "nasco" "fluorescent bulb" "edition" "accidence" "teaching" "sport" "timer" "ssd" "screw" "wall" "file" "business" "mesh" ///
        "mask aligner" "karl suss" "procedure" "transmitter" "dues" "ura system" "accessory" "pbs detector" "billed" "monthly" "ethovision" ///
        "generator" "accessories" "handheld" "detector" "basement" "survey" "asbestos" "vicryl plus" "ejector" "maint." ///
        "chamber" {
        drop if strpos(clean_desc, "`v'") > 0
    }
    drop if (strpos(clean_desc, "plate") > 0 | strpos(clean_desc, "card")) & category == "synthetic dna oligonucleotide" 
    merge m:1 suppliername using ../temp/supplier_map, assert(1 2 3) keep(3) nogen
    rename (suppliername new_suppliername) (old_suppliername suppliername)
    drop if mi(suppliername)
    drop if suppliername == "na"
    bys suppliername: gen num_sup_obs = _N
    drop if num_sup_obs == 1
    replace suppliername = "thermo fisher scientific" if suppliername == "possible missions" & strpos(agencyname, "texas") > 0
    bys suppliername: gegen tot_sup_spend = total(spend)
    drop if tot_sup_spend  < 0 
    gen obs_cnt = 1 

    bys category: gen cat_id = _n == 1
    bys category year: gegen cat_yr_obs = total(obs_cnt)
    sum cat_yr_obs if cat_id == 1  , d
    local mean : dis %6.2f r(mean)
    local p25: dis %6.2f r(p25)
    local p50 : dis %6.2f r(p50)
    local p75: dis %6.2f r(p75)
    local sd : dis %6.2f r(sd)
    tw hist cat_yr_obs if cat_id == 1, freq xtitle("Number of Observations per year by Product Market", size(small)) ytitle("Number of Markets", size(small)) ///
        legend(on order(- "Mean: `mean'" "Median: `p50'" "sd: `sd'") pos(1) ring(0))
    graph export ../output/figures/hist_cat_yr_obs.pdf, replace

    drop if cat_yr_obs == 1 
    bys category year: gen cat_yr = _n == 1
    bys category: gegen num_yrs_cat = total(cat_yr)
    keep if num_yrs_cat == 10
    merge m:1 category using ../temp/categories_`embed', assert(1 2 3)  keep(1 3)
    drop if support < 25
    drop if similarity_score <= 0.10 & prediction_source == "Expert Model"
    replace category = subinstr(category, "/","-",.)
    gen raw_price = price
    gen raw_qty = qty
    gen raw_spend = spend 
    replace price = log(price)
    replace qty = log(qty)
    replace spend = log(spend)
    bys category year : gegen spend99= pctile(raw_spend), p(99)
    bys category year : gegen spend1 = pctile(raw_spend), p(1)
    bys category year : gegen price99= pctile(raw_price), p(99)
    bys category year : gegen price1 = pctile(raw_price), p(1)
    drop if raw_spend < spend1 & prediction_source == "Expert Model" & similarity_score < 0.25
    drop if raw_price < price1 & prediction_source == "Expert Model" & similarity_score < 0.25
    drop if raw_spend > spend99 & prediction_source == "Expert Model" & similarity_score < 0.25
    drop if raw_price > price99 & prediction_source == "Expert Model" & similarity_score < 0.25
    drop spend1 spend99 price1 price99
    bys category  : gegen spend99= pctile(raw_spend), p(99)
    bys category  : gegen spend1 = pctile(raw_spend), p(1)
    bys category  : gegen price99= pctile(raw_price), p(99)
    bys category  : gegen price1 = pctile(raw_price), p(1)
    drop if raw_spend < spend1 & prediction_source == "Expert Model" & similarity_score < 0.25
    drop if raw_spend > spend99 & prediction_source == "Expert Model" & similarity_score < 0.25
    drop if raw_price < price1  & prediction_source == "Expert Model" & similarity_score < 0.25
    drop if raw_price > price99 & prediction_source == "Expert Model" & similarity_score < 0.25
    drop spend1 spend99 price1 price99
    preserve
    gcollapse (mean) recall precision support keep , by(category)
    tw kdensity recall || kdensity precision , xlab(, labsize(small)) ylab(, labsize(small)) xtitle("Score (0-1)", size(small)) ytitle("Density", size(small)) xline(0.8, lcolor(gs5) lpattern(dash)) ///
        legend(on order(1 "Recall" 2 "Precision") pos(11) ring(0))
    graph export ../output/figures/recall_precision_density_`embed'.pdf, replace
    binscatter2 recall support, xlab(, labsize(small)) ylab(, labsize(small)) ///
        xtitle("Support", size(small)) ytitle("Recall", size(small))
    graph export ../output/figures/recall_support_`embed'.pdf, replace
    binscatter2 precision support, xlab(, labsize(small)) ylab(, labsize(small)) ///
        xtitle("Precision", size(small)) ytitle("Recall", size(small))
    graph export ../output/figures/precision_support_`embed'.pdf, replace
    restore
    drop if precision <0.2 | recall < 0.2
    sum raw_spend 
    local tot_spend = r(sum)
    sum raw_spend if keep == 1
    di "Total spend in matched categories: " r(sum) " out of " `tot_spend' " (" string(r(sum)/`tot_spend'*100) "%)"
    count
    local tot_obs = r(N)
    count if keep  == 1
    di "Total observations in matched categories: " r(N) " out of " `tot_obs' " (" string(r(N)/`tot_obs'*100) "%)"
    save ../output/full_item_level_`embed', replace

    keep if keep == 1 
    drop num_yrs orgid
    bys suppliername year: gen supplier_yr = _n == 1
    bys suppliername: gegen tot_supplier_obs = total(obs_cnt) 
    bys suppliername: gen sup_id = _n == 1
    gegen uni_id = group(agencyname)
    gegen supplier_id = group(suppliername)
    bys category : gen num_times = _N
    bys supplier_id category year: gegen total_spend = total(raw_spend)
    bys category year: gegen category_spend = total(raw_spend)
    bys category supplier_id year: gen num_suppliers_id = _n == 1
    bys category year: gegen num_suppliers = total(num_suppliers) 
    save ../temp/item_level_`embed', replace
end

program make_panels
    syntax, embed(string)
    use ../temp/item_level_`embed', clear
    gegen mkt = group(category)
    preserve
    collapse (max) treated (mean) *price num_suppliers (sum) obs_cnt *raw_qty *raw_spend (firstnm) suppliername mkt , by(supplier_id category year)
    save ../output/supplier_category_yr_`embed', replace
    preserve
    // quick fbs
    keep if category == "us fbs"
    replace suppliername = "thermo fisher scientific" if suppliername == "hyclone lab" & year <= 2014
    replace suppliername = "atcc" if suppliername == "american type culture collec"
    replace suppliername = "ge healthcare" if suppliername == "hyclone lab" & year > 2014
    bys suppliername year: gen sup_year = _n == 1
    bys suppliername : egen num_yrs = total(sup_year)
    keep if num_yrs == 10  
    tw line raw_price year , by(suppliername) xline(2014) xlab(2010(2)2019) xtitle("Year", size(small)) ytitle("Price of FBS", size(small)) legend(off pos(1) ring(0))
    graph export ../output/fbs_prices.pdf, replace
    tw line raw_spend year , by(suppliername) xline(2014) xlab(2010(2)2019) xtitle("Year", size(small)) ytitle("Spend of FBS", size(small)) legend(off pos(1) ring(0))
    graph export ../output/fbs_spend.pdf, replace
    tw line raw_qty year , by(suppliername) xline(2014) xlab(2010(2)2019) xtitle("Year", size(small)) ytitle("QTY of FBS", size(small)) legend(off pos(1) ring(0))
    graph export ../output/fbs_qty.pdf, replace
    restore

    gen pre_period = year < 2014
    keep if inrange(year, 2012,2013) | inrange(year, 2015, 2016)
    collapse (sum) raw_spend obs_cnt (firstnm) suppliername treated , by(supplier_id category pre_period)
    bys category: gegen total_spend = total(raw_spend)
    gen mkt_shr = raw_spend/total_spend * 100 
    gen life_tech = mkt_shr if suppliername == "life technologies"
    gen thermo = mkt_shr if suppliername == "thermo fisher scientific"
    bys category pre_period (life_tech): replace life_tech = life_tech[_n-1] if mi(life_tech) 
    bys category pre_period (thermo): replace thermo = thermo[_n-1] if mi(thermo) 
    gen simulated_hhi = 2 * life_tech * thermo if pre_period == 1
    bys category (simulated_hhi): replace simulated_hhi = simulated_hhi[_n-1] if mi(simulated_hhi) & pre_period == 0
    replace mkt_shr = mkt_shr * mkt_shr
    gcollapse (sum) obs_cnt hhi = mkt_shr (firstnm) simulated_hhi treated mkt, by(category pre_period)
    ashsort category -pre_period
    by category : gen delta_hhi = hhi - hhi[_n-1] if pre_period == 0
    bys category: gegen tot_cnt = total(obs_cnt)
    bys category (delta_hhi): replace delta_hhi = delta_hhi[_n-1] if mi(delta_hhi) 
    gcontract category simulated_hhi delta_hhi treated tot_cnt
    drop _freq
    gisid category
    save ../output/category_hhi_`embed', replace    
    restore

    bys category: gegen cat_spend = total(raw_spend) 
    bys category: gegen tot_obs = total(obs_cnt)
    gen obs_2013 = tot_obs if year == 2013
    gen spend_2013 = cat_spend if year == 2013
    hashsort category spend_2013
    bys category : replace spend_2013 = spend_2013[_n-1] if mi(spend_2013)
    hashsort category obs_2013
    bys category : replace obs_2013 = obs_2013[_n-1] if mi(obs_2013)

    gen avg_log_spend = spend
    gen avg_log_qty = qty 
    gen avg_log_price = price 

    save ../output/item_level_`embed', replace
    preserve
    collapse (max) treated (mean) raw_spend raw_price raw_qty avg_log_price avg_log_spend avg_log_qty num_suppliers precision recall spend_2013 (sum) obs_cnt (firstnm) suppliername agencyname mkt , by(uni_id category year)
    save ../output/uni_category_yr_`embed', replace
    restore
    collapse (max) treated (mean) raw_spend raw_price raw_qty avg_log_price avg_log_spend avg_log_qty num_suppliers precision recall spend_2013  (firstnm) mkt (sum) obs_cnt , by(category year)
    save "../output/category_yr_`embed'", replace 
    keep if category == "us fbs"
    tw line raw_price year , xline(2014) xlab(2010(2)2019) xtitle("Year", size(small)) ytitle("Price of FBS", size(small)) legend(off pos(1) ring(0))
    graph export ../output/figures/fbs_price_over_time.pdf, replace      
    tw line raw_spend year , xline(2014) xlab(2010(2)2019) xtitle("Year", size(small)) ytitle("Spend of FBS", size(small)) legend(off pos(1) ring(0))
    graph export ../output/figures/fbs_spend_over_time.pdf, replace
    tw line raw_qty year , xline(2014) xlab(2010(2)2019) xtitle("Year", size(small)) ytitle("QTY of FBS", size(small)) legend(off pos(1) ring(0))           
    graph export ../output/figures/fbs_qty_over_time.pdf, replace 
end

**
main
