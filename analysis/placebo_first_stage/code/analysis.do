set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main
    indiv_did_placebo
end

program indiv_did_placebo
    // per-placebo-treated DiD on log_raw_price
    use ../external/placebo/placebo_matched_mkts, clear
    qui glevelsof category, local(categories)

    mat drop _all
    foreach c in `categories' {
        preserve
        use ../external/placebo/placebo_matched_pairs, clear
        qui glevelsof control_market if category == "`c'", local(match)
        use ../external/placebo/placebo_matched_uni_category_panel, clear
        gegen uni_mkt = group(uni_id mkt)
        bys uni_mkt : egen min_year = min(year)
        bys uni_mkt : egen max_year = max(year)
        keep if min_year < 2014 & max_year > 2014
        gen post = year >= 2014
        gen posttreat = treated * post
        gen keep = category == "`c'"
        foreach m in `match' {
            replace keep = 1 if category == "`m'"
        }
        keep if keep == 1
        cap noi reghdfe log_raw_price posttreat [aw=spend_2013], cluster(mkt) absorb(year uni_id mkt)
        if _rc == 0 {
            mat coef = nullmat(coef) \ (_b[posttreat], _se[posttreat])
        }
        else {
            mat coef = nullmat(coef) \ (., .)
        }
        restore
    }
    svmat coef
    rename coef1 b
    rename coef2 se
    local counter = 1
    foreach m in `categories' {
        replace category = "`m'" if _n == `counter'
        local counter = `counter' + 1
    }
    keep b se category
    drop if mi(b)

    // bring in spend_2013 for the placebo treated markets
    preserve
    use ../external/placebo/placebo_matched_category_panel, clear
    keep if treated == 1
    gcontract category spend_2013
    drop _freq
    tempfile placebo_spend_xw
    save `placebo_spend_xw'
    restore
    merge m:1 category using `placebo_spend_xw', keep(1 3) nogen

    gen lb = b - 1.96*se
    gen ub = b + 1.96*se
    hashsort b
    save ../output/did_coefs_placebo, replace

    // ranked CI plot
    gen rank = _n
    labmask rank, values(category)
    count
    local n = r(N)
    tw rcap ub lb rank, msize(vsmall) || ///
       scatter b rank, msize(tiny) mcolor(lavender) ///
       yline(0) ylab(-1(0.2)1, labsize(small)) ///
       ysc(titlegap(-6) outergap(0)) ///
       ytitle("Placebo DiD Estimate + 95% CI", size(small)) ///
       xlab(1(1)`n', angle(45) labsize(small) valuelabel) ///
       graphregion(margin(b+35 l+5)) xtitle("") legend(off)
    graph export ../output/figures/coef_rank_placebo.pdf, replace

    // distribution of point estimates
    sum b, d
    local N    = r(N)
    local mean : di %6.3f r(mean)
    local sd   : di %6.3f r(sd)
    local p25  : di %6.3f r(p25)
    local p50  : di %6.3f r(p50)
    local p75  : di %6.3f r(p75)
    local minv : di %6.3f r(min)
    local maxv : di %6.3f r(max)

    tw hist b, freq bin(30) color(lavender%70) ///
        xtitle("Placebo DiD Coefficient", size(small)) ///
        ytitle("# of Placebo Markets", size(small)) ///
        xlab(, labsize(small)) ylab(, labsize(small)) ///
        xline(0, lcolor(gs6) lpattern(dash)) ///
        legend(on order(- "N = `N'" "mean = `mean'" "sd = `sd'" ///
                          "p25 = `p25'" "p50 = `p50'" "p75 = `p75'" ///
                          "min = `minv'" "max = `maxv'") ///
               pos(1) ring(0) region(fcolor(none)))
    graph export ../output/figures/did_coefs_placebo_hist.pdf, replace

    tw kdensity b, color(lavender) ///
        xtitle("Placebo DiD Coefficient", size(small)) ///
        ytitle("Density", size(small)) ///
        xlab(, labsize(small)) ylab(, labsize(small)) ///
        xline(0, lcolor(gs6) lpattern(dash)) ///
        legend(on order(- "N = `N'" "mean = `mean'" "sd = `sd'") ///
               pos(1) ring(0) region(fcolor(none)))
    graph export ../output/figures/did_coefs_placebo_kdens.pdf, replace
end

main
