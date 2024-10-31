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
    foreach f in thermo_fisher_1965 sigma_aldrich_1965 subset_target_sic {
            clean_mergers, file(`f')
            merger_hist, file(`f')
    }
end

program clean_mergers 
    syntax, file(str)
    use ../external/sdc/sdc_mergers_`file', clear
    rename *, lower
    destring master_deal_no, replace
    save  ../temp/`file', replace
end

program merger_hist
    syntax, file(str)
    use ../temp/`file', clear
    foreach date in ann eff with {
        preserve
        drop if mi(date`date')
        gen year = year(date`date')
        gcollapse (count) num_`date' = master_deal_no, by(year)
        save ../temp/`file'_`date', replace
        restore
    }
    use ../temp/`file'_ann, clear
    merge 1:1 year using ../temp/`file'_eff, assert(1 2 3) nogen
    merge 1:1 year using ../temp/`file'_with, assert(1 2 3) nogen
    qui sum year, d
    local min = r(min)
    local max = r(max) 
    graph bar num_ann num_eff num_with, over(year, label(labsize(vsmall) angle(45))) ylab(#8, labsize(vsmall)) bar(1, color(ebblue)) bar(2, color(orange)) bar(3, color(cranberry))  legend(on label(1 "Deals Announced") label(2 "Deals Go Into Effect") label(3 "Deals Withdrawn") pos(11) size(vsmall) ring(0)) 
    graph export ../output/figures/num_deals_`file'.pdf, replace
end

**
main
