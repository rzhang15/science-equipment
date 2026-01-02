set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17
global temp "/scratch"

program main    
    clean_pi_id 
end

program merge_nih
    clear
    save ../temp/merged_nih.dta, replace emptyok
    local list: dir "../external/nih/" files "*.csv"
    foreach file of local list {
        import delimited "../external/nih/`file'", clear stringcols(_all) case(lower) bindquote(strict)
        contract application_id activity fy pi_names pi_ids org_name full_project_num total_cost  
        drop _freq
        compress, nocoalesce 
        append using ../temp/merged_nih.dta 
        save ../temp/merged_nih.dta, replace 
    }
    save ../output/nih_pi_award, replace
end
program clean_pi_id 
    // ttu utaustin ukansas all have PI names!
    // ecu has agency name
    use ../external/foias/merged_foias, clear
    keep if uni == "ecu" 
    replace funder = "NIH" if strpos(funder, "National Institutes of Health")
    keep if funder == "NIH"
    replace fund_id = substr(fund_id, 2, strlen(fund_id))
    save ../temp/ecu_nih.dta, replace 

end


main
