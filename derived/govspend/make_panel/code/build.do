set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17
global temp "/scratch"
global output "/scratch"

program main    
    import_pulls
end

program import_pulls
    import delimited "../external/postsamp/govspend_idealpull", clear 
    frame copy default ideal
    foreach f in bottles gloves syringes_needles tubes facemask new_keywords stains_dyes  synthetics {
        import delimited "../external/postsamp/`f'", clear
        frame copy default `f'
    }
    foreach f in ideal bottles gloves syringes_needles tubes facemask new_keywords stains_dyes synthetics {
        frame change `f'
        rename lineitemdescription product_desc
        rename companyname suppliername
        rename lineitemunitprice price
        rename lineitemquantity qty 
        rename lineitemtotalprice spend
        rename pouniqueid poid
        rename lineitemlinenumber linenumber
		rename sledagencyid orgid
        replace product_desc = strtrim(product_desc)
        replace suppliername = strlower(suppliername)
        replace product_desc = strlower(product_desc)
        replace date = substr(date , 1, 10)
        gen purchasedate = date(date, "YMD")
        format purchasedate %td
        gen year = year(purchasedate)
        keep product_desc suppliername price year agencyname qty spend id poid orgid
    }
    frame change default
    clear
    fframeappend , using(ideal bottles facemask gloves new_keywords syringes_needles tubes stains_dyes)
    gduplicates drop id, force
    compress, nocoalesce
    replace price = subinstr(price, "$","",.)
    replace price = subinstr(price, ",","",.)
    replace spend = subinstr(spend, "$","",.)
    replace spend = subinstr(spend, ",","",.)
    destring price, replace
    destring qty, replace
    destring spend, replace
    save ../output/govspend_post2015, replace
end

program append_predata
    use ../external/presamp/ls_items_1995, clear
    gen year =  1995
    forval i = 1996/2009 {
        append using ../external/presamp/ls_items_`i'
        replace year = `i' if mi(year)
    }
    save ../temp/part1, replace
    clear
    use ../temp/part1, clear
    forval i = 2010/2014 {
        forval q = 1/4 {
            append using ../external/presamp/ls_items_`i'q`q'
        }
        replace year = `i' if mi(year)
    }
    save ../temp/govspend_pre2015, replace
    gcontract poid
    drop _freq
    save ../output/ls_poids, replace

    clear
    forval i = 1995/2014 {
        append using ../external/presamp/pos_`i' 
    }
    save ../output/pos, replace
    merge 1:1 poid using ../output/ls_poids, assert(1 3) keep(3) nogen
    keep poid orgid vendorid ponumber issueddate issuedamount accountname city state zip 
    save ../output/ls_pos, replace
    gcontract vendorid
    drop _freq
    save ../output/list_of_vendors, replace

    import delimited using "../external/samp/Vendors.csv", clear bindquote(strict) maxquotedrows(unlimited)
    rename id vendorid
    merge 1:1 vendorid using ../output/list_of_vendors, assert(1 3) keep(3) nogen
    keep vendorid name1 name2
    save ../output/vendor_chars, replace

    use ../temp/govspend_pre2015, clear
    merge m:1 poid using ../output/ls_pos, assert(3) keep(3) nogen
    merge m:1 vendorid using ../output/vendor_chars, assert(3) keep(3) nogen
    gen suppliername = name1 + name2
    rename (description category unitprice quantity totalprice accountname) (product_desc lineitemcategory price qty spend agencyname) 
    keep product_desc suppliername price year agencyname qty spend id orgid qty price spend poid year
    tostring id,replace 
    tostring poid,replace 
    save ../output/govspend_pre2015, replace
    append using ../output/govspend_post2015
    replace agencyname = strlower(agencyname)
    replace agencyname = strtrim(agencyname)
    replace suppliername = strtrim(strlower(suppliername))
    drop if strpos(agencyname, "school district")
    foreach v in "prints" "leasing" "bank" "owens" "mckesson" "office" "staples" "paper" "home depot" "officemax" "apple" "electronics" "construction" "us food" "professional hospital supply" "builders" "stryker" "shipyards" "elsevier" "leica" "nikon" "software" "red cross" "flitco" "blood center" "blood bank" "bloodwords" "ebsco" "instrument" "contract" "contracting" "pharmacy" "computer" "electric" "philips" "power" "olympus" "digi" "paving" "cooper-atkins" "diuble" "best buy" "diagnostic" "dell" "cdwg" "govconnection inc" {
        drop if strpos(suppliername, "`v'") > 0 
    }
	foreach v in "hotel" "audit" "consulting" "courier" "custom" "grant" "honorarium" "membership" "postage" "reimb" "salaried" "secur" "ship" "staff" "blanket po" "adapter" "adap" "computer" "dell" "desktop" "ink cartridge" "laptop" "monitor" "optiplex" "printer" "bucket" "cabinet" "can" "cart" "handle" "haz" "laundry Barrier" "laundry FR" "step stool" "tackymat" "label" "fy20" "lodg" "print" "orientation" "isbn" "report" {
        drop if strpos(product_desc, "`v'") > 0 
    }
    drop if strpos(agencyname, "jr college")  > 0
    save ../output/govspend_panel, replace
    keep if year >= 2010
    bys agencyname year: gen org_yr_cntr = _n == 1
    bys agencyname: egen num_yrs = total(org_yr_cntr)
    keep if num_yrs == 10
    save ../output/balanced_govspend_2010_2019, replace
    export delimited ../output/govspend_panel, replace
end

main
