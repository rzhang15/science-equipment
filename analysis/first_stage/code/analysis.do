 set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main
   *raw_plots
   did
   robustness
   output_tables
   event_study
   *uni_fes
end

program raw_plots
    use ../external/samp/full_category_yr_tfidf, clear
    gen tot_qty = raw_qty
    gen tot_spend = raw_spend
    replace treated = 2 if keep == 0 & treated == 1
    replace treated = 3 if keep == 0 & treated == 0
    *collapse (mean) avg_raw_price  item_price avg_log_price r_raw_qty r_raw_spend r_raw_price raw_qty log_raw_qty avg_raw_qty raw_spend log_raw_spend avg_raw_spend (sum) tot_spend tot_qty [aw = spend_2013], by(year treated)
    collapse (mean) avg_raw_price = raw_price item_price avg_log_price raw_qty log_raw_qty avg_raw_qty = raw_qty raw_spend log_raw_spend avg_raw_spend = raw_spend (sum) tot_spend tot_qty [aw = spend_2013], by(year treated)
    gen tot_price = tot_spend/tot_qty
    gen log_tot_price = ln(tot_price)
    gen log_tot_spend = ln(tot_spend)
    gen log_tot_qty = ln(tot_qty)

    foreach var in avg_raw_price item_price avg_log_price tot_price log_tot_price raw_qty log_raw_qty avg_raw_qty tot_qty log_tot_qty raw_spend log_raw_spend avg_raw_spend tot_spend log_tot_spend {
        gen trt_`var' = `var' if treated == 1
        gen ctrl_`var' = `var' if treated == 0
        gen othr_trt_`var' = `var' if treated == 2
        gen othr_ctrl_`var' = `var' if treated == 3
    }
    foreach var in avg_log_price log_raw_qty log_raw_spend avg_raw_price raw_qty raw_spend log_tot_price log_tot_qty log_tot_spend { //avg_log_price item_price log_raw_price tot_price log_tot_price raw_qty log_raw_qty avg_log_qty tot_qty log_tot_qty raw_spend log_raw_spend avg_log_spend tot_spend log_tot_spend {
        if strpos("`var'", "price") > 0 {
            local yname "Price"
        }   
        if strpos("`var'", "qty") > 0 {
            local yname "Qty"
        }   
        if strpos("`var'", "spend") > 0 {
            local yname "Spend"
        }   
        if strpos("`var'", "log") > 0 {
            local yname = "Log " + "`yname'"
        }
        local yname = "Avg. " + "`yname'"
        qui sum trt_`var' if year == 2013 
        qui replace trt_`var' = trt_`var' - r(mean)
        qui sum ctrl_`var' if year == 2013 
        qui replace ctrl_`var' = ctrl_`var' - r(mean)
        qui sum othr_trt_`var' if year == 2013 
        qui replace othr_trt_`var' = othr_trt_`var' - r(mean)
        qui sum othr_ctrl_`var' if year == 2013 
        qui replace othr_ctrl_`var' = othr_ctrl_`var' - r(mean)
        qui tw connected trt_`var' year , lcolor(lavender) mcolor(lavender) || connected ctrl_`var' year , lcolor(dkorange) mcolor(dkorange) ///
          || connected othr_trt_`var' year, lcolor(lavender%40) mcolor(lavender%20) lpattern(dash) || ///
          connected othr_ctrl_`var' year, lcolor(dkorange%40) mcolor(dkorange%20) lpattern(dash) legend(on label(1 "Treated") label(2 "Control") label(3 "Bad ML Treated") label(4 "Bad ML Control") ring(1) pos(6) rows(1) size(small)) ytitle("`yname'", size(small)) yline(0, lcolor(gs10) lpattern(solid)) ylabel(#6, labsize(small)) xlabel(2010(1)2019, labsize(small)) xtitle("Year", size(small)) tline(2013.5, lpattern(shortdash) lcolor(gs4%80)) 
        qui graph export "../output/figures/raw/`var'_trends_pooled.pdf", replace
    }
    use ../external/merged/matched_mkts, clear
    qui glevelsof category, local(categories)
    foreach c in `categories' {
        preserve
        use ../external/merged/matched_pairs, clear 
        local del_hhi
        local sim_hhi
        qui glevelsof control_market if category == "`c'", local(match) 
        use ../external/merged/matched_category_panel, clear
        gen keep = 1 if category == "`c'" 
        qui glevelsof delta_hhi if category == "`c'", local(del_hhi) 
        local del_hhi = round(`del_hhi', 0.001)
        qui glevelsof simulated_hhi if category == "`c'", local(sim_hhi) 
        local sim_hhi = round(`sim_hhi', 0.001)
        local match_name ""
        foreach  m in `match' {
            replace keep = 1 if category == "`m'"
            local match_name = "`match_name'" + ", " + strproper("`m'")
        }
        qui keep if keep == 1 
        local name = strproper("`c'")
        gen tot_qty = raw_qty
        gen tot_spend = raw_spend
        collapse (mean) avg_log_price item_price raw_qty log_raw_qty avg_log_qty raw_spend log_raw_spend avg_log_spend (sum) tot_spend tot_qty [aw=spend_2013], by(year treated)
        gen tot_price = tot_spend/tot_qty
        gen log_tot_price = ln(tot_price)
        gen log_tot_spend = ln(tot_spend)
        gen log_tot_qty = ln(tot_qty)
        foreach var in log_tot_price log_tot_spend log_tot_qty { //avg_log_price item_price log_raw_price tot_price log_tot_price raw_qty log_raw_qty avg_log_qty tot_qty log_tot_qty raw_spend log_raw_spend avg_log_spend tot_spend log_tot_spend { 
            gen trt_`var' = `var' if treated == 1
            gen ctrl_`var' = `var' if treated == 0
        }
        foreach var in log_tot_price log_tot_qty log_tot_spend { // avg_log_price item_price log_raw_price tot_price log_tot_price raw_qty log_raw_qty avg_log_qty tot_qty log_tot_qty raw_spend log_raw_spend avg_log_spend tot_spend log_tot_spend { 
            if strpos("`var'", "price") > 0 {
                local yname "Price"
            }   
            if strpos("`var'", "qty") > 0 {
                local yname "Qty"
            }   
            if strpos("`var'", "spend") > 0 {
                local yname "Spend"
            }   
            if strpos("`var'", "log") > 0 {
                local yname = "Log " + "`yname'"
            }
            local yname = "Avg. " + "`yname'"
            qui sum trt_`var' if year == 2013 
            qui replace trt_`var' = trt_`var' - r(mean)
            qui sum ctrl_`var' if year == 2013 
            qui replace ctrl_`var' = ctrl_`var' - r(mean)
            qui tw connected trt_`var' year , lcolor(lavender) mcolor(lavender) || connected ctrl_`var' year , lcolor(dkorange%40) mcolor(dkorange%40) legend(on label(1 "Treated: `name'") label(2 "Control: `match_name'") ring(1) pos(6) rows(1) size(small)) ytitle("`yname'", size(small)) yline(0, lcolor(gs10) lpattern(solid)) ylabel(#6, labsize(small)) xlabel(2010(1)2019, labsize(small)) xtitle("Year", size(small)) tline(2013.5, lpattern(shortdash) lcolor(gs4%80)) title("Simulated HHI: `sim_hhi'; Delta HHI: `del_hhi'", size(small))
            qui graph export "../output/figures/raw/`var'_trends_category`c'.pdf", replace
        }
        restore
    }
