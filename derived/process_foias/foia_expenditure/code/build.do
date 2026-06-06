set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main
    boe 

    // Run the observed (FOIA) first stage once -- it doesn't depend on
    // imputation tag. Save its estimates so we can stack them next to the
    // imputed columns inside imputed_expenditure_fd.
    capture noisily observed_expenditure_fd
    local rc = _rc
    if `rc' {
        di as error "observed_expenditure_fd failed (rc=`rc'); continuing"
    }

    capture noisily imputed_expenditure_fd "_restricted"
    local rc = _rc
    if `rc' {
        di as error "imputed_expenditure_fd failed (rc=`rc'); continuing"
    }

    // Observed-only: qty (headline) + price (robustness). Imputed pipeline
    // doesn't produce per-author price/qty so these are FOIA-sample only.
    capture noisily observed_qty_price_fd
    local rc = _rc
    if `rc' {
        di as error "observed_qty_price_fd failed (rc=`rc'); continuing"
    }

    // Level trajectories by exposure quartile -- shows whether the
    // aggregate "spend up, qty flat, price up" decomposition holds within
    // and across exposure groups. Complements the FD coefs above.
    capture noisily level_trajectories_by_exposure
    local rc = _rc
    if `rc' {
        di as error "level_trajectories_by_exposure failed (rc=`rc'); continuing"
    }
end

program imputed_expenditure_fd
    // First-stage on imputed annual spending, run two ways:
    //   1. Long difference: per-author (post mean - pre mean) regressed on
    //      exposure (+ mkt_spend_shr). Cross-section, robust SE.
    //   2. Year-on-year FD: D.ln(spend) on D.Z_it (+ D.s_it) with year FE,
    //      clustered on athr.
    //
    // `tag' selects which Python-pipeline outputs to consume:
    //   ""           -> baseline artifacts
    //   "_restricted"-> --restrict-to-foia-clusters variant
    args tag
    local label = cond("`tag'" == "", "baseline", "`tag'")
    di _newline "=== Imputed annual spending first-difference  [`label'] ==="

    // -------- Build imputed panel once, save to ../temp/ --------
    import delimited ../external/imputed/final_imputed_exposure`tag'.csv, ///
        varnames(1) stringcols(1) clear
    save ../temp/exposure`tag'.dta, replace

    import delimited ../external/imputed/imputed_annual_spend`tag'.csv, ///
        varnames(1) stringcols(1) clear
    keep if inrange(year, 2010, 2019)
    drop if missing(spend) & missing(lab_spend) & missing(spend_keep)
    merge m:1 athr_id using ../temp/exposure`tag'.dta, keep(3) nogen
    drop if exposure <= 0
    foreach v in spend lab_spend spend_keep {
        gen ln_`v' = ln(`v' + 1)
    }
    save ../temp/imputed_panel`tag'.dta, replace

    // -------- Long difference --------
    use ../temp/imputed_panel`tag'.dta, clear
    gen post = year >= 2014
    gcollapse (mean) ln_spend ln_lab_spend ln_spend_keep ///
                     exposure mkt_spend_shr, by(athr_id post)
    reshape wide ln_spend ln_lab_spend ln_spend_keep, ///
        i(athr_id exposure mkt_spend_shr) j(post)
    foreach v in ln_spend ln_lab_spend ln_spend_keep {
        gen d_`v' = `v'1 - `v'0
    }

    eststo clear
    foreach v in ln_spend ln_lab_spend ln_spend_keep {
        reg d_`v' exposure mkt_spend_shr, vce(robust)
        eststo m_d_`v'
        binscatter d_`v' exposure, controls(mkt_spend_shr) ///
            ytitle("D.ln(imputed `v' + 1)") xtitle("exposure")
        graph export ../output/bs_imp_longdiff_`v'`tag'.pdf, replace
    }
    capture confirm file ../temp/observed_longdiff.ster
    if !_rc {
        estimates use ../temp/observed_longdiff.ster
        eststo m_observed
        esttab m_d_ln_spend m_d_ln_lab_spend m_d_ln_spend_keep m_observed ///
            using ../output/firststage_longdiff`tag'.tex, replace ///
            b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
            mtitles("Imp. D.ln(spend)" "Imp. D.ln(lab\_spend)" ///
                    "Imp. D.ln(spend\_keep)" "Obs. D.ln(keep==1)") ///
            keep(exposure mkt_spend_shr) ///
            addnotes("Long difference: per-author post-pre mean of LHS regressed on exposure." ///
                     "Imputed sample = universe authors (`label'), exposure>0." ///
                     "Observed sample = FOIA authors, keep==1 lab spend, exposure>0." ///
                     "Robust SE.")
    }
    else {
        esttab m_d_ln_spend m_d_ln_lab_spend m_d_ln_spend_keep ///
            using ../output/firststage_longdiff`tag'.tex, replace ///
            b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
            mtitles("Imp. D.ln(spend)" "Imp. D.ln(lab\_spend)" ///
                    "Imp. D.ln(spend\_keep)") ///
            keep(exposure mkt_spend_shr) ///
            addnotes("Long difference. Imputed universe (`label'), exposure>0. Robust SE.")
    }

    // -------- Year-on-year FD --------
    use ../temp/imputed_panel`tag'.dta, clear
    gegen athr = group(athr_id)
    xtset athr year
    gen post = year >= 2014
    gen Z_it = exposure * post
    gen s_it = mkt_spend_shr * post
    // Materialize FDs so binscatter2 can residualize against them
    foreach v in ln_spend ln_lab_spend ln_spend_keep Z_it s_it {
        gen d_`v' = D.`v'
    }

    eststo clear
    foreach v in ln_spend ln_lab_spend ln_spend_keep {
        reghdfe d_`v' d_Z_it d_s_it, absorb(year) vce(cluster athr)
        eststo m_`v'
        binscatter2 d_`v' d_Z_it, absorb(year) controls(d_s_it) ///
            ytitle("D.ln(imputed `v')") xtitle("D.Z_it = exposure x D.post")
        graph export ../output/bs_imp_yoyfd_`v'`tag'.pdf, replace
    }
    capture confirm file ../temp/observed_yoyfd.ster
    if !_rc {
        estimates use ../temp/observed_yoyfd.ster
        eststo m_observed
        esttab m_ln_spend m_ln_lab_spend m_ln_spend_keep m_observed ///
            using ../output/firststage_yoyfd`tag'.tex, replace ///
            b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
            mtitles("Imp. D.ln(spend)" "Imp. D.ln(lab\_spend)" ///
                    "Imp. D.ln(spend\_keep)" "Obs. D.ln(keep==1)") ///
            keep(d_Z_it d_s_it D.Z_it D.s_it) ///
            addnotes("Year-on-year FD: D.ln(LHS) on D.Z_it (+ D.s_it), year FE, cluster athr." ///
                     "Imputed sample = universe (`label'), exposure>0." ///
                     "Observed sample = FOIA authors, keep==1 lab spend, exposure>0.")
    }
    else {
        esttab m_ln_spend m_ln_lab_spend m_ln_spend_keep ///
            using ../output/firststage_yoyfd`tag'.tex, replace ///
            b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
            mtitles("Imp. D.ln(spend)" "Imp. D.ln(lab\_spend)" ///
                    "Imp. D.ln(spend\_keep)") ///
            keep(d_Z_it d_s_it) ///
            addnotes("Year-on-year FD. Imputed universe (`label'), exposure>0. Year FE, cluster athr.")
    }
