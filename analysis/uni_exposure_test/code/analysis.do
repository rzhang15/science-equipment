 set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

* ============================================================
*  ONE PLACE TO SWITCH EXPOSURE MEASURE
*  EXPOSURE_VERSION : hc | all | treated_hc
*    hc         : EB-shrunk DiD price coefs, hi-conf treated + hi-conf control
*                 markets in the pre-2013 share denominator. (Default.)
*    all        : raw (un-shrunk) DiD price coefs, hi-conf treated + hi-conf
*                 control markets in the denominator.
*    treated_hc : EB-shrunk DiD price coefs, denominator restricted to hi-conf
*                 treated markets only (share concentrated on treated exposure).
*  Selects ../external/betas/{did_coefs_eb_price | did_coefs_price}.dta and
*  optionally re-normalizes s_jm inside build_panel.
* ============================================================
global EXPOSURE_VERSION "hc"

program main
   build_panel
   did
   ppml_did
   binscatter_did
   event_study
   build_uc_panel
   uc_did
   ppml_uc_did
   binscatter_uc_did
   hi_ctrl_uc_es
   output_tables
end

program build_panel
    // Resolve beta source + share-denominator restriction from EXPOSURE_VERSION.
    //   hc         : did_coefs_eb_price, all hi-conf mkts in denominator
    //   all        : did_coefs_price   , all hi-conf mkts in denominator
    //   treated_hc : did_coefs_eb_price, only hi-conf TREATED mkts in denominator
    local beta_file "did_coefs_eb_price"
    if "$EXPOSURE_VERSION" == "all"        local beta_file "did_coefs_price"
    local beta_var "b_eb"
    if "$EXPOSURE_VERSION" == "all"        local beta_var "b"
    local treated_only 0
    if "$EXPOSURE_VERSION" == "treated_hc" local treated_only 1
    di as text "build_panel using EXPOSURE_VERSION=$EXPOSURE_VERSION beta=`beta_file' (`beta_var'), treated_only=`treated_only'"

    use ../external/samp/full_uni_category_yr_tfidf, clear
    keep category year uni_id treated keep raw_spend raw_qty
    gen hi_conf = (keep == 1)
    // --- pre-2013 shares and exposure (computed off hi-conf only) -------------
    preserve
    keep if year <= 2013 & hi_conf == 1
    if `treated_only' == 1 keep if treated == 1
    gcollapse (sum) raw_spend, by(uni_id category treated)
    bys uni_id: egen tot_pre_spend = total(raw_spend)
    gen s_jm = raw_spend / tot_pre_spend
    // pre-period treated and control totals (for sample restriction)
    by uni_id: egen pre_treat_spend = total(raw_spend * (treated == 1))
    by uni_id: egen pre_ctrl_spend  = total(raw_spend * (treated == 0))
    // merge beta coefs (only present for treated markets)
    merge m:1 category using ../external/betas/`beta_file', ///
        keepusing(`beta_var') keep(1 3) nogen
    if "`beta_var'" != "b_eb" rename `beta_var' b_eb
    gen exp_contrib     = cond(treated == 1, s_jm * b_eb, 0)
    gen s_treat_contrib = cond(treated == 1, s_jm, 0)
    gcollapse (sum) exposure = exp_contrib s_treat = s_treat_contrib ///
              (first) pre_treat_spend pre_ctrl_spend tot_pre_spend, by(uni_id)
    // sample restriction: positive pre-2013 spend in both hi-conf treated AND control.
    // Under EXPOSURE_VERSION == "treated_hc" the denominator drops control mkts, so
    // pre_ctrl_spend is 0 by construction — skip the control-spend gate in that mode.
    keep if pre_treat_spend > 0 & !mi(exposure) & !mi(s_treat)
    if `treated_only' == 0 keep if pre_ctrl_spend > 0
    keep uni_id exposure s_treat tot_pre_spend
    save ../temp/exposure_xw, replace
    restore

    // --- aggregate outcomes (full universe, split by treated x hi_conf) ------
    gen hi_ctrl_spend  = raw_spend * (treated == 0 & hi_conf == 1)
    gen hi_treat_spend = raw_spend * (treated == 1 & hi_conf == 1)
    gen lo_ctrl_spend  = raw_spend * (treated == 0 & hi_conf == 0)
    gen lo_treat_spend = raw_spend * (treated == 1 & hi_conf == 0)
    gen hi_ctrl_qty    = raw_qty   * (treated == 0 & hi_conf == 1)
    gen hi_treat_qty   = raw_qty   * (treated == 1 & hi_conf == 1)
    gen lo_ctrl_qty    = raw_qty   * (treated == 0 & hi_conf == 0)
    gen lo_treat_qty   = raw_qty   * (treated == 1 & hi_conf == 0)
    gcollapse (sum) hi_ctrl_spend hi_treat_spend lo_ctrl_spend lo_treat_spend ///
                    hi_ctrl_qty hi_treat_qty lo_ctrl_qty lo_treat_qty ///
                    raw_spend raw_qty, by(uni_id year)
    rename raw_spend total_full_spend
    rename raw_qty   total_full_qty

    // backward-compat aliases (old "ctrl"/"treat"/"tot" = hi-conf only)
    gen ctrl_spend  = hi_ctrl_spend
    gen treat_spend = hi_treat_spend
    gen tot_spend   = hi_ctrl_spend + hi_treat_spend
    gen ctrl_qty    = hi_ctrl_qty
    gen treat_qty   = hi_treat_qty

    // aggregates across confidence levels (all hi+lo conf, by treated status)
    gen total_ctrl_full  = hi_ctrl_spend  + lo_ctrl_spend
    gen total_treat_full = hi_treat_spend + lo_treat_spend

    // --- merge to exposure crosswalk (restricts sample) -----------------------
    merge m:1 uni_id using ../temp/exposure_xw, assert(1 3) keep(3) nogen

    // require uni observed both pre and post 2014
    bys uni_id: egen min_year = min(year)
    bys uni_id: egen max_year = max(year)
    keep if min_year < 2014 & max_year >= 2014
    drop min_year max_year

    // outcomes (log(1+x) keeps zero-spend uni-years)
    foreach v in ctrl_spend ctrl_qty treat_spend treat_qty tot_spend ///
                 hi_ctrl_spend hi_ctrl_qty hi_treat_spend hi_treat_qty ///
                 lo_ctrl_spend lo_ctrl_qty lo_treat_spend lo_treat_qty ///
                 total_ctrl_full total_treat_full ///
                 total_full_spend total_full_qty {
        gen log1_`v' = ln(1 + `v')
    }

    // pre-2013 uni spending for weighted regressions
    gen wt_spend = tot_pre_spend

    label var exposure          "Uni exposure: sum_m s_jm * b_eb_m (hi-conf treated)"
    label var s_treat           "Pre-2013 hi-conf treated-mkt share"
    label var ctrl_spend        "Spend in hi-conf control mkts (= hi_ctrl_spend)"
    label var treat_spend       "Spend in hi-conf treated mkts (= hi_treat_spend)"
    label var tot_spend         "Spend in hi-conf treated+control mkts"
    label var ctrl_qty          "Qty in hi-conf control mkts"
    label var treat_qty         "Qty in hi-conf treated mkts"
    label var hi_ctrl_spend     "Spend in hi-conf control mkts"
    label var hi_treat_spend    "Spend in hi-conf treated mkts"
    label var lo_ctrl_spend     "Spend in lo-conf control mkts (substitution target)"
    label var lo_treat_spend    "Spend in lo-conf treated mkts"
    label var hi_ctrl_qty       "Qty in hi-conf control mkts"
    label var hi_treat_qty      "Qty in hi-conf treated mkts"
    label var lo_ctrl_qty       "Qty in lo-conf control mkts"
    label var lo_treat_qty      "Qty in lo-conf treated mkts"
    label var total_ctrl_full   "Spend in all control mkts (hi+lo conf)"
    label var total_treat_full  "Spend in all treated mkts (hi+lo conf)"
    label var total_full_spend  "Spend across full sample (headline budget test)"
    label var total_full_qty    "Qty across full sample"
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

    foreach yvar in log1_ctrl_spend log1_ctrl_qty log1_tot_spend log1_treat_spend log1_treat_qty ///
                    log1_lo_ctrl_spend log1_lo_ctrl_qty log1_lo_treat_spend log1_lo_treat_qty ///
                    log1_total_ctrl_full log1_total_treat_full ///
                    log1_total_full_spend log1_total_full_qty {
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
// ppml_did: Poisson (ppmlhdfe) analog of `did`. Runs on RAW counts (spend/qty
// in $ / units, not log1_) because ppmlhdfe models log(E[y]) directly and
// handles the zero-outcome cells natively.
//   y_jt = exp( mu_j + lambda_t + beta * Post_t * Exposure_j
//                                + gamma * Post_t * S_j )   (optional S)
//   cluster on uni_id.
// Coefficients are semi-elasticities (Δ log E[y] per unit Δ post_exp).
// Same outcome loop as `did` minus the log1_tot_spend combined outcome
// (redundant now — ppml on the two components gives the same info).
// -----------------------------------------------------------------------------
program ppml_did
    use ../temp/uni_yr_panel, clear
    gen post = year >= 2014
    gen post_exp = post * exposure
    gen post_s   = post * s_treat

    tempname memhold
    tempfile ppmldidres
    postfile `memhold' str40 outcome str20 spec str40 rhs ///
        double b se str10 stars int N using `ppmldidres', replace

    // Raw-count outcomes (no log1_ prefix). Matches the outcome families in
    // `did` but reads the underlying levels for ppmlhdfe.
    foreach yvar in ctrl_spend ctrl_qty tot_spend treat_spend treat_qty ///
                    lo_ctrl_spend lo_ctrl_qty lo_treat_spend lo_treat_qty ///
                    total_ctrl_full total_treat_full ///
                    total_full_spend total_full_qty {
        // raw (no S control)
        cap noi ppmlhdfe `yvar' post_exp, absorb(uni_id year) cluster(uni_id)
        if _rc {
            di as error "ppml_did `yvar' raw failed (rc=`_rc'); skipping."
            continue
        }
        local N = e(N)
        local b  = _b[post_exp]
        local se = _se[post_exp]
        local p  = 2*(1 - normal(abs(`b'/`se')))
        local stars = cond(`p'<.01,"***",cond(`p'<.05,"**",cond(`p'<.1,"*","")))
        post `memhold' ("`yvar'") ("raw") ("post_exp") (`b') (`se') ("`stars'") (`N')

        // identified (S control)
        cap noi ppmlhdfe `yvar' post_exp post_s, absorb(uni_id year) cluster(uni_id)
        if _rc {
            di as error "ppml_did `yvar' with_S failed (rc=`_rc'); skipping."
            continue
        }
        local N = e(N)
        local b  = _b[post_exp]
        local se = _se[post_exp]
        local p  = 2*(1 - normal(abs(`b'/`se')))
        local stars = cond(`p'<.01,"***",cond(`p'<.05,"**",cond(`p'<.1,"*","")))
        post `memhold' ("`yvar'") ("with_S") ("post_exp") (`b') (`se') ("`stars'") (`N')

        // also save Post×S from the identified spec
        local b  = _b[post_s]
        local se = _se[post_s]
        local p  = 2*(1 - normal(abs(`b'/`se')))
        local stars = cond(`p'<.01,"***",cond(`p'<.05,"**",cond(`p'<.1,"*","")))
        post `memhold' ("`yvar'") ("with_S") ("post_s") (`b') (`se') ("`stars'") (`N')
    }
    postclose `memhold'

    use `ppmldidres', clear
    save ../output/estimates/uniyr_ppml_did, replace
    export delimited using ../output/estimates/uniyr_ppml_did.csv, replace
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
    foreach yvar in log1_ctrl_spend log1_ctrl_qty log1_tot_spend log1_treat_spend log1_treat_qty ///
                    log1_lo_ctrl_spend log1_lo_ctrl_qty log1_lo_treat_spend log1_lo_treat_qty ///
                    log1_total_ctrl_full log1_total_treat_full ///
                    log1_total_full_spend log1_total_full_qty {
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

    _pretty_label, name(`yvar')
    local ytit "`r(label)'"

    tw rcap ub lb rel if rel != -1, lcolor(ebblue%70) msize(vsmall) || ///
       scatter b rel, mcolor(ebblue) msize(small) || ///
       scatteri `ymax' -0.25 `ymax' 0.25, bcolor(gs12%30) recast(area) base(`ymin') ///
       xlab(`xmin'(1)`xmax', labsize(small)) ///
       xtitle("Years Relative to 2014", size(small)) ///
       ytitle("Coefficient on Year {&times} Exposure", size(small)) ///
       ylab(, labsize(small)) ///
       yline(0, lcolor(gs10) lpattern(solid)) ///
       title("`ytit'", size(small)) ///
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
    keep category year uni_id treated raw_spend raw_qty ///
         log_raw_spend log_raw_qty avg_log_price
    merge m:1 uni_id using ../temp/uni_exposure_xw, keep(3) nogen

    // pre-2013 dollar spend per category, summed across all unis — category-size
    // weight (agnostic to which uni purchased). raw_spend/raw_qty retained for
    // the PPML uc panel spec (ppml_uc_did); log_raw_* still feed reghdfe.
    bys category: egen w_pre = total(raw_spend * (year <= 2013))

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
// ppml_uc_did: Poisson (ppmlhdfe) analog of uc_did on RAW counts (raw_spend /
// raw_qty). Skips avg_log_price — log-price is a conditional mean, not a count,
// and doesn't belong in a ppmlhdfe log-link. Same FE / cluster / weight
// structure as uc_did (uc, year FE; aw=w_pre; two-way cluster on uni_id, cat).
// Coefficients are semi-elasticities: Δlog E[y] per unit Δ regressor.
//   post_exp     = exposure semielasticity in control cells
//   post_tr      = average treated log-response (price / spend increase in $)
//   post_exp_tr  = differential exposure effect, treated minus control
// -----------------------------------------------------------------------------
program ppml_uc_did
    use ../temp/uni_cat_yr_panel, clear
    gen post        = year >= 2014
    gen post_exp    = post * exposure
    gen post_tr     = post * treated
    gen post_exp_tr = post * exposure * treated
    gen post_s      = post * s_treat
    gen post_s_tr   = post * s_treat * treated

    tempname memhold
    postfile `memhold' str20 yvar str10 spec str20 rhs ///
        double b se str10 stars int N using ../temp/uc_ppml_didres, replace

    foreach yvar in raw_spend raw_qty {
        // raw
        cap noi ppmlhdfe `yvar' post_exp post_tr post_exp_tr [aw = w_pre], ///
            absorb(uc year) cluster(uni_id category)
        if _rc {
            di as error "ppml_uc_did `yvar' raw failed (rc=`_rc'); skipping."
            continue
        }
        local N = e(N)
        foreach rhs in post_exp post_tr post_exp_tr {
            local b  = _b[`rhs']
            local se = _se[`rhs']
            local p  = 2*(1 - normal(abs(`b'/`se')))
            local stars = cond(`p'<.01,"***",cond(`p'<.05,"**",cond(`p'<.1,"*","")))
            post `memhold' ("`yvar'") ("raw") ("`rhs'") (`b') (`se') ("`stars'") (`N')
        }

        // with_S
        cap noi ppmlhdfe `yvar' post_exp post_tr post_exp_tr post_s post_s_tr [aw = w_pre], ///
            absorb(uc year) cluster(uni_id category)
        if _rc {
            di as error "ppml_uc_did `yvar' with_S failed (rc=`_rc'); skipping."
            continue
        }
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

    use ../temp/uc_ppml_didres, clear
    save ../output/estimates/uc_ppml_did, replace
    export delimited using ../output/estimates/uc_ppml_did.csv, replace
    list, sepby(yvar) noobs
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

            local ytitle = cond("`series'"=="exp", "Coefficient on Year {&times} Exposure (Control Cells)", ///
                          cond("`series'"=="tr",  "Coefficient on Year {&times} Treated", ///
                                                  "Coefficient on Year {&times} Exposure {&times} Treated"))

            _pretty_label, name(`yvar')
            local ttit "`r(label)'"

            tw rcap ub lb rel if rel != -1, lcolor(ebblue%70) msize(vsmall) || ///
               scatter b rel, mcolor(ebblue) msize(small) || ///
               scatteri `ymax' -0.25 `ymax' 0.25, bcolor(gs12%30) recast(area) base(`ymin') ///
               xlab(`xmin'(1)`xmax', labsize(small)) ///
               xtitle("Years Relative to 2014", size(small)) ///
               ytitle("`ytitle'", size(small)) ///
               ylab(, labsize(small)) ///
               yline(0, lcolor(gs10) lpattern(solid)) ///
               title("`ttit'", size(small)) ///
               legend(off) plotregion(margin(sides))
            graph export ../output/figures/es/es_uc_`yvar'_`series'_`spec'.pdf, replace
        }
        restore
    }
end

// -----------------------------------------------------------------------------
// _pretty_label: outcome/regressor name -> human-readable label for figures.
//   Centralizes the variable->label mapping so binscatter and event-study
//   programs share one source of truth. Returns r(label).
// -----------------------------------------------------------------------------
program _pretty_label, rclass
    syntax, name(str)
    local L = "`name'"
    // uni-yr outcomes (figure caption / filename carries the segment qualifier)
    if "`name'" == "log1_ctrl_spend"        local L "Log Spend"
    if "`name'" == "log1_ctrl_qty"          local L "Log Quantity"
    if "`name'" == "log1_hi_ctrl_spend"     local L "Log Spend"
    if "`name'" == "log1_hi_ctrl_qty"       local L "Log Quantity"
    if "`name'" == "log1_tot_spend"         local L "Log Spend"
    if "`name'" == "log1_treat_spend"       local L "Log Spend"
    if "`name'" == "log1_treat_qty"         local L "Log Quantity"
    if "`name'" == "log1_hi_treat_spend"    local L "Log Spend"
    if "`name'" == "log1_hi_treat_qty"      local L "Log Quantity"
    if "`name'" == "log1_lo_ctrl_spend"     local L "Log Spend"
    if "`name'" == "log1_lo_ctrl_qty"       local L "Log Quantity"
    if "`name'" == "log1_lo_treat_spend"    local L "Log Spend"
    if "`name'" == "log1_lo_treat_qty"      local L "Log Quantity"
    if "`name'" == "log1_total_ctrl_full"   local L "Log Spend"
    if "`name'" == "log1_total_treat_full"  local L "Log Spend"
    if "`name'" == "log1_total_full_spend"  local L "Log Spend"
    if "`name'" == "log1_total_full_qty"    local L "Log Quantity"
    // uc-level outcomes
    if "`name'" == "log_raw_spend"          local L "Log Spend"
    if "`name'" == "log_raw_qty"            local L "Log Quantity"
    if "`name'" == "avg_log_price"          local L "Average Log Price"
    // focal regressors
    if "`name'" == "post_exp"               local L "Post x Exposure"
    if "`name'" == "post_tr"                local L "Post x Treated"
    if "`name'" == "post_exp_tr"            local L "Post x Exposure x Treated"
    return local label "`L'"
end

// -----------------------------------------------------------------------------
// _bin_did: Frisch-Waugh partial-regression binscatter helper.
//   Residualize y and the focal regressor z on the same FE set (and any
//   controls), refit the static DiD to grab b/SE matching the regression
//   tables, and binscatter the residuals with the beta/SE in a pos(7) legend.
//   uc_panel = 1 uses uc/year FE, aw=w_pre, two-way cluster on uni_id/category;
//   uc_panel = 0 uses uni_id/year FE, no weights, cluster on uni_id.
// -----------------------------------------------------------------------------
program _bin_did
    syntax, yvar(str) zvar(str) outfile(str) xtit(str) ytit(str) ///
            uc_panel(int) [ctrl(str asis) nbins(int 20)]
    preserve
    cap drop _y_r _Z_r
    if `uc_panel' == 1 {
        qui reghdfe `yvar' `ctrl' [aw=w_pre], absorb(uc year) residuals(_y_r)
        qui reghdfe `zvar' `ctrl' [aw=w_pre], absorb(uc year) residuals(_Z_r)
        qui reghdfe `yvar' `zvar' `ctrl' [aw=w_pre], absorb(uc year) ///
            cluster(uni_id category)
    }
    else {
        qui reghdfe `yvar' `ctrl', absorb(uni_id year) residuals(_y_r)
        qui reghdfe `zvar' `ctrl', absorb(uni_id year) residuals(_Z_r)
        qui reghdfe `yvar' `zvar' `ctrl', absorb(uni_id year) cluster(uni_id)
    }
    local b_str  : di %7.3f _b[`zvar']
    local se_str : di %7.3f _se[`zvar']
    qui gunique uni_id if e(sample)
    local Nstr = trim(string(r(unique), "%15.0fc"))
    if `uc_panel' == 1 {
        binscatter _y_r _Z_r [aw=w_pre], n(`nbins') msymbol(O) mcolors(gs6) lcolors(ebblue) ///
            xtitle("`xtit'") ytitle("`ytit'") ///
            ylab(#10) ///
            legend(on order(- "{&beta} = `b_str' (SE: `se_str')") ///
                   pos(7) ring(1) size(small) region(lwidth(none))) ///
            plotregion(margin(sides))
    }
    else {
        binscatter _y_r _Z_r, n(`nbins') msymbol(O) mcolors(gs6) lcolors(ebblue) ///
            xtitle("`xtit'") ytitle("`ytit'") ///
            ylab(#10) ///
            legend(on order(- "{&beta} = `b_str' (SE: `se_str')") ///
                   pos(7) ring(1) size(small) region(lwidth(none))) ///
            plotregion(margin(sides))
    }
    graph export `outfile', replace
    restore
end

// -----------------------------------------------------------------------------
// binscatter_did: FW binscatter of post_exp on each uni-yr outcome, raw and
// with_S. Mirrors the outcome loop and FE/cluster structure of `did`.
// -----------------------------------------------------------------------------
program binscatter_did
    use ../temp/uni_yr_panel, clear
    gen post     = year >= 2014
    gen post_exp = post * exposure
    gen post_s   = post * s_treat

    cap mkdir ../output/figures/binscatter

    foreach yvar in log1_hi_ctrl_spend log1_hi_ctrl_qty ///
                    log1_hi_treat_spend log1_hi_treat_qty ///
                    log1_tot_spend ///
                    log1_lo_ctrl_spend log1_lo_ctrl_qty ///
                    log1_lo_treat_spend log1_lo_treat_qty ///
                    log1_total_ctrl_full log1_total_treat_full ///
                    log1_total_full_spend log1_total_full_qty {
        _pretty_label, name(`yvar')
        local ytit "`r(label)'"
        _pretty_label, name(post_exp)
        local xtit "`r(label)'"
        _bin_did, yvar(`yvar') zvar(post_exp) uc_panel(0) ///
            outfile(../output/figures/binscatter/bins_`yvar'_raw.pdf) ///
            xtit("`xtit'") ytit("`ytit'")
        _bin_did, yvar(`yvar') zvar(post_exp) uc_panel(0) ctrl(post_s) ///
            outfile(../output/figures/binscatter/bins_`yvar'_with_S.pdf) ///
            xtit("`xtit'") ytit("`ytit'")
    }
end

// -----------------------------------------------------------------------------
// binscatter_uc_did: FW binscatter at the uni x cat x year level for each of
// {post_exp, post_tr, post_exp_tr}, raw and with_S. Same FE/cluster/weight
// structure as `uc_did`.
//   - post_exp:    exposure effect in CONTROL cells (substitution check)
//   - post_tr:     average treated effect (price/spend response)
//   - post_exp_tr: differential exposure effect, treated minus control
// -----------------------------------------------------------------------------
program binscatter_uc_did
    use ../temp/uni_cat_yr_panel, clear
    gen post        = year >= 2014
    gen post_exp    = post * exposure
    gen post_tr     = post * treated
    gen post_exp_tr = post * exposure * treated
    gen post_s      = post * s_treat
    gen post_s_tr   = post * s_treat * treated

    cap mkdir ../output/figures/binscatter

    foreach yvar in log_raw_spend log_raw_qty avg_log_price {
        _pretty_label, name(`yvar')
        local ytit "`r(label)'"
        _pretty_label, name(post_exp)
        local xtit_exp "`r(label)'"
        _pretty_label, name(post_tr)
        local xtit_tr  "`r(label)'"
        _pretty_label, name(post_exp_tr)
        local xtit_xtr "`r(label)'"
        // raw spec: residualize on FE + the two non-focal interactions
        _bin_did, yvar(`yvar') zvar(post_exp) uc_panel(1) ///
            ctrl(post_tr post_exp_tr) nbins(30) ///
            outfile(../output/figures/binscatter/bins_uc_`yvar'_post_exp_raw.pdf) ///
            xtit("`xtit_exp'") ytit("`ytit'")
        _bin_did, yvar(`yvar') zvar(post_tr) uc_panel(1) ///
            ctrl(post_exp post_exp_tr) nbins(30) ///
            outfile(../output/figures/binscatter/bins_uc_`yvar'_post_tr_raw.pdf) ///
            xtit("`xtit_tr'") ytit("`ytit'")
        _bin_did, yvar(`yvar') zvar(post_exp_tr) uc_panel(1) ///
            ctrl(post_exp post_tr) nbins(30) ///
            outfile(../output/figures/binscatter/bins_uc_`yvar'_post_exp_tr_raw.pdf) ///
            xtit("`xtit_xtr'") ytit("`ytit'")
        // with_S spec: add post_s, post_s_tr as additional controls
        _bin_did, yvar(`yvar') zvar(post_exp) uc_panel(1) ///
            ctrl(post_tr post_exp_tr post_s post_s_tr) nbins(30) ///
            outfile(../output/figures/binscatter/bins_uc_`yvar'_post_exp_with_S.pdf) ///
            xtit("`xtit_exp'") ytit("`ytit'")
        _bin_did, yvar(`yvar') zvar(post_tr) uc_panel(1) ///
            ctrl(post_exp post_exp_tr post_s post_s_tr) nbins(30) ///
            outfile(../output/figures/binscatter/bins_uc_`yvar'_post_tr_with_S.pdf) ///
            xtit("`xtit_tr'") ytit("`ytit'")
        _bin_did, yvar(`yvar') zvar(post_exp_tr) uc_panel(1) ///
            ctrl(post_exp post_tr post_s post_s_tr) nbins(30) ///
            outfile(../output/figures/binscatter/bins_uc_`yvar'_post_exp_tr_with_S.pdf) ///
            xtit("`xtit_xtr'") ytit("`ytit'")
    }
end

// -----------------------------------------------------------------------------
// hi_ctrl_uc_es: buyer-level event study restricted to HI-CONF CONTROL cells
// (treated == 0 in the hi-conf uc panel). Isolates the substitution margin
// where the budget-binds story is the only mechanism that should move the
// outcome; own-price elasticity has no role here because prices in these
// cells didn't change. Coefficient series plotted = post x exposure.
// -----------------------------------------------------------------------------
program hi_ctrl_uc_es
    foreach yvar in log_raw_spend log_raw_qty {
        foreach spec in raw with_S {
            hi_ctrl_uc_es_inner, yvar(`yvar') spec(`spec')
        }
    }
end

program hi_ctrl_uc_es_inner
    syntax, yvar(str) spec(str)
    use ../temp/uni_cat_yr_panel, clear
    keep if treated == 0
    gen rel = year - 2014
    qui sum rel
    local rmin = r(min)
    local rmax = r(max)

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
        reghdfe `yvar' `exp_terms' [aw=w_pre], absorb(uc year) cluster(uni_id category)
    }
    else {
        reghdfe `yvar' `exp_terms' `str_terms' [aw=w_pre], ///
            absorb(uc year) cluster(uni_id category)
    }
    local Nobs = e(N)

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
        ../output/estimates/es_hi_ctrl_uc_`yvar'_`spec'.csv, replace
    save ../temp/es_hi_ctrl_uc_`yvar'_`spec', replace

    sum ub, d
    local ymax = round(r(max), 0.01) + 0.01
    sum lb, d
    local ymin = round(r(min), 0.01) - 0.01
    qui sum rel
    local xmin = r(min)
    local xmax = r(max)

    _pretty_label, name(`yvar')
    local ttit "`r(label)' (Hi-Conf Control Cells)"

    tw rcap ub lb rel if rel != -1, lcolor(ebblue%70) msize(vsmall) || ///
       scatter b rel, mcolor(ebblue) msize(small) || ///
       scatteri `ymax' -0.25 `ymax' 0.25, bcolor(gs12%30) recast(area) base(`ymin') ///
       xlab(`xmin'(1)`xmax', labsize(small)) ///
       xtitle("Years Relative to 2014", size(small)) ///
       ytitle("Coefficient on Year {&times} Exposure", size(small)) ///
       ylab(, labsize(small)) ///
       yline(0, lcolor(gs10) lpattern(solid)) ///
       title("`ttit'", size(small)) ///
       legend(off) plotregion(margin(sides))
    graph export ../output/figures/es/es_hi_ctrl_uc_`yvar'_`spec'.pdf, replace
    restore
end

// -----------------------------------------------------------------------------
// output_tables: 3-row budget-binds summary table.
//   Row 1: post_exp on log1_total_full_spend (uni-yr)        - envelope test
//   Row 2: post_exp on log1_hi_ctrl_qty      (uni-yr)        - substitution
//   Row 3: post_tr  on avg_log_price         (uni-cat-yr)    - shock landed
//   Cols:  b_raw  se_raw  N_raw  b_with_S  se_with_S  N_with_S
// -----------------------------------------------------------------------------
program output_tables
    cap mat drop budget_binds
    mat budget_binds = J(3, 6, .)
    mat colnames budget_binds = b_raw se_raw N_raw b_with_S se_with_S N_with_S
    mat rownames budget_binds = total_full_spend hi_ctrl_qty avg_log_price_tr

    use ../temp/uni_yr_panel, clear
    gen post     = year >= 2014
    gen post_exp = post * exposure
    gen post_s   = post * s_treat

    // Row 1: total_full_spend ~ post_exp [+ post_s]
    qui reghdfe log1_total_full_spend post_exp, absorb(uni_id year) cluster(uni_id)
    mat budget_binds[1,1] = _b[post_exp]
    mat budget_binds[1,2] = _se[post_exp]
    mat budget_binds[1,3] = e(N)
    qui reghdfe log1_total_full_spend post_exp post_s, absorb(uni_id year) cluster(uni_id)
    mat budget_binds[1,4] = _b[post_exp]
    mat budget_binds[1,5] = _se[post_exp]
    mat budget_binds[1,6] = e(N)

    // Row 2: hi_ctrl_qty ~ post_exp [+ post_s]
    qui reghdfe log1_hi_ctrl_qty post_exp, absorb(uni_id year) cluster(uni_id)
    mat budget_binds[2,1] = _b[post_exp]
    mat budget_binds[2,2] = _se[post_exp]
    mat budget_binds[2,3] = e(N)
    qui reghdfe log1_hi_ctrl_qty post_exp post_s, absorb(uni_id year) cluster(uni_id)
    mat budget_binds[2,4] = _b[post_exp]
    mat budget_binds[2,5] = _se[post_exp]
    mat budget_binds[2,6] = e(N)

    // Row 3: avg_log_price ~ post_tr (uc panel, full triple interaction)
    use ../temp/uni_cat_yr_panel, clear
    gen post        = year >= 2014
    gen post_exp    = post * exposure
    gen post_tr     = post * treated
    gen post_exp_tr = post * exposure * treated
    gen post_s      = post * s_treat
    gen post_s_tr   = post * s_treat * treated
    qui reghdfe avg_log_price post_exp post_tr post_exp_tr [aw=w_pre], ///
        absorb(uc year) cluster(uni_id category)
    mat budget_binds[3,1] = _b[post_tr]
    mat budget_binds[3,2] = _se[post_tr]
    mat budget_binds[3,3] = e(N)
    qui reghdfe avg_log_price post_exp post_tr post_exp_tr post_s post_s_tr [aw=w_pre], ///
        absorb(uc year) cluster(uni_id category)
    mat budget_binds[3,4] = _b[post_tr]
    mat budget_binds[3,5] = _se[post_tr]
    mat budget_binds[3,6] = e(N)

    cap mkdir ../output/tables
    qui matrix_to_txt, saving("../output/tables/budget_binds.txt") ///
        matrix(budget_binds) title(<tab:budget_binds>) format(%20.4f) replace
    mat list budget_binds

    // ---- PPML companion: same 3-row structure, ppmlhdfe on raw counts ------
    // Row 1: total_full_spend ~ post_exp [+ post_s]        (uni-yr)
    // Row 2: hi_ctrl_qty      ~ post_exp [+ post_s]        (uni-yr)
    // Row 3: raw_spend        ~ post_tr full triple interaction (uni-cat-yr)
    // avg_log_price row from the reghdfe table is intentionally NOT ported —
    // PPML on a log-mean price is nonsense; raw_spend is the count-scale test.
    cap mat drop budget_binds_ppml
    mat budget_binds_ppml = J(3, 6, .)
    mat colnames budget_binds_ppml = b_raw se_raw N_raw b_with_S se_with_S N_with_S
    mat rownames budget_binds_ppml = total_full_spend hi_ctrl_qty raw_spend_tr

    use ../temp/uni_yr_panel, clear
    gen post     = year >= 2014
    gen post_exp = post * exposure
    gen post_s   = post * s_treat

    cap noi qui ppmlhdfe total_full_spend post_exp, absorb(uni_id year) cluster(uni_id)
    if _rc == 0 {
        mat budget_binds_ppml[1,1] = _b[post_exp]
        mat budget_binds_ppml[1,2] = _se[post_exp]
        mat budget_binds_ppml[1,3] = e(N)
    }
    cap noi qui ppmlhdfe total_full_spend post_exp post_s, absorb(uni_id year) cluster(uni_id)
    if _rc == 0 {
        mat budget_binds_ppml[1,4] = _b[post_exp]
        mat budget_binds_ppml[1,5] = _se[post_exp]
        mat budget_binds_ppml[1,6] = e(N)
    }

    cap noi qui ppmlhdfe hi_ctrl_qty post_exp, absorb(uni_id year) cluster(uni_id)
    if _rc == 0 {
        mat budget_binds_ppml[2,1] = _b[post_exp]
        mat budget_binds_ppml[2,2] = _se[post_exp]
        mat budget_binds_ppml[2,3] = e(N)
    }
    cap noi qui ppmlhdfe hi_ctrl_qty post_exp post_s, absorb(uni_id year) cluster(uni_id)
    if _rc == 0 {
        mat budget_binds_ppml[2,4] = _b[post_exp]
        mat budget_binds_ppml[2,5] = _se[post_exp]
        mat budget_binds_ppml[2,6] = e(N)
    }

    use ../temp/uni_cat_yr_panel, clear
    gen post        = year >= 2014
    gen post_exp    = post * exposure
    gen post_tr     = post * treated
    gen post_exp_tr = post * exposure * treated
    gen post_s      = post * s_treat
    gen post_s_tr   = post * s_treat * treated
    cap noi qui ppmlhdfe raw_spend post_exp post_tr post_exp_tr [aw=w_pre], ///
        absorb(uc year) cluster(uni_id category)
    if _rc == 0 {
        mat budget_binds_ppml[3,1] = _b[post_tr]
        mat budget_binds_ppml[3,2] = _se[post_tr]
        mat budget_binds_ppml[3,3] = e(N)
    }
    cap noi qui ppmlhdfe raw_spend post_exp post_tr post_exp_tr post_s post_s_tr [aw=w_pre], ///
        absorb(uc year) cluster(uni_id category)
    if _rc == 0 {
        mat budget_binds_ppml[3,4] = _b[post_tr]
        mat budget_binds_ppml[3,5] = _se[post_tr]
        mat budget_binds_ppml[3,6] = e(N)
    }

    qui matrix_to_txt, saving("../output/tables/budget_binds_ppml.txt") ///
        matrix(budget_binds_ppml) title(<tab:budget_binds_ppml>) format(%20.4f) replace
    mat list budget_binds_ppml
end

**
main