end

program did
    // naive did
    use ../external/samp/uni_category_yr_tfidf, clear
    gegen uni_mkt = group(uni_id mkt)
    bys uni_mkt : egen min_year = min(year)
    bys uni_mkt : egen max_year = max(year)
    keep if min_year < 2014 & max_year > 2014
    gen post = 0 
    replace post = 1 if year >= 2014
    gen posttreat = treated * post
    foreach var in avg_log_price log_raw_qty log_raw_spend {
        di "`name'"
        reghdfe `var' posttreat [aw=spend_2013], cluster(mkt) absorb(year uni_id mkt)
    }

    // pooled did
    use ../external/merged/matched_uni_category_panel, clear
    gegen uni_mkt = group(uni_id mkt)
    bys uni_mkt : egen min_year = min(year)
    bys uni_mkt : egen max_year = max(year)
    keep if min_year < 2014 & max_year > 2014
    gen post = 0
    replace post = 1 if year >= 2014
    gen posttreat = treated * post
    foreach var in avg_log_price log_raw_qty log_raw_spend{
        di "`name'"
        reghdfe `var' posttreat [aw=spend_2013], cluster(mkt) absorb(year uni_id mkt)
    }
   // unexpanded panel pool version
    use ../external/merged/matched_category_panel, clear
    gen post = 0
    replace post = 1 if year >= 2014
    gen posttreat = treated * post
    foreach var in avg_log_price log_raw_qty log_raw_spend {
        di "`name'"
        reghdfe `var' posttreat [aw=spend_2013], cluster(mkt) absorb(year mkt)
    }
    // indiv did -- run both avg_log_price and log_raw_spend per category
    use ../external/merged/matched_mkts, clear
    qui glevelsof category, local(categories)
    foreach c in `categories' {
        preserve
        use ../external/merged/matched_pairs, clear
        qui glevelsof control_market if category == "`c'", local(match)
        use ../external/merged/matched_uni_category_panel, clear
        gegen uni_mkt = group(uni_id mkt)
        bys uni_mkt : egen min_year = min(year)
        bys uni_mkt : egen max_year = max(year)
        keep if min_year < 2014 & max_year > 2014
        gen post = 0
        replace post = 1 if year >= 2014
        gen posttreat = treated * post
        gen keep = 1 if category == "`c'"
        foreach  m in `match' {
            replace keep = 1 if category == "`m'"
        }
        keep if keep == 1
        glevelsof category if treated == 1, local(name)
        local name = strproper(`name')
        di "`name'"
        cap noi reghdfe avg_log_price posttreat [aw=spend_2013], cluster(mkt) absorb(year uni_id mkt)
        if _rc == 0 {
            mat coef_price = nullmat(coef_price) \ (_b[posttreat], _se[posttreat])
        }
        else {
            mat coef_price = nullmat(coef_price) \ (., .)
        }
        cap noi reghdfe log_raw_spend posttreat [aw=spend_2013], cluster(mkt) absorb(year uni_id mkt)
        if _rc == 0 {
            mat coef_spend = nullmat(coef_spend) \ (_b[posttreat], _se[posttreat])
        }
        else {
            mat coef_spend = nullmat(coef_spend) \ (., .)
        }
        restore
    }

    // build per-outcome category-labeled tempfiles, then post-process each
    tempfile coefs_price coefs_spend
    foreach yvar in price spend {
        clear
        svmat coef_`yvar'
        rename coef_`yvar'1 b
        rename coef_`yvar'2 se
        gen category = ""
        local counter = 1
        foreach m in `categories' {
            replace category = "`m'" if _n == `counter'
            local counter = `counter' + 1
        }
        drop if mi(b)
        save `coefs_`yvar'', replace
    }

    process_coefs, infile(`coefs_price') outcome("price")
    process_coefs, infile(`coefs_spend') outcome("spend")
end

program process_coefs
    syntax, infile(str) outcome(str)

    use `infile', clear
    merge m:1 category using ../external/samp/category_hhi_tfidf, assert(1 2 3) keep(3) nogen
*    drop if delta_hhi <= -2500
    merge m:1 category using ../external/merged/spend_xw, assert(2 3) keep(3) nogen
    gen lb = b - 1.96*se
    gen ub = b + 1.96*se
    hashsort b
    save ../output/did_coefs_`outcome', replace

    sum b, d
    local N    = r(N)
    local mean = round(r(mean), 0.001)
    local sd   = round(r(sd), 0.001)
    tw kdensity b, color(lavender) ///
        xtitle("DiD Coefficient (log `outcome')", size(small)) ///
        ytitle("Density", size(small)) ///
        xlab(, labsize(small)) ylab(, labsize(small)) ///
        xline(0, lcolor(gs6) lpattern(dash)) ///
        legend(on order(- "N = `N'" "mean = `mean'" "sd = `sd'") ///
               pos(1) ring(0) region(fcolor(none)))
    graph export ../output/figures/did_coefs_kdens_`outcome'.pdf, replace
    gen rank = _n
    labmask rank, values(category)
    count
    local n = r(N)
    tw rcap ub lb rank, msize(vsmall) || scatter b rank, msize(tiny) mcolor(lavender) yline(0) ylab(-1(0.2)1, labsize(small)) ysc(titlegap(-6) outergap(0)) ytitle("DiD Estimate (log `outcome') + 95% CI", size(small)) xlab(1(1)`n', angle(45) labsize(small) valuelabel) graphregion(margin(b+35 l+5)) xtitle("") legend(off)
    graph export ../output/figures/coef_rank_`outcome'.pdf, replace
    hashsort spend_2013
    gen rank_spend = _n
    labmask rank_spend, values(category)
    count
    local n = r(N)
    tw rcap ub lb rank_spend, msize(vsmall) || scatter b rank_spend, msize(tiny) mcolor(lavender) yline(0) ylab(-1(0.2)1, labsize(small)) ysc(titlegap(-6) outergap(0)) ytitle("DiD Estimate (log `outcome') + 95% CI", size(small)) xlab(1(1)`n', angle(45) labsize(small) valuelabel) graphregion(margin(b+35 l+5)) xtitle("") legend(off)
    graph export ../output/figures/coef_spend_rank_`outcome'.pdf, replace
    corr b delta_hhi [aw=spend_2013]
    local corr : di %4.3f r(rho)
    binscatter2 b delta_hhi [aw = spend_2013], legend(on order(- "corr: `corr'") ring(0) pos(1)) xtitle("Delta HHI") ytitle("Estimated Coefficient (log `outcome')")
    graph export ../output/figures/delta_hhi_corr_`outcome'.pdf, replace
    corr b simulated_hhi [aw=spend_2013]
    local corr : di %4.3f r(rho)
    binscatter2 b simulated_hhi [aw = spend_2013], legend(on order(- "corr: `corr'") ring(0) pos(1)) xtitle("Simulated HHI") ytitle("Estimated Coefficient (log `outcome')")
    graph export ../output/figures/sim_hhi_corr_`outcome'.pdf, replace

    // ============================================================
    // Empirical Bayes shrinkage of per-market DiD coefficients
    // ------------------------------------------------------------
    //   b_i ~ N(theta_i, se_i^2)    (sampling distribution)
    //   theta_i ~ N(mu, tau^2)      (cross-market prior)
    // Posterior:
    //   b_eb_i = w_i * b_i + (1 - w_i) * mu_hat,   w_i = tau^2 / (tau^2 + se_i^2)
    //   se_eb_i = sqrt(w_i * se_i^2)
    // mu_hat: precision-weighted mean of b
    // tau^2 : method of moments, max(0, var(b) - mean(se^2))
    // Markets with high SE (noisy/few obs) get pulled toward mu_hat.
    // ============================================================
    gen var_se = se^2
    qui sum var_se
    local mean_var2 = r(mean)
    qui sum b
    local sample_var = r(Var)
    local tau2 = max(0, `sample_var' - `mean_var2')
    qui sum b [aw = 1/var_se]
    local mu_hat = r(mean)
    di "EB shrinkage (`outcome'): mu_hat = `mu_hat', tau2 = `tau2', sample_var(b) = `sample_var', mean(se^2) = `mean_var2'"
    gen w_eb  = `tau2' / (`tau2' + var_se)
    gen b_eb  = w_eb * b + (1 - w_eb) * `mu_hat'
    gen se_eb = sqrt(w_eb * var_se)
    gen lb_eb = b_eb - 1.96 * se_eb
    gen ub_eb = b_eb + 1.96 * se_eb
    drop var_se
    save ../output/did_coefs_eb_`outcome', replace

    qui sum b_eb, d
    local N_eb    = r(N)
    local mean_eb = round(r(mean), 0.001)
    local sd_eb   = round(r(sd), 0.001)
    qui sum b, d
    local sd_raw  = round(r(sd), 0.001)
    local tau2_lab = round(`tau2', 0.001)
    local mu_lab   = round(`mu_hat', 0.001)
    tw kdensity b_eb, color(lavender) ///
        xtitle("DiD Coefficient (log `outcome', EB-shrunk)", size(small)) ///
        ytitle("Density", size(small)) ///
        xlab(, labsize(small)) ylab(, labsize(small)) ///
        xline(0, lcolor(gs6) lpattern(dash)) ///
        legend(on order(- "N = `N_eb'" "mean = `mean_eb'" "sd = `sd_eb'" ///
                        "raw sd = `sd_raw'" "tau2 = `tau2_lab'" "mu_hat = `mu_lab'") ///
               pos(1) ring(0) region(fcolor(none)))
    graph export ../output/figures/did_coefs_kdens_eb_`outcome'.pdf, replace

    tw kdensity b, color(gs10%70) lpattern(dash) || ///
       kdensity b_eb, color(lavender) ///
        xtitle("DiD Coefficient (log `outcome')", size(small)) ytitle("Density", size(small)) ///
        xlab(, labsize(small)) ylab(, labsize(small)) ///
        xline(0, lcolor(gs6) lpattern(dash)) ///
        legend(on order(1 "Raw (sd=`sd_raw')" 2 "EB-shrunk (sd=`sd_eb')") ///
               ring(0) pos(1) region(fcolor(none)))
    graph export ../output/figures/did_coefs_kdens_overlay_`outcome'.pdf, replace

    drop rank
    hashsort b_eb
    gen rank = _n
    labmask rank, values(category)
    count
    local n = r(N)
    tw rcap ub_eb lb_eb rank, msize(vsmall) || ///
       scatter b_eb rank, msize(tiny) mcolor(lavender) ///
       yline(0) ylab(-1(0.2)1, labsize(small)) ysc(titlegap(-6) outergap(0)) ///
       ytitle("EB DiD Estimate (log `outcome') + 95% CI", size(small)) ///
       xlab(1(1)`n', angle(45) labsize(small) valuelabel) ///
       graphregion(margin(b+35 l+5)) xtitle("") legend(off)
    graph export ../output/figures/coef_rank_eb_`outcome'.pdf, replace

    drop rank_spend
    hashsort spend_2013
    gen rank_spend = _n
    labmask rank_spend, values(category)
    count
    local n = r(N)
    tw rcap ub_eb lb_eb rank_spend, msize(vsmall) || ///
       scatter b_eb rank_spend, msize(tiny) mcolor(lavender) ///
       yline(0) ylab(-1(0.2)1, labsize(small)) ysc(titlegap(-6) outergap(0)) ///
       ytitle("EB DiD Estimate (log `outcome') + 95% CI", size(small)) ///
       xlab(1(1)`n', angle(45) labsize(small) valuelabel) ///
       graphregion(margin(b+35 l+5)) xtitle("") legend(off)
    graph export ../output/figures/coef_spend_rank_eb_`outcome'.pdf, replace

    corr b_eb delta_hhi [aw=spend_2013]
    local corr_eb : di %4.3f r(rho)
    tw scatter b_eb delta_hhi [aw = spend_2013], ///
        legend(on order(- "corr: `corr_eb'") ring(0) pos(1)) ///
        xtitle("Delta HHI") ytitle("EB DiD Coefficient (log `outcome')")
    graph export ../output/figures/delta_hhi_corr_eb_`outcome'.pdf, replace

    corr b_eb simulated_hhi [aw=spend_2013]
    local corr_eb : di %4.3f r(rho)
    binscatter2 b_eb simulated_hhi [aw = spend_2013], legend(on order(- "corr: `corr_eb'") ring(0) pos(1)) xtitle("Simulated HHI") ytitle("EB DiD Coefficient (log `outcome')")
    graph export ../output/figures/sim_hhi_corr_eb_`outcome'.pdf, replace
end

program robustness
    // robustness: pooled DiD with uni#mkt and uni#year fixed effects
    use ../external/merged/matched_uni_category_panel, clear
    gegen uni_mkt = group(uni_id mkt)
    bys uni_mkt : egen min_year = min(year)
    bys uni_mkt : egen max_year = max(year)
    keep if min_year < 2014 & max_year > 2014
    gen post = 0
    replace post = 1 if year >= 2014
    gen posttreat = treated * post
    gegen uni_year = group(uni_id year)
    foreach var in avg_log_price log_raw_qty log_raw_spend {
        cap mat drop robust_`var'
        reghdfe `var' posttreat [aw=spend_2013], cluster(mkt) absorb(year uni_id mkt)
        mat robust_`var' = nullmat(robust_`var') \ (_b[posttreat], _se[posttreat], e(N), e(r2))
        reghdfe `var' posttreat [aw=spend_2013], cluster(mkt) absorb(uni_mkt year)
        mat robust_`var' = nullmat(robust_`var') \ (_b[posttreat], _se[posttreat], e(N), e(r2))
        reghdfe `var' posttreat [aw=spend_2013], cluster(mkt) absorb(uni_year mkt)
        mat robust_`var' = nullmat(robust_`var') \ (_b[posttreat], _se[posttreat], e(N), e(r2))
        reghdfe `var' posttreat [aw=spend_2013], cluster(mkt) absorb(uni_mkt uni_year)
        mat robust_`var' = nullmat(robust_`var') \ (_b[posttreat], _se[posttreat], e(N), e(r2))
        mat colnames robust_`var' = b se N r2
        mat rownames robust_`var' = baseline uni_mkt_year uni_year_mkt uni_mkt_uni_year
    }
    // event study: leads/lags under each FE spec, overlaid per outcome
    gen rel = year - 2014
    replace rel = . if treated == 0
    forval i = 1/5 {
        gen lag`i' = 1 if rel == `i'
        gen lead`i' = 1 if rel == -`i'
    }
    gen lag0 = 1 if rel == 0
    ds lead* lag*
    foreach v in `r(varlist)' {
        replace `v' = 0 if mi(`v')
    }
    local rhs lead5 lead4 lead3 lead2 lag0 lag1 lag2 lag3 lag4 lag5
    foreach var in avg_log_price log_raw_qty log_raw_spend {
        if "`var'" == "avg_log_price" local yname "Avg. Log Price"
        if "`var'" == "log_raw_qty"   local yname "Log Qty"
        if "`var'" == "log_raw_spend" local yname "Log Spend"
        cap mat drop es_`var'
        local s = 0
        foreach fespec in "year uni_id mkt" "uni_mkt year" "uni_year mkt" "uni_mkt uni_year" {
            local s = `s' + 1
            reghdfe `var' `rhs' [aw=spend_2013], absorb(`fespec') vce(cluster mkt)
            foreach lv of local rhs {
                local relval = cond(substr("`lv'",1,3)=="lea", -1*real(substr("`lv'",5,.)), real(substr("`lv'",4,.)))
                mat es_`var' = nullmat(es_`var') \ (`s', `relval', _b[`lv'], _se[`lv'])
            }
            mat es_`var' = nullmat(es_`var') \ (`s', -1, 0, 0)
        }
        mat colnames es_`var' = spec rel b se
        preserve
        clear
        svmat es_`var', names(col)
        gen lb = b - 1.96*se
        gen ub = b + 1.96*se
        replace rel = rel + 0.15*(spec - 2.5)
        sum lb, d
        local ymin = round(r(min) - 0.1, 0.1)
        sum ub, d
        local ymax = round(r(max) + 0.1, 0.1)
        tw rcap ub lb rel if spec == 1, lcolor(lavender%70) msize(vsmall) || ///
           scatter b rel if spec == 1, mcolor(lavender) msize(small) || ///
           rcap ub lb rel if spec == 2, lcolor(orange%70) msize(vsmall) || ///
           scatter b rel if spec == 2, mcolor(orange) msymbol(smdiamond) msize(small) || ///
           rcap ub lb rel if spec == 3, lcolor(ebblue%70) msize(vsmall) || ///
           scatter b rel if spec == 3, mcolor(ebblue) msymbol(smsquare) msize(small) || ///
           rcap ub lb rel if spec == 4, lcolor(emerald%70) msize(vsmall) || ///
           scatter b rel if spec == 4, mcolor(emerald) msymbol(smtriangle) msize(small) ///
           , xlab(-5(1)5, labsize(small)) ylab(`ymin'(0.1)`ymax', labsize(small)) ///
           yline(0, lcolor(gs10) lpattern(solid)) ///
           xtitle("Relative Year", size(small)) ytitle("`yname'", size(small)) ///
           legend(on order(2 "baseline" 4 "uni#mkt + year" 6 "uni#year + mkt" 8 "uni#mkt + uni#year") ///
                  pos(6) rows(2) size(small) region(fcolor(none))) ///
           plotregion(margin(sides))
        graph export ../output/figures/robust_es_`var'.pdf, replace
        restore
    }
end

program output_tables
    foreach tab in robust_avg_log_price robust_log_raw_qty robust_log_raw_spend {
        qui matrix_to_txt, saving("../output/tables/`tab'.txt") matrix(`tab') ///
            title(<tab:`tab'>) format(%20.4f) replace
    }
end

program event_study
    // naive event study
    use ../external/samp/uni_category_yr_tfidf, clear
    merge m:1 category using ../external/samp/category_hhi_tfidf, assert(1 2 3) keep(3) nogen
    drop if delta_hhi <= -2000
    gen rel = year - 2014
    replace rel = . if treated == 0
    local fes uni_id mkt
    bys category: gen cat_id = _n == 1
    gen time_trend = year - 2009
    gen lin_time_trend = treated*time_trend
    foreach yvar in price qty spend {
        preserve
        mat drop _all
        if "`yvar'" == "price" local yname "Avg. Log Price"
        if "`yvar'" == "qty" local yname "Avg. Log Qty"
        if "`yvar'" == "spend" local yname "Avg. Log Spend"
        qui sum raw_`yvar' if treated == 1 & year == 2013
        local trt_mean = round(r(mean), 0.001)
        qui sum raw_`yvar' if treated == 0 & year == 2013
        local ctrl_mean = round(r(mean) + 0.001, 0.001)
        if "`yvar'" == "price" {
            di "hi"
            manual_event_study, lag(5) lead(-4) yvar(avg_log_`yvar') ymin(-0.2) ymax(0.6) ygap(0.1) trt_mean(`trt_mean') ctrl_mean(`ctrl_mean')  name(`yname') fes(`fes') wt_var(spend_2013) cluster_var(mkt) file_suf("naive")
        }
        if "`yvar'" != "price" {
            manual_event_study, lag(5) lead(-4) yvar(log_raw_`yvar') ymin(-0.2) ymax(0.6) ygap(0.1) trt_mean(`trt_mean') ctrl_mean(`ctrl_mean')  name(`yname') fes(`fes') wt_var(spend_2013) cluster_var(mkt) file_suf("naive")
        }
        restore
    }

    // main pooled result
    use ../external/merged/matched_uni_category_panel ,clear 
    merge m:1 category using ../external/samp/category_hhi_tfidf, assert(1 2 3) keep(3) nogen
    drop if delta_hhi <= -2000
    gegen uni_mkt = group(uni_id mkt)
    bys uni_mkt : egen min_year = min(year)
    bys uni_mkt : egen max_year = max(year)
    keep if min_year < 2014 & max_year > 2014
    gen rel = year - 2014
    replace rel = . if treated == 0
    local fes uni_id mkt 
    bys category: gen cat_id = _n == 1
    gen time_trend = year - 2009
    gen lin_time_trend = treated*time_trend
    foreach yvar in price qty spend {
        preserve
        mat drop _all
        if "`yvar'" == "price" local yname "Avg. Log Price"
        if "`yvar'" == "qty" local yname "Avg. Log Qty"
        if "`yvar'" == "spend" local yname "Avg. Log Spend"
        qui sum raw_`yvar' if treated == 1 & year == 2013
        local trt_mean = round(r(mean), 0.001)
        qui sum raw_`yvar' if treated == 0 & year == 2013
        local ctrl_mean = round(r(mean) + 0.001, 0.001)
        if "`yvar'" == "price" {
            manual_event_study, lag(5) lead(-4) yvar(avg_log_`yvar') ymin(-0.4) ymax(0.7) ygap(0.1) trt_mean(`trt_mean') ctrl_mean(`ctrl_mean')  name(`yname') fes(`fes') wt_var(spend_2013) cluster_var(mkt) file_suf("pooled")
        }
        local fes uni_id mkt
        if "`yvar'" != "price" {
            manual_event_study, lag(5) lead(-4) yvar(log_raw_`yvar') ymin(-0.4) ymax(0.7) ygap(0.1) trt_mean(`trt_mean') ctrl_mean(`ctrl_mean')  name(`yname') fes(`fes') wt_var(spend_2013) cluster_var(mkt) file_suf("pooled")
        }
        restore
    }
    foreach yvar in raw_price  { 
        preserve
        mat drop _all
        local yname "Price"
        qui sum `yvar' if treated == 1 & year == 2013
        local trt_mean = round(r(mean), 0.001)
        qui sum `yvar' if treated == 0 & year == 2013
        local ctrl_mean = round(r(mean) + 0.001, 0.001)
        manual_event_study, lag(5) lead(-4) yvar(`yvar') ymin(-50) ymax(50) ygap(5) trt_mean(`trt_mean') ctrl_mean(`ctrl_mean')  name(`yname') fes(`fes') wt_var(spend_2013) cluster_var(mkt) file_suf("pooled")
        restore
    }
    foreach yvar in raw_qty { 
        preserve
        mat drop _all
        local yname "Qty"
        qui sum `yvar' if treated == 1 & year == 2013
        local trt_mean = round(r(mean), 0.001)
        qui sum `yvar' if treated == 0 & year == 2013
        local ctrl_mean = round(r(mean) + 0.001, 0.001)
        manual_event_study, lag(5) lead(-4) yvar(`yvar') ymin(-50) ymax(50) ygap(5) trt_mean(`trt_mean') ctrl_mean(`ctrl_mean')  name(`yname') fes(`fes') wt_var(spend_2013) cluster_var(mkt) file_suf("pooled")
        restore
    }
    foreach yvar in raw_spend { 
        preserve
        mat drop _all
        local yname "Spend"
        qui sum `yvar' if treated == 1 & year == 2013
        local trt_mean = round(r(mean), 0.001)
        qui sum `yvar' if treated == 0 & year == 2013
        local ctrl_mean = round(r(mean) + 0.001, 0.001)
        manual_event_study, lag(5) lead(-4) yvar(`yvar') ymin(-600) ymax(6000) ygap(750) trt_mean(`trt_mean') ctrl_mean(`ctrl_mean')  name(`yname') fes(`fes') wt_var(spend_2013) cluster_var(mkt) file_suf("pooled")
        restore
    }
    // hhi
    /*
    sum delta_hhi if cat_id == 1, d
    local p25 = r(p25)
    local p50 = r(p50)
    local p75 = r(p75)

    gen hhi1 = delta_hhi <= `p25' 
    gen hhi2 = inrange(delta_hhi, `p25', `p50')
    gen hhi3 = inrange(delta_hhi, `p50', `p75')
    gen hhi4 = delta_hhi >= `p75' 
    forval i = 1/4 {
        foreach yvar in price qty spend {
            preserve
            keep if hhi`i' == 1
            mat drop _all 
            if "`yvar'" == "price" local yname "Avg. Log Price"
            if "`yvar'" == "qty" local yname "Avg. Log Qty"
            if "`yvar'" == "spend" local yname "Avg. Log Spend"
            qui sum raw_`yvar' if treated == 1 & year == 2013 
            local trt_mean :  dis %6.3f r(mean)
            qui sum raw_`yvar' if treated == 0 & year == 2013 
            local ctrl_mean : dis %6.3f r(mean)
            manual_event_study, lag(5) lead(-4) yvar(avg_log_`yvar') ymin(-0.2) ymax(0.6) ygap(0.1) trt_mean(`trt_mean') ctrl_mean(`ctrl_mean')  name("`yname' HHI Quartile `i'") fes(`fes') wt_var(spend_2013) cluster_var(mkt) file_suf("hhi`i'")
            restore
        }
    }*/

    qui glevelsof category if treated == 1, local(categories)
	foreach c in `categories' {
        use ../external/merged/matched_pairs, clear 
        qui glevelsof control_market if category == "`c'", local(match) 
        use ../external/merged/matched_uni_category_panel, clear 
        gen rel = year - 2014
        replace rel = . if treated == 0
        gen keep = 1 if category == "`c'"
        foreach  m in `match' {
            replace keep = 1 if category == "`m'"
        }
        local match_name ""
        foreach  m in `match' {
            replace keep = 1 if category == "`m'"
            local match_name = "`match_name'" + ", " + strproper("`m'")
        }
        keep if keep == 1
        glevelsof category if treated == 1, local(name)
        local name = strproper(`name')
        foreach yvar in price qty spend { 
            preserve
            mat drop _all 
            if "`yvar'" == "price" local yname "Avg. Log Price"
            if "`yvar'" == "qty" local yname "Avg. Log Qty"
            if "`yvar'" == "spend" local yname "Avg. Log Spend"
            qui sum raw_`yvar' if treated == 1 & year == 2013
            local trt_mean = round(r(mean), 0.001)
            qui sum raw_`yvar' if treated == 0 & year == 2013
            local ctrl_mean = round(r(mean) + 0.001, 0.001)
            if "`yvar'" == "price" {
                manual_event_study, lag(5) lead(-4) yvar(avg_log_`yvar') ymin(-0.2) ymax(0.6) ygap(0.1) trt_mean(`trt_mean') ctrl_mean(`ctrl_mean')  name(`yname') fes(`fes') wt_var(spend_2013) cluster_var(mkt) file_suf("`c'")
            }
            if "`yvar'" != "price" {
                manual_event_study, lag(5) lead(-4) yvar(log_raw_`yvar') ymin(-0.2) ymax(0.6) ygap(0.1) trt_mean(`trt_mean') ctrl_mean(`ctrl_mean')  name(`yname') fes(`fes') wt_var(spend_2013) cluster_var(mkt) file_suf("`c'")
            }
            restore
        }
    }
    /*
    use "../temp/es_avg_log_price_estimateshhi1", clear 
    gen group = 1 
    replace rel = rel - 0.24 
    append using ../temp/es_avg_log_price_estimateshhi2
    replace group = 2 if mi(group)
    replace rel = rel - 0.08 if group == 2
    append using ../temp/es_avg_log_price_estimateshhi3
    replace group = 3 if mi(group)
    replace rel = rel + 0.08  if group == 3
    append using ../temp/es_avg_log_price_estimateshhi4
    replace group = 4 if mi(group)
    replace rel = rel + 0.24 if group == 4
    tw rcap ub lb rel if rel != -1.24 & group == 1,  lcolor(lavender%70) msize(small) || ///
       scatter b rel if group == 1, mcolor(lavender%70) msize(small) || ///
       rcap ub lb rel if rel != -1.08 & group == 2,  lcolor(orange%70) msize(small) || ///
       scatter b rel if group == 2, mcolor(orange%70) msymbol(smdiamond) msize(small) || /// 
       rcap ub lb rel if rel != -0.92 & group == 3,  lcolor(ebblue%70) msize(small) || ///
       scatter b rel if group == 3, mcolor(ebblue%70) msymbol(smsquare) msize(small) || /// 
       rcap ub lb rel if rel != -0.76 & group == 4,  lcolor(cranberry%70) msize(small) || ///
       scatter b rel if group == 4, mcolor(cranberry%70) msymbol(smtriangle) msize(small) || /// 
       scatteri 0.6 -0.3 0.6 0.3 , bcolor(gs12%30) recast(area) base(-0.6) ///
       xlab(-4(1)5, labsize(small)) ylab(-0.6(0.1)0.6, labsize(vsmall)) ///
          yline(0, lcolor(black) lpattern(solid)) ///
          legend(on order(2 "Delta HHI Q1" 4 "Delta HHI Q2" 6 "Delta HHI Q3" 8 "Delta HHI Q4") pos(11) rows(2) ring(0) size(vsmall) region(fcolor(none))) xtitle("Relative Year", size(small)) ytitle("Avg. Log Price", size(small)) plotregion(margin(sides))
    graph export ../output/figures/es_estimates_hhi.pdf, replace
    */
    // combined plots
    use "../temp/es_log_raw_spend_estimatespooled", clear
    gen group = "spend"
    replace rel = rel - 0.2 
    sum b if group == "spend" & rel > 0
    local spend_mean : dis %4.3f r(mean)
    append using ../temp/es_avg_log_price_estimatespooled
    replace group = "price" if mi(group)
    sum b if group == "price" & rel > 0
    local price_mean : dis %4.3f r(mean)
    append using ../temp/es_log_raw_qty_estimatespooled
    replace group = "qty" if mi(group)
    replace rel = rel + 0.2 if group == "qty"
    sum b if group == "qty" & rel >0.2
    local qty_mean : dis %4.3f r(mean)
    tw rcap ub lb rel if rel != -1.2 & group == "spend",  lcolor(lavender%70) msize(small) || ///
       scatter b rel if group == "spend", mcolor(lavender%70) msize(small) || ///
       rcap ub lb rel if rel != -1.0 & group == "price",  lcolor(orange%70) msize(small) || ///
       scatter b rel if group == "price", mcolor(orange%70) msymbol(smdiamond) msize(small) || /// 
       rcap ub lb rel if rel != -0.8 & group == "qty",  lcolor(ebblue%70) msize(small) || ///
       scatter b rel if group == "qty", mcolor(ebblue%70) msymbol(smsquare) msize(small) || /// 
       scatteri 0.6 -0.3 0.6 0.3 , bcolor(gs12%30) recast(area) base(-0.2) ///
       xlab(-4(1)5, labsize(small)) ylab(-0.2(0.1)0.6, labsize(vsmall)) ///
          yline(0, lcolor(black) lpattern(solid)) ///
          legend(on order(2 "Spending (Post Period Avg: `spend_mean')" 4 "Price (Post Period Avg: `price_mean')" 6 "Quantity (Post Period Avg: `qty_mean')") pos(11) ring(0) size(small) region(fcolor(none))) xtitle("Relative Year", size(small)) ytitle("Log Estimates", size(small)) plotregion(margin(sides))
    graph export ../output/figures/es_estimatespooled.pdf, replace

end


program uni_fes
    use ../external/merged/matched_uni_category_panel, clear 
    keep if inrange(year, 2015,2019)
    gen post = 0 
    replace post = 1 if year >= 2017
    gen posttreat = treated * post
    reghdfe avg_log_price posttreat [aw = spend_2013], absorb(mkt year uni_id) cluster(mkt)
    glevelsof uni_id, local(unis)
    foreach u in `unis' {
        gen u_`u' = uni_id == `u'
        gen posttreat_`u'  = posttreat * u_`u'
    }
    reghdfe avg_log_price posttreat_* [aw = spend_2013], absorb(mkt uni_id year) cluster(mkt) 
    foreach u in `unis' {
        local val = . 
        local se = . 
        cap local val = _b[posttreat_`u']
        cap local se = _se[posttreat_`u']
        mat betas_placebo = nullmat(betas_placebo) \ (`u',  `val', `se')
    }
    svmat betas_placebo
    keep if !mi(betas_placebo1)
    keep betas*
    rename (betas_placebo1 betas_placebo2 betas_placebo3) (uni_id beta_u_pl se_pl)
    sum beta_u_pl, d
    local mean_pl = round(r(mean), 0.001)
    gen lb_pl = beta_u_pl - 1.96*se_pl
    gen ub_pl = beta_u_pl + 1.96*se_pl
    save ../output/beta_u_placebo, replace

    use ../external/merged/matched_uni_category_panel, clear 
    global r1 `" "east carolina university" "florida international university" "florida state university (fsu)" "georgia institute of technology" "kent state university" "texas a&m university" "texas tech university" "university of florida" "university of central florida" "university of kentucky" "university of florida" "university of kentucky" "university of michigan at ann arbor" "university of south florida" "university of southern mississippi" "washington state university" "wayne state university" "'
    global r2 `" "central michigan university" "georgia southern university" "idaho state university" "illinois state university" "indiana university of pennsylvania" "kennesaw state university" "louisiana state university health sciences center - new orleans" "northern illinois university" "suny upstate medical university" "the university of akron" "university of michigan - dearborn" "university of new orleans" "university of north carolina-wilmington" "'
    global r3 `" "grand valley state university" "lincoln university" "morehead state university" "northern kentucky university" "sul ross state university" "texas a&m international university" "western kentucky university" "western washington university" "youngstown state university" "'
    gen r1 = .
    gen r2 = .
    gen r3 = .
    foreach u in $r1 {
        replace r1 = 1 if agencyname == "`u'"        
    }
    foreach u in $r2 {
        replace r2 = 1 if agencyname == "`u'"        
    }
    foreach u in $r3 {
        replace r3 = 1 if agencyname == "`u'"        
    }
    preserve
    contract uni_id agencyname r1 r2 r3
    drop _freq
    save ../temp/uni_list, replace
    restore
    gen post = 0 
    replace post = 1 if year >= 2014
    gen posttreat = treated * post
    gen lr = inrange(year, 2016,2019) 
    gen sr = inrange(year, 2014,2016)
    gen posttreatlr = lr * posttreat
    gen posttreatsr = sr * posttreat
    reghdfe avg_log_price posttreat [aw = spend_2013], absorb(mkt year uni_id) cluster(mkt)
    reghdfe avg_log_price posttreatlr posttreatsr [aw = spend_2013], absorb(mkt year uni_id) cluster(mkt)
    glevelsof uni_id, local(unis)
    foreach u in `unis' {
        gen u_`u' = uni_id == `u'
        gen posttreat_`u'  = posttreat * u_`u'
        gen posttreatlr_`u'  = posttreatlr * u_`u'
        gen posttreatsr_`u'  = posttreatsr * u_`u'
    }
    reghdfe avg_log_price posttreat_* [aw = spend_2013], absorb(mkt year) cluster(mkt) 
    estimates save posttreat_beta_u, replace
    foreach u in `unis' {
        local val = . 
        local se = . 
        cap local val = _b[posttreat_`u']
        cap local se = _se[posttreat_`u']
        mat betas = nullmat(betas) \ (`u',  `val', `se')
    }
    preserve
    svmat betas
    keep if !mi(betas1)
    keep betas*
    rename (betas1 betas2 betas3) (uni_id beta_u se)
    merge 1:1 uni_id using ../temp/uni_list, assert(1 3) keep(1 3) nogen
    sum beta_u, d
    local N = r(N)
    local min : dis %6.3f r(min)
    local p25 : dis %6.3f r(p25)
    local p50 : dis %6.3f r(p50)
    local mean : dis %6.3f  r(mean)
    local p75 : dis %6.3f r(p75)
    local max : dis %6.3f r(max)
    local sd : dis %6.3f r(sd)
    drop if mi(beta_u)
    tw hist beta_u  , freq ytitle("% of Unis", size(small)) bin(50) xlab(, labsize(vsmall)) ylab(, labsize(vsmall)) xtitle("Beta_u", size(small)) legend(on order(- "N = `N'" "min = `min'" "p25 = `p25'" "p50 = `p50'" "mean = `mean'" "p75 = `p75'" "max = `max'" "sd =`sd'") pos(1) ring(0))
    graph export ../output/figures/beta_u_dist.pdf, replace
    gen lb = beta_u - 1.96*se
    gen ub = beta_u + 1.96*se
    save ../output/beta_u, replace
    hashsort beta_u
    gen id = _n 
    gen sig = ub < 0 | lb > 0
    count if sig == 1 
    local sig = r(N)
    sum lb, d
    local ymin = round(r(min),1)
    sum ub, d
    local ymax = round(r(max),1)
    labmask id, values(agencyname)
    tw rcap ub lb id if r1 == 1 , lcolor(midgreen) msize(vsmall) || scatter beta_u id if r1 == 1, mcolor(midgreen) msize(tiny) ///
     || rcap ub lb id if r2 == 1 ,  lcolor(dkorange) msize(vsmall) || scatter beta_u id if r2 == 1, mcolor(dkorange) msize(tiny) ///
     || rcap ub lb id if r1 == .  & r2 == . , lcolor(eltblue%90)  msize(vsmall) || scatter beta_u id if r1 == . & r2 == . , mcolor(eltblue%90) msize(tiny) ///
      xtitle("") ytitle("Beta_u + 95% CI", size(vsmall))  ///
      xlab(, nolabel notick labsize(tiny) valuelabel angle(45) nogrid) ylab(`ymin'(0.5)`ymax', labsize(vsmall) nogrid)  yline(0, lcolor(gs12) lwidth(vthin)) ///
      legend(on order(1 "R1 Universities" 3 "R2 Universities" 5 "Other Universities") pos(5) ring(0) size(vsmall))
    graph export ../output/figures/beta_u_ci.pdf, replace
    restore

    reghdfe avg_log_price posttreatlr_*  posttreatsr_* [aw = spend_2013], absorb(uni_id mkt year) cluster(mkt) 
    estimates save posttreat_beta_u_lrsr, replace
    foreach u in `unis' {
        local val_lr = . 
        local val_sr = . 
        local se_lr = . 
        local se_sr = . 
        cap local val_lr = _b[posttreatlr_`u']
        cap local val_sr = _b[posttreatsr_`u']
        cap local se_lr = _se[posttreatlr_`u']
        cap local se_sr = _se[posttreatsr_`u']
        mat betas_lr_sr = nullmat(betas_lr_sr) \ (`u',  `val_sr', `se_sr', `val_lr', `se_lr')
    }
    preserve
    svmat betas_lr_sr
    keep if !mi(betas_lr_sr1)
    keep betas_lr_sr*
    rename (betas_lr_sr1 betas_lr_sr2 betas_lr_sr3 betas_lr_sr4 betas_lr_sr5) (uni_id betasr_u se_sr betalr_u se_lr)
    foreach v in sr lr {
        sum beta`v'_u, d
        local N_`v' = r(N)
        local min_`v' : dis %6.3f r(min)
        local p25_`v' : dis %6.3f r(p25)
        local p50_`v' : dis %6.3f r(p50)
        local mean_`v' : dis %6.3f  r(mean)
        local p75_`v' : dis %6.3f r(p75)
        local max_`v' : dis %6.3f r(max)
        local sd_`v' : dis %6.3f r(sd)
        tw hist beta`v'_u  , freq bin(50) xlab(,labsize(small)) ylab(, labsize(vsmall)) ytitle("% of Unis") xtitle("Beta`v'_u") legend(on order(- "N = `N_`v''" "min = `min_`v''" "p25 = `p25_`v''" "p50 = `p50_`v''" "mean = `mean_`v''" "p75 = `p75_`v''" "max = `max_`v''" "sd =`sd_`v''") pos(1) ring(0))
        graph export ../output/figures/beta`v'_u_dist.pdf, replace
        gen ub_`v' = beta`v'_u + 1.96 * se_`v'
        gen lb_`v' = beta`v'_u - 1.96 * se_`v'
        gen sig_`v' = ub_`v' < 0 | lb_`v' > 0
        hashsort beta`v'_u
        gen id = _n 
        count if sig_`v'==1
        local sig_`v' = r(N)
        tw rcap ub_`v' lb_`v' id if sig_`v' == 0 , lcolor(gs5%70) lwidth(vvthin) msize(vsmall) || rcap ub_`v' lb_`v' id if sig_`v' == 1 , lcolor(emerald) msize(vsmall) lwidth(vthin) , xlab(1(2)82, labsize(tiny) angle(45) nogrid) ylab(-2(0.2)2, labsize(tiny) nogrid)  yline(0, lcolor(blue) lwidth(vthin)) legend(on order(- "# Sig. = `sig_`v''" "Mean = `mean_`v''" "sd = `sd_`v''") pos(5) ring(0) size(vsmall))
        graph export ../output/figures/beta`v'_u_ci.pdf, replace
        drop id
    }
    drop sig*
    save ../output/beta_sr_lr_u, replace
    restore
    
    use ../output/beta_u, clear
    merge 1:1 uni_id using ../output/beta_sr_lr_u, assert(3) keep(3) nogen
    merge 1:1 uni_id using ../output/beta_u_placebo, assert(1 3) keep(3) nogen
    tw kdensity betalr_u, color(ebblue%90) || kdensity betasr_u, color(orange%90)  || ///
        kdensity beta_u ,   color(lavender%80) || kdensity beta_u_pl, color(gs12) ytitle("% of Unis") xtitle("Beta_u") ///
        legend(on order(1 "Long run (mean): `mean_lr'" 2  "Short run (mean): `mean_sr'" 3 "All (mean):  `mean'" 4 "Placebo (mean): `mean_pl'") ring(0) pos(11) region(fcolor(none)))  ///
        xlab(, labsize(small)) xtitle("University Price Estimates", size(small)) 
    graph export ../output/figures/overlaid_beta_u.pdf, replace
    keep uni_id beta_u betasr_u betalr_u 
    save ../output/betas, replace
    use ../output/beta_u, clear
    merge 1:1 uni_id using ../output/beta_u_placebo, assert(1 3) keep(3) nogen
    tw kdensity beta_u ,   color(lavender) || kdensity beta_u_pl, color(dkorange) ytitle("% of Unis") xtitle("Beta_u") ///
        legend(on order(1 "University Price Effect Mean: `mean'" 2 "Placebo Treatment Year (mean): `mean_pl'") ring(0) pos(11) region(fcolor(none)))  ///
        xlab(, labsize(small)) xtitle("University Price Estimates", size(small)) 
    graph export ../output/figures/overlaid_beta_u_simple.pdf, replace
    use ../output/beta_u, clear
    tw kdensity beta_u ,   color(lavender%80) ytitle("% of Unis", size(small)) xtitle("Beta_u", size(small)) ///
        legend(on order(1 "Mean: `mean'") ring(0) pos(11) region(fcolor(none)))  ///
        xlab(, labsize(small))  
    graph export ../output/figures/overlaid_beta_u_single.pdf, replace
end

program manual_event_study
    syntax, lag(int) lead(int) yvar(str) ymin(real) ymax(real) ygap(real) trt_mean(real) ctrl_mean(real) name(str) fes(str) wt_var(str) cluster_var(str) [unwt(real 0)balance(real 0) file_suf(str) title(str)]
    cap drop lag* lead* year_fes*
    local suf ""
    if `balance' == 1 local suf "bal_" 
	keep if inrange(rel,`lead',`lag') | rel ==. 
    assert `lag' > 0 & `lead' < 0
    local abs_lag = abs(`lag')
    local abs_lead = abs(`lead')
    local timeframe = max(`abs_lag', `abs_lead')
    forval i = 1/`timeframe' {
        gen lag`i' = 1 if rel == `i'
        gen lead`i' = 1 if rel == -`i'
    }
    gen lag0 = 1 if rel == 0
    ds lead* lag*
    foreach var in `r(varlist)' {
        replace `var' = 0 if mi(`var')
    }
    local leads
    local lags
    forval i = 2/`abs_lead' {
        local leads lead`i' `leads'
    }
    forval i = 0/`abs_lag' {
        local lags `lags' lag`i'
    }
    forval i = 2010/2019 {
        gen year_fes`i' = 1 if year == `i'
    }
    ds year_fes*
    foreach var in `r(varlist)' {
        replace `var' = 0 if mi(`var')
    }
    local years
    forval i = 2010/2012 {
        local years `years' year_fes`i'
    }
    forval i = 2014/2019 {
        local years `years' year_fes`i'
    }
    preserve
    mat drop _all 
    if `unwt' == 1 {
        reghdfe `yvar' `leads' `lags' lead1 `years' year_fes2013 , absorb(`fes') vce(cluster `cluster_var')
    }
    if `unwt' == 0{
        reghdfe `yvar' `leads' `lags' lead1 `years' year_fes2013  [aw = `wt_var'], absorb(`fes') vce(cluster `cluster_var')
    }
    foreach var in `leads' `lags' lead1 {
        mat row = _b[`var'], _se[`var']
        if "`var'" == "lead1" {
            mat row = 0,0
        }
        mat es = nullmat(es) \ row
    }
    foreach var in `years' year_fes2013 {
        mat year_fes_row = _b[`var'], _se[`var']
        if "`var'" == "year_fes2013" {
            mat year_fes_row = 0,0
        }
        mat year_fes = nullmat(year_fes) \ year_fes_row
    }
    forval i =  2010/2012 {
        local j = 2014-`i'
        lincom year_fes`i' +  lead`j'
        mat trt_coef_row = r(estimate), r(se)
        mat trt_coef = nullmat(trt_coef) \ trt_coef_row
    }
    forval i = 2014/2019 {
        local j = `i' - 2014
        lincom year_fes`i' +  lag`j'
        mat trt_coef_row = r(estimate), r(se)
        mat trt_coef = nullmat(trt_coef) \ trt_coef_row
    } 
    mat trt_coef = trt_coef \ 0,0
    mat es = es , year_fes, trt_coef
    svmat es
    keep es1 es2 es3 es4 es5 es6 
    drop if mi(es1)
    rename (es1 es2 es3 es4 es5 es6) (b se year_fes year_fes_se trt_coef trt_coef_se)
    gen ub = b + 1.96*se
    gen lb = b - 1.96*se
    gen rel = `lead' if _n == 1
    replace rel = rel[_n-1]+1 if _n > 1
    replace rel = rel + 1 if rel >= -1 
    replace rel = -1 if rel == `abs_lag' + 1
    gen upper = `ymax'
    gen year = rel + 2014
    reg year_fes rel 
    predict control_trend, xb
    sum control_trend if rel == -1, d
    local base =  r(mean)
    replace year_fes = year_fes - control_trend + `base'
    replace trt_coef = trt_coef - control_trend + `base'
    gen year_fes_ub = year_fes + 1.96*year_fes_se
    gen year_fes_lb = year_fes - 1.96*year_fes_se
    gen trt_coef_ub = trt_coef + 1.96*trt_coef_se
    gen trt_coef_lb = trt_coef - 1.96*trt_coef_se 
    gen rel_year_fes = year + 0.1
    
    hashsort rel
    sum ub , d
    local ymax = max(`ymax', round(r(max),0.1))
    sum lb , d
    local ymin = min(`ymin', round(r(min),0.1))
    export delimited using "../output/estimates/`suf'es_`yvar'_estimates`file_suf'.csv", replace
    save "../temp/`suf'es_`yvar'_estimates`file_suf'", replace
    sum year , d
    local year_min = r(min)
    local year_max = r(max)
   /* if "`title'" == "" {
        tw rcap ub lb rel if rel != -1 & inrange(rel, `lead', `lag') , lcolor(ebblue%70) msize(vsmall) || ///
        scatter b rel if inrange(rel, `lead', `lag') , mcolor(ebblue) || ///
        scatteri `ymax' -0.25 `ymax' 0.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
        xlab(`lead'(1)`lag', labsize(vsmall)) xtitle("Relative Year", size(small)) ///
        ytitle("`name'", size(small)) ylab(`ymin'(`ygap')`ymax', labsize(vsmall)) yline(0, lcolor(gs10) lpattern(solid))  ///
        legend(on order(- "Treatment Level Avg. in t = -1: `trt_mean'" "Control Level Avg. in t = -1: `ctrl_mean'") pos(6) rows(2))  ///
        plotregion(margin(sides))
        graph export "../output/figures/es/`suf'es_`yvar'_`file_suf'.pdf", replace
    }*/
        tw rcap ub lb year if rel != -1 & inrange(rel, `lead', `lag') , lcolor(ebblue%70) msize(vsmall) || ///
        scatter b year if inrange(rel, `lead', `lag') , mcolor(ebblue) || ///
        scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
        xlab(`year_min'(1)`year_max') xtitle("Year") ///
        ytitle("`name'") ylab(`ymin'(`ygap')`ymax') yline(0, lcolor(gs10) lpattern(solid)) ///
        legend(on order(- "Treatment Level Avg. in t = -1: `trt_mean'" "Control Level Avg. in t = -1: `ctrl_mean'") pos(7) rows(2) bmargin(zero) size(small)) ///
        title(`title', size(small)) plotregion(margin(sides))
        graph export "../output/figures/es/`suf'es_`yvar'_`file_suf'.pdf", replace

        tw rcap trt_coef_ub trt_coef_lb year if rel != -1 & inrange(rel, `lead', `lag') , lcolor(ebblue%70) msize(vsmall) || ///
        rcap year_fes_ub year_fes_lb rel_year_fes if rel != -1 & inrange(rel, `lead', `lag') , lcolor(dkorange%70) lpattern(dash) msize(vsmall) || ///
        scatter trt_coef year if inrange(rel, `lead', `lag') , mcolor(ebblue) || ///
        scatter year_fes rel_year_fes if inrange(rel, `lead', `lag') , mcolor(dkorange) msymbol(diamond) || ///
        scatteri `ymax' 2013.75 `ymax' 2014.25 , bcolor(gs12%30) recast(area) base(`ymin') ///
        xlab(`year_min'(1)`year_max') xtitle("Year") ///
        ytitle("`name'") ylab(`ymin'(`ygap')`ymax') yline(0, lcolor(gs10) lpattern(solid)) ///
        legend(on order(1 "Treatment Level Avg. in t = -1: `trt_mean'" 2 "Control Level Avg. in t = -1: `ctrl_mean'") pos(7) rows(2) bmargin(zero) size(small)) ///
        title(`title', size(small)) plotregion(margin(sides))
        graph export "../output/figures/es/split_`suf'es_`yvar'_`file_suf'.pdf", replace
    restore
end
**
main