end

program observed_expenditure_fd
    // First stage on directly observed FOIA expenditure, high-confidence
    // consumables only (categories_tfidf.keep == 1). Saved estimates are
    // picked up by imputed_expenditure_fd to build the side-by-side table.
    di _newline "=== Observed (FOIA, keep==1) first-difference ==="

    use ../external/samp/merged_foias_with_pis, clear
    gen year = year(date(date, "YMD"))
    keep if inrange(year, 2010, 2019)
    drop if mi(athr_id)
    merge m:1 category using ../external/categories/categories_tfidf, ///
        keep(1 3) nogen
    keep if keep == 1
    // Missing spend is a data-quality flag -- includes misclassified
    // instruments (e.g. KPA/Gilson autosamplers tagged as cuvettes/vials)
    // that have a printed unit price but no recorded expenditure.
    drop if mi(spend)
    gcollapse (sum) spend, by(athr_id year)
    merge m:1 athr_id using ../external/real_exposure/athr_exposure, ///
        keep(3) nogen
    gegen athr = group(athr_id)
    xtset athr year
    tsfill
    replace spend = 0 if mi(spend)
    foreach v in exposure mkt_spend_shr {
        bys athr (year): replace `v' = `v'[_n-1] if mi(`v')
        gsort athr -year
        by athr: replace `v' = `v'[_n-1] if mi(`v')
        hashsort athr year
    }
    drop if exposure <= 0
    keep if inrange(year, 2010, 2019)
    gen ln_spend = ln(spend + 1)
    save ../temp/observed_panel.dta, replace

    // -------- Long difference --------
    use ../temp/observed_panel.dta, clear
    gen post = year >= 2014
    gcollapse (mean) ln_spend exposure mkt_spend_shr, by(athr_id post)
    reshape wide ln_spend, i(athr_id exposure mkt_spend_shr) j(post)
    gen d_ln_spend = ln_spend1 - ln_spend0

    reg d_ln_spend exposure mkt_spend_shr, vce(robust)
    estimates save ../temp/observed_longdiff.ster, replace
    eststo clear
    eststo m_observed
    esttab m_observed using ../output/observed_longdiff.tex, replace ///
        b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
        mtitles("D.ln(keep==1 spend)") ///
        keep(exposure mkt_spend_shr) ///
        addnotes("Long difference. FOIA authors, keep==1 lab spend, exposure>0. Robust SE.")

    binscatter d_ln_spend exposure, controls(mkt_spend_shr) ///
        ytitle("{&Delta}ln(observed keep==1 spend + 1)") xtitle("exposure")
    graph export ../output/bs_observed_longdiff.pdf, replace

    // -------- Year-on-year FD --------
    use ../temp/observed_panel.dta, clear
    xtset athr year
    gen post = year >= 2014
    gen Z_it = exposure * post
    gen s_it = mkt_spend_shr * post
    foreach v in ln_spend Z_it s_it {
        gen d_`v' = D.`v'
    }

    reghdfe d_ln_spend d_Z_it d_s_it, absorb(year) vce(cluster athr)
    estimates save ../temp/observed_yoyfd.ster, replace
    eststo clear
    eststo m_observed
    esttab m_observed using ../output/observed_yoyfd.tex, replace ///
        b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
        mtitles("D.ln(keep==1 spend)") ///
        keep(d_Z_it d_s_it) ///
        addnotes("Year-on-year FD. FOIA authors, keep==1 lab spend, exposure>0. Year FE, cluster athr.")

    binscatter2 d_ln_spend d_Z_it, absorb(year) controls(d_s_it) ///
        ytitle("D.ln(observed keep==1 spend + 1)") xtitle("D.Z_it = exposure x D.post")
    graph export ../output/bs_observed_yoyfd.pdf, replace
