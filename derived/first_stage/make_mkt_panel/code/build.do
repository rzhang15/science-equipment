set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

global cc_media `" "dmem" "rpmi" "emem" "mem" "bme" "imdm" "hams f12" "mccoys" "leibovitz" "medium 199" "optimem" "insect cell media" "stem cell media" "neural media" "neurobasal medium" "keratinocyte tissue media" "begm" "megem" "cardiomyocyte tissue media" "liver media" "corneal tissue media" "basal media" "proprietary media" "custom media" "hepatocyte wash medium" "'
global cc_sera `" "fbs" "serum" "sera" "bovine growth serum" "'
global sirna `" "synthetic sirna" "sirna transfection reagents" "sirna transfection medium" "sirna dilution buffer" "sirna buffer" "gene-specific rnai reagents" "synthetic shrna" "'
global magnetic_beads `" "magnetic polystyrene beads" "streptavidin magnetic polystyrene beads" "magnetic ip kit" "magnetic bead-based mrna selection kit"  "'
global tier1 "$cc_media $cc_sera $sirna $magnetic_beads"

global pcr_reagents `" "taq polymerase" "high-fidelity dna polymerase" "hot start dna polymerase" "high-fidelity hot start dna polymerase" "dna polymerase i" "dntps" "pcr systems" "dye-based qpcr systems" "probe-based qpcr systems" "probe-based rt-qpcr systems" "rt-pcr systems" "high-fidelity pcr systems" "hot start pcr systems" "high-fidelity hot start pcr systems" "long template pcr systems" "tissue pcr systems" "qpcr beads" "qrt-pcr titration kit" "pre amplification kits" "pcr barcoding expansion" "taq buffers" "specialized pcr reaction buffer" "'
global rt_cdna `" "reverse transcriptase" "first-strand cdna synthesis systems" "microrna reverse transcription kit" "'
global cloning `" "restriction enzymes" "nucleic acid modifying enzymes" "seamless cloning kits" "blunt-end cloning kits" "ta cloning kits" "gateway cloning kits" "rapid dna ligation kits" "site-directed mutagenesis systems" "plasmid vectors" "chemically competent cells" "electrocompetent cells" "taq dna ligases" "'
global electrophoresis `" "pre-cast tris-glycine gels" "pre-cast bis-tris gels" "pre-cast tbe gels" "pre-cast tris-tricine gels" "polyacrylamide gels casting kit" "acrylamide/bis solution" "acrylamide" "temed" "gel electrophoresis power supplies" "vertical electrophoresis systems" "horizontal electrophoresis systems" "'
global western_blot `" "pvdf blotting membranes" "nitrocellulose blotting membranes" "precut nitrocellulose transfer blotting packs" "precut pvdf transfer blotting packs" "chemiluminescent substrates" "western blot transfer buffers" "western blot blockers" "western blot stripping buffers" "western blot boxes" "western blot pen" "western blot enhancers" "western blot rollers" "gel blotting papers" "chemiluminescence western blotting kit" "north/south chemiluminescent detection kit" "'
global mw_standards `" "unstained dna ladders" "pre-stained dna ladders" "unstained rna ladders" "pre-stained rna ladders" "pre-stained protein molecular-weight ladder" "unstained protein molecular-weight ladder" "'
global protein_mod `" "crosslinking reagents" "protein modifying enzymes" "protein labeling kits" "pegylation reagents" "bioconjugation reagents" "bioconjugate dye" "'
global protein_assays `" "protein gel stains" "bca protein assay kit" "bradford protein assay kit" "total protein assay kit" "modified lowry protein assay kit" "'
global transfection `" "transfection reagents" "transfection kits" "'
global na_purification `" "column-based" "spin columns" "rna extraction reagents" "magnetic-bead based purification kit" "magnetic bacterial rna purification kit" "rna stabilization reagent" "liquid-based dna plasmid purification kit" "'
global dyes `" "fluorophore - general" "fluorophore - bioconjugate dyes" "quantum dots" "nucleic acid gel stains" "'
global oligo_synthesis `" "synthetic dna oligonucleotide" "synthetic rna oligonucleotide" "synthetic dna primers" "synthetic dsdna gene fragment" "synthetic gene constructs" "synthetic dual-labeled probe" "synthetic bacterial expression plasmids" "synthetic mammalian expression plasmids" "'
global tier2 "$pcr_reagents $rt_cdna $cloning $electrophoresis $western_blot $mw_standards $protein_mod $protein_assays $transfection $na_purification $dyes $oligo_synthesis"

