set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17
global temp "/scratch"

program main    
    /*get_unis
    extract_POs
    import_items*/
    filter_keywords
end

program get_unis
    import delimited using "../external/samp/Organizations.csv", clear bindquote(strict) maxquotedrows(unlimited)
    keep if accounttype == "State University/College"
    drop if strpos(accountname, "Community College") > 0 | strpos(accountname, "Junior College") | strpos(accountname, "Technical College")
    rename id orgid
    save ../output/uni_chars, replace
    collapse (firstnm) uni = accountname , by(orgid)
    save ../output/uni_list, replace
end

program extract_POs
    forval i = 1995/2014 {
        import delimited using "../external/samp/PO-`i'.csv", clear bindquote(strict) maxquotedrows(unlimited)
        merge m:1 orgid using ../output/uni_chars, keep(3) nogen
        rename id poid
        save "../output/pos_`i'", replace
        gcontract poid
        drop _freq
        save ../output/uni_pos_`i', replace
    }
    clear
    forval i = 1995/2014 {
        append using ../output/uni_pos_`i'
    }
    save ../output/all_uni_pos, replace 
end

program import_items
    forval i = 1995/2009 {
        qui import delimited using "../external/samp/Item-`i'.csv", clear bindquote(strict) maxquotedrows(unlimited)
        merge m:1 poid using ../output/uni_pos_`i', keep(3) nogen
        keep id poid linenumber description quantity unitprice totalprice commoditycode category
        replace description = strlower(description)
        replace description = strtrim(description)
        save "../output/items_`i'", replace
    }

    forval i = 2010/2014 {
        forval q = 1/4 {
            qui import delimited using "../external/samp/Item-`i'-Q`q'.csv", clear bindquote(strict) maxquotedrows(unlimited)
            merge m:1 poid using ../output/uni_pos_`i', keep(3) nogen
            keep id poid linenumber description quantity unitprice totalprice commoditycode category
            replace description = strlower(description)
            replace description = strtrim(description)
            save "../output/items_`i'q`q'", replace
        }
    }
end

program filter_keywords
    import excel using "../external/keywords/govspend keywords.xlsx", clear firstrow
    glevelsof anyvariationofkeyword, local(keywords)
    glevelsof discard, local(discardwords)
    forval i = 1995/2009 {
        use ../output/items_`i', clear
        drop if mi(description)
        gen keyword = ""
        gen keep = 0
        foreach k in `keywords' {
            local k = strlower("`k'")
            replace keep = 1 if strpos(description, "`k'")>0
            if strpos("`k'", "-") > 0 {
                di "`k'"
                local k =  subinstr("`k'", "-", " ",.)
                replace keep = 1 if strpos(description, "`k'")>0
            }
            if strpos("`k'", " ")>0 {
                di "`k'"
                local hits = 0
                local n : word count "`k'"
                di `n'
                forval j = 1/`n' {
                    local w : word `j' of "`k'"
                    local hits = `hits' + strpos(description,"`w'") > 0
                }
                replace keep = 1 if `hits' == `n' & keep == 0
            }
            replace keyword = "`k'" if keep == 1 & mi(keyword)
        }
        keep if keep == 1
        qui count
        if r(N) != 0 {
            save ../temp/ls_items_`i', replace
        }
    }
    forval i = 1995/2009 {
        cap {
            use ../temp/ls_items_`i', clear
            keep if keep == 1
            foreach d in `discardwords' {
                local d = strlower("`d'")
                drop if strpos(description, "`d'") > 0
            }
            save ../output/ls_items_`i', replace
        }
    }
    forval i = 2010/2014 {
        forval q = 1/4 {
            use ../output/items_`i'q`q', clear
            drop if mi(description)
            gen keyword = ""
            gen keep = 0
            foreach k in `keywords' {
                local k = strlower("`k'")
                replace keep = 1 if strpos(description, "`k'")>0
                if strpos("`k'", "-") > 0 {
                    di "`k'"
                    local k =  subinstr("`k'", "-", " ",.)
                    replace keep = 1 if strpos(description, "`k'")>0
                }
                if strpos("`k'", " ")>0 {
                    di "`k'"
                    local hits = 0
                    local n : word count `k'
                    di `n'
                    forval j = 1/`n' {
                        local w : word `j' of "`k'"
                        local hits = `hits' + strpos(description,"`w'") > 0
                    }
                    replace keep = 1 if `hits' == `n' & keep == 0
                }
                replace keyword = "`k'" if keep == 1 & mi(keyword)
            }
            keep if keep == 1
            qui count
            if r(N) != 0 {
                save ../temp/ls_items_`i'q`q', replace
            }
        }
    }
    forval i = 2010/2014 {
        forval q = 1/4 {
            cap {
                use ../temp/ls_items_`i'q`q', clear
                keep if keep == 1
                foreach d in `discardwords' {
                    local d = strlower("`d'")
                    drop if strpos(description, "`d'") > 0
                }
                save ../output/ls_items_`i'q`q', replace
            }
        }
    }
end
main
