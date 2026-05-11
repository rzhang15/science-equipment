set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

// Per-PI back-of-envelope size estimates.
// For each PI i:
//   te_i   = beta_avg * exposure_i      (predicted treatment effect on yvar)
//   size_i = athr_fe_i * te_i           (FE-scaled "size", as user requested)
// Also reports te_i / |athr_fe_i| (treatment effect as share of baseline level).

program main
    foreach yvar in cite_affl_wt ppr_cnt body_affl_wt {
        pi_size_estimates, yvar(`yvar') samp(all_jrnls) suf(_r1_r2_public)
        pi_het_beta,       yvar(`yvar') samp(all_jrnls) suf(_r1_r2_public)
    }
end

program pi_size_estimates
    syntax, yvar(string) samp(string) [suf(string)]

    use "../temp/es_`samp'`suf'", clear

    // rel is created inside event_study; rebuild it here.
    cap confirm variable rel
    if _rc gen rel = year - 2014

    // Reconstruct the int_lag/int_lead variables exactly as in reduced_form
    qui sum rel, d
    local abs_lag  = abs(r(max))
    local abs_lead = abs(r(min))

    forval i = 1/`abs_lag' {
        cap gen int_lag`i' = exposure if rel == `i'
    }
    forval i = 1/`abs_lead' {
        cap gen int_lead`i' = exposure if rel == -`i'
    }
    cap gen int_lag0 = exposure if rel == 0

    ds int_lag* int_lead*
    foreach v in `r(varlist)' {
        replace `v' = 0 if mi(`v')
    }

    local int_leads
    local int_lags
    forval i = 2/`abs_lead' {
        local int_leads int_lead`i' `int_leads'
    }
    forval i = 0/`abs_lag' {
        local int_lags `int_lags' int_lag`i'
    }

    // Re-run the event study, saving athr_id fixed effects as a variable
    reghdfe `yvar' `int_leads' `int_lags' int_lead1, ///
        absorb(athr_fe = athr_id year_fe = year) vce(cluster athr_id)

    // Average post-period beta (lag0..lag_max)
    local n_post = `abs_lag' + 1
    local sum_b = 0
    forval i = 0/`abs_lag' {
        local sum_b = `sum_b' + _b[int_lag`i']
    }
    local beta_avg = `sum_b'/`n_post'
    di as txt "beta_avg (`yvar', `samp'`suf') = " as res `beta_avg'

    // Collapse to one obs per PI
    keep athr_id athr_fe exposure year_fe
    bys athr_id: keep if _n == 1

    // Treatment effect and FE-scaled size
    gen double beta_avg = `beta_avg'
    gen double te       = beta_avg * exposure
    gen double size_fe  = athr_fe * te
    gen double te_share = te / athr_fe          // treatment effect as share of baseline FE

    label var athr_fe   "Author FE (baseline level of `yvar')"
    label var exposure  "Imputed exposure"
    label var beta_avg  "Mean post-period beta on exposure"
    label var te        "Predicted treatment effect (beta_avg * exposure)"
    label var size_fe   "FE-scaled size (athr_fe * beta_avg * exposure)"
    label var te_share  "Treatment effect / athr_fe"

    // Save full PI-level table
    save     "../temp/pi_size_`yvar'`suf'.dta", replace
    export delimited using "../output/tables/pi_size_`yvar'`suf'.csv", replace

    // Quick distributional summary
    sum athr_fe exposure te size_fe te_share, d

    // Histograms of the per-PI treatment effect and FE-scaled size
    tw hist te, color(edkblue) frac ///
        xtitle("Predicted treatment effect on `yvar' (beta_avg x exposure)") ///
        ytitle("Fraction of PIs")
    graph export "../output/figures/pi_te_`yvar'`suf'.pdf", replace

    tw hist size_fe, color(edkblue) frac ///
        xtitle("FE-scaled size (athr_fe x beta_avg x exposure)") ///
        ytitle("Fraction of PIs")
    graph export "../output/figures/pi_size_fe_`yvar'`suf'.pdf", replace
end

// Heterogeneous-beta: per-PI post-pre change in yvar (year-FE adjusted), and
// the implied per-PI exposure coefficient beta_i = delta_i / exposure_i.
// Frisch-Waugh equivalent (in balanced panels) to running
//   reghdfe yvar i.athr_id#c.post, absorb(athr_id year)
// but avoids estimating ~N_athrs interaction coefficients directly.
program pi_het_beta
    syntax, yvar(string) samp(string) [suf(string) min_pre(int 2) min_post(int 2)]

    use "../temp/es_`samp'`suf'", clear
    cap confirm variable rel
    if _rc gen rel = year - 2014
    gen post = rel >= 0

    // Drop PIs with too few obs in either period to estimate delta_i
    bys athr_id post: gen tmp = _N
    bys athr_id: egen n_pre  = max(cond(post==0, tmp, 0))
    bys athr_id: egen n_post = max(cond(post==1, tmp, 0))
    drop tmp
    keep if n_pre >= `min_pre' & n_post >= `min_post'

    // Residualize y wrt athr_id and year FEs
    cap drop y_resid
    reghdfe `yvar', absorb(athr_id year) residuals(y_resid)

    // Per-PI post-pre shift in residuals
    collapse (mean) y_resid (mean) exposure (max) n_pre n_post, by(athr_id post)
    reshape wide y_resid, i(athr_id exposure n_pre n_post) j(post)
    gen double delta  = y_resid1 - y_resid0
    gen double beta_i = delta / exposure if exposure > 0

    label var delta   "Per-PI post-pre change in `yvar' (year-FE adjusted)"
    label var beta_i  "Per-PI exposure coefficient (delta / exposure)"
    label var n_pre   "Pre-period obs for PI"
    label var n_post  "Post-period obs for PI"

    sum delta beta_i, d

    save "../temp/pi_het_`yvar'`suf'.dta", replace
    export delimited using "../output/tables/pi_het_`yvar'`suf'.csv", replace

    // Trim 1st/99th pct for plotting (heavy tails common with per-PI estimates)
    qui sum delta, d
    local d_lo = r(p1)
    local d_hi = r(p99)
    qui sum delta if delta >= `d_lo' & delta <= `d_hi'
    local d_mean : di %5.3f r(mean)
    local d_med  : di %5.3f r(p50)
    tw hist delta if inrange(delta, `d_lo', `d_hi'), color(edkblue) frac ///
        xtitle("Per-PI post-pre change in `yvar' (year-FE adjusted)") ///
        ytitle("Fraction of PIs") ///
        legend(on order(- "Mean = `d_mean'" "Median = `d_med'") pos(1) ring(0) region(fcolor(none)) size(small))
    graph export "../output/figures/pi_delta_`yvar'`suf'.pdf", replace

    qui sum beta_i, d
    local b_lo = r(p1)
    local b_hi = r(p99)
    qui sum beta_i if beta_i >= `b_lo' & beta_i <= `b_hi'
    local b_mean : di %5.3f r(mean)
    local b_med  : di %5.3f r(p50)
    tw hist beta_i if inrange(beta_i, `b_lo', `b_hi'), color(edkblue) frac ///
        xtitle("Per-PI exposure coefficient (delta / exposure)") ///
        ytitle("Fraction of PIs") ///
        legend(on order(- "Mean = `b_mean'" "Median = `b_med'") pos(1) ring(0) region(fcolor(none)) size(small))
    graph export "../output/figures/pi_het_beta_`yvar'`suf'.pdf", replace
end

main
