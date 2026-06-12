 set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main
   build_panel
   did
   event_study
   build_uc_panel
   uc_did
end

// -----------------------------------------------------------------------------
// build_panel: construct the university-by-year analysis panel.
//   - exposure_j = sum_{m in treated, high-conf} s_jm * b_eb_m
//   - s_treat_j  = sum_{m in treated, high-conf} s_jm  (overall treated share)
//   - s_jm: uni j's pre-2013 spend in market m as share of pre-2013 spend
//           across all high-confidence markets (treated + control).
//   - outcomes summed over high-confidence markets only:
//       ctrl_spend_jt, ctrl_qty_jt, treat_spend_jt, tot_spend_jt
//   - sample: unis with positive pre-2013 spend in both treated and control
//             high-conf markets, observed both before and after 2014.
// -----------------------------------------------------------------------------
program build_panel
    use ../external/samp/uni_category_yr_tfidf, clear
    keep category year uni_id treated raw_spend raw_qty
    // --- pre-2013 shares and exposure -----------------------------------------
    preserve
    keep if year <= 2013
    gcollapse (sum) raw_spend, by(uni_id category treated)
    bys uni_id: egen tot_pre_spend = total(raw_spend)
    gen s_jm = raw_spend / tot_pre_spend
    // pre-period treated and control totals (for sample restriction)
    by uni_id: egen pre_treat_spend = total(raw_spend * (treated == 1))
    by uni_id: egen pre_ctrl_spend  = total(raw_spend * (treated == 0))
    // merge EB-shrunk price betas (only present for treated markets)
    merge m:1 category using ../external/betas/did_coefs_eb_price, ///
        keepusing(b_eb) keep(1 3) nogen
    gen exp_contrib    = cond(treated == 1, s_jm * b_eb, 0)
    gen s_treat_contrib = cond(treated == 1, s_jm, 0)
    gcollapse (sum) exposure = exp_contrib s_treat = s_treat_contrib ///
              (first) pre_treat_spend pre_ctrl_spend tot_pre_spend, by(uni_id)
    // sample restriction: positive pre-2013 spend in both treated and control
    keep if pre_treat_spend > 0 & pre_ctrl_spend > 0 & !mi(exposure) & !mi(s_treat)
    keep uni_id exposure s_treat tot_pre_spend
    tempfile exposure_xw
    save `exposure_xw'
    restore

    // --- aggregate outcomes to uni-year ---------------------------------------
    gen ctrl_spend  = raw_spend * (treated == 0)
    gen treat_spend = raw_spend * (treated == 1)
    gen ctrl_qty    = raw_qty   * (treated == 0)
    gen treat_qty   = raw_qty   * (treated == 1)
    gcollapse (sum) ctrl_spend treat_spend ctrl_qty treat_qty raw_spend raw_qty, by(uni_id year)
    rename raw_spend tot_spend
    rename raw_qty   tot_qty

    // --- merge to exposure crosswalk (restricts sample) -----------------------
    merge m:1 uni_id using `exposure_xw', assert(1 3) keep(3) nogen

    // require uni observed both pre and post 2014
    bys uni_id: egen min_year = min(year)
    bys uni_id: egen max_year = max(year)
    keep if min_year < 2014 & max_year >= 2014
    drop min_year max_year

    // outcomes (log(1+x) per spec discussion: keeps zero-spend uni-years)
    foreach v in ctrl_spend ctrl_qty treat_spend treat_qty tot_spend {
        gen log1_`v' = ln(1 + `v')
    }

    // pre-2013 uni spending for weighted regressions
    gen wt_spend = tot_pre_spend

    label var exposure     "University exposure: sum_m s_jm * b_eb_m (treated mkts)"
    label var s_treat      "Pre-2013 treated-market spending share"
    label var ctrl_spend   "Spend in high-conf control markets (level)"
    label var treat_spend  "Spend in high-conf treated markets (level)"
    label var tot_spend    "Spend in all high-conf markets (level)"
    label var ctrl_qty     "Quantity in high-conf control markets (level)"
    label var treat_qty    "Quantity in high-conf treated markets (level)"
    save ../temp/uni_yr_panel, replace
end