global cc_supplements `" "cell culture nutritional supplements" "cell culture antibiotics" "cell culture dissociation reagents" "cell culture coating reagents" "cell culture surface adhesion promotors" "cell culture scaffold" "cell recovery solution" "'
global cc_plastic `" "cell culture plates" "cell culture flasks" "cell culture dishes" "cell culture tubes" "cell culture inserts" "cell culture slides" "specialty surface cellware" "chamber slide systems" "chambered coverslip" "pre-coated dishes" "cryovials" "media bottles" "cell scrapers" "cell strainers" "cell spreaders" "'
global cc_buffers `" "phosphate-buffered saline (pbs) buffer" "dpbs" "hanks" "'
global cell_lines `" "cell line" "bacterial strain" "ecoli" "'
global antibodies `" "monoclonal primary antibody" "polyclonal primary antibody" "polyclonal secondary antibody" "monoclonal secondary antibody" "isotype control" "'
global recomb_proteins `" "recombinant human protein" "recombinant mouse protein" "recombinant proteins" "'
global inhibitors `" "protease inhibitor cocktails" "protease inhibitors" "phosphatase inhibitor cocktails" "reducing agents - dtt" "reducing agents - tcep" "'
global cell_lysis `" "cell lysis buffers" "cell lysis detergents" "cell lysis enzymes" "cell lysis kits" "cell lysis tubes" "tissue lysis buffers" "cell lysis rt-qpcr kits" "subcellular protein fractionation kit" "'
global cell_bio_assays `" "cell viability kits" "viability/cytotoxicity kit" "apoptosis detection kits" "cell proliferation kits" "cellular metabolism assay kits" "ldh cytotoxicity assay" "live cell imaging reagents" "viability stains" "phalloidin conjugates" "cell stimulation cocktail" "cell imaging signal enhancer" "'
global protein_purif `" "his-tag imac affinity resins" "tag-binding affinity resins" "imac columns" "desalting columns" "spin desalting columns" "gravity flow desalting columns" "endotoxin removal resins" "streptavidin-biotin binding products" "avidin products" "column-based protein purification kit" "'
global electro_buffers `" "tris-glycine-sds (tgs) buffer" "tris-glycine buffer" "tbe buffer" "tris-acetate-edta (tae) buffer" "mes-sds buffer" "mops-sds buffer" "tbe-urea sample buffer" "tris-tricine-sds buffer" "laemmli sample buffer" "lds sample buffer" "native-page sample buffer" "'
global molbio_enzymes `" "rnase inhibitors" "rnase" "rnase control reagent" "nuclease enzymes" "nuclease decontaminant" "proteases" "dnase/rnase-free & molecular-biology-grade water" "'
global na_labeling `" "nucleic acid labeling/detection kits" "dna labeling kit" "'
global pcr_consumables `" "pcr tubes" "pcr tube strips" "pcr tube strip caps" "'
global ivt `" "t7 in vitro transcription kit" "in-vitro translation systems" "rabbit reticulocyte lysate system" "'
global bsa `" "bovine serum albumin" "'
global tier3 "$cc_supplements $cc_plastic $cc_buffers $cell_lines $antibodies $recomb_proteins $inhibitors $cell_lysis $cell_bio_assays $protein_purif $electro_buffers $molbio_enzymes $na_labeling $pcr_consumables $ivt $bsa"

