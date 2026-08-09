set more off
clear all
capture log close
program drop _all
set scheme modern
version 17
set maxvar 120000

program main
    build_awards
    build_panel
    build_pis
    build_abstracts
    build_pgm
end

program import_csv
    args file
    import delimited using ../temp/`file'.csv, varnames(1) bindquote(strict) ///
        stringcols(_all) encoding(utf8) clear
end

program to_date
    foreach v of local 0 {
        gen double `v'_d = date(`v', "YMD")
        format %td `v'_d
        drop `v'
        rename `v'_d `v'
    }
end

program build_awards
    import_csv awards
    destring org_id award_year n_pi n_pi_lead, replace force
    destring awd_amount tot_intn_awd_amt awd_arra_amount, replace force
    recast double awd_amount tot_intn_awd_amt awd_arra_amount
    to_date project_start project_end amd_first_date amd_last_date

    label var awd_id        "NSF award id"
    label var award_year    "award-year folder the record was published in"
    label var org_id        "grantee institution id, minted in parse.py (>90m)"
    label var org_uei_num   "grantee UEI, blank before ~2010 registrations"
    label var pi_names      "all PIs, 'LAST, FIRST M' separated by ;"
    label var n_pi_lead     "PIs with role (Former) Principal Investigator"
    label var awd_amount    "total awarded to date"
    label var tot_intn_awd_amt "total intended award"

    isid awd_id
    save ../output/nsf_awards, replace
    save ../temp/nsf_awards, replace
end

program build_panel
    import_csv award_fy
    destring fy total_cost, replace force
    recast double total_cost
    collapse (sum) total_cost (firstnm) fy_src, by(awd_id fy)

    merge m:1 awd_id using ../temp/nsf_awards, keep(1 3)
    count if _merge == 1
    if r(N) di as error "  `r(N)' obligation rows with no award record"
    drop _merge

    label var fy         "obligation fiscal year"
    label var total_cost "obligated in this fiscal year"
    label var fy_src     "oblg = NSF obligation record; eff_date = imputed"
    isid awd_id fy
    save ../output/nsf_2010_2019, replace
end

program build_pis
    import_csv pis
    to_date pi_start_date pi_end_date
    label var pi_name "'LAST, FIRST M', the RePORTER convention"
    label var nsf_id  "NSF person id, stable across awards"
    save ../output/nsf_pi_long, replace
end

program build_abstracts
    import_csv abstracts
    isid awd_id
    save ../output/nsf_abstracts, replace
end

program build_pgm
    import_csv pgm
    label var pgm_type "ele = program element; ref = program reference"
    save ../output/nsf_pgm_long, replace
end

main