// -----------------------------------------------------------------------------
// did: pooled difference-in-differences (single Post coefficient).
//   y_jt = mu_j + lambda_t + beta * Post_t * Exposure_j
//                          + gamma * Post_t * S_j  (optional)
//   Cluster SEs at uni_id.
// -----------------------------------------------------------------------------
program did
    use ../temp/uni_yr_panel, clear
    gen post = year >= 2014
    gen post_exp = post * exposure
    gen post_s   = post * s_treat

    tempname memhold
    tempfile didres
    postfile `memhold' str40 outcome str20 spec str40 rhs ///
        double b se str10 stars int N using `didres', replace

    foreach yvar in log1_ctrl_spend log1_ctrl_qty log1_tot_spend log1_treat_spend log1_treat_qty {
        // raw (no S control)
        reghdfe `yvar' post_exp, absorb(uni_id year) cluster(uni_id)
        local N = e(N)
        local b  = _b[post_exp]
        local se = _se[post_exp]
        local p  = 2*(1 - normal(abs(`b'/`se')))
        local stars = cond(`p'<.01,"***",cond(`p'<.05,"**",cond(`p'<.1,"*","")))
        post `memhold' ("`yvar'") ("raw") ("post_exp") (`b') (`se') ("`stars'") (`N')

        // identified (S control)
        reghdfe `yvar' post_exp post_s, absorb(uni_id year) cluster(uni_id)
        local N = e(N)
        local b  = _b[post_exp]
        local se = _se[post_exp]
        local p  = 2*(1 - normal(abs(`b'/`se')))
        local stars = cond(`p'<.01,"***",cond(`p'<.05,"**",cond(`p'<.1,"*","")))
        post `memhold' ("`yvar'") ("with_S") ("post_exp") (`b') (`se') ("`stars'") (`N')

        // also save Post×S coefficient from the identified spec
        local b  = _b[post_s]
        local se = _se[post_s]
        local p  = 2*(1 - normal(abs(`b'/`se')))
        local stars = cond(`p'<.01,"***",cond(`p'<.05,"**",cond(`p'<.1,"*","")))
        post `memhold' ("`yvar'") ("with_S") ("post_s") (`b') (`se') ("`stars'") (`N')
    }
    postclose `memhold'

    use `didres', clear
    save ../output/estimates/uniyr_did, replace
    export delimited using ../output/estimates/uniyr_did.csv, replace
    list, sepby(outcome) noobs
end

