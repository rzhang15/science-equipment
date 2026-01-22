set more off
clear all
capture log close
program drop _all
set scheme modern
pause on
set seed 8975
set maxvar 120000

global cell_culture `" "basal media" "proprietary media" "custom media" "fbs" "serum" "sera" "hepes buffer" "phosphate-buffered saline (pbs) buffer" "dpbs" "hanks' balanced salt solution (hbss) buffer" "tris-buffered salie (tbs) buffer" "tris-acetate-edta (tae) buffer" "tris-glycine-sds (tgs) buffer" "tris-edta (te) buffer" "tbe buffer" "mes (2-(n-morpholino)ethanesulfonic acid) buffer" "mops-sds buffer" "cell culture nutritional supplements" "media supplements" "cell culture antibiotics" "cell culture dissociation reagents"  "cryopreservation solution" "serological pipettes" "cell line"  "'
global mol_bio `" "synthetic" "sirna" "transfection reagents" "taq polymerase" "dna polymerase" "reverse transcriptase" "pcr system" "qpcr system" "rt-qcr" "rt-pcr" "restriction enzymes" "nucleic acid modifying enzymes" "cloning kit" "polystyrene bead" "dna ladder" "rnai" "dna ligase" "expression plasmid" "plasmid vector" "chemically competent cells" "electrocompetent cell" "column-based" "magnetic-bead" "rna ladder" "agarose" "nucleic acid gel stains" "tbe buffer" "tae buffer"  "cell lysis" "cdna" "dntps" "electrophoresis" "laemmli" "'
global protein_bio `" "pre-cast" "pre-stained" "protein gel stains" "acrylamide/bis solution" "blotting membrane" "chemiluminescent substrate" "protease" "crosslinking reagent" "bioconjugate dye" "antibody" "protein molecular-weight ladder" "western blot" "bca protein assay kit" "bradford protein assay kit" "bovine serum albumin" "protease inhibitor cocktails" "reducing agents" "dtt" "elisa"  "ladder" "'
global treated_products  "$cell_culture $mol_bio $protein_bio"


program main
    *foia_pis
    clean_foia_data
end

program foia_pis 
    use ../external/foia/foia_athrs, clear
    merge 1:1 athr_id using ../external/ls_samp/list_of_athrs, assert(1 2 3) keep(3) nogen
    save ../output/foia_athrs, replace

    import delimited using ../external/fields/author_static_clusters, clear varnames(1)
    merge 1:1 athr_id using ../output/foia_athrs, assert(1 2 3) keep(3) nogen 
    save ../output/foia_athrs_with_clusters, replace
    
    import delimited using ../external/fields/author_static_clusters_15, clear varnames(1)
    merge 1:1 athr_id using ../output/foia_athrs, assert(1 2 3) keep(3) nogen 
    save ../output/foia_athrs_with_clusters_15, replace
    
    import delimited using ../external/fields/author_static_clusters_12, clear varnames(1)
    merge 1:1 athr_id using ../output/foia_athrs, assert(1 2 3) keep(3) nogen 
    save ../output/foia_athrs_with_clusters_12, replace

    import delimited using ../external/fields/author_static_clusters_10, clear varnames(1)
    merge 1:1 athr_id using ../output/foia_athrs, assert(1 2 3) keep(3) nogen 
    save ../output/foia_athrs_with_clusters_10, replace
end

program clean_foia_data    
    use ../external/foia/merged_foias_with_pis, clear
    drop category
    rename predicted_market category
    replace category = "cryovials" if strpos(clean_desc, "cryo") >0 & strpos(clean_desc, "vial") >0 
    // get rid of negated orders
    drop if price <= 0 | qty <= 0 | spend <= 0
    merge m:1 athr_id using ../output/foia_athrs_with_clusters_10, assert(1 2 3) keep(3) nogen

    gen avg_log_spend = spend
    gen avg_log_qty = qty 
    gen avg_log_price = price 
    gen year = year(date(date, "YMD"))    
    gen treated = 0
    foreach c of global treated_products {
        replace treated = 1 if strpos(category, "`c'") > 0 
    }
    keep if year <= 2013
    gcollapse (sum) spend (mean) cluster_label treated, by(athr_id category)
    gen lab = !inlist(category , "Non-Lab", "unclassified")
    bys athr_id: egen tot_spend = total(spend)
    bys athr_id: egen tot_lab_spend = total(spend*lab)
    gen tot_lab_spend_shr = tot_lab_spend / tot_spend * 100
    keep if lab == 1
    gen spend_shr = spend / tot_spend * 100 
    gen lab_spend_shr = spend / tot_lab_spend * 100  if lab == 1
    merge m:1 category using ../external/betas/did_coefs, assert(1 2 3) keep(1 3)
    rename _merge has_beta
    replace has_beta = 0 if has_beta == 1
    replace has_beta = 1 if has_beta == 3
    glevelsof cluster_label, local(clusters)
    foreach cl in `clusters' {
        preserve
        keep if cluster_label == `cl'
        graph hbox lab_spend_shr if has_beta == 1, over(category, label(labsize(tiny))) 
        graph export ../output/pi_spread_cluster_`cl'.pdf, replace
        restore 
    }  
    sum cluster_label
    local maxcl = r(max)
    gcollapse (mean) lab_spend_shr spend_shr treated has_beta (firstnm) b, by(cluster_label category)  
    heatplot lab_spend_shr cluster_label category if has_beta==1, keylabels(, range(1))  cuts(0(5)30) xlabel(, angle(90) labsize(tiny)) ylabel(0(1)`maxcl', angle(0) labsize(vsmall))  colors(Greens)
    graph export ../output/foia_heatmap.pdf, replace

    gen exposure =  b*lab_spend_shr/100
    drop if mi(exposure)
    gcollapse (sum)  exposure ,by(cluster_label)
end


main
