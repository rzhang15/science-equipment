set more off
clear all
capture log close
program drop _all
set scheme modern
pause on
set seed 8975
here, set
set maxvar 120000
global dropbox_dir "~/dropbox (harvard university)/scientific equipment"
global derived_output "${dropbox_dir}/derived_output/"
program main
    append_files
    append_mesh
    append_concepts
	append_grants
end
program append_files
        forval i =2000/2024 {
        di "`i'"
        qui {
                import delimited using ../output/openalex_authors`i', stringcols(_all) clear varn(1) bindquotes(strict) maxquotedrows(unlimited)
                keep if pub_type == "article" & pub_type_crossref == "journal-article"
                gen n = `i'
                compress, nocoalesce
                save ../output/openalex_authors`i', replace
            }
        }
        clear
        forval i = 2000/2024 {
            di "`i'"
            qui append using ../output/openalex_authors`i'
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
	gen dallas_pi = athr_pos == "last" & inst_id == "I162577319"
	bys id: egen has_dallas_pi = max(dallas_pi)
	keep if has_dallas_pi == 1
    save "${derived_output}/pull_openalex/openalex_all_jrnls_merged", replace
    preserve
	gcontract id, nomiss
	drop _freq
	save "${derived_output}/pull_openalex/list_of_works", replace
	restore
	preserve
	gcontract athr_id, nomiss
	drop _freq
	save "${derived_output}/pull_openalex/list_of_athrs", replace
	restore
    gcontract inst_id, nomiss
    drop _freq
    save "${derived_output}/pull_openalex/list_of_insts", replace
end
program append_mesh
        forval i = 2000/2024 {
        di "`i'"
        qui {
                cap import delimited using ../output/mesh_terms`i', stringcols(_all) clear varn(1) bindquotes(strict) maxquotedrows(unlimited)
                cap drop n
                gen year = `i'
                keep if is_major_topic == "TRUE"
                if _N > 0 {
                    gduplicates drop id term qualifier_name, force
                    compress, nocoalesce
                    save ../output/mesh_terms`i', replace
                }
            }
        }
        clear
        forval i = 2000/2024 {
            di "`i'"
            cap qui append using ../output/mesh_terms`i'
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
		merge m:1 id using "${derived_output}/pull_openalex/list_of_works", assert(1 2 3) keep(3) nogen
        save "${derived_output}/pull_openalex/contracted_gen_mesh_all_jrnls", replace
end
program append_concepts
        forval i = 2000/2024 {
        di "`i'"
        qui {
                cap import delimited using ../output/topics`i', stringcols(_all) clear varn(1) bindquotes(strict) maxquotedrows(unlimited)
                gen year = `i'
                compress, nocoalesce
                save ../output/topics`i', replace
            }
        }
        clear
        forval i = 2000/2024 {
            di "`i'"
            cap qui append using ../output/topics`i'
        }
		merge m:1 id using "${derived_output}/pull_openalex/list_of_works", assert(1 2 3) keep(3) nogen
        save "${derived_output}/pull_openalex/topics_all_jrnls_merged",replace
end
program append_grants
        forval i = 2000/2024 {
        di "`i'"
        qui {
                cap import delimited using ../output/grants`i', stringcols(_all) clear varn(1) bindquotes(strict) maxquotedrows(unlimited)
                cap gen year = `i'
                cap compress, nocoalesce
                cap save ../output/grants`i', replace
            }
        }
        clear
        forval i = 2000/2024 {
            di "`i'"
            cap qui append using ../output/grants`i'
        }
		merge m:1 id using "${derived_output}/pull_openalex/list_of_works", assert(1 2 3) keep(3) nogen
        save "${derived_output}/pull_openalex/grants_all_jrnls_merged",replace
end
main
