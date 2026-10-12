set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries, loadglob(../external/lib/globals.txt)
adopath ++ "../external/lib/stata"
version 17
set maxvar 20000

global DEBUG_YVAR "ppr_cnt"
global HET_AGE_BINW 10
global HET_AGE_BIN_MINPI 30
global HET_AGE_TOPCODE 40
global HET_MATCH_OUT_BINS 4
global HET_MATCH_FUND_BINS 3
global HET_MATCHED_ONLY 0
if "`1'" == "matched" global HET_MATCHED_ONLY 1

program main
    cap mkdir ../temp
    cap mkdir "../output/figures/all_jrnls"
    het_group_labels
    foreach pub in 0 1 {
        build_het_panel, samp(all_jrnls) r1r2(1) public(`pub')
        if $HET_MATCHED_ONLY == 0 {
            desc_pre_output_by_age, samp(all_jrnls) r1r2(1) public(`pub')
            desc_exposure_by_age,   samp(all_jrnls) r1r2(1) public(`pub')
            ppml_age_gradient,      samp(all_jrnls) r1r2(1) public(`pub')
        }
        matched_career_comparison, samp(all_jrnls) r1r2(1) public(`pub')
        output_matched_tables,     samp(all_jrnls) r1r2(1) public(`pub')
    }
end

program desc_exposure_by_age
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    cap mkdir "../output/figures/`samp'"

    use ../temp/es_`samp'`suf', clear
    cap confirm variable nih_pi
    if _rc gen byte nih_pi = .
    egen long inst_num = group(inst_id)
    gcollapse (firstnm) exposure young nih_pi inst_num, by(athr_id)
    drop if mi(young) | mi(exposure)

    local tag_all ""
    local tag_nih "_nih"
    local cond_all "1"
    local cond_nih "nih_pi == 1"
    foreach s in all nih {
        qui count if `cond_`s'' & young == 1
        local n_y = r(N)
        qui count if `cond_`s'' & young == 0
        local n_o = r(N)
        if `n_y' == 0 | `n_o' == 0 {
            di as error "desc_exposure_by_age `samp'`suf' [`s']: empty group -- SKIPPED."
            continue
        }
        qui sum exposure if `cond_`s'' & young == 1, d
        local mu_y = strtrim(string(r(mean), "%6.3f"))
        local md_y = strtrim(string(r(p50),  "%6.3f"))
        qui sum exposure if `cond_`s'' & young == 0, d
        local mu_o = strtrim(string(r(mean), "%6.3f"))
        local md_o = strtrim(string(r(p50),  "%6.3f"))
        di as text _n "desc_exposure_by_age `samp'`suf' [`s']: N young = `n_y' (mean=`mu_y' p50=`md_y'), N old = `n_o' (mean=`mu_o' p50=`md_o')"
        cap noi ksmirnov exposure if `cond_`s'', by(young)
        qui reg exposure young if `cond_`s'', vce(cluster inst_num)
        di as text "  young-old diff = " %8.4f _b[young] " (se " %8.4f _se[young] ")"

        qui sum exposure if `cond_`s'', d
        local xcap = r(p99)
        cap drop _kx _kd_y _kd_o _kd_c
        gen _kx = `xcap' * (_n - 1) / 199 if _n <= 200
        kdensity exposure if `cond_`s'' & young == 1 & exposure <= `xcap', at(_kx) gen(_kd_y) nograph
        kdensity exposure if `cond_`s'' & young == 0 & exposure <= `xcap', at(_kx) gen(_kd_o) nograph
        gen _kd_c = min(_kd_y, _kd_o)
        local leg_y "Early-Career (N=`n_y'): mean=`mu_y'"
        local leg_o "Late-Career (N=`n_o'): mean=`mu_o'"
        local kd_leg `"legend(order(3 "`leg_y'" 4 "`leg_o'") pos(2) ring(0) rows(2) size(small))"'
        local fdir ../output/figures/`samp'
        foreach fmode of global FIG_MODES {
            if "`fmode'" == "paper" {
                local kd_leg `"legend(order(3 "${LBL_young}" 4 "${LBL_old}") pos(2) ring(0) rows(2) size(small))"'
                cap mkdir "`fdir'"
            }
            tw (rarea _kd_c _kd_y _kx, color(ebblue*0.3) lwidth(none)) ///
               (rarea _kd_c _kd_o _kx, color(dkorange*0.3) lwidth(none)) ///
               (line _kd_y _kx, lcolor(ebblue) lwidth(medthick)) ///
               (line _kd_o _kx, lcolor(dkorange) lwidth(medthick)) ///
               , xtitle("Exposure measure") ytitle("Density") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                 `kd_leg' ///
                 plotregion(margin(sides))
            fig_export, path("`fdir'/desc_kd_exposure`tag_`s''`suf'.pdf") mode(`fmode')
        }
        cap drop _kx _kd_y _kd_o _kd_c
    }
end

