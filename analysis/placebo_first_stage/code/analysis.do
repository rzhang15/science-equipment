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
    // per-(iter, placebo-treated category) DiD on log_raw_price
    use ../external/placebo/placebo_matched_mkts, clear
    qui sum iter
    local n_iter = r(max)

    tempfile results pairs_i panel_i
    local first_iter = 1

    forvalues i = 1/`n_iter' {
        di as text "===== iter `i' / `n_iter' ====="

        use ../external/placebo/placebo_matched_pairs, clear
        keep if iter == `i'
        save `pairs_i', replace

        use ../external/placebo/placebo_matched_uni_category_panel, clear
        keep if iter == `i'
        save `panel_i', replace

        use ../external/placebo/placebo_matched_mkts, clear
        keep if iter == `i'
        qui glevelsof category, local(categories)

        mat drop _all
        foreach c in `categories' {
            preserve
            use `pairs_i', clear
            qui glevelsof control_market if category == "`c'", local(match)
            use `panel_i', clear
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

        clear
        svmat coef
        rename coef1 b
        rename coef2 se
        gen iter = `i'
        gen category = ""
        local counter = 1
        foreach m in `categories' {
            replace category = "`m'" if _n == `counter'
            local counter = `counter' + 1
        }
        keep iter category b se
        drop if mi(b)

        if `first_iter' == 1 {
            save `results', replace
            local first_iter = 0
        }
        else {
            append using `results'
            save `results', replace
        }
    }

    use `results', clear

    // spend_2013 lookup -- category-level constant, dedupe across iters
    preserve
    use ../external/placebo/placebo_matched_category_panel, clear
    keep if treated == 1
    gcontract category spend_2013
    drop _freq
    duplicates drop category, force
    tempfile placebo_spend_xw
    save `placebo_spend_xw'
    restore
    merge m:1 category using `placebo_spend_xw', keep(1 3) nogen

    gen lb = b - 1.96*se
    gen ub = b + 1.96*se
    save ../output/did_coefs_placebo, replace

    // rank of coef within each iter (1 = highest b); label top categories per iter
    preserve
    gsort iter -b
    by iter: gen coef_rank = _n
    gen toplab = category if coef_rank <= 3
    qui sum iter
    local n_iter = r(max)
    tw scatter b iter, msize(vsmall) mcolor(gs10) ///
       || scatter b iter if coef_rank <= 3, msize(small) mcolor(cranberry) ///
            mlabel(toplab) mlabsize(tiny) mlabcolor(cranberry) mlabposition(3) ///
       yline(0, lcolor(gs6) lpattern(dash)) ///
       ytitle("Placebo DiD coefficient") ///
       xtitle("Iteration") ///
       xlab(1(1)`n_iter') ///
       legend(off)
    graph export ../output/figures/did_coefs_placebo_top_cats.pdf, replace
    restore

    // coef-rank profile: x = within-iter rank, y = b, one line per iter
    preserve
    gsort iter -b
    by iter: gen coef_rank = _n
    tw line b coef_rank, by(iter, note("") legend(off)) ///
       ytitle("Placebo DiD coefficient") ///
       xtitle("Within-iter rank (1 = highest)") ///
       yline(0, lcolor(gs6) lpattern(dash))
    graph export ../output/figures/did_coefs_placebo_rank_profile.pdf, replace
    restore

    // distribution of point estimates across all (iter, market) pairs
    sum b, d
    local N    = r(N)
    local mean : di %6.3f r(mean)
    local sd   : di %6.3f r(sd)
    local p25  : di %6.3f r(p25)
    local p50  : di %6.3f r(p50)
    local p75  : di %6.3f r(p75)
    local minv : di %6.3f r(min)
    local maxv : di %6.3f r(max)

    tw hist b, freq bin(40) color(lavender%70) ///
        xtitle("Placebo DiD Coefficient") ///
        ytitle("# of (iter, market) pairs") ///
        xline(0, lcolor(gs6) lpattern(dash)) ///
        legend(on order(- "N = `N'" "iters = `n_iter'" "mean = `mean'" "sd = `sd'" ///
                          "p25 = `p25'" "p50 = `p50'" "p75 = `p75'" ///
                          "min = `minv'" "max = `maxv'") ///
               pos(1) ring(0) region(fcolor(none)) size(small))
    graph export ../output/figures/did_coefs_placebo_hist.pdf, replace

    tw kdensity b, color(lavender) ///
        xtitle("Placebo DiD Coefficient") ///
        ytitle("Density") ///
        xline(0, lcolor(gs6) lpattern(dash)) ///
        legend(on order(- "N = `N'" "iters = `n_iter'" "mean = `mean'" "sd = `sd'") ///
               pos(1) ring(0) region(fcolor(none)) size(small))
    graph export ../output/figures/did_coefs_placebo_kdens.pdf, replace

    // per-iter mean coefficient (one point per placebo replication)
    preserve
    gcollapse (mean) b_mean = b (sd) b_sd = b (count) n_cats = b, by(iter)
    gen lb = b_mean - 1.96*b_sd/sqrt(n_cats)
    gen ub = b_mean + 1.96*b_sd/sqrt(n_cats)
    hashsort b_mean
    gen rank = _n
    count
    local nr = r(N)
    tw rcap ub lb rank, msize(vsmall) || ///
       scatter b_mean rank, msize(small) mcolor(lavender) ///
       yline(0) ytitle("Mean placebo DiD (per iter)") ///
       xlab(1(1)`nr') xtitle("Placebo iteration (ranked)") ///
       legend(off)
    graph export ../output/figures/did_coefs_placebo_by_iter.pdf, replace
    restore
end

main
