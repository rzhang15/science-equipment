set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17
global temp "/scratch"
program main   
    import_cluster_classification 
    athr_cluster
    create_panel
end

program import_cluster_classification
    import excel using "../external/exposure/gemini_clusters.xlsx", firstrow case(lower) clear
    keep clusterid mergerexposurecategory
    gen exposure = 0 if mergerexposurecategory == "Low"
    replace exposure = 1 if mergerexposurecategory == "Medium"
    replace exposure = 2 if mergerexposurecategory == "High"
    rename mergerexposurecategory exposure_category
    gen engine = "gemini"
    save ${temp}/gemini, replace

    import excel using "../external/exposure/gpt_cluster.xlsx", firstrow case(lower) clear
    keep clusterid exposure_category 
    gen exposure = 0 if exposure_category == "Low"
    replace exposure = 1 if exposure_category == "Medium"
    replace exposure = 2 if exposure_category == "High"
    gen engine = "gpt"
    save ${temp}/gpt, replace
    append using ${temp}/gemini
    reshape wide exposure exposure_category, i(clusterid) j(engine) string 
    heatplot exposuregemini exposuregpt,  xlab(0 "Low" 1 "Medium" 2 "High") ylab(0 "Low" 1 "Medium" 2 "High") bwidth(1) color(carto Teal, intensity(.5))  statistic(count) values(format(%9.0f)) legend(off) cuts(0 4  7 8 12 16 30 32 68 168)
    graph export ../output/correlation.pdf, replace
    keep if exposuregemini==exposuregpt
    *drop if exposuregemini==0
    gcontract clusterid exposuregemini
    drop _freq
    rename exposuregemini exposure
    save ${temp}/relevant_clusters, replace
end

program athr_cluster
    import delimited ../external/clusters/author_subfield_mapping.csv, clear
    drop if cluster == -1
    rename cluster clusterid
    merge m:1 clusterid using ${temp}/relevant_clusters, assert(1 3) keep(3) nogen
    keep if inlist(clusterid, 8, 2, 278, 75, 47,97, 63, 246, 267) | inlist(clusterid, 343, 52, 9, 306)
    replace exposure = 0 if  inlist(clusterid, 8, 2, 278, 75, 47,97, 63, 246, 267)
    replace exposure = 2 if inlist(clusterid, 343, 52, 9, 306)
    save ${temp}/relevant_athrs, replace

    use if inrange(year, 2000, 2024) using ../external/samp/second/cleaned_all_15jrnls, clear
    merge m:1 athr_id using ${temp}/relevant_athrs, assert(1 2 3) keep(3) nogen
    save ${temp}/restricted_samp, replace
end

program create_panel
    use id pmid which_athr which_affl pub_date year jrnl cite_count athr_id athr_name impact_fctr country_code msa_comb msa_c_world inst inst_id msacode exposure clusterid using ${temp}/restricted_samp, replace
    gen ppr_cnt = 1
    gen qrtr = qofd(pub_date)
    bys pmid athr_id (which_athr which_affl): gen author_id = _n == 1
    bys pmid (which_athr which_affl): gen which_athr2 = sum(author_id)
    replace which_athr = which_athr2
    drop which_athr2
    bys pmid which_athr: gen num_affls = _N
    assert num_affls == 1
    bys pmid: gegen num_athrs = max(which_athr)
    gen affl_wt = 1/num_affls * 1/num_athrs
    local date  date("`c(current_date)'", "DMY")
    gen time_since_pub = yofd(`date') - `time'+1
    gen avg_cite = cite_count/time_since_pub
    bys pmid: replace avg_cite = . if _n != 1
    sum avg_cite
    gen cite_wt = avg_cite/r(sum)
    bys jrnl: gegen tot_cite_N = total(cite_wt)
    gsort pmid cite_wt
    qui bys pmid: replace cite_wt = cite_wt[_n-1] if mi(cite_wt)
    gunique pmid
    local articles = r(unique)
    qui gen cite_affl_wt = affl_wt * cite_wt * `articles'
    qui bys pmid: gen pmid_cntr = _n == 1
    qui bys jrnl: gen first_jrnl = _n == 1
    qui by jrnl: gegen jrnl_N = total(pmid_cntr)
    qui sum impact_fctr if first_jrnl == 1
    gen impact_shr = impact_fctr/r(sum)
    gen reweight_N = impact_shr * `articles'
    replace  tot_cite_N = tot_cite_N * `articles'
    gen impact_wt = reweight_N/jrnl_N
    gen impact_affl_wt = impact_wt * affl_wt
    gen impact_cite_wt = reweight_N * cite_wt / tot_cite_N * `articles'
    gen impact_cite_affl_wt = impact_cite_wt * affl_wt
    foreach v in affl_wt cite_affl_wt impact_affl_wt impact_cite_affl_wt {
        qui sum `v'
        assert round(r(sum)-`articles') == 0
    }
    keep if country_code == "US" & !mi(msa_comb)
    collapse (sum) ppr_cnt affl_wt cite_affl_wt impact_affl_wt impact_cite_affl_wt (firstnm) exposure inst_id inst msacode msa_comb, by(athr_id year)
    save ../output/athr_panel_full_year, replace


end
**
main