program desc_pre_output_by_age
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    cap mkdir "../output/figures/`samp'"

    use ../temp/es_`samp'`suf', clear
    keep if year < 2014
    qui sum year
    local y0 = r(min)
    local y1 = r(max)

    local sum_src   ppr_cnt cite_affl_wt n_first_ppr n_last_ppr
    local sum_alias ppr_tot cite         first       last
    local mean_src   ppr_cnt
    local mean_alias ppr_yr
    local lbl_ppr_tot "total papers"
    local lbl_ppr_yr  "papers per year"
    local lbl_cite    "affiliation-weighted citations"
    local lbl_first   "first-authored papers"
    local lbl_last    "last-authored papers"
    local fmt_ppr_tot %6.1f
    local fmt_ppr_yr  %5.2f
    local fmt_cite    %8.1f
    local fmt_first   %6.1f
    local fmt_last    %6.1f

    local coll_sum
    local coll_mean
    local keep_alias
    foreach stat in sum mean {
        local nsrc : word count ``stat'_src'
        forvalues i = 1/`nsrc' {
            local src : word `i' of ``stat'_src'
            local a   : word `i' of ``stat'_alias'
            cap confirm variable `src'
            if _rc {
                di as error "desc_pre_output_by_age `samp'`suf': `src' not in panel -- `a' density SKIPPED."
                continue
            }
            local coll_`stat' `coll_`stat'' pre_`a'=`src'
            local keep_alias `keep_alias' `a'
        }
    }
    if "`keep_alias'" == "" {
        di as error "desc_pre_output_by_age `samp'`suf': no outcomes available -- nothing plotted."
        exit
    }
    local coll_sum_part = cond("`coll_sum'" == "", "", "(sum) `coll_sum'")
    local coll_mean_part = cond("`coll_mean'" == "", "", "(mean) `coll_mean'")

    egen long inst_num = group(inst_id)
    gcollapse `coll_sum_part' `coll_mean_part' (firstnm) young inst_num, by(athr_id)
    drop if mi(young)

    qui count if young == 1
    local n_y = r(N)
    qui count if young == 0
    local n_o = r(N)
    di as text _n "desc_pre_output_by_age `samp'`suf': pre-period = `y0'-`y1', N young = `n_y', N old = `n_o'"

    foreach a of local keep_alias {
        local f "`fmt_`a''"
        qui sum pre_`a' if young == 1, d
        local mu_y = strtrim(string(r(mean), "`f'"))
        local md_y = strtrim(string(r(p50),  "`f'"))
        qui sum pre_`a' if young == 0, d
        local mu_o = strtrim(string(r(mean), "`f'"))
        local md_o = strtrim(string(r(p50),  "`f'"))
        local leg_y "Early-Career (N=`n_y'): mean=`mu_y'"
        local leg_o "Late-Career (N=`n_o'): mean=`mu_o'"
        di as text "  `a': young mean=`mu_y' p50=`md_y' | old mean=`mu_o' p50=`md_o'"
        cap noi ksmirnov pre_`a', by(young)
        qui reg pre_`a' young, vce(cluster inst_num)
        di as text "  `a': young-old diff = " %8.3f _b[young] " (se " %8.3f _se[young] ")"

        gen double ln_pre_`a' = ln(1 + pre_`a')
        qui sum ln_pre_`a'
        cap drop _kx _kd_y _kd_o _kd_c
        gen _kx = r(min) + (r(max) - r(min)) * (_n - 1) / 199 if _n <= 200
        kdensity ln_pre_`a' if young == 1, at(_kx) gen(_kd_y) nograph
        kdensity ln_pre_`a' if young == 0, at(_kx) gen(_kd_o) nograph
        gen _kd_c = min(_kd_y, _kd_o)
        local kd_leg `"legend(order(3 "`leg_y'" 4 "`leg_o'") pos(2) ring(0) rows(2) size(small))"'
        local fdir ../output/figures/`samp'
        foreach fmode of global FIG_MODES {
            if "`fmode'" == "paper" {
                local kd_leg `"legend(order(3 "${LBL_young}" 4 "${LBL_old}") pos(2) ring(0) rows(2) size(small))"'
                cap mkdir "`fdir'"
            }
            tw (rarea _kd_c _kd_y _kx, color(ebblue*0.3) lwidth(none)) ///
               (rarea _kd_c _kd_o _kx, color(dkorange*0.3) lwidth(none)) ///
               (line _kd_y _kx, lcolor(ebblue) lwidth(medthick)) ///
               (line _kd_o _kx, lcolor(dkorange) lwidth(medthick)) ///
               , xtitle("ln(1 + pre-period `lbl_`a'', `y0'-`y1')") ytitle("Density") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                 `kd_leg' ///
                 plotregion(margin(sides))
            fig_export, path("`fdir'/desc_kd_pre_`a'_ln`suf'.pdf") mode(`fmode')
        }

        qui sum pre_`a', d
        local xcap = r(p95)
        cap drop _kx _kd_y _kd_o _kd_c
        gen _kx = `xcap' * (_n - 1) / 199 if _n <= 200
        kdensity pre_`a' if young == 1 & pre_`a' <= `xcap', at(_kx) gen(_kd_y) nograph
        kdensity pre_`a' if young == 0 & pre_`a' <= `xcap', at(_kx) gen(_kd_o) nograph
        gen _kd_c = min(_kd_y, _kd_o)
        local kd_leg `"legend(order(3 "`leg_y'" 4 "`leg_o'") pos(2) ring(0) rows(2) size(small))"'
        local fdir ../output/figures/`samp'
        foreach fmode of global FIG_MODES {
            if "`fmode'" == "paper" {
                local kd_leg `"legend(order(3 "${LBL_young}" 4 "${LBL_old}") pos(2) ring(0) rows(2) size(small))"'
                cap mkdir "`fdir'"
            }
            tw (rarea _kd_c _kd_y _kx, color(ebblue*0.3) lwidth(none)) ///
               (rarea _kd_c _kd_o _kx, color(dkorange*0.3) lwidth(none)) ///
               (line _kd_y _kx, lcolor(ebblue) lwidth(medthick)) ///
               (line _kd_o _kx, lcolor(dkorange) lwidth(medthick)) ///
               , xtitle("Pre-period `lbl_`a'', `y0'-`y1' (x capped at pooled p95)") ytitle("Density") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                 `kd_leg' ///
                 plotregion(margin(sides))
            fig_export, path("`fdir'/desc_kd_pre_`a'_raw`suf'.pdf") mode(`fmode')
        }
        cap drop _kx _kd_y _kd_o _kd_c
    }

    save ../temp/desc_pre_output_`samp'`suf', replace
end

