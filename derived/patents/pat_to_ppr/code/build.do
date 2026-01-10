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
    import delimited ../external/patents/_pcs_oa.csv, clear
    tostring oaid , gen(id)
    replace id = "W"+id
    fmerge m:1 id using ../external/openalex/list_of_works, assert(1 2 3) keep(2 3) 
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


