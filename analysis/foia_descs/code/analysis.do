set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 18
set maxvar 120000, perm 
global dropbox_dir "~/dropbox (harvard university)/scientific equipment"

program main   
    price_dispersion
end

program price_dispersion 
    use ../external/samp/merged_unis_consumables, clear
    keep if inrange(year, 2019, 2019)
    *replace prdct_ctgry = "antibody" if strpos(prdct_ctgry, "antibod")
    replace prdct_ctgry = "cell lysis reagents" if prdct_ctgry == "cell lysis reagent"
    replace prdct_ctgry = "dehydrated microbacterial media" if prdct_ctgry == "dehydrated microbacterial medium"
    replace prdct_ctgry = "media supplement" if prdct_ctgry == "medium supplement"
	drop if inlist(prdct_ctgry, "containers & storage", "cleaning supplies & wipes")
    drop if inlist(prdct_ctgry,  "service", "hardware" ,"non chemical item", "no match")
    drop if inlist(prdct_ctgry, "office supplies", "mouse", "3d printing", "adapter")
    drop if inlist(prdct_ctgry, "shipping", "subaward", "fees", "chemical", "electronics")
    drop if strpos(prdct_ctgry, "sequencing") > 0
    drop if strpos(prdct_ctgry, "tubing") > 0
    drop if strpos(prdct_ctgry, "accessorie") > 0
    drop if strpos(prdct_ctgry, "general") > 0
    drop if strpos(prdct_ctgry, "misc") > 0
    drop if strpos(prdct_ctgry, "lamp") > 0
    drop if strpos(prdct_ctgry, "lighting") > 0
    drop if strpos(prdct_ctgry, "hotplate") > 0
    drop if strpos(prdct_ctgry, "vacuum") > 0
    drop if strpos(prdct_ctgry, "rotary traps") > 0
    drop if strpos(prdct_ctgry, "rotators") > 0
    drop if uni == "und"
    replace prdct_ctgry = subinstr(prdct_ctgry, "/", "_", .)
    qui glevelsof prdct_ctgry, local(grps)
    foreach g in `grps' {
        cap di "`g'"
        preserve
        qui keep if prdct_ctgry == "`g'" 
        qui sum price , d
        qui drop if price >= r(p90)
        qui sum price , d
        qui drop if price <= r(p10)
        cap gunique uni
        if r(unique) == 3 & _rc == 0 {
            qui sum price if uni == "oregon_state"
            local oregon_mean : di %4.3f r(mean)
            qui sum price if uni == "ut_austin"
            local austin_mean : di %4.3f r(mean)
            qui sum price if uni == "ut_dallas"
            local dallas_mean : di %4.3f r(mean)
            cap tw kdensity price if uni == "oregon_state" , color(lavender%70) || kdensity price if uni == "ut_austin" , color(dkorange%70) || kdensity price if uni == "ut_dallas", color(ebblue%70) legend(order(1 "Oregon State University (mean = `oregon_mean')" 2 "UT Austin (mean = `austin_mean')" 3 "UT Dallas (mean = `dallas_mean')") ring(1) pos(6) row(1) size(vsmall)) xtitle("Unit Price", size(small))  ytitle("Probability Density", size(small)) 
            if _rc == 0 {
            graph export "../output/figures/dist_`g'.pdf", replace
            }
        }
        restore
    }
    use ../external/samp/merged_unis, clear
    replace prdct_ctgry = "antibody" if strpos(prdct_ctgry, "antibod")
	replace prdct_ctgry = "antibody" if strpos(prdct_ctgry, "antibod")
	drop if inlist(prdct_ctgry, "containers & storage", "cleaning supplies & wipes")
    drop if inlist(prdct_ctgry,  "service", "hardware" ,"non chemical item", "no match")
    drop if inlist(prdct_ctgry, "office supplies", "mouse", "3d printing", "adapter")
    drop if inlist(prdct_ctgry, "shipping", "subaward", "fees", "chemical", "electronics")
    drop if strpos(prdct_ctgry, "sequencing") > 0
    drop if strpos(prdct_ctgry, "pipette") > 0
    drop if strpos(prdct_ctgry, "accessorie") > 0
    drop if strpos(prdct_ctgry, "general") > 0
    drop if strpos(prdct_ctgry, "misc") > 0
    drop if strpos(prdct_ctgry, "lamp") > 0
    drop if strpos(prdct_ctgry, "lighting") > 0
    drop if strpos(prdct_ctgry, "hotplate") > 0
    drop if strpos(prdct_ctgry, "vacuum") > 0
    drop if strpos(prdct_ctgry, "rotary traps") > 0
    drop if strpos(prdct_ctgry, "rotators") > 0
	drop if uni == "und" | uni == "oregon_state"
    gen antibody_spending = spend if prdct_ctgry=="antibody"
	gcollapse (sum) spend antibody_spend, by(year)
    gen shr_antibody = antibody_spend/spend
end

**
main