program ppml_age_gradient
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local fes athr_id year
    local vce_cl athr_id
    if "$FE_MODE" == "inst_cluster" {
        local fes inst_id cluster_30 year
        local vce_cl inst_id
    }
    if "$FE_MODE" == "inst_cluster_fldyr" {
        local fes inst_id i.cluster_30#i.year
        local vce_cl inst_id
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    cap mkdir "../output/figures/`samp'"

    local yvar_list ppr_cnt cite_affl_wt
    if "$DEBUG_YVAR" != "" local yvar_list $DEBUG_YVAR
    local ppml_skip avg_position avg_team_size_last avg_team_size_notlast

    use ../temp/es_`samp'`suf', clear
    gen post       = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post

    local binw = $HET_AGE_BINW
    foreach agevar in lab_age_any_2014 lab_age_2014 lab_age_ns_2014 {
    cap confirm variable `agevar'
    if _rc {
        di as error "ppml_age_gradient `samp'`suf': `agevar' not in panel -- skipped."
        continue
    }
    local gpfx labanygrad
    local gtmp lab_any_gradient
    local gxtit "Years since first publication in 2014"
    if "`agevar'" == "lab_age_2014" {
        local gpfx labgrad
        local gtmp lab_gradient
        local gxtit "Years running lab in 2014"
    }
    if "`agevar'" == "lab_age_ns_2014" {
        local gpfx labnsgrad
        local gtmp lab_ns_gradient
        local gxtit "Years running lab in 2014 (excl. solo papers)"
    }
    cap drop agebin
    gen _agebin_pi = floor(min(max(`agevar', 0), $HET_AGE_TOPCODE) / `binw') + 1 if athr_indicator == 1
    bys athr_id: egen agebin = max(_agebin_pi)
    drop _agebin_pi
    qui sum agebin if athr_indicator == 1
    local K = r(max)
    while `K' > 1 {
        gunique athr_id if agebin == `K' & athr_indicator == 1
        if r(unique) >= $HET_AGE_BIN_MINPI continue, break
        replace agebin = `K' - 1 if agebin == `K'
        local --K
    }

    local zvars
    local svars
    local bins_used
    forval k = 1/`K' {
        qui count if agebin == `k' & athr_indicator == 1
        if r(N) == 0 {
            di as error "ppml_age_gradient `samp'`suf': age bin `k' empty -- skipped."
            continue
        }
        cap drop Z_a`k'
        cap drop S_a`k'
        gen Z_a`k' = Z_it       * (agebin == `k')
        gen S_a`k' = Z_share_it * (agebin == `k')
        local zvars `zvars' Z_a`k'
        local svars `svars' S_a`k'
        local bins_used `bins_used' `k'
    }
    local ptvars
    local nb : word count `bins_used'
    forval i = 1/`=`nb'-1' {
        local k : word `i' of `bins_used'
        cap drop PT_a`k'
        gen PT_a`k' = post * (agebin == `k')
        local ptvars `ptvars' PT_a`k'
    }

    foreach yvar of local yvar_list {
        if strpos(" `ppml_skip' ", " `yvar' ") > 0 {
            di as text "ppml_age_gradient: `yvar' not a count outcome -- skipped."
            continue
        }
        local pooled_fes `fes'
        local pooled_vce_cl `vce_cl'
        if "`yvar'" == "nih_total_cost" {
            * Plotting below already uses preserve/restore in this program.
            tempfile annual_nih_age
            quietly save `annual_nih_age', replace
            nih_award_period_means
            local pooled_fes athr_id year
            local pooled_vce_cl athr_id
        }
        local ppml_ytit "Output-cost elasticity"
        if "`yvar'" == "n_grants"       local ppml_ytit "{&Delta} log expected active NIH research grants"
        if "`yvar'" == "n_new_grants"   local ppml_ytit "{&Delta} log expected new NIH research grants"
        if "`yvar'" == "nih_total_cost" local ppml_ytit "{&Delta} log expected average annual NIH award dollars"

        cap noi ppmlhdfe `yvar' `zvars' `svars' `ptvars' if !mi(agebin), ///
            absorb(`pooled_fes') vce(cluster `pooled_vce_cl')
        local rc = _rc
        if `rc' {
            if "`yvar'" == "nih_total_cost" use `annual_nih_age', clear
            di as error "ppml_age_gradient `samp'`suf' `yvar' failed (rc=`rc'); skipping."
            continue
        }
        gunique athr_id if e(sample)
        local n_pis = r(unique)
        gunique inst_id if e(sample)
        local n_insts = r(unique)
        cap mat drop AG
        foreach k of local bins_used {
            if _se[Z_a`k'] == 0 {
                di as error "ppml_age_gradient `samp'`suf' `yvar': Z_a`k' dropped/degenerate -- omitted from plot."
                continue
            }
            qui sum `agevar' if athr_indicator == 1 & agebin == `k'
            mat AG = nullmat(AG) \ (`k', r(mean), (`k' - 0.5) * `binw', r(N), _b[Z_a`k'], _se[Z_a`k'])
        }
        preserve
        clear
        svmat AG
        rename (AG1 AG2 AG3 AG4 AG5 AG6) (bin age_mean age_mid n_pis b se)
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        save ../temp/`gtmp'_`samp'`suf'_`yvar', replace
        qui reg b age_mid [aw=1/(se*se)]
        local slope_lbl = "Slope: " + strtrim(string(_b[age_mid], "%7.3f")) + " (" + strtrim(string(_se[age_mid], "%7.3f")) + ")"
        local xlab
        forval i = 1/`=_N' {
            local k = bin[`i']
            local lo = (`k' - 1) * `binw'
            if `k' == `K' local xlab `xlab' `=age_mid[`i']' "`lo'+"
            else          local xlab `xlab' `=age_mid[`i']' "`lo'-`=`lo' + `binw' - 1'"
        }
        local ygap 0.3
        qui sum ub
        local ymax : di %5.2f ceil(r(max) / `ygap') * `ygap'
        qui sum lb
        local ymin : di %5.2f floor(r(min) / `ygap') * `ygap'
        if `ymin' > 0 local ymin = 0
        if `ymax' < 0 local ymax = 0
        local stats_leg `"legend(on order(- "Num. PIs: `n_pis'" "Num. insts: `n_insts'" "`slope_lbl'") pos(7) ring(1) rows(3) bmargin(zero) size(small))"'
        local fdir ../output/figures/`samp'
        foreach fmode of global FIG_MODES {
            if "`fmode'" == "paper" {
                local stats_leg `"legend(on order(- "`slope_lbl'") ring(0) position(11) cols(1) region(lcolor(none)) size(small))"'
                cap mkdir "`fdir'"
            }
            local slope_col = cond("`fmode'" == "paper", "gs8", "dkorange")
            local ylab_m ylab(`ymin'(`ygap')`ymax')
            if "`fmode'" == "paper" local ylab_m ylab(`ymin'(`ygap')`ymax', format(%3.1f))
            tw rcap ub lb age_mid, lcolor(ebblue%70) msize(vsmall) || ///
               scatter b age_mid, mcolor(ebblue) || ///
               lfit b age_mid [aw=1/(se*se)], lcolor(`slope_col') lpattern(dash) ///
               xlab(`xlab', noticks) xsc(r(0 `=`K' * `binw'')) xtitle("`gxtit'") ytitle("`ppml_ytit'") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
               `ylab_m' ///
               yline(0, lcolor(gs10) lpattern(solid)) ///
               `stats_leg' ///
               plotregion(margin(sides))
            fig_export, path("`fdir'/`gpfx'_`yvar'`suf'_ppml_mshrctrl.pdf") mode(`fmode')
        }
        restore
        if "`yvar'" == "nih_total_cost" use `annual_nih_age', clear
    }
    }
end

program matched_career_comparison
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local fes athr_id year
    local vce_cl athr_id
    if "$FE_MODE" == "inst_cluster" {
        local fes inst_id cluster_30 year
        local vce_cl inst_id
    }
    if "$FE_MODE" == "inst_cluster_fldyr" {
        local fes inst_id i.cluster_30#i.year
        local vce_cl inst_id
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    cap mkdir "../output/figures/`samp'"
    cap mkdir "../output/figures/`samp'/matched"

    use ../temp/es_`samp'`suf', clear
    foreach v in young old nih_pi cluster_30 pre_ppr_cnt_sum pre_nihd lab_age_2014 {
        cap confirm variable `v'
        if _rc {
            di as error "matched_career_comparison `samp'`suf': `v' not in panel -- SKIPPED."
            exit
        }
    }
    keep if !mi(young)
    foreach v in post post1 post2 cell cs w_cem out_bin fund_bin {
        cap drop `v'
    }
    gen _pre_cite = cite_affl_wt if year < 2014
    bys athr_id: egen pre_cite_sum = total(_pre_cite)
    drop _pre_cite
    gen byte any_award = nih_pi == 1 & !mi(pre_nihd)
    gen double ln_nihd = cond(any_award == 1, ln(1 + pre_nihd), 0) if nih_pi == 1
    gen double ln_pre_out = ln(pre_ppr_cnt_sum)
    gen byte post  = year >= 2014
    gen byte post1 = inrange(year, 2014, 2016)
    gen byte post2 = inrange(year, 2017, 2019)
    foreach g in young old {
        gen Z_`g' = exposure      * post * `g'
        gen S_`g' = mkt_spend_shr * post * `g'
        foreach k in 1 2 {
            gen Z`k'_`g' = exposure      * post`k' * `g'
            gen S`k'_`g' = mkt_spend_shr * post`k' * `g'
        }
    }
    gen PT_young  = post  * young
    gen PT1_young = post1 * young
    gen PT2_young = post2 * young
    save ../temp/matched_panel_`samp'`suf', replace

    local bal_vars_all lab_age_2014 pre_ppr_cnt_sum pre_cite_sum exposure mkt_spend_shr
    local bal_vars_nih `bal_vars_all' ln_nihd any_award
    foreach u in nih all {
        use ../temp/matched_panel_`samp'`suf', clear
        keep if athr_indicator == 1
        if "`u'" == "nih" keep if nih_pi == 1
        xtile out_bin = pre_ppr_cnt_sum, nq($HET_MATCH_OUT_BINS)
        if "`u'" == "nih" {
            xtile fund_bin = pre_nihd if any_award == 1, nq($HET_MATCH_FUND_BINS)
            replace fund_bin = 0 if any_award == 0
            egen long cell = group(cluster_30 out_bin fund_bin)
        }
        else {
            gen byte fund_bin = .
            egen long cell = group(cluster_30 out_bin)
        }
        bys cell: egen n_y_cell = total(young == 1)
        bys cell: egen n_o_cell = total(young == 0)
        gen byte cs = n_y_cell > 0 & n_o_cell > 0
        qui count if cs == 1 & young == 1
        local N_y = r(N)
        qui count if cs == 1 & young == 0
        local N_o = r(N)
        gen double w_cem = cond(young == 1, 1, (n_y_cell / n_o_cell) * (`N_o' / `N_y')) if cs == 1
        gunique cell
        local n_cells = r(unique)
        gunique cell if cs == 1
        local n_cells_cs = r(unique)
        qui count if young == 1
        local n_y_all = r(N)
        qui count if young == 0
        local n_o_all = r(N)
        di as text "matched_career_comparison `samp'`suf' [`u']: `n_cells' cells (`n_cells_cs' with both career stages); " ///
            "early-career PIs in common support `N_y'/`n_y_all', late-career `N_o'/`n_o_all'"
        mat mcs_`u'`suf' = (`n_cells', `n_cells_cs', `n_y_all', `N_y', `n_o_all', `N_o', ., ., ., .)
        mat colnames mcs_`u'`suf' = n_cells n_cells_cs n_young n_young_cs n_old n_old_cs ps_lo ps_hi ps_share_young ps_share_old

        cap mat drop mbal_`u'`suf'
        local bal_rows
        foreach v of local bal_vars_`u' {
            qui sum `v' if young == 1
            local m_y0 = r(mean)
            local v_y0 = r(Var)
            qui sum `v' if young == 0
            local m_o0 = r(mean)
            local v_o0 = r(Var)
            local sd_pool = sqrt((`v_y0' + `v_o0') / 2)
            if `sd_pool' == 0 continue
            qui sum `v' if young == 1 & cs == 1
            local m_y1 = r(mean)
            qui sum `v' [aw=w_cem] if young == 0 & cs == 1
            local m_o1 = r(mean)
            mat mbal_`u'`suf' = nullmat(mbal_`u'`suf') \ ///
                (`m_y0', `m_o0', (`m_y0' - `m_o0') / `sd_pool', `m_y1', `m_o1', (`m_y1' - `m_o1') / `sd_pool')
            local bal_rows `bal_rows' `v'
        }
        qui levelsof cluster_30, local(clusters)
        local sum_abs0 0
        local sum_abs1 0
        local max_abs0 0
        local max_abs1 0
        local n_cl 0
        foreach c of local clusters {
            cap drop _cl
            gen byte _cl = cluster_30 == `c'
            qui sum _cl if young == 1
            local m_y0 = r(mean)
            local v_y0 = r(Var)
            qui sum _cl if young == 0
            local m_o0 = r(mean)
            local v_o0 = r(Var)
            local sd_pool = sqrt((`v_y0' + `v_o0') / 2)
            if `sd_pool' == 0 continue
            qui sum _cl if young == 1 & cs == 1
            local m_y1 = r(mean)
            qui sum _cl [aw=w_cem] if young == 0 & cs == 1
            local m_o1 = r(mean)
            local a0 = abs((`m_y0' - `m_o0') / `sd_pool')
            local a1 = abs((`m_y1' - `m_o1') / `sd_pool')
            local sum_abs0 = `sum_abs0' + `a0'
            local sum_abs1 = `sum_abs1' + `a1'
            local max_abs0 = max(`max_abs0', `a0')
            local max_abs1 = max(`max_abs1', `a1')
            local ++n_cl
        }
        cap drop _cl
        if `n_cl' > 0 {
            mat mbal_`u'`suf' = mbal_`u'`suf' \ (., ., `sum_abs0' / `n_cl', ., ., `sum_abs1' / `n_cl')
            mat mbal_`u'`suf' = mbal_`u'`suf' \ (., ., `max_abs0', ., ., `max_abs1')
            local bal_rows `bal_rows' topic_mean_abs topic_max_abs
        }
        mat rownames mbal_`u'`suf' = `bal_rows'
        mat colnames mbal_`u'`suf' = mean_early mean_late smd mean_early_cs mean_late_rw smd_rw
        di as result _n "== balance `samp'`suf' [`u']: early minus late, standardized; before | common support with late-career reweighted =="
        matlist mbal_`u'`suf', format(%9.3f) lines(oneline)

        if "`u'" == "nih" {
            cap noi logit young i.cluster_30 c.ln_pre_out c.ln_nihd i.any_award, iterate(100)
            local rc = _rc
            if `rc' di as error "matched_career_comparison `samp'`suf': propensity logit failed (rc=`rc'); overlap figure skipped."
            else {
                predict double ps, pr
                qui sum ps if young == 1
                local ps_y_lo = r(min)
                local ps_y_hi = r(max)
                qui sum ps if young == 0
                local ps_lo = max(`ps_y_lo', r(min))
                local ps_hi = min(`ps_y_hi', r(max))
                qui count if young == 1 & inrange(ps, `ps_lo', `ps_hi')
                local sh_y = r(N) / `n_y_all'
                qui count if young == 0 & inrange(ps, `ps_lo', `ps_hi')
                local sh_o = r(N) / `n_o_all'
                di as text "matched_career_comparison `samp'`suf' [nih]: propensity-score overlap [" %5.3f `ps_lo' ", " %5.3f `ps_hi' ///
                    "] holds " %5.1f 100 * `sh_y' "% of early-career and " %5.1f 100 * `sh_o' "% of late-career PIs"
                mat mcs_`u'`suf'[1, 7]  = `ps_lo'
                mat mcs_`u'`suf'[1, 8]  = `ps_hi'
                mat mcs_`u'`suf'[1, 9]  = `sh_y'
                mat mcs_`u'`suf'[1, 10] = `sh_o'
                cap drop _kx _kd_y _kd_o _kd_c
                gen _kx = (_n - 1) / 199 if _n <= 200
                kdensity ps if young == 1, at(_kx) gen(_kd_y) nograph
                kdensity ps if young == 0, at(_kx) gen(_kd_o) nograph
                gen _kd_c = min(_kd_y, _kd_o)
                tw (rarea _kd_c _kd_y _kx, color(ebblue*0.3) lwidth(none)) ///
                   (rarea _kd_c _kd_o _kx, color(dkorange*0.3) lwidth(none)) ///
                   (line _kd_y _kx, lcolor(ebblue) lwidth(medthick)) ///
                   (line _kd_o _kx, lcolor(dkorange) lwidth(medthick)) ///
                   , xtitle("Estimated probability of being early-career") ytitle("Density") ysc(titlegap($FIG_YTITLEGAP) outergap(0)) ///
                     xlab(0(0.2)1) ///
                     legend(order(3 "${LBL_young}" 4 "${LBL_old}") pos(2) ring(0) rows(2) size(small)) ///
                     plotregion(margin(sides))
                fig_export, path("../output/figures/`samp'/matched/pscore_overlap`suf'.pdf")
                cap drop _kx _kd_y _kd_o _kd_c ps
            }

            preserve
            clear
            local nb = rowsof(mbal_nih`suf')
            local rn : rownames mbal_nih`suf'
            svmat double mbal_nih`suf', names(col)
            gen str32 rowname = ""
            forval i = 1/`nb' {
                replace rowname = "`: word `i' of `rn''" in `i'
            }
            drop if inlist(rowname, "lab_age_2014", "topic_max_abs")
            gen y = _N - _n + 1
            local ylabs
            forval i = 1/`=_N' {
                local rname = rowname[`i']
                local lbl "`rname'"
                if "`rname'" == "pre_ppr_cnt_sum" local lbl "Pre-merger last-author papers"
                if "`rname'" == "pre_cite_sum"    local lbl "Pre-merger citation-weighted output"
                if "`rname'" == "ln_nihd"         local lbl "Log baseline NIH funding"
                if "`rname'" == "any_award"       local lbl "Any baseline NIH research award"
                if "`rname'" == "exposure"        local lbl "Exposure"
                if "`rname'" == "mkt_spend_shr"   local lbl "Treated-market spending share"
                if "`rname'" == "topic_mean_abs"  local lbl "Research topic (mean abs. diff. across clusters)"
                local ylabs `"`ylabs' `=y[`i']' "`lbl'""'
            }
            qui sum smd
            local xmin = min(-0.5, floor(r(min) / 0.25) * 0.25)
            local xmax = max(0.5, ceil(r(max) / 0.25) * 0.25)
            tw scatter y smd, mcolor(dkorange) msymbol(D) msize(small) || ///
               scatter y smd_rw, mcolor(ebblue) msymbol(O) msize(small) ///
               , xline(0, lcolor(gs10) lpattern(solid)) xline(-0.1 0.1, lcolor(gs12) lpattern(dash)) ///
                 ylabel(`ylabs', angle(0) labsize(small) noticks nogrid) ytitle("") ///
                 xtitle("Standardized difference, early minus late career", size(medsmall)) ///
                 xlabel(`xmin'(0.25)`xmax', labsize(small)) ///
                 legend(order(1 "Before matching" 2 "After matching") pos(6) ring(1) rows(1) size(small)) ///
                 ysize(4) xsize(8) yscale(range(0.5 `=_N + 0.5')) ///
                 plotregion(margin(l=zero r=zero b=zero t=vsmall))
            fig_export, path("../output/figures/`samp'/matched/balance`suf'.pdf") xsize(8) ysize(4)
            restore
        }
        keep athr_id cell out_bin fund_bin cs w_cem
        save ../temp/matched_w_`u'_`samp'`suf', replace
    }

    local yvar_list ppr_cnt cite_affl_wt
    if "$DEBUG_YVAR" != "" local yvar_list $DEBUG_YVAR
    local specs all_unm nih_unm nih_cs nih_cem all_cem
    local per_specs all_unm nih_unm nih_cem
    foreach yvar of local yvar_list {
        if "`yvar'" == "nih_total_cost" {
            di as text "matched_career_comparison: `yvar' uses period means elsewhere -- skipped."
            continue
        }
        mat mcar_`yvar'`suf' = J(5, 11, .)
        mat rownames mcar_`yvar'`suf' = `specs'
        mat colnames mcar_`yvar'`suf' = b_young se_young b_old se_old b_diff se_diff p_diff N n_pis_young n_pis_old n_cells
        mat mper_`yvar'`suf' = J(3, 21, .)
        mat rownames mper_`yvar'`suf' = `per_specs'
        mat colnames mper_`yvar'`suf' = b_young1 se_young1 b_old1 se_old1 b_diff1 se_diff1 p_diff1 ///
                                        b_young2 se_young2 b_old2 se_old2 b_diff2 se_diff2 p_diff2 ///
                                        b_gapchg se_gapchg p_gapchg b_young21 se_young21 p_young21 N
        local r 0
        foreach spec of local specs {
            local ++r
            local u = substr("`spec'", 1, 3)
            use ../temp/matched_panel_`samp'`suf', clear
            merge m:1 athr_id using ../temp/matched_w_`u'_`samp'`suf', keep(3) nogen
            local wt ""
            if inlist("`spec'", "nih_cs", "nih_cem", "all_cem") keep if cs == 1
            if inlist("`spec'", "nih_cem", "all_cem") local wt "[pw=w_cem]"
            cap noi ppmlhdfe `yvar' Z_young Z_old S_young S_old PT_young `wt', ///
                absorb(`fes') vce(cluster `vce_cl')
            local rc = _rc
            if `rc' {
                di as error "matched_career_comparison `samp'`suf' `yvar' `spec' pooled ppml failed (rc=`rc'); row left missing."
                continue
            }
            local Nppml = e(N)
            gunique athr_id if e(sample) & young == 1
            local n_y = r(unique)
            gunique athr_id if e(sample) & young == 0
            local n_o = r(unique)
            gunique cell if e(sample)
            local n_cells = r(unique)
            local b_y  = _b[Z_young]
            local se_y = _se[Z_young]
            local b_o  = _b[Z_old]
            local se_o = _se[Z_old]
            qui lincom Z_young - Z_old
            mat mcar_`yvar'`suf'[`r', 1]  = `b_y'
            mat mcar_`yvar'`suf'[`r', 2]  = `se_y'
            mat mcar_`yvar'`suf'[`r', 3]  = `b_o'
            mat mcar_`yvar'`suf'[`r', 4]  = `se_o'
            mat mcar_`yvar'`suf'[`r', 5]  = r(estimate)
            mat mcar_`yvar'`suf'[`r', 6]  = r(se)
            mat mcar_`yvar'`suf'[`r', 7]  = r(p)
            mat mcar_`yvar'`suf'[`r', 8]  = `Nppml'
            mat mcar_`yvar'`suf'[`r', 9]  = `n_y'
            mat mcar_`yvar'`suf'[`r', 10] = `n_o'
            mat mcar_`yvar'`suf'[`r', 11] = `n_cells'
            di as text "matched PPML `samp'`suf' `yvar' `spec': early=" %8.4f `b_y' " (" %6.4f `se_y' ")  late=" %8.4f `b_o' ///
                " (" %6.4f `se_o' ")  diff=" %8.4f r(estimate) " (" %6.4f r(se) ") p=" %6.4f r(p) ///
                "  N=" %9.0f `Nppml' " PIs=`n_y'/`n_o' cells=`n_cells'"

            if strpos(" `per_specs' ", " `spec' ") == 0 continue
            local pr : list posof "`spec'" in per_specs
            cap noi ppmlhdfe `yvar' Z1_young Z1_old Z2_young Z2_old S1_young S1_old S2_young S2_old ///
                PT1_young PT2_young `wt', absorb(`fes') vce(cluster `vce_cl')
            local rc = _rc
            if `rc' {
                di as error "matched_career_comparison `samp'`suf' `yvar' `spec' window ppml failed (rc=`rc'); persistence row left missing."
                continue
            }
            mat mper_`yvar'`suf'[`pr', 21] = e(N)
            foreach k in 1 2 {
                local c0 = cond(`k' == 1, 0, 7)
                mat mper_`yvar'`suf'[`pr', `c0' + 1] = _b[Z`k'_young]
                mat mper_`yvar'`suf'[`pr', `c0' + 2] = _se[Z`k'_young]
                mat mper_`yvar'`suf'[`pr', `c0' + 3] = _b[Z`k'_old]
                mat mper_`yvar'`suf'[`pr', `c0' + 4] = _se[Z`k'_old]
                qui lincom Z`k'_young - Z`k'_old
                mat mper_`yvar'`suf'[`pr', `c0' + 5] = r(estimate)
                mat mper_`yvar'`suf'[`pr', `c0' + 6] = r(se)
                mat mper_`yvar'`suf'[`pr', `c0' + 7] = r(p)
            }
            qui lincom (Z2_young - Z2_old) - (Z1_young - Z1_old)
            mat mper_`yvar'`suf'[`pr', 15] = r(estimate)
            mat mper_`yvar'`suf'[`pr', 16] = r(se)
            mat mper_`yvar'`suf'[`pr', 17] = r(p)
            qui lincom Z2_young - Z1_young
            mat mper_`yvar'`suf'[`pr', 18] = r(estimate)
            mat mper_`yvar'`suf'[`pr', 19] = r(se)
            mat mper_`yvar'`suf'[`pr', 20] = r(p)
            di as text "matched PPML windows `samp'`suf' `yvar' `spec': 2014-16 early=" %8.4f _b[Z1_young] " late=" %8.4f _b[Z1_old] ///
                "  2017-19 early=" %8.4f _b[Z2_young] " late=" %8.4f _b[Z2_old] ///
                "  gap change=" %8.4f mper_`yvar'`suf'[`pr', 15] " (" %6.4f mper_`yvar'`suf'[`pr', 16] ") p=" %6.4f mper_`yvar'`suf'[`pr', 17]
        }

        matched_coefplot, samp(`samp') yvar(`yvar') suf(`suf')
    }
end

program matched_coefplot
    syntax, samp(string) yvar(string) [suf(string)]
    cap confirm matrix mcar_`yvar'`suf'
    if _rc exit 0
    preserve
    clear
    set obs 10
    gen byte row   = ceil(_n / 2)
    gen byte early = mod(_n, 2) == 1
    gen double b  = .
    gen double se = .
    local i 0
    foreach spec in all_unm nih_unm nih_cem {
        local ++i
        local rr = rownumb(mcar_`yvar'`suf', "`spec'")
        qui replace b  = mcar_`yvar'`suf'[`rr', 1] if row == `i' & early == 1
        qui replace se = mcar_`yvar'`suf'[`rr', 2] if row == `i' & early == 1
        qui replace b  = mcar_`yvar'`suf'[`rr', 3] if row == `i' & early == 0
        qui replace se = mcar_`yvar'`suf'[`rr', 4] if row == `i' & early == 0
    }
    local rr = rownumb(mper_`yvar'`suf', "nih_cem")
    foreach k in 1 2 {
        local ++i
        local c0 = cond(`k' == 1, 0, 7)
        qui replace b  = mper_`yvar'`suf'[`rr', `c0' + 1] if row == `i' & early == 1
        qui replace se = mper_`yvar'`suf'[`rr', `c0' + 2] if row == `i' & early == 1
        qui replace b  = mper_`yvar'`suf'[`rr', `c0' + 3] if row == `i' & early == 0
        qui replace se = mper_`yvar'`suf'[`rr', `c0' + 4] if row == `i' & early == 0
    }
    drop if mi(b)
    if _N > 0 {
        gen ub = b + 1.96 * se
        gen lb = b - 1.96 * se
        gen double y = cond(row <= 3, 8 - row, 7.5 - row) + cond(early == 1, 0.15, -0.15)
        local ylabs `"7 "All PIs" 6 "PIs with NIH records" 5 "Matched on topic, pre-merger output, and NIH funding" 3.5 "Matched, 2014-2016" 2.5 "Matched, 2017-2019""'
        qui sum lb
        local xmin = floor(r(min) / 0.5) * 0.5
        qui sum ub
        local xmax = ceil(r(max) / 0.5) * 0.5
        tw rcap ub lb y if early == 1, horizontal lcolor(ebblue%70) msize(vsmall) || ///
           scatter y b if early == 1, mcolor(ebblue) msize(small) || ///
           rcap ub lb y if early == 0, horizontal lcolor(dkorange%70) msize(vsmall) || ///
           scatter y b if early == 0, mcolor(dkorange) msymbol(D) msize(small) ///
           , xline(0, lcolor(gs10) lpattern(solid)) yline(4.25, lcolor(gs12) lpattern(dash)) ///
             ylabel(`ylabs', angle(0) labsize(small) noticks nogrid) ytitle("") ///
             xtitle("Output-cost elasticity", size(medsmall)) xlabel(`xmin'(0.5)`xmax', labsize(small)) ///
             legend(order(2 "${LBL_young}" 4 "${LBL_old}") pos(6) ring(1) rows(1) size(small)) ///
             ysize(4) xsize(8) yscale(range(1.9 7.6)) ///
             plotregion(margin(l=zero r=zero b=zero t=vsmall))
        fig_export, path("../output/figures/`samp'/matched/coefplot_`yvar'`suf'.pdf") xsize(8) ysize(4)
    }
    restore
end

program _mc_fmt, rclass
    args b se
    if mi(`b') | mi(`se') {
        return local b_s "--"
        return local se_s ""
        exit
    }
    local t = abs(`b' / `se')
    local st = cond(`t' >= 2.576, "^{***}", cond(`t' >= 1.960, "^{**}", cond(`t' >= 1.645, "^{*}", "")))
    local b_s  : dis %7.3f `b'
    local se_s : dis %7.3f `se'
    return local b_s  "$`b_s'`st'$"
    return local se_s "($`se_s'$)"
end

program _mc_num, rclass
    args v fmt
    if mi(`v') {
        return local s ""
        exit
    }
    local s : dis `fmt' `v'
    local s = strtrim("`s'")
    return local s "`s'"
end

program write_matched_tex
    syntax, samp(string) yvar(string) [suf(string)]
    cap confirm matrix mcar_`yvar'`suf'
    if _rc exit 0
    local out ../output/tables/`samp'/matched_career_`yvar'`suf'.tex
    local lbl_all_unm "All PIs"
    local lbl_nih_unm "PIs with NIH records"
    local lbl_nih_cs  "\quad Common support on topic $\times$ output $\times$ funding"
    local lbl_nih_cem "\quad Common support, late-career reweighted"
    local lbl_all_cem "All PIs, common support on topic $\times$ output, reweighted"
    local plbl_all_unm "All PIs"
    local plbl_nih_cem "Matched PIs"
    tempname fh
    file open `fh' using "`out'", write replace
    file write `fh' "\begin{table}[htbp]" _n
    file write `fh' "\centering" _n
    file write `fh' "\caption{Career Stage and the Output Response among Comparable PIs}" _n
    file write `fh' "\label{tab:matched_career_`yvar'`suf'}" _n
    file write `fh' "\begin{tabular}{lcccc}" _n
    file write `fh' "\toprule" _n
    file write `fh' " & Early-career PIs & Late-career PIs & Difference & PIs (early / late) \\" _n
    file write `fh' "\midrule" _n
    file write `fh' "\multicolumn{5}{l}{\textit{Panel A: Pooled post-period, 2014--2019}} \\" _n
    foreach spec in all_unm nih_unm nih_cs nih_cem all_cem {
        local rr = rownumb(mcar_`yvar'`suf', "`spec'")
        if mi(mcar_`yvar'`suf'[`rr', 1]) continue
        local line_b  "`lbl_`spec''"
        local line_se ""
        forval j = 1(2)5 {
            _mc_fmt `=mcar_`yvar'`suf'[`rr', `j']' `=mcar_`yvar'`suf'[`rr', `j' + 1]'
            local line_b  "`line_b' & `r(b_s)'"
            local line_se "`line_se' & `r(se_s)'"
        }
        _mc_num `=mcar_`yvar'`suf'[`rr', 9]' %9.0fc
        local n_y "`r(s)'"
        _mc_num `=mcar_`yvar'`suf'[`rr', 10]' %9.0fc
        local n_o "`r(s)'"
        file write `fh' "`line_b' & `n_y' / `n_o' \\" _n
        file write `fh' "`line_se' & \\" _n
    }
    cap confirm matrix mper_`yvar'`suf'
    if !_rc {
        file write `fh' "\addlinespace" _n
        file write `fh' "\multicolumn{5}{l}{\textit{Panel B: Persistence of the career-stage gap}} \\" _n
        foreach spec in all_unm nih_cem {
            local rr = rownumb(mper_`yvar'`suf', "`spec'")
            if mi(mper_`yvar'`suf'[`rr', 1]) continue
            local rc_ = rownumb(mcar_`yvar'`suf', "`spec'")
            _mc_num `=mcar_`yvar'`suf'[`rc_', 9]' %9.0fc
            local n_y "`r(s)'"
            _mc_num `=mcar_`yvar'`suf'[`rc_', 10]' %9.0fc
            local n_o "`r(s)'"
            foreach k in 1 2 {
                local c0 = cond(`k' == 1, 0, 7)
                local win = cond(`k' == 1, "2014--2016", "2017--2019")
                local line_b  "`plbl_`spec'', `win'"
                local line_se ""
                forval j = 1(2)5 {
                    _mc_fmt `=mper_`yvar'`suf'[`rr', `c0' + `j']' `=mper_`yvar'`suf'[`rr', `c0' + `j' + 1]'
                    local line_b  "`line_b' & `r(b_s)'"
                    local line_se "`line_se' & `r(se_s)'"
                }
                file write `fh' "`line_b' & `n_y' / `n_o' \\" _n
                file write `fh' "`line_se' & \\" _n
            }
            _mc_fmt `=mper_`yvar'`suf'[`rr', 15]' `=mper_`yvar'`suf'[`rr', 16]'
            file write `fh' "\quad Change in gap, 2017--19 minus 2014--16 & & & `r(b_s)' & \\" _n
            file write `fh' " & & & `r(se_s)' & \\" _n
            file write `fh' "\addlinespace" _n
        }
    }
    file write `fh' "\bottomrule" _n
    file write `fh' "\end{tabular}" _n
    file write `fh' "\end{table}" _n
    file close `fh'
    di as text "wrote `out'"
end

program write_matched_balance_tex
    syntax, samp(string) [suf(string)]
    cap confirm matrix mbal_nih`suf'
    if _rc exit 0
    local out ../output/tables/`samp'/matched_balance`suf'.tex
    local lbl_lab_age_2014    "Years running lab in 2014"
    local lbl_pre_ppr_cnt_sum "Pre-merger last-author papers, 2010--2013"
    local lbl_pre_cite_sum    "Pre-merger citation-weighted output"
    local lbl_exposure        "Exposure"
    local lbl_mkt_spend_shr   "Treated-market spending share"
    local lbl_ln_nihd         "Log baseline NIH funding (zero if no award)"
    local lbl_any_award       "Any baseline NIH research award"
    local lbl_topic_mean_abs  "Research topic, mean abs.\ std.\ diff.\ across clusters"
    local lbl_topic_max_abs   "Research topic, max abs.\ std.\ diff.\ across clusters"
    local fmt_lab_age_2014    %9.1f
    local fmt_pre_ppr_cnt_sum %9.1f
    local fmt_pre_cite_sum    %9.1f
    local fmt_exposure        %9.3f
    local fmt_mkt_spend_shr   %9.3f
    local fmt_ln_nihd         %9.2f
    local fmt_any_award       %9.2f
    tempname fh
    file open `fh' using "`out'", write replace
    file write `fh' "\begin{table}[htbp]" _n
    file write `fh' "\centering" _n
    file write `fh' "\caption{Covariate Balance: Early- versus Late-Career PIs with NIH Records}" _n
    file write `fh' "\label{tab:matched_balance`suf'}" _n
    file write `fh' "\begin{tabular}{lcccccc}" _n
    file write `fh' "\toprule" _n
    file write `fh' " & \multicolumn{3}{c}{All PIs with NIH records} & \multicolumn{3}{c}{Common support, late-career reweighted} \\" _n
    file write `fh' "\cmidrule(lr){2-4} \cmidrule(lr){5-7}" _n
    file write `fh' " & Early & Late & Std.\ diff. & Early & Late & Std.\ diff. \\" _n
    file write `fh' "\midrule" _n
    local rn : rownames mbal_nih`suf'
    local nb = rowsof(mbal_nih`suf')
    forval i = 1/`nb' {
        local v : word `i' of `rn'
        local lbl "`lbl_`v''"
        if "`lbl'" == "" local lbl "`v'"
        local f "`fmt_`v''"
        if "`f'" == "" local f %9.3f
        local line "`lbl'"
        forval j = 1/6 {
            local cf = cond(inlist(`j', 3, 6), "%9.3f", "`f'")
            _mc_num `=mbal_nih`suf'[`i', `j']' `cf'
            local line "`line' & `r(s)'"
        }
        file write `fh' "`line' \\" _n
    }
    cap confirm matrix mcs_nih`suf'
    if !_rc {
        file write `fh' "\midrule" _n
        _mc_num `=mcs_nih`suf'[1, 3]' %9.0fc
        local a "`r(s)'"
        _mc_num `=mcs_nih`suf'[1, 5]' %9.0fc
        local b "`r(s)'"
        _mc_num `=mcs_nih`suf'[1, 4]' %9.0fc
        local c "`r(s)'"
        _mc_num `=mcs_nih`suf'[1, 6]' %9.0fc
        local d "`r(s)'"
        file write `fh' "PIs & `a' & `b' & & `c' & `d' & \\" _n
        _mc_num `=mcs_nih`suf'[1, 1]' %9.0fc
        local a "`r(s)'"
        _mc_num `=mcs_nih`suf'[1, 2]' %9.0fc
        local b "`r(s)'"
        file write `fh' "Matching cells (topic $\times$ pre-merger output $\times$ NIH funding) & \multicolumn{3}{c}{`a'} & \multicolumn{3}{c}{`b' with both career stages} \\" _n
    }
    file write `fh' "\bottomrule" _n
    file write `fh' "\end{tabular}" _n
    file write `fh' "\end{table}" _n
    file close `fh'
    di as text "wrote `out'"
end

program output_matched_tables
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0)]
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'
    foreach m in mcs_nih mcs_all mbal_nih mbal_all {
        cap confirm matrix `m'`suf'
        if _rc continue
        qui matrix_to_txt, saving("../output/tables/`samp'/matched_`m'`suf'.txt") ///
            matrix(`m'`suf') title(<tab:matched_`m'`suf'>) format(%20.4f) replace
    }
    local yvar_list ppr_cnt cite_affl_wt
    if "$DEBUG_YVAR" != "" local yvar_list $DEBUG_YVAR
    foreach yvar of local yvar_list {
        foreach m in mcar mper {
            cap confirm matrix `m'_`yvar'`suf'
            if _rc continue
            qui matrix_to_txt, saving("../output/tables/`samp'/matched_`m'_`yvar'`suf'.txt") ///
                matrix(`m'_`yvar'`suf') title(<tab:matched_`m'_`yvar'`suf'>) format(%20.4f) replace
        }
        write_matched_tex, samp(`samp') yvar(`yvar') suf(`suf')
    }
    write_matched_balance_tex, samp(`samp') suf(`suf')
end

main