end

program observed_qty_price_fd
    // Observed-only first stages on quantity (headline) and price (robustness):
    //   - qty: ln(qty+1), tsfill + zero-fill (no purchase = qty 0). Captures
    //     extensive + intensive margin response.
    //   - price: ln(price), no zero fill (no purchase != price 0). Sample
    //     restricted to athr-years with positive observed price. Long-diff
    //     additionally requires both pre and post means to exist per athr.
    // No imputed counterpart -- imputation pipeline only produces spend.
    di _newline "=== Observed (FOIA, keep==1) qty & price first-difference ==="

    use ../external/samp/merged_foias_with_pis, clear
    gen year = year(date(date, "YMD"))
    keep if inrange(year, 2010, 2019)
    drop if mi(athr_id)
    merge m:1 category using ../external/categories/categories_tfidf, ///
        keep(1 3) nogen
    keep if keep == 1
    drop if mi(spend)  // see observed_expenditure_fd for rationale

    gcollapse (sum) qty (mean) price, by(athr_id year)
    merge m:1 athr_id using ../external/real_exposure/athr_exposure, ///
        keep(3) nogen
    gegen athr = group(athr_id)
    xtset athr year
    tsfill
    replace qty = 0 if mi(qty)
    foreach v in exposure mkt_spend_shr {
        bys athr (year): replace `v' = `v'[_n-1] if mi(`v')
        gsort athr -year
        by athr: replace `v' = `v'[_n-1] if mi(`v')
        hashsort athr year
    }
    drop if exposure <= 0
    keep if inrange(year, 2010, 2019)
    gen ln_qty   = ln(qty + 1)
    gen ln_price = ln(price)
    save ../temp/observed_qty_price_panel.dta, replace

    // ============ Quantity (headline) ============
    // -------- long difference --------
    use ../temp/observed_qty_price_panel.dta, clear
    gen post = year >= 2014
    gcollapse (mean) ln_qty exposure mkt_spend_shr, by(athr_id post)
    reshape wide ln_qty, i(athr_id exposure mkt_spend_shr) j(post)
    gen d_ln_qty = ln_qty1 - ln_qty0

    eststo clear
    reg d_ln_qty exposure mkt_spend_shr, vce(robust)
    eststo m_qty
    esttab m_qty using ../output/firststage_qty_longdiff.tex, replace ///
        b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
        mtitles("D.ln(keep==1 qty)") ///
        keep(exposure mkt_spend_shr) ///
        addnotes("Long difference. FOIA authors, keep==1 qty, exposure>0. Robust SE.")

    binscatter d_ln_qty exposure, controls(mkt_spend_shr) ///
        ytitle("D.ln(observed keep==1 qty + 1)") xtitle("exposure")
    graph export ../output/bs_obs_qty_longdiff.pdf, replace

    // -------- year-on-year FD --------
    use ../temp/observed_qty_price_panel.dta, clear
    xtset athr year
    gen post = year >= 2014
    gen Z_it = exposure * post
    gen s_it = mkt_spend_shr * post
    foreach v in ln_qty Z_it s_it {
        gen d_`v' = D.`v'
    }

    eststo clear
    reghdfe d_ln_qty d_Z_it d_s_it, absorb(year) vce(cluster athr)
    eststo m_qty
    esttab m_qty using ../output/firststage_qty_yoyfd.tex, replace ///
        b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
        mtitles("D.ln(keep==1 qty)") ///
        keep(d_Z_it d_s_it) ///
        addnotes("Year-on-year FD. FOIA authors, keep==1 qty, exposure>0. Year FE, cluster athr.")

    binscatter2 d_ln_qty d_Z_it, absorb(year) controls(d_s_it) ///
        ytitle("D.ln(observed keep==1 qty + 1)") xtitle("D.Z_it = exposure x D.post")
    graph export ../output/bs_obs_qty_yoyfd.pdf, replace

    // ============ Price (robustness) ============
    // -------- long difference --------
    use ../temp/observed_qty_price_panel.dta, clear
    drop if mi(ln_price)
    gen post = year >= 2014
    gcollapse (mean) ln_price exposure mkt_spend_shr, by(athr_id post)
    bys athr_id: gen n_periods = _N
    keep if n_periods == 2
    drop n_periods
    reshape wide ln_price, i(athr_id exposure mkt_spend_shr) j(post)
    gen d_ln_price = ln_price1 - ln_price0

    eststo clear
    reg d_ln_price exposure mkt_spend_shr, vce(robust)
    eststo m_price
    esttab m_price using ../output/robustness_price_longdiff.tex, replace ///
        b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
        mtitles("D.ln(keep==1 price)") ///
        keep(exposure mkt_spend_shr) ///
        addnotes("Long difference. FOIA authors, keep==1 mean price, conditional on transacting both pre and post, exposure>0. Robust SE.")

    binscatter d_ln_price exposure, controls(mkt_spend_shr) ///
        ytitle("D.ln(observed keep==1 mean price)") xtitle("exposure")
    graph export ../output/bs_obs_price_longdiff.pdf, replace

    // -------- year-on-year FD --------
    use ../temp/observed_qty_price_panel.dta, clear
    drop if mi(ln_price)
    xtset athr year
    gen post = year >= 2014
    gen Z_it = exposure * post
    gen s_it = mkt_spend_shr * post
    foreach v in ln_price Z_it s_it {
        gen d_`v' = D.`v'
    }

    eststo clear
    reghdfe d_ln_price d_Z_it d_s_it, absorb(year) vce(cluster athr)
    eststo m_price
    esttab m_price using ../output/robustness_price_yoyfd.tex, replace ///
        b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
        mtitles("D.ln(keep==1 price)") ///
        keep(d_Z_it d_s_it) ///
        addnotes("Year-on-year FD. FOIA authors, keep==1 mean price, conditional on transacting, exposure>0. Year FE, cluster athr.")

    binscatter2 d_ln_price d_Z_it, absorb(year) controls(d_s_it) ///
        ytitle("D.ln(observed keep==1 mean price)") xtitle("D.Z_it = exposure x D.post")
    graph export ../output/bs_obs_price_yoyfd.pdf, replace
