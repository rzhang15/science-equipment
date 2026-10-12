set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries

global PRES_SCALE 1.2

cap program drop fig_export
program fig_export
    syntax, path(string) [mode(string) xsize(real 6) ysize(real 4)]
    local p : subinstr local path "/paper/" "/", all
    local p : subinstr local p "/pres/" "/", all
    local k = strpos("`p'", "figures/")
    if `k' > 0 {
        local base = substr("`p'", 1, `k' + 7)
        local rest = substr("`p'", `k' + 8, .)
    }
    else {
        local slash = strrpos("`p'", "/")
        local base = substr("`p'", 1, `slash')
        local rest = substr("`p'", `slash' + 1, .)
    }
    local tscale = cond(`xsize' >= `ysize', (2/3) * `xsize' / min(`xsize', `ysize'), 1)
    if "`mode'" == "presentation" local mode pres
    foreach m in paper pres {
        if "`mode'" != "" & "`mode'" != "`m'" continue
        local dir "`base'`m'"
        cap mkdir "`dir'"
        local sub "`rest'"
        while strpos("`sub'", "/") > 0 {
            local seg = substr("`sub'", 1, strpos("`sub'", "/") - 1)
            local dir "`dir'/`seg'"
            cap mkdir "`dir'"
            local sub = substr("`sub'", strpos("`sub'", "/") + 1, .)
        }
        local s = cond("`m'" == "pres", `tscale' * $PRES_SCALE, `tscale')
        graph display, scale(`s')
        graph export "`base'`m'/`rest'", replace
    }
end
version 17

program main   
    price_dist
end
program price_dist
/*    use ../external/samp/item_level_tfidf, clear
    keep if category == "us fbs"
    keep if strpos(clean_desc, "500ml")
    keep if year == 2013
        tw kdensity avg_log_price if agencyname == "university of florida" || ///
        kdensity avg_log_price if agencyname == "georgia institute of technology" || ///
          kdensity avg_log_price if  agencyname == "university of michigan at ann arbor",  ///
          xtitle("Average log price")  ytitle("Probability density") legend(order(1 "UofF" 2 "Georgia Tech" 3 "UMich") pos(1) ring(0)) 
        fig_export, path("../output/figures/us_fbs_uni_dist_2010.pdf")
   
    use ../external/samp/item_level_tfidf, clear
    foreach c in "us fbs" "erlenmeyer flasks" "nitrile gloves" "taq polymerases" "reverse transcriptase" "chemiluminescent substrates" ///
     "pre-stained protein molecular-weight ladder" "hot start dna polymerase" "high-fidelity dna polymerases" ///
     "column-based pcr purification kits" "dntps" "stir bars" {
        preserve
        keep if category == "`c'"
        local name = subinstr("`c'", " ", "_", .)
        graph box avg_log_price, over(year)
        fig_export, path("../output/figures/`name'_price_box_dist.pdf")

        tw kdensity avg_log_price if inrange(year,2010, 2013) & agencyname == "east carolina university" || ///
          kdensity avg_log_price if inrange(year, 2010,2013) & agencyname == "university of michigan at ann arbor" || ///
          kdensity avg_log_price if inrange(year, 2010,2013) & agencyname == "georgia institute of technology" || ///
          kdensity avg_log_price if inrange(year, 2010,2013) &  agencyname == "texas tech university", ///
          xtitle("Average log price")  ytitle("Probability density") ///
          title("`c'") ///
          legend(order(1 "FIU" 2 "UMich" 3 "Georgia Tech" 4 "Texas Tech") pos(1) ring(0)) 
        fig_export, path("../output/figures/`name'_price_uni_dist_2010.pdf")

        tw kdensity avg_log_price if inrange(year ,2016, 2019) & agencyname == "east carolina university" || ///
          kdensity avg_log_price if inrange(year, 2016, 2019) & agencyname == "university of michigan at ann arbor" || ///
          kdensity avg_log_price if inrange(year, 2016, 2019) & agencyname == "georgia institute of technology" || ///
          kdensity avg_log_price if inrange(year, 2016, 2019) &  agencyname == "texas tech university", ///
          xtitle("Average log price")  ytitle("Probability density") ///
          title("`c'") ///
          legend(order(1 "FIU" 2 "UMich" 3 "Georgia Tech" 4 "Texas Tech") pos(1) ring(0)) 
        fig_export, path("../output/figures/`name'_price_uni_dist_2019.pdf")*/

    use ../external/samp/item_level_tfidf, clear
    foreach c in "us fbs" {
        preserve
        keep if category == "`c'"
        local name = subinstr("`c'", " ", "_", .)
        forval i = 2010/2019 {
            tw kdensity price if year == `i' , ///
              xtitle("Average log price")  ytitle("Probability density") title("`c'")
            fig_export, path("../output/figures/`name'_price_dist_`i'.pdf") 
        }

        tw kdensity price if year == 2010 || ///
            kdensity price if year == 2019 , ///
            xtitle("Average log price")  ytitle("Probability density") ///
            legend(order(1 "2010" 2 "2019") pos(1) ring(0)) 
        fig_export, path("../output/figures/`name'_log_price_dist_end_years.pdf")

        tw kdensity raw_price if year == 2010 || ///
            kdensity raw_price if year == 2019 , ///
            xtitle("Price")  ytitle("Probability density") ///
            legend(order(1 "2010" 2 "2019") pos(1) ring(0)) 
        fig_export, path("../output/figures/`name'_price_dist_end_years.pdf")
        restore
    }
end

main
