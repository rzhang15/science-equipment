set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17
set maxvar 120000, perm
global dropbox_dir "~/Dropbox (Harvard University)/Regulation_and_Bargaining"
global ecri_data "${dropbox_dir}/Data/ECRI/"

program main   
    append_data
    mfg_vendor_xw
end

program append_data
    forval y = 2012/2022 {
	global tot_trans = 0
	global mi_umdnscode = 0
        local end = cond(`y' == 2022, 2, 4)
        forval q = 1/`end' {
            use "${ecri_data}/Unzipped/commonextract_`y'_q`q'", clear
            local name = "commonextract_`y'_q`q'"
            di "`name'"
            qui {
                rename (standardizedmfgnamelong standardizedvendornamelong) (mfg_name vendor_name)
                cap tostring vendorid, replace
                cap tostring mfgid, replace
                replace mfg_name = strtrim(strlower(subinstr(mfg_name, " ", "_",.)))
                replace vendor_name = strtrim(strlower(subinstr(vendor_name, " ", "_",.)))
                gcontract mfgid vendorid mfg_name vendor_name
                drop _freq
				compress, nocoalesce
                preserve
                gcontract mfgid mfg_name
                drop _freq
                gen mfg = 1 
                gen vendor = .
				frame put *, into(mfg_`y'_q`q')
				restore
                preserve
                gcontract vendorid vendor_name
                drop _freq
                gen mfg = . 
                gen vendor = 1
				frame put *, into(vend_`y'_q`q')
				restore
            }
        }
    }
end

program mfg_vendor_xw
	frame change default
	clear 
	fframeappend, using(mfg_*) drop
    gduplicates drop
    rename (mfgid mfg_name) (id name)
    save ../temp/mfg_list, replace
	frame change default
	clear 
	fframeappend, using(vend_*) drop
    gduplicates drop
    rename (vendorid vendor_name) (id name)
    save ../temp/vend_list, replace
    append using ../temp/mfg_list
    bys id: egen is_mfg = max(mfg)
    bys id: egen is_vendor= max(vendor)
    gen is_both = is_mfg == 1 & is_vendor == 1 
    gcontract id name is_mfg is_vendor is_both
    drop _freq
    replace name = strproper(subinstr(name, "_", " ", .))
    replace is_mfg = 0 if mi(is_mfg)
    replace is_vendor = 0 if mi(is_vendor)
    save ../output/mfg_vendor_list.dta, replace
	
	* divid into separate files of 1000 firms
	drop if name == "Unknown"
	foreach i in 1 1001 2001 3001 4001 5001 6001 7001 8001 9001 10001 11001 12001 13001 14001 {
		local start = `i'
		local end = `start' + 999
	    export excel using "../output/mfg_vendor_`i'" in `start'/`end', replace
	}
	count
	export excel using "../output/mfg_vendor_15001" in 15001/`r(N)', replace
	
end

**
main

