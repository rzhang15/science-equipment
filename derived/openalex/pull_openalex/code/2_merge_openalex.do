set more off
clear all
capture log close
program drop _all
set scheme modern
pause on
set seed 8975
set maxvar 120000
global dropbox_dir "~/dropbox (harvard university)/scientific equipment"
global derived_output "${dropbox_dir}/derived_output/"
program main
   * upload_files
    *append_files, section(6)
    *append_mesh, section(1)
    append_topics, section(6)
    append_grants, section(6)

    clear
    forval i = 1/6 {
        append using ../output/list_of_insts_`i'
    }
    drop if mi(inst_id)
    gduplicates drop inst_id, force
    drop if inst == "I-1"
    save ../output/list_of_insts, replace
    
    clear
    forval i = 1/6 {
        append using ../output/list_of_athrs_`i'
    }
    drop if mi(athr_id)
    gduplicates drop athr_id, force
    gen id = substr(athr_id,2, length(athr_id))
    destring id, replace
    drop if id < 5000000000
    drop id
    save ../output/list_of_athrs, replace

    clear
    forval i = 1/6 {
        append using ../output/list_of_works_`i'
    }
    drop if mi(id)
    gduplicates drop id, force
    save ../output/list_of_works, replace

    clear
    forval i = 1/6 {
        append using ../output/openalex_all_jrnls_merged_`i'
    }
    compress, nocoalesce
    save ../output/openalex_all_jrnls_merged, replace
end

program upload_files
    // work details
    forval i =1/5473 {
        di "`i'"
        qui {
                cap import delimited using ../output/openalex_authors`i', stringcols(_all) clear varn(1) bindquotes(strict) maxquotedrows(unlimited)
                if _rc == 0 {
                    keep if pub_type == "article" 
                    gen n = `i'
                    compress, nocoalesce
                    save ../temp/openalex_authors`i', replace
                }
            }
    }
    // mesh terms
    forval i = 1/5473 {
        di "`i'"
        qui {
            cap import delimited using ../output/mesh_terms`i', stringcols(_all) clear varn(1) bindquotes(strict) maxquotedrows(unlimited)
            if _rc == 0 {
                cap drop n
                gen year = `i'
                keep if is_major_topic == "TRUE"
                if _N > 0 {
                    gduplicates drop id term qualifier_name, force
                    compress, nocoalesce
                    save ../temp/mesh_terms`i', replace
                }
            }
        }
    } 

    // topics
    forval i = 1/5473 {
        di "`i'"
        qui {
            cap import delimited using ../output/topics`i', stringcols(_all) clear varn(1) bindquotes(strict) maxquotedrows(unlimited) 
            if _rc == 0 {
                cap gen n = `i'
                cap compress, nocoalesce
                cap save ../temp/topics`i', replace
            }
        }
    }

    // grants
    forval i = 1/5473 {
        di "`i'"
        qui {
            cap import delimited using ../output/grants`i', stringcols(_all) clear varn(1) bindquotes(strict) maxquotedrows(unlimited)
            if _rc == 0 {
                cap gen n = `i'
                cap compress, nocoalesce
                cap save ../temp/grants`i', replace
            }
        }
    }
end

program append_files
    syntax, section(int)
    clear
    local start = (`section'-1)*1000+1
    local end = min(`section'*1000 , 5473)
    forval i = `start'/`end' {
        di "`i'"
        qui cap append using ../temp/openalex_authors`i'
    }
    destring pmid, replace
    destring which_athr, replace
    destring which_affl, replace
    destring cite_count, replace
    gduplicates drop  id which_athr which_affl inst_id , force
    gduplicates drop  id which_athr inst_id , force
    gduplicates tag id which_athr which_affl, gen(dup)
    drop if dup == 1 & mi(inst)
    drop dup 
    gsort id athr_id which_athr
    gduplicates drop id athr_id inst_id, force
    bys id athr_id which_athr : gen which_athr_counter = _n == 1
    bys id athr_id: egen num_which_athr = sum(which_athr_counter)
    gen mi_inst = mi(inst)
    bys id athr_id: egen has_nonmi_inst = min(mi_inst)  
    replace has_nonmi_inst = has_nonmi_inst == 0
    drop if mi(inst) & num_which_athr > 1 & has_nonmi_inst
    drop which_athr_counter num_which_athr
    bys id athr_id which_athr : gen which_athr_counter = _n == 1
    bys id athr_id: egen num_which_athr = sum(which_athr_counter)
    cap destring which_athr, replace
    bys id athr_id: egen min_which_athr = min(which_athr)
    replace which_athr = min_which_athr if num_which_athr > 1
    gduplicates drop pmid which_athr inst_id, force
    bys id which_athr: gen author_id = _n == 1
    bys id: gen which_athr2 = sum(author_id)
    replace which_athr = which_athr2
    drop which_athr2
    bys id which_athr (which_affl) : replace which_affl = _n 
    gisid id which_athr which_affl
    save "../output/openalex_all_jrnls_merged_`section'", replace
    preserve
	gcontract id, nomiss
	drop _freq
	save "../output/list_of_works_`section'", replace
	restore
	preserve
	gcontract athr_id, nomiss
	drop _freq
	save "../output/list_of_athrs_`section'", replace
	restore
    gcontract inst_id, nomiss
    drop _freq
    save "../output/list_of_insts_`section'", replace
end

program append_mesh
    syntax, section(int)
    clear
    local start = (`section'-1)*1000+1
    local end = min(`section'*1000 , 5473)
    clear
    forval i = `start'/`end' {
        di "`i'"
        cap qui append using ../temp/mesh_terms`i'
    }
    gen gen_mesh = term if strpos(term, ",") == 0 & strpos(term, ";") == 0
    replace gen_mesh = term if strpos(term, "Models")>0
    replace gen_mesh = subinstr(gen_mesh, "&; ", "&",.)
    gen rev_mesh = reverse(term)
    replace rev_mesh = substr(rev_mesh, strpos(rev_mesh, ",")+1, strlen(rev_mesh)-strpos(rev_mesh, ","))
    replace rev_mesh = reverse(rev_mesh)
    replace gen_mesh = rev_mesh if mi(gen_mesh)
    drop rev_mesh
    contract id gen_mesh qualifier_name, nomiss
    merge m:1 id using "../output/list_of_works_`section'", assert(1 2 3) keep(3) nogen
    save "../output/contracted_gen_mesh_all_jrnls_`section'", replace
end

program append_topics
    syntax, section(int)
    local start = (`section'-1)*1000+1
    local end = min(`section'*1000 , 5473)
    clear
    forval i = `start'/`end' {
        di "`i'"
        cap qui append using ../temp/topics`i'
    }
    merge m:1 id using "../output/list_of_works_`section'", assert(1 2 3) keep(3) nogen
    save "../output/topics_all_jrnls_merged_`section'",replace
end
program append_grants
    syntax, section(int)
    local start = (`section'-1)*1000+1
    local end = min(`section'*1000 , 5473)
    clear
    forval i = `start'/`end' {
        di "`i'"
        cap qui append using ../temp/grants`i'
    }
    merge m:1 id using "../output/list_of_works_`section'", assert(1 2 3) keep(3) nogen
    cap rename year n
    save "../output/grants_all_jrnls_merged_`section'",replace
end
main