end

program level_trajectories_by_exposure
    // Pure level trajectories of spend / qty / price by exposure quartile
    // (FOIA, keep==1). No FE, no controls. Mirrors the aggregate plots
    // people typically show alongside FD tables -- helps see whether the
    // market-level pattern (e.g. price+spend up, qty flat) shows up
    // similarly within each exposure group, or whether it's concentrated
    // in low-exposure athrs. Also outputs the pooled aggregate trajectory
    // (Total spend, Total qty, Mean price) for comparison.
    di _newline "=== Level trajectories by exposure quartile (FOIA, keep==1) ==="

    use ../external/samp/merged_foias_with_pis, clear
    gen year = year(date(date, "YMD"))
    keep if inrange(year, 2010, 2019)
    drop if mi(athr_id)
    merge m:1 category using ../external/categories/categories_tfidf, ///
        keep(1 3) nogen
    keep if keep == 1
    drop if mi(spend)  // see observed_expenditure_fd for rationale
    gcollapse (sum) spend qty (mean) price, by(athr_id year)
    merge m:1 athr_id using ../external/real_exposure/athr_exposure, ///
        keep(3) nogen
    drop if exposure <= 0

    // Time-invariant exposure quartile per athr (computed before tsfill so
    // pooled quantiles use one obs per athr, not one per athr-year).
    preserve
        bys athr_id: keep if _n == 1
        sum exposure, d
        local p25 = r(p25)
        local p50 = r(p50)
        local p75 = r(p75)
        gen qrtl = 1 if exposure < `p25'
        replace qrtl = 2 if inrange(exposure, `p25', `p50') & mi(qrtl)
        replace qrtl = 3 if inrange(exposure, `p50', `p75') & mi(qrtl)
        replace qrtl = 4 if exposure >= `p75' & mi(qrtl)
        keep athr_id qrtl
        save ../temp/exposure_quartiles.dta, replace
    restore
    merge m:1 athr_id using ../temp/exposure_quartiles.dta, keep(3) nogen

    // tsfill + zero-fill spend & qty so quartile means reflect both
    // extensive (any purchase) and intensive (how much) margins.
    // Price kept missing on no-purchase years -> quartile mean = mean price
    // among athrs who actually transacted.
    gegen athr = group(athr_id)
    xtset athr year
    tsfill
    replace spend = 0 if mi(spend)
    replace qty   = 0 if mi(qty)
    foreach v in qrtl exposure mkt_spend_shr {
        bys athr (year): replace `v' = `v'[_n-1] if mi(`v')
        gsort athr -year
        by athr: replace `v' = `v'[_n-1] if mi(`v')
        hashsort athr year
    }
    keep if inrange(year, 2010, 2019)
    drop if mi(qrtl)
    save ../temp/observed_levels_panel.dta, replace

    // -------- per-athr mean by quartile-year --------
    preserve
        gcollapse (mean) spend qty price, by(qrtl year)
        foreach v in spend qty price {
            if "`v'" == "spend" local ylab "Mean per-athr spend (\$, keep==1)"
            if "`v'" == "qty"   local ylab "Mean per-athr qty (keep==1)"
            if "`v'" == "price" local ylab "Mean unit price (\$, keep==1)"
            tw line `v' year if qrtl == 1, lcolor(lavender)  lwidth(medium) || ///
               line `v' year if qrtl == 2, lcolor(dkorange)  lwidth(medium) || ///
               line `v' year if qrtl == 3, lcolor(ebblue)    lwidth(medium) || ///
               line `v' year if qrtl == 4, lcolor(dkemerald) lwidth(medium) ///
               , legend(on order(1 "Q1 (lowest exposure)" 2 "Q2" 3 "Q3" 4 "Q4 (highest exposure)") ///
                        pos(7) ring(0) size(small)) ///
                 xtitle("Year") ytitle("`ylab'") ///
                 xline(2014, lpattern(dash) lcolor(gs10)) plotregion(margin(sides))
            graph export ../output/levels_`v'_by_qrtl.pdf, replace
        }
    restore

    // -------- pooled aggregate (everyone) --------
    preserve
        gcollapse (sum) tot_spend = spend tot_qty = qty (mean) mean_price = price, by(year)
        foreach v in tot_spend tot_qty mean_price {
            if "`v'" == "tot_spend"  local ylab "Total spend (\$, keep==1, all athrs)"
            if "`v'" == "tot_qty"    local ylab "Total qty (keep==1, all athrs)"
            if "`v'" == "mean_price" local ylab "Mean unit price (\$, keep==1, all athrs)"
            tw line `v' year, lcolor(ebblue) lwidth(medium) ///
               , xtitle("Year") ytitle("`ylab'") ///
                 xline(2014, lpattern(dash) lcolor(gs10)) ///
                 legend(off) plotregion(margin(sides))
            graph export ../output/levels_agg_`v'.pdf, replace
        }
    restore
end


program boe
    use ../external/rf_athrs/es_all_jrnls_r1_r2_public, clear
    contract athr_id exposure
    drop _freq
    save ../temp/rf_athrs, replace
    use ../external/samp/merged_foias_with_pis,  clear
    keep if inlist(uni , "utdallas", "umich")
    merge m:1 athr_id using ../temp/rf_athrs, keep(3) nogen
    drop if mi(athr_id)
    gen year = year(date(date, "YMD"))
    drop if year > 2013
    merge m:1 category using ../external/categories/categories_tfidf, keep(1 3)
    rename _merge nonlab
    replace nonlab = 0 if nonlab == 3
    sum spend, d
    local total_spend = r(sum)
    sum spend if nonlab == 0
    local lab_spend = r(sum)
    di "% lab spend = " `lab_spend'/`total_spend'*100
    sum spend if keep == 1 & nonlab == 0 | bad_control == 1
    local spend_in_sample = r(sum)
    di "%lab spend classified as high quality= "  `spend_in_sample'/`lab_spend'*100
    replace keep = 2 if keep ==.
    gen nonlab_spend = spend if nonlab == 1
    gen lab_spend = spend if nonlab == 0
    gen hq = keep == 1 | (bad_control == 1 & support >= 25 & precision >= 0.8 & recall >= 0.8)
    collapse (sum) spend nonlab_spend lab_spend (mean) exposure, by(athr_id year hq)
    gen hq_labspend = lab_spend if hq == 1
    gen lq_labspend = lab_spend if hq == 0
    collapse (sum) tot_spend = spend nonlab_spend lab_spend hq_labspend lq_labspend  (mean) exposure, by(athr_id year)
    gen perc_lab_spend = lab_spend/tot_spend* 100
    gen perc_nonlab_spend = nonlab_spend/tot_spend* 100
    collapse (mean) tot_spend nonlab_spend lab_spend hq_labspend lq_labspend perc_lab_spend perc_nonlab_spend exposure, by(athr_id)
    graph bar lab_spend nonlab_spend, over(athr_id ,sort((mean) tot_spend) descending) stack bar(1, color(lavender%70)) bar(2, color(dkorange%70)) legend(on order(- "Lab Spend" - "Non-Lab Spend") pos(1) ring(0) size(small) region(fcolor(none))) ytitle("Average Annual Spend ($)") plotregion(margin(sides))
    graph export ../output/avg_spend_by_athr.pdf, replace
    sum lab_spend if lab_spend >0, d
    local mean_lab_spend : di %6.2f r(mean)
    local sd_lab_spend : di %6.2f r(sd)
    local min_lab_spend : di %6.2f r(min)
    local max_lab_spend : di %10.2f r(max)
    local N_lab_spend : di %6.0f r(N)
    local q1_lab_spend : di %6.2f r(p25)
    local q3_lab_spend : di %6.2f r(p75)
    local median_lab_spend : di %6.2f r(p50)
   tw hist lab_spend if lab_spend >0, color(edkblue) frac width(5000) xlab(0(7500)100000, angle(45)) ///
       xtitle("Consumables Expenditure ($)") ytitle("Fraction of PI-Years") legend(on order(- "Mean = `mean_lab_spend'" "SD = `sd_lab_spend'" "Min = `min_lab_spend'" "Q1 = `q1_lab_spend'" "Median = `median_lab_spend'" "Q3 = `q3_lab_spend'" "Max = `max_lab_spend'") pos(1) ring(0) region(fcolor(none)) size(small))
   graph export ../output/lab_spend.pdf, replace
   kdensity perc_lab_spend
   graph export ../output/perc_lab_spend.pdf, replace
   kdensity perc_nonlab_spend
   graph export ../output/perc_nonlab_spend.pdf, replace
   stop
   gcollapse (mean) perc_lab_spend perc_nonlab_spend tot_spend nonlab_spend lab_spend (count) year, by(athr_id)
   binscatter perc_lab_spend lab_spend
   graph export ../output/bs_perc_lab_spend_by_lab_spend.pdf, replace
   binscatter perc_lab_spend tot_spend
   graph export ../output/bs_perc_lab_spend_by_tot_spend.pdf, replace
   binscatter perc_nonlab_spend nonlab_spend
   graph export ../output/bs_perc_nonlab_spend_by_lab_spend.pdf, replace
   binscatter lab_spend tot_spend
   graph export ../output/bs_lab_spend_by_tot_spend.pdf, replace
end

main
