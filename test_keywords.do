set more off
use category year product_desc clean_desc price similarity_score ///
    using /n/home02/cxu75/sci_eq/derived/first_stage/make_mkt_panel/output/full_item_level_tfidf.dta if ///
    inlist(category, "human serum", "crystallizing dishes", "rectangular carboys", "nitrogen", "bacterial selection antibiotics - rifampicin", "storage jars") | ///
    inlist(category, "potassium acetate", "carbon dioxide", "depc", "sodium sulfate", "colorimetric substrates - onpg", "ammonium sulfate") | ///
    inlist(category, "paraffin", "thrombin", "colorimetric substrates - dab", "chromatography paper", "flash chromatography columns - silica gel", "cell lysis detergents - digitonin") | ///
    inlist(category, "cell culture antibiotics - zeocin", "dewar flasks", "drug - anticoagulant", "direct pcr lysis reagents", "lds sample buffer"), clear
keep if inrange(year, 2010, 2018)
rename price log_price
gen kept = 1

* === Apply category-specific keyword filters ===
* CARBON DIOXIDE: anatomical/stem cell/bone-related
foreach v in "bone " "marrow" "skull" "stem cell" "graft tiss" "ostase" "decalcified" "mesenchymal" "mscs" {
    replace kept = 0 if category == "carbon dioxide" & strpos(clean_desc, "`v'") > 0
}

* DIRECT PCR LYSIS REAGENTS: construction/paint primer, medical needles
foreach v in "plaster" "primer c-" "gallon pail" "catheter" "butterfly needle" "infusion" "5# pail" {
    replace kept = 0 if category == "direct pcr lysis reagents" & strpos(clean_desc, "`v'") > 0
}

* STORAGE JARS: drierite, pigments, antibodies caught on "jar"
foreach v in "jarid" "drierite" "pigment" "anitbody" "antibody" {
    replace kept = 0 if category == "storage jars" & strpos(clean_desc, "`v'") > 0
}

* COLORIMETRIC DAB: pharmacopoeia-grade other chemicals (DAB = Deutsches Arzneibuch)
foreach v in "extra pure dab" "xtra pure dab" "ph. eur" "ph. franc" "ph. eu" {
    replace kept = 0 if category == "colorimetric substrates - dab" & strpos(clean_desc, "`v'") > 0
}

* CRYSTALLIZING DISHES: non-crystallizing items
foreach v in "non-crystallizing" "polishing" {
    replace kept = 0 if category == "crystallizing dishes" & strpos(clean_desc, "`v'") > 0
}

* RECTANGULAR CARBOYS: bundled orders, gas accessories
foreach v in "gas cylinder support" "sparkleen" "stylus" "pen light" {
    replace kept = 0 if category == "rectangular carboys" & strpos(clean_desc, "`v'") > 0
}

* ZEOCIN: different antibiotics (phleomycin, gentamicin), expression plasmids
foreach v in "phleomycin" "expression plasmid" "gentamicin" "resistance gene" {
    replace kept = 0 if category == "cell culture antibiotics - zeocin" & strpos(clean_desc, "`v'") > 0
}

* DIGITONIN: stopwatches caught on "digit"
foreach v in "stopwatch" "digital stopwatch" {
    replace kept = 0 if category == "cell lysis detergents - digitonin" & strpos(clean_desc, "`v'") > 0
}

* CHROMATOGRAPHY PAPER: paper plates / bench protector / bundled
foreach v in "paper plate" "ppr plt" "bench prot" "laycoat" {
    replace kept = 0 if category == "chromatography paper" & strpos(clean_desc, "`v'") > 0
}

* LDS SAMPLE BUFFER: 4x monoculars, antibodies, glove dispensers
foreach v in "monocular" "ha tag dylight" "glve dispnsr" "glove dispenser" {
    replace kept = 0 if category == "lds sample buffer" & strpos(clean_desc, "`v'") > 0
}

* NITROGEN: bacterial media (tryptone source nitrogen), antibodies, polymerases
foreach v in "tryptone" "peptone" "casein" "dna pol" "primary 100ul" "calibration gas" {
    replace kept = 0 if category == "nitrogen" & strpos(clean_desc, "`v'") > 0
}

* RIFAMPICIN: rifaximin (related drug, different)
replace kept = 0 if category == "bacterial selection antibiotics - rifampicin" & strpos(clean_desc, "rifaximin") > 0

* HUMAN SERUM: albumin (BSA-like)
replace kept = 0 if category == "human serum" & strpos(clean_desc, "albumin") > 0

* DRUG - ANTICOAGULANT: cell culture supplement form
foreach v in "endothelial cell growth" "cell culture tested" {
    replace kept = 0 if category == "drug - anticoagulant" & strpos(clean_desc, "`v'") > 0
}

* THROMBIN: antithrombin (inhibitor, not thrombin)
replace kept = 0 if category == "thrombin" & strpos(clean_desc, "antithrombin") > 0

* === COMPARE BEFORE/AFTER ===
preserve
    collapse (mean) avg_lp = log_price (count) n=log_price, by(category year)
    sort category year
    by category: gen dlp = avg_lp - avg_lp[_n-1]
    collapse (sd) sd_before = dlp (sum) n_b=n, by(category)
    tempfile b
    save `b'
restore
preserve
    keep if kept == 1
    collapse (mean) avg_lp = log_price (count) n=log_price, by(category year)
    sort category year
    by category: gen dlp = avg_lp - avg_lp[_n-1]
    collapse (sd) sd_after = dlp (sum) n_a=n, by(category)
    tempfile a
    save `a'
restore

use `b', clear
merge 1:1 category using `a', nogen
gen pct = 100*(sd_before-sd_after)/sd_before
gen n_drop = n_b - n_a
gsort -sd_before
format sd_before sd_after %5.2f
format pct %5.1f
list category sd_before sd_after pct n_b n_drop, sep(0) noobs