global treated "$tier1 $tier2 $tier3"

program main
    qui import_suppliers
    foreach t in tfidf {
        qui merge_price_data, embed(`t')
        qui select_good_categories, embed(`t')
        clean_raw, embed(`t')
        qui make_panels, embed(`t')
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
           "fashion" "gardens" "art suppies" "cellular" "unifirst" "tractor" "toyota" "traffic" "foods"  "deli" "tiger" "thyssenkrupp" "accounting" ///
           "blackboard inc" "apex systems" "simplex grinnell" "mci enterpise" {
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
    gen tier1 = 0
    gen tier2 = 0
    gen tier3 = 0
    foreach c of global tier1 {
        replace tier1 = 1 if strpos(category, "`c'") > 0 
    }
    foreach c of global tier2 {
        replace tier2 = 1 if strpos(category, "`c'") > 0 
    }
    foreach c of global tier3 {
        replace tier3 = 1 if strpos(category, "`c'") > 0 
    }
    foreach c of global treated {
        replace treated = 1 if strpos(category, "`c'") > 0 
    }
    *drop if inlist(category, "recombinant human protein") | strpos(category, "recombinant") > 0 | strpos(category, "growth factor") > 0  | strpos(category, "cell line") > 0 | strpos(category, "small molecule inhibitor") > 0  
    gen keep  = (support >= 25 & precision >= 0.85 & recall >= 0.85) | (support >= 10 & precision >= 0.9 & recall >=0.75) 
    save ../temp/categories_`embed', replace
end


program clean_raw
    syntax, embed(string)
    use ../external/merged/first_stage_data_`embed', clear
    qui count
    local total_obs = r(N)
    qui sum spend, d
    local total_spend : di %16.0f r(sum)
    di "[All purchases EVER] N:  `total_obs' Total Spend:  `total_spend'"

    qui {
        merge m:1 suppliername using ../temp/supplier_map, assert(1 2 3) keep(3) nogen
        rename (suppliername new_suppliername) (old_suppliername suppliername)
        drop if mi(suppliername)
        drop if suppliername == "na"
        bys suppliername: gen num_sup_obs = _N
        drop if num_sup_obs == 1
        replace suppliername = "thermo fisher scientific" if suppliername == "possible missions" & strpos(agencyname, "texas") > 0
        bys suppliername: gegen tot_sup_spend = total(spend)
        drop if tot_sup_spend  < 0 
    }
    qui count
    local total_obs = r(N)
    qui sum spend, d
    local total_spend : di %16.0f r(sum)
    di "[Supplier Cut]  N: `total_obs' Total Spend: `total_spend'"

    qui {
        rename predicted_market category
        replace category = "cryovials" if strpos(clean_desc, "cryo") >0 & strpos(clean_desc, "vial") >0 
        // get rid of negated orders these are returns
        gduplicates tag poid clean_desc, gen(dup_order)
        bys poid clean_desc: gegen has_neg = max(qty<0)
        drop if has_neg == 1 & dup_order > 0
        // drop nonsense negatives
        drop if price <= 0 | qty <= 0 | spend <= 0
        // filter to consumables
        drop if category == "Non-Lab"
        drop if category == "unclassified"
        replace qty = spend / price if qty == 1
        replace spend = price * qty 
    }
    qui count
    local total_obs = r(N)
    qui sum spend, d
    local total_spend : di %16.0f r(sum)
    di "[ML Consumables & Negative Orders] N: `total_obs' Total Spend: `total_spend'"

    qui {
        drop if spend > 100000 | price > 100000
        foreach v in "furnace" "vacuum" "lighting" "truck" "pump" "student" ///
            "graduate " "cfx" "table" "library" "appliance" "charger" "dtba1d1" ///
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
            "chamber" "2010" "2011" "2012" "2013" "2014" "2015" "2016" "2017" "2018" "2019" "etching" ///
            "development of" "steam distr" ///
            "analyzer" "spectrometer" "cytometer" "centrifuge" "incubator" "autoclave" ///
            "freezer" "refrigerator" "oven" "microscope" "fume hood" "biosafety cabinet" ///
            "wo#" "dining" "union up" "renovation" "construction" "flooring" ///
            "glucarpidase" "voraxaze" ///
            "supplement issue" "ajph" "phssr" ///
            "capillarys" "droplet digital" {
            drop if strpos(clean_desc, "`v'") > 0
        }
        drop if (strpos(clean_desc, "plate") > 0 | strpos(clean_desc, "card")) & category == "synthetic dna oligonucleotide"
        // drop borderline terms only when model confidence is low
        foreach v in "service" "repair" "maintenance" "consulting" "training" ///
            "rental" "subscription" "license" "software" "warranty" "support contract" ///
            "calibration" "installation" "shipping" "freight" "quote" "estimate" ///
            "contract" "agreement" "professional" "labor" "hourly" {
            drop if strpos(clean_desc, "`v'") > 0 & prediction_source == "Expert Model" & similarity_score < 0.20
        }
    }
    qui count
    local total_obs = r(N)
    qui sum spend, d
    local total_spend : di %16.0f r(sum)
    di "[Remove Possible Non-consumables] N: `total_obs' Total Spend: `total_spend'"

    qui {
        gen obs_cnt = 1 
        bys category: gen cat_id = _n == 1
        bys category year: gegen cat_yr_obs = total(obs_cnt)
        bys category year: gen cat_yr = _n == 1
        bys category: gegen num_yrs_cat = total(cat_yr)
        keep if num_yrs_cat == 10
    }
    qui count
    local total_obs = r(N)
    qui sum spend, d
    local total_spend : di %16.0f r(sum)
    di "[Balance Cat-years] N: `total_obs' Total Spend: `total_spend'"
    
    qui {
        merge m:1 category using ../temp/categories_`embed', assert(1 2 3)  keep(1 3) nogen
    *    drop if support < 25
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
        bys category year : gegen qty99= pctile(raw_qty), p(99)
        bys category year : gegen qty1 = pctile(raw_qty), p(1)
        bys category year : gegen price99= pctile(raw_price), p(99)
        bys category year : gegen price1 = pctile(raw_price), p(1)
        drop if raw_spend < spend1
        drop if raw_price < price1
        drop if raw_qty < qty1
        drop if raw_spend > spend99
        drop if raw_price > price99
        drop if raw_qty > qty99
        drop spend1 spend99 price1 price99 qty1 qty99
        bys category  : gegen spend99= pctile(raw_spend), p(99)
        bys category  : gegen spend1 = pctile(raw_spend), p(1)
        bys category  : gegen qty99= pctile(raw_qty), p(99)
        bys category  : gegen qty1 = pctile(raw_qty), p(1)
        bys category  : gegen price99= pctile(raw_price), p(99)
        bys category  : gegen price1 = pctile(raw_price), p(1)
        drop if raw_spend < spend1
        drop if raw_spend > spend99
        drop if raw_qty < qty1
        drop if raw_qty > qty99
        drop if raw_price < price1
        drop if raw_price > price99
        drop spend1 spend99 price1 price99 qty1 qty99
    }
    qui count
    local total_obs = r(N)
    qui sum spend, d
    local total_spend : di %16.0f r(sum)
    di "[Windsorize] N: `total_obs' Total Spend: `total_spend'

    qui {
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
    } 
    *drop if precision <0.2 | recall < 0.2
    qui sum raw_spend 
    local tot_spend = r(sum)
    qui sum raw_spend if keep == 1
    di "Total spend in matched categories: " r(sum) " out of " `tot_spend' " (" string(r(sum)/`tot_spend'*100) "%)"
    qui count
    local tot_obs = r(N)
    qui count if keep  == 1
    di "Total observations in matched categories: " r(N) " out of " `tot_obs' " (" string(r(N)/`tot_obs'*100) "%)"
    save ../output/full_item_level_`embed', replace

    keep if keep == 1 
    qui {
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
    }
end

program make_panels
    syntax, embed(string)
    use ../temp/item_level_`embed', clear
    bys uni_id year: gen cnt = _n == 1
    bys uni_id : egen num_years = total(cnt)
    drop if num_years != 10
    gegen mkt = group(category)
   
    preserve
    collapse (max) treated (mean) *price num_suppliers (sum) obs_cnt *raw_qty *raw_spend (firstnm) suppliername mkt , by(supplier_id category year)
    save ../output/supplier_category_yr_`embed', replace
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
    hashsort category -pre_period
    by category : gen delta_hhi = hhi - hhi[_n-1] if pre_period == 0
    bys category: gegen tot_cnt = total(obs_cnt)
    bys category (delta_hhi): replace delta_hhi = delta_hhi[_n-1] if mi(delta_hhi) 
    gcontract category simulated_hhi delta_hhi treated tot_cnt
    drop _freq
    gisid category
    save ../output/category_hhi_`embed', replace    
    restore

    bys category year: gen yr_cnt = _n == 1
    cap drop num_years
    bys category : egen num_years = total(yr_cnt)
    drop yr_cnt
    drop if num_years != 10
    bys category: gegen cat_spend = total(raw_spend) 
    bys category: gegen tot_obs = total(obs_cnt)
    gen obs_2013 = tot_obs if year == 2013
    gen spend_2013 = cat_spend if year == 2013
    hashsort category spend_2013
    bys category : replace spend_2013 = spend_2013[_n-1] if mi(spend_2013)
    hashsort category obs_2013
    bys category : replace obs_2013 = obs_2013[_n-1] if mi(obs_2013)
    gen avg_log_price = price 
    save ../output/item_level_`embed', replace

    preserve
    collapse (max) treated (sum) raw_spend raw_qty obs_cnt (mean) avg_log_price num_suppliers precision recall spend_2013 (firstnm) suppliername agencyname mkt , by(uni_id category year)
    gen raw_price = raw_spend/raw_qty
    gen log_raw_spend = ln(raw_spend)
    gen log_raw_qty = ln(raw_qty)
    gen log_raw_price = ln(raw_price)
    save ../output/uni_category_yr_`embed', replace
    restore

    collapse (max) treated (mean) avg_log_price num_suppliers precision recall spend_2013  (firstnm) mkt (sum) raw_spend raw_qty obs_cnt , by(category year)
    gen raw_price = raw_spend/raw_qty
    gen log_raw_spend = ln(raw_spend)
    gen log_raw_qty = ln(raw_qty)
    gen log_raw_price = ln(raw_price)
    save "../output/category_yr_`embed'", replace 

    use ../output/uni_category_yr_`embed', clear
    keep if category == "us fbs"
    bys uni_id: gen num_years = _N
    keep if num_years == 10
    collapse (sum) raw_spend raw_qty (mean) raw_price , by(year)
    tw line raw_price year , xline(2014) xlab(2010(2)2019) xtitle("Year", size(small)) ytitle("Price of FBS", size(small)) legend(off pos(1) ring(0))
    graph export ../output/figures/fbs_price_over_time.pdf, replace      
    tw line raw_spend year , xline(2014) xlab(2010(2)2019) xtitle("Year", size(small)) ytitle("Spend of FBS", size(small)) legend(off pos(1) ring(0))
    graph export ../output/figures/fbs_spend_over_time.pdf, replace
    tw line raw_qty year , xline(2014) xlab(2010(2)2019) xtitle("Year", size(small)) ytitle("QTY of FBS", size(small)) legend(off pos(1) ring(0))           
    graph export ../output/figures/fbs_qty_over_time.pdf, replace 
end

**
main
