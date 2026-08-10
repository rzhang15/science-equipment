set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main
    boe
    gather_nih
    foreach ds in r1_r2 r1_r2_public {
        local sufopt = cond("`ds'" == "r1_r2", "", "suf(_public)")
        spend_by_age, `sufopt'
        spend_by_age_piyr, `sufopt'
        gather_pubs, `sufopt'
        foreach s in foia all {
            nih_by_age,      samp(`s') `sufopt'
            nih_by_age_piyr, samp(`s') `sufopt'
            pubs_by_age,     samp(`s') `sufopt'
            prod_per_dollar, samp(`s') `sufopt'
        }
    }
end

* ---------------------------------------------------------------------------
* Young-vs-old tests behind the kdensity overlays. Welch t-test on the means
* plus a Kolmogorov-Smirnov test on the full distributions -- the t-test only
* speaks to means, and these variables are skewed and zero-heavy, so the two
* can disagree. Both run on the uncapped sample (matching the legend stats),
* not the p95 plotting range. cluster() replaces the t-test with a clustered
* mean difference where obs are PI-years rather than PIs.
* ---------------------------------------------------------------------------
program kd_tests, rclass
    syntax varname [, cluster(varname)]
    local v `varlist'
    if "`cluster'" == "" {
        qui ttest `v', by(young) unequal
        return scalar diff = r(mu_2) - r(mu_1)
        return scalar p_t  = r(p)
    }
    else {
        qui reg `v' young, cluster(`cluster')
        return scalar diff = _b[young]
        return scalar p_t  = 2 * ttail(e(df_r), abs(_b[young] / _se[young]))
    }
    qui ksmirnov `v', by(young)
    return scalar p_ks = cond(mi(r(p_exact)), r(p), r(p_exact))
end

* p-value as text for a graph note: 3 decimals, "<0.001" when smaller.
program pfmt, rclass
    syntax anything(name=p)
    return local s = cond(`p' < 0.001, "<0.001", string(`p', "%5.3f"))
end