// -----------------------------------------------------------------------------
// event_study: continuous-treatment event study.
//   y_jt = mu_j + lambda_t + sum_n beta_n [1{rel=n} * Exposure_j]
//                          + sum_n gamma_n [1{rel=n} * S_j]   (optional)
//   rel = year - 2014, base period rel = -1 (year 2013).
//   Cluster SEs at uni_id.
// -----------------------------------------------------------------------------
program event_study
    foreach yvar in log1_ctrl_spend log1_ctrl_qty log1_tot_spend log1_treat_spend log1_treat_qty {
        foreach spec in raw with_S {
            cont_es, yvar(`yvar') spec(`spec')
        }
    }
end

program cont_es
    syntax, yvar(str) spec(str)
    use ../temp/uni_yr_panel, clear
    gen rel = year - 2014
    qui sum rel
    local rmin = r(min)
    local rmax = r(max)

    // build event-time interactions; base = rel == -1
    forval k = `rmin'/`rmax' {
        if `k' == -1 continue
        local tag = cond(`k' < 0, "n" + string(abs(`k')), string(`k'))
        gen exp_`tag' = exposure * (rel == `k')
        gen str_`tag' = s_treat * (rel == `k')
    }
    ds exp_*
    local exp_terms `r(varlist)'
    ds str_*
    local str_terms `r(varlist)'

    if "`spec'" == "raw" {
        reghdfe `yvar' `exp_terms', absorb(uni_id year) cluster(uni_id)
    }
    else {
        reghdfe `yvar' `exp_terms' `str_terms', absorb(uni_id year) cluster(uni_id)
    }
    local Nobs = e(N)

    // collect coefficients
    mat drop _all
    forval k = `rmin'/`rmax' {
        if `k' == -1 {
            mat row = `k', 0, 0
        }
        else {
            local tag = cond(`k' < 0, "n" + string(abs(`k')), string(`k'))
            mat row = `k', _b[exp_`tag'], _se[exp_`tag']
        }
        mat es = nullmat(es) \ row
    }

    preserve
    clear
    svmat es
    rename (es1 es2 es3) (rel b se)
    gen ub = b + 1.96*se
    gen lb = b - 1.96*se
    gen year = rel + 2014
    gen yvar = "`yvar'"
    gen spec = "`spec'"
    export delimited using ///
        ../output/estimates/es_`yvar'_`spec'.csv, replace
    save ../temp/es_`yvar'_`spec', replace

    sum ub, d
    local ymax = round(r(max), 0.01) + 0.01
    sum lb, d
    local ymin = round(r(min), 0.01) - 0.01
    qui sum rel
    local xmin = r(min)
    local xmax = r(max)

    tw rcap ub lb rel if rel != -1, lcolor(ebblue%70) msize(vsmall) || ///
       scatter b rel, mcolor(ebblue) msize(small) || ///
       scatteri `ymax' -0.25 `ymax' 0.25, bcolor(gs12%30) recast(area) base(`ymin') ///
       xlab(`xmin'(1)`xmax', labsize(small)) ///
       xtitle("Years relative to 2014", size(small)) ///
       ytitle("Coef on rel x Exposure", size(small)) ///
       ylab(, labsize(small)) ///
       yline(0, lcolor(gs10) lpattern(solid)) ///
       title("`yvar' (`spec', N=`Nobs')", size(small)) ///
       legend(off) plotregion(margin(sides))
    graph export ../output/figures/es/es_`yvar'_`spec'.pdf, replace
    restore
end

// -----------------------------------------------------------------------------
// build_uc_panel: uni × category × year panel for the buyer-level sanity checks.
//   - merges in uni-level exposure and s_treat from ../temp/uni_yr_panel
//     (so the sample matches the main one)
//   - outcomes: log_raw_spend, log_raw_qty, avg_log_price (all in logs)
//   - w_pre: pre-2013 raw_spend per (uni, category), used as analytic weight
//   - egen uc = group(uni_id category) for absorb()
// -----------------------------------------------------------------------------
program build_uc_panel
    use uni_id exposure s_treat using ../temp/uni_yr_panel, clear
    duplicates drop uni_id, force
    save ../temp/uni_exposure_xw, replace

    use ../external/samp/uni_category_yr_tfidf, clear
    keep category year uni_id treated raw_spend log_raw_spend log_raw_qty avg_log_price
    merge m:1 uni_id using ../temp/uni_exposure_xw, keep(3) nogen

    // pre-2013 dollar spend per category, summed across all unis — category-size
    // weight (agnostic to which uni purchased)
    bys category: egen w_pre = total(raw_spend * (year <= 2013))
    drop raw_spend

    egen uc = group(uni_id category)
    save ../temp/uni_cat_yr_panel, replace
end

// -----------------------------------------------------------------------------
// uc_did: pooled buyer-level test at uni × category × year with treated
// interactions (equivalent to the split-sample form but recovers the average
// treated effect, which year FE absorb inside each subset).
//   y_{jmt} = mu_{jm} + lambda_t
//             + b1 Post×Exp + b2 Post×Treated + b3 Post×Exp×Treated
//             [+ b4 Post×S + b5 Post×S×Treated]
//   for y in {log_raw_spend, log_raw_qty, avg_log_price}.
//   aw = w_pre (pre-2013 category-level spend). Two-way cluster on uni, cat.
//   Readings:
//     post_exp     = exposure effect in control cells
//     post_tr      = average treated effect (the "treated price increase")
//     post_exp_tr  = differential exposure effect, treated minus control
// -----------------------------------------------------------------------------
program uc_did
    use ../temp/uni_cat_yr_panel, clear
    gen post        = year >= 2014
    gen post_exp    = post * exposure
    gen post_tr     = post * treated
    gen post_exp_tr = post * exposure * treated
    gen post_s      = post * s_treat
    gen post_s_tr   = post * s_treat * treated

    tempname memhold
    postfile `memhold' str20 yvar str10 spec str20 rhs ///
        double b se str10 stars int N using ../temp/uc_didres, replace

    foreach yvar in log_raw_spend log_raw_qty avg_log_price {
        // raw
        reghdfe `yvar' post_exp post_tr post_exp_tr [aw = w_pre], ///
            absorb(uc year) cluster(uni_id category)
        local N = e(N)
        foreach rhs in post_exp post_tr post_exp_tr {
            local b  = _b[`rhs']
            local se = _se[`rhs']
            local p  = 2*(1 - normal(abs(`b'/`se')))
            local stars = cond(`p'<.01,"***",cond(`p'<.05,"**",cond(`p'<.1,"*","")))
            post `memhold' ("`yvar'") ("raw") ("`rhs'") (`b') (`se') ("`stars'") (`N')
        }

        // with_S
        reghdfe `yvar' post_exp post_tr post_exp_tr post_s post_s_tr [aw = w_pre], ///
            absorb(uc year) cluster(uni_id category)
        local N = e(N)
        foreach rhs in post_exp post_tr post_exp_tr post_s post_s_tr {
            local b  = _b[`rhs']
            local se = _se[`rhs']
            local p  = 2*(1 - normal(abs(`b'/`se')))
            local stars = cond(`p'<.01,"***",cond(`p'<.05,"**",cond(`p'<.1,"*","")))
            post `memhold' ("`yvar'") ("with_S") ("`rhs'") (`b') (`se') ("`stars'") (`N')
        }
    }
    postclose `memhold'

    use ../temp/uc_didres, clear
    save ../output/estimates/uc_did, replace
    export delimited using ../output/estimates/uc_did.csv, replace
    list, sepby(yvar) noobs

    foreach yvar in log_raw_spend log_raw_qty avg_log_price {
        foreach spec in raw with_S {
            uc_es, yvar(`yvar') spec(`spec')
        }
    }
