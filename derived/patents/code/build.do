set more off
clear all
capture log close
program drop _all
set scheme modern
pause on
set seed 8975
here, set

program main
    merge_w_openalex
end
program merge_w_openalex
    use ../external/openalex/openalex_15jrnls_merged.dta, clear
    gcontract id
    drop _freq
    save ../temp/list_of_papers, replace

    import delimited ../external/patents/_pcs_oa.csv, clear
    tostring oaid , gen(id)
    replace id = "W"+id
    fmerge m:1 id using ../temp/list_of_papers, assert(1 2 3) keep(2 3) 
    gen wt = 1 if wherefound == "body" | wherefound == "front"
    replace wt = 2 if wherefound == "both"
    gen patent_count = _merge == 3
    gen front_only = wherefound == "front"
    gen body_only = wherefound == "body"
    gcollapse (sum) wt patent_count front_only body_only, by(id)
    save ../output/patent_ppr_cnt, replace
end

** 
main