* ---------------------------------------------------------------------------
* kdensity overlay, young vs old, rescaled to percent of obs per fixed bin
* (raw densities over dollar amounts are unreadable 1e-5-scale numbers).
* x capped at p95 of the pooled distribution (long right tail otherwise
* flattens everything); kernel spills past the data boundary, so only the
* [0, cap] range is drawn.
* ---------------------------------------------------------------------------
program kd_young_old
    syntax varname, xtitle(string) w(real) wlab(string) unit(string) ///
        out(string) [xcap(real -1) fmt(string) cluster(varname)]
    local v `varlist'
    if "`fmt'" == "" local fmt %9.0fc
    if `xcap' < 0 {
        qui sum `v', d
        local xcap = r(p95)
    }
    qui sum `v' if young == 1, d
    local mean_y = strtrim("`: di `fmt' r(mean)'")
    local n_y    = r(N)
    qui sum `v' if young == 0, d
    local mean_o = strtrim("`: di `fmt' r(mean)'")
    local n_o    = r(N)

    if "`cluster'" != "" local clopt cluster(`cluster')
    kd_tests `v', `clopt'
    local diff = strtrim("`: di `fmt' r(diff)'")
    local p_t  = r(p_t)
    local p_ks = r(p_ks)
    pfmt `p_t'
    local pt_s `r(s)'
    pfmt `p_ks'
    local pks_s `r(s)'
    if "`cluster'" != "" local ptxt "Early-career - late-career = `diff'; t-test p = `pt_s' (`cluster'-clustered); K-S p = `pks_s'"
    else                 local ptxt "Early-career - late-career = `diff'; t-test p = `pt_s'; K-S p = `pks_s'"
    di as text "`v': `ptxt'"

    * both densities evaluated on one common x grid so rarea can shade the gap
    cap drop _kx _kd_y _kd_o _kp_y _kp_o _kp_c
    gen _kx = `xcap' * (_n - 1) / 199 if _n <= 200
    kdensity `v' if young == 1 & `v' <= `xcap', at(_kx) gen(_kd_y) nograph
    kdensity `v' if young == 0 & `v' <= `xcap', at(_kx) gen(_kd_o) nograph
    gen _kp_y = _kd_y * `w' * 100
    gen _kp_o = _kd_o * `w' * 100
    * opaque lightened tints (*0.3), not %-opacity: translucent fills leave
    * hairline seam artifacts in exported PDFs. Excess bands run from the
    * common envelope up to each curve (zero-height where no excess), so no
    * if-splits are needed.
    gen _kp_c = min(_kp_y, _kp_o)
    tw (rarea _kp_c _kp_y _kx, color(ebblue*0.3) lwidth(none)) ///
       (rarea _kp_c _kp_o _kx, color(dkorange*0.3) lwidth(none)) ///
       (line _kp_y _kx, lcolor(ebblue)) ///
       (line _kp_o _kx, lcolor(dkorange)), ///
       xtitle("`xtitle'") ytitle("Percent of `unit' (per `wlab' bin)") ///
       legend(order(3 "Early-Career (N=`n_y'): mean=`mean_y'" ///
                    4 "Late-Career (N=`n_o'): mean=`mean_o'") ///
           pos(1) ring(0) cols(1) size(small) region(fcolor(none))) ///
       note("`ptxt'", size(small)) ///
       plotregion(margin(sides))
    graph export `out', replace
    cap drop _kx _kd_y _kd_o _kp_y _kp_o _kp_c
end

* ---------------------------------------------------------------------------
* NIH funding by athr-year from RePORTER (FY2010-2019, one row per
* project-FY). fy is the funding year, so nih_amt is the dollar flow received
* that year -- the right analogue of annual FOIA spend. n_grants in the
* pi_descriptives panel instead counts project-FY records stamped to the
* project's start year, so it is not a grant count; count distinct projects
* here. A grant-PI pair can appear twice when the same name matches twice in
* the pi_names string, hence the dedup on athr_id-grant_id.
* ---------------------------------------------------------------------------
program gather_nih
    use athr_id grant_id full_project_num fy total_cost project_start ///
        using ../external/nih/nih_grants_by_athr_id, clear
    duplicates drop athr_id grant_id, force
    gen double amt = total_cost
    bys athr_id fy full_project_num: gen byte proj = _n == 1
    gen byte new_grant = proj & year(project_start) == fy
    gcollapse (sum) nih_amt        = amt ///
              (sum) nih_active     = proj ///
              (sum) nih_new_grants = new_grant, by(athr_id fy) fast
    rename fy year
    save ../temp/nih_athr_yr, replace

    keep if inrange(year, 2010, 2013)
    preserve
        collapse (sum) nih_amt nih_active nih_new_grants, by(athr_id)
        * annual averages over the 4 pre-merger years
        gen double nih_amt_yr    = nih_amt        / 4
        gen double nih_active_yr = nih_active     / 4
        gen double nih_new_yr    = nih_new_grants / 4
        keep athr_id nih_amt_yr nih_active_yr nih_new_yr
        save ../temp/nih_pre_amt, replace
    restore
    bys athr_id: keep if _n == 1
    keep athr_id
    save ../temp/nih_pre_pis, replace
end

* ---------------------------------------------------------------------------
* NIH grant counts and amounts for young vs old PIs, same split as
* spend_by_age (median age_2014, age = 2014 - first pub year + 30).
* samp(foia) = the FOIA PIs in the analysis sample; samp(all) = the full
* analysis sample. Pre-merger only: per-PI annual averages over FY2010-2013,
* always dividing by 4 so grantless years count as zeros.
* Restricted to PIs matched to RePORTER AND holding at least one FY2010-2013
* award. An unmatched PI's zero is a failed name match, not an absence of
* funding; a matched PI whose grants all start post-2013 was not an NIH PI
* pre-merger, so neither belongs in the funding distribution.
* ---------------------------------------------------------------------------
program nih_by_age
    syntax, samp(string) [suf(string)]
    cap mkdir ../output/tables
    cap mkdir ../output/figures

    use ../external/pi_samp/pi_desc_all_jrnls_r1_r2`suf', clear
    keep if athr_indicator == 1
    if "`samp'" == "foia" keep if foia_athr == 1
    gen byte nih_matched = !mi(nih_pi_name)
    keep athr_id age_2014 nih_matched
    save ../temp/nih_age_pis_`samp'`suf', replace

    use ../temp/nih_pre_amt, clear
    merge 1:1 athr_id using ../temp/nih_age_pis_`samp'`suf', keep(2 3)
    qui count
    local n_pis = r(N)
    qui count if nih_matched == 1
    local n_match = r(N)
    qui count if _merge == 3
    local n_grants_pi = r(N)
    di as text "nih_by_age `samp'`suf': `n_pis' PIs, `n_match' matched to RePORTER, " ///
        "`n_grants_pi' with grant records in 2010-2013"

    qui sum age_2014, d
    local med_age = r(p50)
    gen young = age_2014 < `med_age'
    di as text "nih_by_age `samp'`suf': median age_2014 = `med_age' (young = below median)"

    * composition before the restriction: unmatched vs matched-but-unfunded
    foreach g in 1 0 {
        qui count if young == `g'
        local n_samp_`g' = r(N)
        qui count if young == `g' & nih_matched == 0
        local n_drop_`g' = r(N)
        qui count if young == `g' & nih_matched == 1 & _merge == 2
        local n_nogrant_`g' = r(N)
    }

    keep if nih_matched == 1 & _merge == 3
    drop _merge
    save ../output/nih_by_age_pis_`samp'`suf', replace

    cap mat drop nih_age
    qui count if young == 1
    local n_young = r(N)
    qui count if young == 0
    local n_old = r(N)
    foreach g in 1 0 {
        qui count if young == `g' & nih_amt_yr == 0
        local n_zero_`g' = r(N)
    }
    mat nih_age = (`n_samp_1', ., `n_samp_1', `n_samp_0', ., `n_samp_0')
    mat nih_age = nih_age \ (`n_drop_1', ., `n_drop_1', `n_drop_0', ., `n_drop_0')
    mat nih_age = nih_age \ ///
        (`n_nogrant_1', ., `n_nogrant_1', `n_nogrant_0', ., `n_nogrant_0')
    mat nih_age = nih_age \ (`n_young', ., `n_young', `n_old', ., `n_old')
    mat nih_age = nih_age \ (`n_zero_1', ., `n_zero_1', `n_zero_0', ., `n_zero_0')
    local rownames "n_pis_sample n_pis_unmatched_dropped n_pis_nopregrant_dropped"
    local rownames "`rownames' n_pis_kept n_pis_zero_amt"
    foreach v in age_2014 nih_amt_yr nih_active_yr nih_new_yr {
        qui sum `v' if young == 1, d
        local y_mean = r(mean)
        local y_p50  = r(p50)
        local y_N    = r(N)
        qui sum `v' if young == 0, d
        mat nih_age = nullmat(nih_age) \ ///
            (`y_mean', `y_p50', `y_N', r(mean), r(p50), r(N))
        local rownames "`rownames' `v'"
    }
    mat colnames nih_age = young_mean young_p50 young_N old_mean old_p50 old_N
    mat rownames nih_age = `rownames'
    qui matrix_to_txt, saving("../output/tables/nih_by_age_`samp'`suf'.txt") ///
        matrix(nih_age) title(<tab:nih_by_age_`samp'`suf'>) format(%14.2f) replace

    kd_young_old nih_amt_yr, xtitle(Avg annual NIH funding, 2010-2013 ($)) ///
        w(100000) wlab("$100,000") unit(PIs) ///
        out(../output/figures/kd_nih_amt_by_age_`samp'`suf'.pdf)
    kd_young_old nih_active_yr, xtitle(Avg # active NIH grants per year, 2010-2013) ///
        w(0.5) wlab("0.5 grants") unit(PIs) fmt(%9.2f) ///
        out(../output/figures/kd_nih_active_by_age_`samp'`suf'.pdf)

    bs_stats, y(nih_amt_yr) x(age_2014) ///
        xtitle(Age in 2014 (yrs since first pub + 30)) ///
        ytitle(Avg annual NIH funding, 2010-2013 ($)) ///
        out(../output/figures/bs_nih_amt_by_age_`samp'`suf'.pdf)
    bs_stats, y(nih_active_yr) x(age_2014) ///
        xtitle(Age in 2014 (yrs since first pub + 30)) ///
        ytitle(Avg # active NIH grants per year, 2010-2013) ///
        out(../output/figures/bs_nih_active_by_age_`samp'`suf'.pdf)
end

* ---------------------------------------------------------------------------
* Same young/old comparison at the PI-YEAR level: one obs per PI-year of NIH
* funding over 2010-2013, rectangular so grantless years enter as zeros.
* Young/old uses the same PI-level median age as nih_by_age.
* ---------------------------------------------------------------------------
program nih_by_age_piyr
    syntax, samp(string) [suf(string)]

    use ../temp/nih_age_pis_`samp'`suf', clear
    qui sum age_2014, d
    local med_age = r(p50)
    keep if nih_matched == 1
    merge 1:1 athr_id using ../temp/nih_pre_pis, keep(3) nogen
    expand 4
    bys athr_id: gen int year = 2009 + _n
    merge 1:1 athr_id year using ../temp/nih_athr_yr, keep(1 3) nogen
    foreach v in nih_amt nih_active nih_new_grants {
        replace `v' = 0 if mi(`v')
    }

    gen young = age_2014 < `med_age'
    egen _tag = tag(athr_id)
    qui count if _tag & young == 1
    local npi_y = r(N)
    qui count if _tag & young == 0
    local npi_o = r(N)
    drop _tag
    di as text "nih_by_age_piyr `samp'`suf': median age = `med_age'; PIs young/old = `npi_y'/`npi_o'"

    keep athr_id year age_2014 young nih_amt nih_active nih_new_grants
    save ../output/nih_by_age_piyrs_`samp'`suf', replace

    cap mat drop nih_age_piyr
    qui count if young == 1
    local nyr_y = r(N)
    qui count if young == 0
    local nyr_o = r(N)
    foreach g in 1 0 {
        qui count if young == `g' & nih_amt == 0
        local nzero_`g' = r(N)
    }
    mat nih_age_piyr = (`npi_y', ., `npi_y', `npi_o', ., `npi_o')
    mat nih_age_piyr = nih_age_piyr \ (`nyr_y', ., `nyr_y', `nyr_o', ., `nyr_o')
    mat nih_age_piyr = nih_age_piyr \ (`nzero_1', ., `nzero_1', `nzero_0', ., `nzero_0')
    local rownames "n_pis n_pi_yrs n_pi_yrs_zero"
    foreach v in nih_amt nih_active nih_new_grants {
        qui sum `v' if young == 1, d
        local y_mean = r(mean)
        local y_p50  = r(p50)
        local y_N    = r(N)
        qui sum `v' if young == 0, d
        mat nih_age_piyr = nih_age_piyr \ ///
            (`y_mean', `y_p50', `y_N', r(mean), r(p50), r(N))
        local rownames "`rownames' `v'"
    }
    mat colnames nih_age_piyr = young_mean young_p50 young_N old_mean old_p50 old_N
    mat rownames nih_age_piyr = `rownames'
    qui matrix_to_txt, saving("../output/tables/nih_by_age_piyr_`samp'`suf'.txt") ///
        matrix(nih_age_piyr) title(<tab:nih_by_age_piyr_`samp'`suf'>) format(%14.2f) replace

    kd_young_old nih_amt, xtitle(Annual NIH funding ($, PI-year)) ///
        w(100000) wlab("$100,000") unit(PI-years) cluster(athr_id) ///
        out(../output/figures/kd_nih_amt_by_age_piyr_`samp'`suf'.pdf)
    kd_young_old nih_active, xtitle(# active NIH grants (PI-year)) ///
        w(1) wlab("1 grant") unit(PI-years) fmt(%9.2f) cluster(athr_id) ///
        out(../output/figures/kd_nih_active_by_age_piyr_`samp'`suf'.pdf)
end

* ---------------------------------------------------------------------------
* Pre-period publication output for young vs old PIs, same split as
* nih_by_age (median age_2014 within the sample). Two measures: total pubs
* over the pre-period and pubs per year. The panel is rectangular over
* 2010-2019, so the per-year average always divides by the 4 pre-merger
* years and non-publishing years enter as zeros. pre_ppr_cnt_* are
* last-author counts; the any-position analogues are built here.
* ---------------------------------------------------------------------------
program gather_pubs
    syntax [, suf(string)]
    use athr_id year age_2014 athr_indicator foia_athr nih_pi_name ppr_cnt_any ///
        pre_ppr_cnt_sum pre_ppr_cnt_avg ///
        using ../external/pi_samp/pi_desc_all_jrnls_r1_r2`suf', clear
    gen pre_any = ppr_cnt_any if year < 2014
    bys athr_id: egen pre_ppr_any_sum = total(pre_any)
    bys athr_id: egen pre_ppr_any_avg = mean(pre_any)
    keep if athr_indicator == 1
    replace foia_athr = 0 if mi(foia_athr)
    gen byte nih_matched = !mi(nih_pi_name)
    rename (pre_ppr_cnt_sum pre_ppr_cnt_avg) (pre_ppr_sum pre_ppr_avg)
    keep athr_id age_2014 foia_athr nih_matched ///
         pre_ppr_sum pre_ppr_avg pre_ppr_any_sum pre_ppr_any_avg
    save ../temp/pubs_pre_pis`suf', replace
end

program pubs_by_age
    syntax, samp(string) [suf(string)]
    cap mkdir ../output/tables
    cap mkdir ../output/figures

    use ../temp/pubs_pre_pis`suf', clear
    if "`samp'" == "foia" keep if foia_athr == 1
    drop foia_athr nih_matched

    qui sum age_2014, d
    local med_age = r(p50)
    gen young = age_2014 < `med_age'
    qui count
    di as text "pubs_by_age `samp'`suf': `r(N)' PIs, median age_2014 = `med_age' (young = below median)"

    save ../output/pubs_by_age_pis_`samp'`suf', replace

    cap mat drop pubs_age
    qui count if young == 1
    local n_young = r(N)
    qui count if young == 0
    local n_old = r(N)
    mat pubs_age = (`n_young', ., `n_young', `n_old', ., `n_old')
    local rownames "n_pis"
    foreach v in age_2014 pre_ppr_sum pre_ppr_avg pre_ppr_any_sum pre_ppr_any_avg {
        qui sum `v' if young == 1, d
        local y_mean = r(mean)
        local y_p50  = r(p50)
        local y_N    = r(N)
        qui sum `v' if young == 0, d
        mat pubs_age = nullmat(pubs_age) \ ///
            (`y_mean', `y_p50', `y_N', r(mean), r(p50), r(N))
        local rownames "`rownames' `v'"
    }
    mat colnames pubs_age = young_mean young_p50 young_N old_mean old_p50 old_N
    mat rownames pubs_age = `rownames'
    qui matrix_to_txt, saving("../output/tables/pubs_by_age_`samp'`suf'.txt") ///
        matrix(pubs_age) title(<tab:pubs_by_age_`samp'`suf'>) format(%14.2f) replace

    kd_young_old pre_ppr_sum, xtitle(Total pubs 2010-2013) ///
        w(2) wlab("2 pubs") unit(PIs) fmt(%9.1f) ///
        out(../output/figures/kd_pre_ppr_sum_by_age_`samp'`suf'.pdf)
    kd_young_old pre_ppr_avg, xtitle(Avg pubs per year, 2010-2013) ///
        w(0.5) wlab("0.5 pubs") unit(PIs) fmt(%9.2f) ///
        out(../output/figures/kd_pre_ppr_avg_by_age_`samp'`suf'.pdf)
    kd_young_old pre_ppr_any_sum, xtitle(Total pubs 2010-2013 (any position)) ///
        w(5) wlab("5 pubs") unit(PIs) fmt(%9.1f) ///
        out(../output/figures/kd_pre_ppr_any_sum_by_age_`samp'`suf'.pdf)
    kd_young_old pre_ppr_any_avg, xtitle(Avg pubs per year, 2010-2013 (any position)) ///
        w(1) wlab("1 pub") unit(PIs) fmt(%9.2f) ///
        out(../output/figures/kd_pre_ppr_any_avg_by_age_`samp'`suf'.pdf)

    foreach v in pre_ppr_sum pre_ppr_avg pre_ppr_any_sum pre_ppr_any_avg {
        if "`v'" == "pre_ppr_sum"      local ytitle "Total pubs 2010-2013 (last author)"
        if "`v'" == "pre_ppr_avg"      local ytitle "Avg pubs per year, 2010-2013 (last author)"
        if "`v'" == "pre_ppr_any_sum"  local ytitle "Total pubs 2010-2013 (any position)"
        if "`v'" == "pre_ppr_any_avg"  local ytitle "Avg pubs per year, 2010-2013 (any position)"
        bs_stats, y(`v') x(age_2014) ///
            xtitle(Age in 2014 (yrs since first pub + 30)) ///
            ytitle(`ytitle') ///
            out(../output/figures/bs_`v'_by_age_`samp'`suf'.pdf)
    }
end

* ---------------------------------------------------------------------------
* Productivity per research dollar in the pre-period: pubs per year divided
* by dollars per year, both averaged over 2010-2013.
* samp(all)  = analysis-sample PIs matched to RePORTER with pre-period
*              funding; the denominator is NIH dollars.
* samp(foia) = the FOIA PIs among them, which also have observed consumables
*              spend, so the denominator can be FOIA spend or NIH + FOIA
*              combined.
* Ratios are scaled to pubs per $100k (NIH, combined) and per $10k (FOIA
* spend, an order of magnitude smaller); the dollars-per-pub inverse is
* reported alongside since it reads more naturally. The inverse requires a
* nonzero pub count.
* Small denominators are the hazard here: a PI whose RePORTER cost is a few
* dollars over four years produces a ratio in the millions and single-handedly
* sets the group mean. Three guards, in order: PIs below $10k/yr of NIH
* funding (or $1k/yr of FOIA spend) are dropped, the PI-level ratios are
* winsorized at p99 for the table and plots, and the table also reports the
* aggregate ratio (group total pubs / group total dollars), which is the
* summary to quote. The saved PI-level .dta keeps the raw ratios.
* Young/old uses the median age of the sample before these restrictions,
* matching nih_by_age.
* ---------------------------------------------------------------------------
program prod_per_dollar
    syntax, samp(string) [suf(string)]
    cap mkdir ../output/tables
    cap mkdir ../output/figures

    use ../temp/pubs_pre_pis`suf', clear
    if "`samp'" == "foia" keep if foia_athr == 1
    qui count
    local n_start = r(N)

    qui sum age_2014, d
    local med_age = r(p50)
    gen young = age_2014 < `med_age'

    keep if nih_matched == 1
    qui count
    local n_match = r(N)
    merge 1:1 athr_id using ../temp/nih_pre_amt, keep(1 3)
    qui count if _merge == 3
    local n_grant = r(N)
    keep if _merge == 3 & nih_amt_yr > 0
    drop _merge
    qui count
    local n_pos = r(N)

    * A handful of PIs carry a RePORTER total_cost of a few dollars across the
    * four pre-period years (nih_amt_yr as low as $0.25). Dividing by those
    * yields ratios in the millions that swamp every mean, so require a
    * denominator large enough to represent an actually funded lab.
    keep if nih_amt_yr >= 10000
    qui count
    local n_floor = r(N)

    local dvars nih_amt_yr
    if "`samp'" == "foia" {
        merge 1:1 athr_id using ../temp/spend_pi_avg, keep(3) nogen
        keep if tot_spend >= 1000
        gen double comb_dollars_yr = nih_amt_yr + tot_spend
        local dvars nih_amt_yr tot_spend comb_dollars_yr
    }
    qui count
    local n_kept = r(N)
    di as text "prod_per_dollar `samp'`suf': `n_start' PIs -> `n_match' NIH-matched -> " ///
        "`n_grant' with 2010-2013 grants -> `n_pos' with positive funding -> " ///
        "`n_floor' above the $10k/yr floor -> `n_kept' kept"
    di as text "prod_per_dollar `samp'`suf': median age_2014 = `med_age' (young = below median)"

    gen double ppr_per_100k_nih     = pre_ppr_avg     / (nih_amt_yr / 100000)
    gen double ppr_any_per_100k_nih = pre_ppr_any_avg / (nih_amt_yr / 100000)
    gen double nih_per_ppr          = nih_amt_yr / pre_ppr_avg if pre_ppr_avg > 0
    local vars ppr_per_100k_nih ppr_any_per_100k_nih nih_per_ppr
    if "`samp'" == "foia" {
        gen double ppr_per_10k_spend  = pre_ppr_avg / (tot_spend / 10000)
        gen double spend_per_ppr      = tot_spend   / pre_ppr_avg if pre_ppr_avg > 0
        gen double ppr_per_100k_comb  = pre_ppr_avg / (comb_dollars_yr / 100000)
        gen double comb_per_ppr       = comb_dollars_yr / pre_ppr_avg if pre_ppr_avg > 0
        local vars `vars' ppr_per_10k_spend spend_per_ppr ppr_per_100k_comb comb_per_ppr
    }

    save ../output/prod_per_dollar_pis_`samp'`suf', replace

    * Aggregate ratio (total pubs / total dollars within the age group) from
    * the untrimmed data. Unlike the mean of the PI-level ratio it is not
    * driven by small denominators, so it is the summary to quote. The
    * dollars-per-pub aggregates are just its reciprocal and are not repeated.
    local aggnm  ppr_per_100k_nih ppr_any_per_100k_nih
    local aggnum pre_ppr_avg      pre_ppr_any_avg
    local aggden nih_amt_yr       nih_amt_yr
    local aggscl 100000           100000
    if "`samp'" == "foia" {
        local aggnm  `aggnm'  ppr_per_10k_spend ppr_per_100k_comb
        local aggnum `aggnum' pre_ppr_avg       pre_ppr_avg
        local aggden `aggden' tot_spend         comb_dollars_yr
        local aggscl `aggscl' 10000             100000
    }
    local nagg : word count `aggnm'
    forvalues i = 1/`nagg' {
        local nm : word `i' of `aggnm'
        local nu : word `i' of `aggnum'
        local de : word `i' of `aggden'
        local sc : word `i' of `aggscl'
        foreach g in 1 0 {
            qui sum `nu' if young == `g'
            local num = r(sum)
            qui sum `de' if young == `g'
            local agg_`nm'_`g' = `num' / r(sum) * `sc'
        }
    }

    * The PI-level ratios stay heavily right-skewed even above the floor, so
    * winsorize at p99 for the table and the plots. ../output holds raw values.
    foreach v of local vars {
        qui sum `v', d
        qui replace `v' = r(p99) if `v' > r(p99) & !mi(`v')
    }

    cap mat drop prod
    qui count if young == 1
    local n_young = r(N)
    qui count if young == 0
    local n_old = r(N)
    mat prod = (`n_young', ., `n_young', `n_old', ., `n_old')
    local rownames "n_pis"
    foreach v in age_2014 pre_ppr_avg pre_ppr_any_avg `dvars' `vars' {
        qui sum `v' if young == 1, d
        local y_mean = r(mean)
        local y_p50  = r(p50)
        local y_N    = r(N)
        qui sum `v' if young == 0, d
        mat prod = nullmat(prod) \ ///
            (`y_mean', `y_p50', `y_N', r(mean), r(p50), r(N))
        local rownames "`rownames' `v'"
    }
    forvalues i = 1/`nagg' {
        local nm : word `i' of `aggnm'
        mat prod = prod \ (`agg_`nm'_1', ., ., `agg_`nm'_0', ., .)
        local rownames "`rownames' agg_`nm'"
    }
    mat colnames prod = young_mean young_p50 young_N old_mean old_p50 old_N
    mat rownames prod = `rownames'
    qui matrix_to_txt, saving("../output/tables/prod_per_dollar_`samp'`suf'.txt") ///
        matrix(prod) title(<tab:prod_per_dollar_`samp'`suf'>) format(%14.4f) replace

    kd_young_old ppr_per_100k_nih, ///
        xtitle(Pubs per year per $100k NIH funding, 2010-2013) ///
        w(0.5) wlab("0.5 pubs") unit(PIs) fmt(%9.2f) ///
        out(../output/figures/kd_ppr_per_100k_nih_`samp'`suf'.pdf)
    kd_young_old ppr_any_per_100k_nih, ///
        xtitle(Pubs per year per $100k NIH funding, 2010-2013 (any position)) ///
        w(1) wlab("1 pub") unit(PIs) fmt(%9.2f) ///
        out(../output/figures/kd_ppr_any_per_100k_nih_`samp'`suf'.pdf)
    if "`samp'" == "foia" {
        kd_young_old ppr_per_10k_spend, ///
            xtitle(Pubs per year per $10k FOIA spend, 2010-2013) ///
            w(0.5) wlab("0.5 pubs") unit(PIs) fmt(%9.2f) ///
            out(../output/figures/kd_ppr_per_10k_spend_`samp'`suf'.pdf)
        kd_young_old ppr_per_100k_comb, ///
            xtitle(Pubs per year per $100k NIH + FOIA, 2010-2013) ///
            w(0.5) wlab("0.5 pubs") unit(PIs) fmt(%9.2f) ///
            out(../output/figures/kd_ppr_per_100k_comb_`samp'`suf'.pdf)
    }

    foreach v of local vars {
        if "`v'" == "ppr_per_100k_nih"     local ytitle "Pubs per yr per $100k NIH (last author)"
        if "`v'" == "ppr_any_per_100k_nih" local ytitle "Pubs per yr per $100k NIH (any position)"
        if "`v'" == "nih_per_ppr"          local ytitle "NIH $ per pub"
        if "`v'" == "ppr_per_10k_spend"     local ytitle "Pubs per yr per $10k FOIA spend"
        if "`v'" == "spend_per_ppr"         local ytitle "FOIA $ per pub"
        if "`v'" == "ppr_per_100k_comb"     local ytitle "Pubs per yr per $100k NIH + FOIA"
        if "`v'" == "comb_per_ppr"          local ytitle "NIH + FOIA $ per pub"
        bs_stats, y(`v') x(age_2014) ///
            xtitle(Age in 2014 (yrs since first pub + 30)) ///
            ytitle(`ytitle') ///
            out(../output/figures/bs_`v'_by_age_`samp'`suf'.pdf)
    }
end

* ---------------------------------------------------------------------------
* Binscatter with slope + correlation stamped in the legend
* ---------------------------------------------------------------------------
program bs_stats
    syntax, y(string) x(string) ytitle(string) xtitle(string) out(string)
    qui reg `y' `x'
    local b_s  = strtrim("`: di %12.4g _b[`x']'")
    local se_s = strtrim("`: di %12.4g _se[`x']'")
    qui corr `y' `x'
    local r_s = strtrim("`: di %5.3f r(rho)'")
    local n_s = r(N)
    binscatter `y' `x', n(20) msymbol(O) mcolors(gs6) lcolors(ebblue) ///
        xtitle("`xtitle'") ytitle("`ytitle'") ///
        legend(on order(- "slope = `b_s' (SE: `se_s')" "corr = `r_s', N = `n_s'") ///
            pos(1) ring(0) region(fcolor(none)) size(small)) ///
        plotregion(margin(sides))
    graph export `out', replace
end

* ---------------------------------------------------------------------------
* FOIA PI spending by young vs old. Age from pi_descriptives analysis sample
* (age_2014 = 2014 - first pub year + 30, so "young" = short pub history).
* Split at the median age among matched FOIA PIs. Pre-period spend only
* (year <= 2013), same cleaning as boe.
* ---------------------------------------------------------------------------
program spend_by_age
    syntax [, suf(string)]
    cap mkdir ../output/tables
    cap mkdir ../output/figures

    use ../external/pi_samp/pi_desc_all_jrnls_r1_r2`suf', clear
    keep if athr_indicator == 1 & foia_athr == 1
    keep athr_id age_2014
    save ../temp/foia_pi_age`suf', replace

    use ../external/samp/merged_foias_with_pis, clear
    drop if mi(athr_id)
    gen year = year(date(date, "YMD"))
    drop if year > 2013
    merge m:1 category using ../external/categories/categories_tfidf, keep(1 3)
    rename _merge nonlab
    replace nonlab = 0 if nonlab == 3
    replace keep = 2 if keep == .
    gen hq = keep == 1 | (bad_control == 1 & support >= 25 & precision >= 0.8 & recall >= 0.8)
    gen nonlab_spend = spend if nonlab == 1
    gen lab_spend    = spend if nonlab == 0
    gen hq_labspend  = lab_spend if hq == 1
    collapse (sum) tot_spend = spend nonlab_spend lab_spend hq_labspend, by(athr_id year)
    gen perc_lab_spend = lab_spend / tot_spend * 100
    save ../temp/spend_athr_yr, replace
    collapse (mean) tot_spend nonlab_spend lab_spend hq_labspend perc_lab_spend ///
             (count) n_yrs = year, by(athr_id)
    save ../temp/spend_pi_avg, replace

    merge 1:1 athr_id using ../temp/foia_pi_age`suf', keep(1 3)
    qui count
    local n_all = r(N)
    qui count if _merge == 3
    local n_aged = r(N)
    di as text "spend_by_age`suf': `n_aged' of `n_all' FOIA PIs with spend data matched to analysis-sample age"
    keep if _merge == 3
    drop _merge

    qui sum age_2014, d
    local med_age = r(p50)
    gen young = age_2014 < `med_age'
    di as text "spend_by_age`suf': median age_2014 = `med_age' (young = below median)"

    * PI-level dataset behind the table/plots (incl. young/old flag)
    preserve
        keep athr_id age_2014 young tot_spend lab_spend nonlab_spend ///
             hq_labspend perc_lab_spend n_yrs
        save ../output/spend_by_age_pis`suf', replace
    restore

    cap mat drop spend_age
    qui count if young == 1
    local n_young = r(N)
    qui count if young == 0
    local n_old = r(N)
    mat spend_age = (`n_young', ., `n_young', `n_old', ., `n_old')
    local rownames "n_pis"
    foreach v in age_2014 tot_spend lab_spend nonlab_spend hq_labspend perc_lab_spend n_yrs {
        qui sum `v' if young == 1, d
        local y_mean = r(mean)
        local y_p50  = r(p50)
        local y_N    = r(N)
        qui sum `v' if young == 0, d
        mat spend_age = nullmat(spend_age) \ ///
            (`y_mean', `y_p50', `y_N', r(mean), r(p50), r(N))
        local rownames "`rownames' `v'"
    }
    mat colnames spend_age = young_mean young_p50 young_N old_mean old_p50 old_N
    mat rownames spend_age = `rownames'
    qui matrix_to_txt, saving("../output/tables/spend_by_age`suf'.txt") ///
        matrix(spend_age) title(<tab:spend_by_age`suf'>) format(%14.2f) replace

    * kdensity overlays young vs old; x capped at p95 of the pooled
    * distribution — the long right tail otherwise flattens everything.
    * Density is rescaled to percent of PIs per fixed bin (raw densities
    * over dollar amounts are unreadable 1e-5-scale numbers).
    foreach v in tot_spend lab_spend nonlab_spend perc_lab_spend {
        if "`v'" == "tot_spend"      local xtitle "Avg annual total spend ($)"
        if "`v'" == "lab_spend"      local xtitle "Avg annual lab spend ($)"
        if "`v'" == "nonlab_spend"   local xtitle "Avg annual non-lab spend ($)"
        if "`v'" == "perc_lab_spend" local xtitle "Lab share of spend (%)"
        local w 5000
        local wlab "$5,000"
        if "`v'" == "perc_lab_spend" {
            local w 5
            local wlab "5pp"
        }
        qui sum `v', d
        local xcap = r(p95)
        if "`v'" == "perc_lab_spend" local xcap = 100

        qui sum `v' if young == 1, d
        local mean_y = strtrim("`: di %9.0fc r(mean)'")
        local n_y    = r(N)
        qui sum `v' if young == 0, d
        local mean_o = strtrim("`: di %9.0fc r(mean)'")
        local n_o    = r(N)

        kd_tests `v'
        local diff = strtrim("`: di %9.0fc r(diff)'")
        local p_t  = r(p_t)
        local p_ks = r(p_ks)
        pfmt `p_t'
        local pt_s `r(s)'
        pfmt `p_ks'
        local pks_s `r(s)'
        local ptxt "Early-career - late-career = `diff'; t-test p = `pt_s'; K-S p = `pks_s'"
        di as text "`v': `ptxt'"

        * both densities on one common x grid so rarea can shade the gap;
        * grid starts at 0 so the kernel spill into negative spend isn't drawn
        cap drop _kx _kd_y _kd_o _kp_y _kp_o _kp_c
        gen _kx = `xcap' * (_n - 1) / 199 if _n <= 200
        kdensity `v' if young == 1 & `v' <= `xcap', at(_kx) gen(_kd_y) nograph
        kdensity `v' if young == 0 & `v' <= `xcap', at(_kx) gen(_kd_o) nograph
        gen _kp_y = _kd_y * `w' * 100
        gen _kp_o = _kd_o * `w' * 100
        gen _kp_c = min(_kp_y, _kp_o)
        tw (rarea _kp_c _kp_y _kx, color(ebblue*0.3) lwidth(none)) ///
           (rarea _kp_c _kp_o _kx, color(dkorange*0.3) lwidth(none)) ///
           (line _kp_y _kx, lcolor(ebblue)) ///
           (line _kp_o _kx, lcolor(dkorange)), ///
           xtitle("`xtitle'") ytitle("Percent of PIs (per `wlab' bin)") ///
           legend(order(3 "Early-Career (N=`n_y'): mean=`mean_y'" ///
                        4 "Late-Career (N=`n_o'): mean=`mean_o'") ///
               pos(1) ring(0) cols(1) size(small) region(fcolor(none))) ///
           note("`ptxt'", size(small)) ///
           plotregion(margin(sides))
        graph export ../output/figures/kd_`v'_by_age`suf'.pdf, replace
        cap drop _kx _kd_y _kd_o _kp_y _kp_o _kp_c
    }

    * logs drop PIs with no lab spend; N in the legend shows how many
    gen double ln_lab_spend = ln(lab_spend) if lab_spend > 0
    gen double ln_tot_spend = ln(tot_spend) if tot_spend > 0
    foreach v in lab_spend tot_spend ln_lab_spend ln_tot_spend {
        if "`v'" == "lab_spend"    local ytitle "Avg annual lab spend ($)"
        if "`v'" == "tot_spend"    local ytitle "Avg annual total spend ($)"
        if "`v'" == "ln_lab_spend" local ytitle "Log avg annual lab spend"
        if "`v'" == "ln_tot_spend" local ytitle "Log avg annual total spend"
        bs_stats, y(`v') x(age_2014) ///
            xtitle(Age in 2014 (yrs since first pub + 30)) ///
            ytitle(`ytitle') ///
            out(../output/figures/bs_`v'_by_age`suf'.pdf)
    }
end

* ---------------------------------------------------------------------------
* Same young/old comparison at the PI-YEAR level: each obs is one PI-year of
* spending (no averaging across years). Young/old split uses the same
* PI-level median age as spend_by_age.
* ---------------------------------------------------------------------------
program spend_by_age_piyr
    syntax [, suf(string)]
    use ../temp/spend_athr_yr, clear
    merge m:1 athr_id using ../temp/foia_pi_age`suf', keep(3) nogen

    egen _tag = tag(athr_id)
    qui sum age_2014 if _tag, d
    local med_age = r(p50)
    gen young = age_2014 < `med_age'
    qui count if _tag & young == 1
    local npi_y = r(N)
    qui count if _tag & young == 0
    local npi_o = r(N)
    drop _tag
    di as text "spend_by_age_piyr`suf': median age = `med_age'; PIs young/old = `npi_y'/`npi_o'"

    preserve
        keep athr_id year age_2014 young tot_spend lab_spend nonlab_spend ///
             hq_labspend perc_lab_spend
        save ../output/spend_by_age_piyrs`suf', replace
    restore

    cap mat drop spend_age_piyr
    qui count if young == 1
    local nyr_y = r(N)
    qui count if young == 0
    local nyr_o = r(N)
    mat spend_age_piyr = (`npi_y', ., `npi_y', `npi_o', ., `npi_o')
    mat spend_age_piyr = spend_age_piyr \ (`nyr_y', ., `nyr_y', `nyr_o', ., `nyr_o')
    local rownames "n_pis n_pi_yrs"
    foreach v in tot_spend lab_spend nonlab_spend hq_labspend perc_lab_spend {
        qui sum `v' if young == 1, d
        local y_mean = r(mean)
        local y_p50  = r(p50)
        local y_N    = r(N)
        qui sum `v' if young == 0, d
        mat spend_age_piyr = spend_age_piyr \ ///
            (`y_mean', `y_p50', `y_N', r(mean), r(p50), r(N))
        local rownames "`rownames' `v'"
    }
    mat colnames spend_age_piyr = young_mean young_p50 young_N old_mean old_p50 old_N
    mat rownames spend_age_piyr = `rownames'
    qui matrix_to_txt, saving("../output/tables/spend_by_age_piyr`suf'.txt") ///
        matrix(spend_age_piyr) title(<tab:spend_by_age_piyr`suf'>) format(%14.2f) replace

    foreach v in tot_spend lab_spend nonlab_spend perc_lab_spend {
        if "`v'" == "tot_spend"      local xtitle "Annual total spend ($, PI-year)"
        if "`v'" == "lab_spend"      local xtitle "Annual lab spend ($, PI-year)"
        if "`v'" == "nonlab_spend"   local xtitle "Annual non-lab spend ($, PI-year)"
        if "`v'" == "perc_lab_spend" local xtitle "Lab share of spend (%, PI-year)"
        local w 5000
        local wlab "$5,000"
        if "`v'" == "perc_lab_spend" {
            local w 5
            local wlab "5pp"
        }
        qui sum `v', d
        local xcap = r(p95)
        if "`v'" == "perc_lab_spend" local xcap = 100

        qui sum `v' if young == 1, d
        local mean_y = strtrim("`: di %9.0fc r(mean)'")
        local n_y    = r(N)
        qui sum `v' if young == 0, d
        local mean_o = strtrim("`: di %9.0fc r(mean)'")
        local n_o    = r(N)

        * PI-years are clustered within PI, so the mean difference is tested
        * with PI-clustered SEs rather than an iid t-test
        kd_tests `v', cluster(athr_id)
        local diff = strtrim("`: di %9.0fc r(diff)'")
        local p_t  = r(p_t)
        local p_ks = r(p_ks)
        pfmt `p_t'
        local pt_s `r(s)'
        pfmt `p_ks'
        local pks_s `r(s)'
        local ptxt "Early-career - late-career = `diff'; t-test p = `pt_s' (PI-clustered); K-S p = `pks_s'"
        di as text "`v': `ptxt'"

        * both densities on one common x grid
        cap drop _kx _kd_y _kd_o _kp_y _kp_o
        gen _kx = `xcap' * (_n - 1) / 199 if _n <= 200
        kdensity `v' if young == 1 & `v' <= `xcap', at(_kx) gen(_kd_y) nograph
        kdensity `v' if young == 0 & `v' <= `xcap', at(_kx) gen(_kd_o) nograph
        gen _kp_y = _kd_y * `w' * 100
        gen _kp_o = _kd_o * `w' * 100
        tw (line _kp_y _kx, lcolor(ebblue)) ///
           (line _kp_o _kx, lcolor(dkorange)), ///
           xtitle("`xtitle'") ytitle("Percent of PI-years (per `wlab' bin)") ///
           legend(order(1 "Early-Career (N=`n_y', PIs=`npi_y'): mean=`mean_y'" ///
                        2 "Late-Career (N=`n_o', PIs=`npi_o'): mean=`mean_o'") ///
               pos(1) ring(0) cols(1) size(small) region(fcolor(none))) ///
           note("`ptxt'", size(small)) ///
           plotregion(margin(sides))
        graph export ../output/figures/kd_`v'_by_age_piyr`suf'.pdf, replace
        cap drop _kx _kd_y _kd_o _kp_y _kp_o
    }
end

program boe
    use ../external/samp/merged_foias_with_pis,  clear
   * keep if inlist(uni , "utdallas", "umich")
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
    collapse (sum) spend nonlab_spend lab_spend , by(athr_id year hq)
    gen hq_labspend = lab_spend if hq == 1
    gen lq_labspend = lab_spend if hq == 0
    collapse (sum) tot_spend = spend nonlab_spend lab_spend hq_labspend lq_labspend  , by(athr_id year)
    gen perc_lab_spend = lab_spend/tot_spend* 100
    gen perc_nonlab_spend = nonlab_spend/tot_spend* 100
    collapse (mean) tot_spend nonlab_spend lab_spend hq_labspend lq_labspend perc_lab_spend perc_nonlab_spend, by(athr_id)
    graph bar lab_spend nonlab_spend, over(athr_id ,sort((mean) tot_spend) descending) stack bar(1, color(lavender%70)) bar(2, color(dkorange%70)) legend(on order(- "Lab Spend" - "Non-Lab Spend") pos(1) ring(0) size(small) region(fcolor(none))) ytitle("Average Annual Spend ($)") plotregion(margin(sides))
    graph export ../output/figures/avg_spend_by_athr.pdf, replace
    sum lab_spend if lab_spend >50, d
    local mean_lab_spend : di %6.2f r(mean)
    local sd_lab_spend : di %6.2f r(sd)
    local min_lab_spend : di %6.2f r(min)
    local max_lab_spend : di %10.2f r(max)
    local N_lab_spend : di %6.0f r(N)
    local q1_lab_spend : di %6.2f r(p25)
    local q3_lab_spend : di %6.2f r(p75)
    local median_lab_spend : di %6.2f r(p50)
    local cut = r(p1)
   tw hist lab_spend if lab_spend >50,  color(edkblue) frac width(5000) xlab(0(7500)150000, angle(45)) ///
       xtitle("Consumables Expenditure ($)") ytitle("Fraction of PI-Years") legend(on order(- "N = `N_lab_spend'" "Mean = `mean_lab_spend'" "SD = `sd_lab_spend'" "Min = `min_lab_spend'" "Q1 = `q1_lab_spend'" "Median = `median_lab_spend'" "Q3 = `q3_lab_spend'" "Max = `max_lab_spend'") pos(1) ring(0) region(fcolor(none)) size(small))
   graph export ../output/figures/lab_spend.pdf, replace
   kdensity perc_lab_spend
   graph export ../output/figures/perc_lab_spend.pdf, replace
   kdensity perc_nonlab_spend
   graph export ../output/figures/perc_nonlab_spend.pdf, replace
   bs_stats, y(perc_lab_spend) x(lab_spend) ///
       ytitle(Lab share of spend (%)) xtitle(Avg annual lab spend ($)) ///
       out(../output/figures/bs_perc_lab_spend_by_lab_spend.pdf)
   bs_stats, y(perc_lab_spend) x(tot_spend) ///
       ytitle(Lab share of spend (%)) xtitle(Avg annual total spend ($)) ///
       out(../output/figures/bs_perc_lab_spend_by_tot_spend.pdf)
   bs_stats, y(perc_nonlab_spend) x(nonlab_spend) ///
       ytitle(Non-lab share of spend (%)) xtitle(Avg annual non-lab spend ($)) ///
       out(../output/figures/bs_perc_nonlab_spend_by_lab_spend.pdf)
   bs_stats, y(lab_spend) x(tot_spend) ///
       ytitle(Avg annual lab spend ($)) xtitle(Avg annual total spend ($)) ///
       out(../output/figures/bs_lab_spend_by_tot_spend.pdf)
end

main