end

// -----------------------------------------------------------------------------
// uc_es: pooled event-study version of uc_did. One regression per (yvar, spec)
// with relative-year dummies interacted with {Exposure, Treated, Exp×Treated}
// (and {S, S×Treated} in with_S). Saves three (or five) coefficient series.
// Plots the three substantive series: exp (control effect), tr (avg treated
// effect, the price-increase plot), xtr (differential treated × exposure).
// -----------------------------------------------------------------------------
program uc_es
    syntax, yvar(str) spec(str)
    use ../temp/uni_cat_yr_panel, clear
    gen rel = year - 2014
    qui sum rel
    local rmin = r(min)
    local rmax = r(max)

    forval k = `rmin'/`rmax' {
        if `k' == -1 continue
        local tag = cond(`k' < 0, "n" + string(abs(`k')), string(`k'))
        gen exp_`tag'  = exposure * (rel == `k')
        gen tr_`tag'   = treated  * (rel == `k')
        gen xtr_`tag'  = exposure * treated * (rel == `k')
        gen str_`tag'  = s_treat * (rel == `k')
        gen xstr_`tag' = s_treat * treated * (rel == `k')
    }
    ds exp_*
    local exp_terms `r(varlist)'
    ds tr_*
    local tr_terms `r(varlist)'
    ds xtr_*
    local xtr_terms `r(varlist)'
    ds str_*
    local str_terms `r(varlist)'
    ds xstr_*
    local xstr_terms `r(varlist)'

    if "`spec'" == "raw" {
        reghdfe `yvar' `exp_terms' `tr_terms' `xtr_terms' [aw = w_pre], ///
            absorb(uc year) cluster(uni_id category)
        local series_list exp tr xtr
    }
    else {
        reghdfe `yvar' `exp_terms' `tr_terms' `xtr_terms' `str_terms' `xstr_terms' ///
            [aw = w_pre], absorb(uc year) cluster(uni_id category)
        local series_list exp tr xtr str xstr
    }
    local Nobs = e(N)

    foreach series of local series_list {
        mat drop _all
        forval k = `rmin'/`rmax' {
            if `k' == -1 {
                mat row = `k', 0, 0
            }
            else {
                local tag = cond(`k' < 0, "n" + string(abs(`k')), string(`k'))
                mat row = `k', _b[`series'_`tag'], _se[`series'_`tag']
            }
            mat es = nullmat(es) \ row
        }

        preserve
        clear
        svmat es
        rename (es1 es2 es3) (rel b se)
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        gen year   = rel + 2014
        gen yvar   = "`yvar'"
        gen series = "`series'"
        gen spec   = "`spec'"
        export delimited using ///
            ../output/estimates/es_uc_`yvar'_`series'_`spec'.csv, replace
        save ../temp/es_uc_`yvar'_`series'_`spec', replace

        // plot only the three substantive series; skip s and s_tr to avoid noise
        if inlist("`series'", "exp", "tr", "xtr") {
            sum ub, d
            local ymax = round(r(max), 0.01) + 0.01
            sum lb, d
            local ymin = round(r(min), 0.01) - 0.01
            qui sum rel
            local xmin = r(min)
            local xmax = r(max)

            local ytitle = cond("`series'"=="exp", "Post x Exposure (control)", ///
                          cond("`series'"=="tr",  "Post x Treated (avg treated)", ///
                                                  "Post x Exposure x Treated (diff)"))

            tw rcap ub lb rel if rel != -1, lcolor(ebblue%70) msize(vsmall) || ///
               scatter b rel, mcolor(ebblue) msize(small) || ///
               scatteri `ymax' -0.25 `ymax' 0.25, bcolor(gs12%30) recast(area) base(`ymin') ///
               xlab(`xmin'(1)`xmax', labsize(small)) ///
               xtitle("Years relative to 2014", size(small)) ///
               ytitle("`ytitle'", size(small)) ///
               ylab(, labsize(small)) ///
               yline(0, lcolor(gs10) lpattern(solid)) ///
               title("`yvar' (`spec', N=`Nobs')", size(small)) ///
               legend(off) plotregion(margin(sides))
            graph export ../output/figures/es/es_uc_`yvar'_`series'_`spec'.pdf, replace
        }
        restore
    }
end

**
main
