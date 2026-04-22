set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main
    foreach t in tfidf {
        clean_raw, embed(`t')
        qui make_panels, embed(`t')
    }
end

program clean_raw
    syntax, embed(string)
    use ../external/price_samp/first_stage_data_`embed', clear
    gen purchase_date = date(date, "DMY")
    replace purchase_date = date(date, "YMD") if mi(purchase_date)
    gen year = year(purchase_date)
    keep if inrange(year, 2010,2019)
    drop if strpos(agencyname, "medical") > 0
    qui count
    local total_obs = r(N)
    qui sum spend, d
    local total_spend : di %16.0f r(sum)
    di "[All purchases EVER] N:  `total_obs' Total Spend:  `total_spend'"

    qui {
        merge m:1 suppliername using ../external/sup/lifescience_supplier_map, assert(1 2 3) keep(3) nogen
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
        replace category = "cryovials" if strpos(clean_desc, "cryo") >0 & strpos(clean_desc, "vial") >0 
        replace category = "us fbs" if strpos(clean_desc, "fetal")>0& strpos(clean_desc, "bovine")>0 & strpos(clean_desc, "serum")>0
        replace category = "us fbs" if strpos(clean_desc, "calf")>0& strpos(clean_desc, "bovine")>0 & strpos(clean_desc, "serum")>0
        replace category = "elisa kits" if strpos(clean_desc, "duoset") >0 
        // drop nonsense negatives
        drop if price <= 0 | qty < 1 | spend <= 0
        // filter to consumables
        drop if category == "Non-Lab"
        drop if category == "unclassified"
        replace spend = price * qty  if qty != 1
        replace qty = spend / price if qty == 1
        drop if similarity_score == 0
    }
    qui count
    local total_obs = r(N)
    qui sum spend, d
    local total_spend : di %16.0f r(sum)
    di "[ML Consumables & Negative Orders] N: `total_obs' Total Spend: `total_spend'"

    qui {
        drop if spend > 100000 | price > 100000 | qty > 100000
        foreach v in "graduate " "table" "library" "reader" "po " "replace" ///
            "thesis" "pay" "delivery" "sequencing" "analysis" "transport" "lease" "order" " ins" "date" ///
            "delivered" "deliver" "wire" "fitting" "lamp" "nasco" "sport" ///
            "screw" "wall" "file" "mesh" "chamber" "analyzer" "oven" ///
            "fume hood" "biosafety cabinet" "wo#" "construction" "flooring" ///
            "lab gases" "glucarpidase" "voraxaze" "supplement issue" ///
            "ajph" "phssr" "capillarys" "analyses" "datalogger" ///
            "professionalism" ".org" "lcmsms" "pre-owned" "enterprise" ///
            "dialysis" "tower" "kelvin" "lithography" "seal" ///
            "array" "adverstise" {
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
        foreach v in "animal - " "fees - " "electronics - " "instrument" "office supplies" "lab furniture" "waste disposal" "equipment" "furniture" "software" ///
          "toolkit" "clamp" "tool" "tubing" "random" "unclear" "wire" "towel" "irrelevant chemicals" "oring" "caps" "gas" "first-aid" "first aid" "desk" "chair" "brushes" "trash" "cleaner" ///
          "cotton ball" "bundle of products" "tape" "miscellaneous" "clips" "flint" "accessories" "stands" "batteries" "ear protection" "apron" "pots" "pants" "stoppers" "closures" "rings" ///
          "mortar" "pestle" "support" "trays" "applicators and swabs" "bundle" "sequencing" "tem - " "nonlab" {
            drop if strpos(category, "`v'") > 0
        }
    }
    qui count
    local total_obs = r(N)
    qui sum spend, d
    local total_spend : di %16.0f r(sum)
    di "[Remove Possible Non-consumables] N: `total_obs' Total Spend: `total_spend'"
    qui {
        merge m:1 category using ../external/categories/categories_`embed', assert(1 2 3)  keep(1 3) nogen
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
        drop if raw_spend > spend99
        drop if raw_price > price99
        drop if raw_price < price1
        drop if raw_qty < qty1
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
    qui sum raw_spend, d
    local total_spend : di %16.0f r(sum)
    di "[Windsorize] N: `total_obs' Total Spend: `total_spend'"

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
    drop if support < 5  
    qui count
    local total_obs = r(N)
    qui sum raw_spend, d
    local total_spend : di %16.0f r(sum)
    di "[bad ml categories] N: `total_obs' Total Spend: `total_spend'"
    
    qui {
        gen obs_cnt = 1
        bys suppliername year: gen supplier_yr = _n == 1
        bys suppliername: gegen tot_supplier_obs = total(obs_cnt) 
        bys suppliername: gen sup_id = _n == 1
        drop if tot_supplier_obs == 1
        drop supplier_yr tot_supplier_obs sup_id
        gegen uni_id = group(agencyname)
        gegen supplier_id = group(suppliername)
        bys supplier_id category year: gegen total_sup_spend = total(raw_spend)
        bys uni_id year: gen cnt = _n == 1
        bys uni_id : egen num_years = total(cnt)
        bys uni_id : egen min_year = min(year)
        keep if num_years == 10 | (num_years == 9 & min_year == 2011)
        gegen mkt = group(category)
        drop num_years min_year cnt 
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
        gegen uni_mkt = group(uni_id mkt)
        bys uni_mkt : egen min_year = min(year)
        bys uni_mkt : egen max_year = max(year)
        keep if min_year < 2014 & max_year > 2014
    }

    qui count
    local total_obs = r(N)
    qui sum raw_spend, d
    local total_spend : di %16.0f r(sum)
    di "[Balance Cat-years] N: `total_obs' Total Spend: `total_spend'"
    qui sum raw_spend 
    local tot_spend = r(sum)
    qui sum raw_spend if keep == 1
    di "Total spend in matched categories: " r(sum) " out of " `tot_spend' " (" string(r(sum)/`tot_spend'*100) "%)"
    qui sum raw_spend if keep == 1 & tier3 == 0
    di "Total spend in matched categories minus tier3: " r(sum) " out of " `tot_spend' " (" string(r(sum)/`tot_spend'*100) "%)"
    qui count
    local tot_obs = r(N)
    qui count if keep  == 1
    di "Total observations in matched categories: " r(N) " out of " `tot_obs' " (" string(r(N)/`tot_obs'*100) "%)"
    qui count if keep  == 1 & tier3 == 0
    di "Total observations in matched categories minus tier3: " r(N) " out of " `tot_obs' " (" string(r(N)/`tot_obs'*100) "%)"
    save ../output/full_item_level_`embed', replace
end

program make_panels
    syntax, embed(string)
    use ../output/full_item_level_`embed', clear
    collapse (mean) spend_2013 obs_2013 recall precision support treated tier1 tier2 tier3 keep item_price = raw_price avg_log_price = price avg_log_spend = spend avg_log_qty = qty (sum) raw_spend raw_qty obs_cnt (firstnm) mkt agencyname, by(category year uni_id)
    gen raw_price = raw_spend/raw_qty
    gen log_raw_price = ln(raw_price)
    gen log_raw_qty = ln(raw_qty)
    gen log_raw_spend = ln(raw_spend)
    save ../output/full_uni_category_yr_`embed', replace

    use ../output/full_item_level_`embed', clear
    collapse (max) treated (mean) precision recall support tier1 tier2 tier3 keep spend_2013 obs_2013 item_price = raw_price avg_log_price = price avg_log_spend = spend avg_log_qty = qty (firstnm) mkt (sum) raw_spend raw_qty obs_cnt , by(category year)
    gen raw_price = raw_spend/raw_qty
    gen log_raw_spend = ln(raw_spend)
    gen log_raw_qty = ln(raw_qty)
    gen log_raw_price = ln(raw_price)
    save "../output/full_category_yr_`embed'", replace 

    use ../output/full_item_level_`embed', clear
    keep if keep == 1  
    cap drop uni_mkt min_year max_year
    gegen uni_mkt = group(uni_id mkt)
    bys uni_mkt : egen min_year = min(year)
    bys uni_mkt : egen max_year = max(year)
    keep if min_year < 2014 & max_year > 2014
    save ../output/item_level_`embed', replace
   
    preserve
    collapse (max) treated (sum) obs_cnt *raw_spend (firstnm) suppliername mkt , by(supplier_id category year)
    save ../output/supplier_category_yr_`embed', replace
    gen pre_period = year < 2014
    keep if inrange(year, 2011,2013) | inrange(year, 2015, 2017)
    collapse (sum) raw_spend obs_cnt (firstnm) suppliername treated , by(supplier_id category pre_period)
    bys category pre_period: gegen total_spend = total(raw_spend)
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


    preserve
    collapse (max) treated (sum) raw_spend raw_qty obs_cnt (mean) spend_2013 obs_2013 precision recall support tier1 tier2 tier3 item_price = raw_price avg_log_price = price avg_log_spend = spend avg_log_qty = qty (firstnm) agencyname mkt , by(uni_id category year)
    gen raw_price = raw_spend/raw_qty
    gen log_raw_spend = ln(raw_spend)
    gen log_raw_qty = ln(raw_qty)
    gen log_raw_price = ln(raw_price)
    save ../output/uni_category_yr_`embed', replace
    restore

    collapse (max) treated (mean) precision recall support tier1 tier2 tier3 spend_2013 obs_2013 item_price = raw_price avg_log_price = price avg_log_spend = spend avg_log_qty = qty (firstnm) mkt (sum) raw_spend raw_qty obs_cnt , by(category year)
    gen raw_price = raw_spend/raw_qty
    gen log_raw_spend = ln(raw_spend)
    gen log_raw_qty = ln(raw_qty)
    gen log_raw_price = ln(raw_price)
    save "../output/category_yr_`embed'", replace 
end

**
main
