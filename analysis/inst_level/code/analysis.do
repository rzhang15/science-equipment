set more off
clear all
capture log close
program drop _all
version 16.1
set scheme modern
set linesize 200
set maxvar 20000

* ============================================================================
* Institution-level heterogeneity in the 2014 procurement shock.
*
* PI i sits in institution j(i); institution LEVELS are collinear with the
* author FE (no movers), so only post-2014 objects are identified.
*
*   SPEC 1  E[Y_it] = exp(a_i + d_t + b*Z_it + g*Zs_it + pi_j * Post_t)
*   SPEC 2  E[Y_it] = exp(a_i + d_t + b*Z_it + g*Zs_it + pi_j * Post_t
*                         + beta_j * Z_it)
*
* Z_it = exposure x Post, Zs_it = mkt_spend_shr x Post (pooled control).
* pi_j   = institution-specific post shift at zero exposure.
* beta_j = institution-specific exposure slope; spec 2's response line is
*          Delta_j(E) = pi_j + beta_j * E, so pi_j stays in spec 2 to stop
*          beta_j from absorbing level shifts.
*
* Only relative effects are identified (sum_j PD_j = Post is absorbed by the
* year FE; sum_j PX_j = Z_it), so one institution is omitted. inst_ord is
* built so level 1 IS the median institution by pre-2014 research output, and
* the PD_/PX_ dummies simply skip level 1 -- so every pi_j / beta_j reads as
* a deviation from the median-output institution, b[Z_it] is that
* institution's own slope, and slope_j = b + beta_j is institution j's
* exposure response in levels.
*
* The dummies are built by hand rather than as i.inst_ord#i.post: factor
* expansion puts the base at the single (inst 1, post 0) CELL, keeps a term
* for every post level, and the author FE then makes the post==1 branch
* collinear -- ppmlhdfe estimates the PRE dummies and omits every post shift.
* ============================================================================

global YVAR    ppr_cnt
global SAMPLE  es_all_jrnls_r1_r2
global MIN_PI  10
* 1 = reuse ../temp/panel.dta + inst_xw.dta from a previous run instead of
* rebuilding them. Only valid while prep_panel is unchanged.
global REUSE_PANEL 1
* `do analysis.do figures' redraws the figures from saved estimates only.
global FIGURES_ONLY 0
if "`1'" == "figures" global FIGURES_ONLY 1

program main
    cap mkdir ../output
    cap mkdir ../output/tables
    cap mkdir ../output/figures
    cap mkdir ../temp

    * `do analysis.do figures' replots from ../temp/inst_effects_all.dta
    * without re-estimating, and writes its own log so the estimation log
    * survives.
    if "$FIGURES_ONLY" == "1" {
        log using ../output/replot.log, replace text
        di as text "FIGURES_ONLY: replotting from ../temp/inst_effects_all.dta"
        use ../temp/inst_effects_all.dta, clear
        figures
        log close
        exit
    }

    log using ../output/inst_level.log, replace text
    if "$REUSE_PANEL" == "1" load_panel_meta
    else                     prep_panel
    estimate_spec, spec(1)
    estimate_spec, spec(2)
    report
    output_tables

    log close
end

* ---------------------------------------------------------------- panel prep
program load_panel_meta
    confirm file ../temp/panel.dta
    use ../temp/inst_xw.dta, clear
    sort inst_ord
    qui count
    global N_INST = r(N)
    di as text "reusing ../temp/panel.dta: $N_INST institutions" ///
        ", reference (inst_ord 1) = " inst_base[1] ", n_pi = " n_pi[1]
end

program prep_panel
    use ../external/prepped_samples/${SAMPLE}.dta, clear

    preserve
        contract athr_id inst_id
        egen byte _t = tag(athr_id)
        bys athr_id: gen k = _N
        qui count if _t & k > 1
        di as text "movers (PIs with >1 inst_id): " r(N)
    restore

    preserve
        gen byte pre = year < 2014
        contract athr_id inst_id pre
        gsort athr_id -pre -_freq inst_id
        by athr_id: keep if _n == 1
        rename inst_id inst_base
        keep athr_id inst_base
        save ../temp/inst_base.dta, replace
    restore
    merge m:1 athr_id using ../temp/inst_base.dta, nogen

    gen byte   post       = year >= 2014
    gen double Z_it       = exposure      * post
    gen double Z_share_it = mkt_spend_shr * post

    egen byte _tagA = tag(inst_base athr_id)
    bys inst_base: egen n_pi = total(_tagA)
    bys inst_base: egen double _sx = total(cond(_tagA, exposure, 0))
    gen double mean_exp = _sx / n_pi
    drop _tagA _sx
    bys inst_base: egen double pre_out = total(cond(year < 2014, $YVAR, 0))

    qui count
    di as text "input panel: N = " r(N)

    * inst_ord: median-output institution first, then the rest by ascending
    * pre-2014 output. Level 1 is the omitted reference.
    preserve
        keep inst_base n_pi pre_out mean_exp
        duplicates drop inst_base, force
        gen byte elig = n_pi >= $MIN_PI
        qui count if elig
        local n_elig = r(N)
        sort pre_out inst_base
        gen long r_elig = sum(elig) if elig
        local med = ceil(`n_elig'/2)
        gen byte is_med = (r_elig == `med') & elig == 1
        replace is_med = 0 if mi(is_med)
        gsort -is_med pre_out inst_base
        gen long inst_ord = _n
        qui count
        global N_INST = r(N)
        di as text "institutions: $N_INST total, `n_elig' with n_pi >= $MIN_PI"
        di as text "reference institution (inst_ord 1): " inst_base[1] ///
            ", rank `med' of `n_elig' by pre-2014 output = " %9.0f pre_out[1] ///
            ", n_pi = " n_pi[1]
        drop elig r_elig is_med
        order inst_ord inst_base
        sort inst_ord
        save ../temp/inst_xw.dta, replace
    restore

    merge m:1 inst_base using ../temp/inst_xw.dta, keepusing(inst_ord) nogen
    save ../temp/panel.dta, replace
end

* ------------------------------------------------------------------ estimate
program estimate_spec
    syntax, spec(int)
    use ../temp/panel.dta, clear

    forval j = 2/$N_INST {
        qui gen byte PD_`j' = (inst_ord == `j') * post
        if `spec' == 2 qui gen double PX_`j' = (inst_ord == `j') * Z_it
    }
    local rhs Z_it Z_share_it PD_*
    if `spec' == 2 local rhs `rhs' PX_*

    di as text _n "===== SPEC `spec': ppmlhdfe $YVAR `rhs', absorb(athr_id year) ====="
    ppmlhdfe $YVAR `rhs', absorb(athr_id year) vce(cluster athr_id)
    estimates save ../temp/est_spec`spec'.ster, replace

    local b_x   = _b[Z_it]
    local se_x  = _se[Z_it]
    local b_s   = _b[Z_share_it]
    local se_s  = _se[Z_share_it]
    local N     = e(N)
    local r2    = e(r2_p)

    qui testparm PD_*
    local chi_d = r(chi2)
    local df_d  = r(df)
    local p_d   = r(p)
    di as text "joint test pi_j = 0: chi2(`df_d') = " %9.2f `chi_d' "  p = " %6.4f `p_d'

    local chi_x = .
    local df_x  = .
    local p_x   = .
    if `spec' == 2 {
        qui testparm PX_*
        local chi_x = r(chi2)
        local df_x  = r(df)
        local p_x   = r(p)
        di as text "joint test beta_j = 0: chi2(`df_x') = " %9.2f `chi_x' "  p = " %6.4f `p_x'
    }

    gen byte smp = e(sample)
    preserve
        keep if smp
        egen byte _t = tag(inst_ord athr_id)
        bys inst_ord: egen n_pi_es = total(_t)
        bys inst_ord: gen N_es = _N
        keep inst_ord n_pi_es N_es
        duplicates drop inst_ord, force
        qui count
        di as text "institutions in e(sample): " r(N) " of $N_INST"
        save ../temp/aux_es`spec'.dta, replace
    restore

    * Institutions dropped by ppmlhdfe come back either absent from e(b) or
    * as an exact 0 with se 0; the se > 0 screen in report() separates those
    * from real estimates. inst_ord 1 is the reference, hence a structural 0.
    tempname pf
    postfile `pf' int inst_ord double pi_j double se_pi double beta_j double se_beta ///
        double slope double se_slope byte base using ../temp/inst_spec`spec'.dta, replace
    local n_miss = 0
    forval j = 1/$N_INST {
        local pi = .
        local sp = .
        local bt = .
        local sb = .
        local sl = .
        local ss = .
        local bs = (`j' == 1)
        if `bs' {
            local pi = 0
            local sp = 0
            local bt = 0
            local sb = 0
            local sl = `b_x'
            local ss = `se_x'
        }
        else {
            cap local pi = _b[PD_`j']
            if !_rc local sp = _se[PD_`j']
            else    local ++n_miss
            if `spec' == 2 {
                cap local bt = _b[PX_`j']
                if !_rc {
                    local sb = _se[PX_`j']
                    qui lincom Z_it + PX_`j'
                    local sl = r(estimate)
                    local ss = r(se)
                }
            }
        }
        post `pf' (`j') (`pi') (`sp') (`bt') (`sb') (`sl') (`ss') (`bs')
    }
    postclose `pf'
    di as text "institution terms absent from e(b): `n_miss' of $N_INST"

    cap mat drop pooled`spec'
    mat pooled`spec' = J(12,1,.)
    mat pooled`spec'[1,1]  = `b_x'
    mat pooled`spec'[2,1]  = `se_x'
    mat pooled`spec'[3,1]  = `b_s'
    mat pooled`spec'[4,1]  = `se_s'
    mat pooled`spec'[5,1]  = `chi_d'
    mat pooled`spec'[6,1]  = `df_d'
    mat pooled`spec'[7,1]  = `p_d'
    mat pooled`spec'[8,1]  = `chi_x'
    mat pooled`spec'[9,1]  = `df_x'
    mat pooled`spec'[10,1] = `p_x'
    mat pooled`spec'[11,1] = `N'
    mat pooled`spec'[12,1] = `r2'
    mat rownames pooled`spec' = b_exp se_exp b_share se_share ///
        chi2_pi df_pi p_pi chi2_beta df_beta p_beta N pseudo_r2
    mat colnames pooled`spec' = spec`spec'
end

* -------------------------------------------------------------------- report
program report
    use ../temp/inst_spec1.dta, clear
    rename (pi_j se_pi) (pi1 se_pi1)
    drop beta_j se_beta slope se_slope
    merge 1:1 inst_ord using ../temp/inst_spec2.dta, nogen
    merge 1:1 inst_ord using ../temp/inst_xw.dta, keep(1 3) nogen
    merge 1:1 inst_ord using ../temp/aux_es2.dta, keep(1 3) nogen

    preserve
        import delimited ../external/college/ipeds_openalex.csv, clear varn(1) stringcols(_all)
        keep inst_id name
        drop if inst_id == ""
        duplicates drop inst_id, force
        rename inst_id inst_base
        save ../temp/inst_names.dta, replace
    restore
    merge m:1 inst_base using ../temp/inst_names.dta, keep(1 3) nogen

    * base is the reference (structural 0), so it is excluded from the
    * dispersion stats and the plots but kept in the exported table.
    gen byte report = !mi(n_pi_es) & n_pi_es >= $MIN_PI & !base ///
        & se_pi1 > 0 & !mi(se_pi1)
    qui count if report
    di as text _n "===== institutions reported: " r(N) " of $N_INST ====="

    label var pi1    "Post x Inst (spec 1)"
    label var pi_j   "Post x Inst (spec 2)"
    label var beta_j "Post x Exposure x Inst (spec 2)"
    label var slope  "Institution exposure slope (level)"

    di as text _n "===== dispersion of institution effects ====="
    sum pi1 pi_j beta_j slope if report, d

    cap noi corr pi1 pi_j if report
    cap noi corr pi_j beta_j if report

    gen double pi1_lo    = pi1    - 1.96 * se_pi1
    gen double pi1_hi    = pi1    + 1.96 * se_pi1
    gen double pi2_lo    = pi_j   - 1.96 * se_pi
    gen double pi2_hi    = pi_j   + 1.96 * se_pi
    gen double beta_j_lo = beta_j - 1.96 * se_beta
    gen double beta_j_hi = beta_j + 1.96 * se_beta

    save ../temp/inst_effects_all.dta, replace
    figures

    order inst_ord inst_base name n_pi n_pi_es N_es mean_exp pre_out ///
        pi1 se_pi1 pi_j se_pi beta_j se_beta slope se_slope base report
    sort inst_ord
    save ../output/inst_effects.dta, replace
    export delimited using ../output/tables/inst_effects.csv if report | base, replace
end

program figures
    * Common x span for the caterpillars = the largest number of institution
    * effects any one of them plots, so the three are read on the same axis.
    global XMAX = 0
    foreach p in pi1 pi_j beta_j {
        local s = cond("`p'" == "pi1", "se_pi1", cond("`p'" == "pi_j", "se_pi", "se_beta"))
        qui count if report & !mi(`p') & `s' > 0 & !mi(`s')
        if r(N) > $XMAX global XMAX = r(N)
    }
    di as text "caterpillar x span = 1/$XMAX institution effects"

    * Ticks must stop at XMAX: xlab(#10) picks a round tick past it and the
    * axis then stretches to cover the label, which is where the trailing
    * white space came from.
    global XLAB 1
    forval t = 20(20)$XMAX {
        if ($XMAX - `t') > 8 global XLAB $XLAB `t'
    }
    global XLAB $XLAB $XMAX

    * --- caterpillars: coefficient on y, institutions ranked by it on x
    caterpillar, y(pi1) lo(pi1_lo) hi(pi1_hi) se(se_pi1) ///
        ytitle("Post x Institution") name(caterpillar_pi_spec1)
    caterpillar, y(pi_j) lo(pi2_lo) hi(pi2_hi) se(se_pi) ///
        ytitle("Post x Institution") name(caterpillar_pi_spec2)
    caterpillar, y(beta_j) lo(beta_j_lo) hi(beta_j_hi) se(se_beta) ///
        ytitle("Post x Exposure x Institution") name(caterpillar_beta_spec2)

    * --- both specs on one panel, each ranked by its own magnitude
    preserve
        keep if report
        sort pi1
        gen long rank1 = _n if !mi(pi1)
        sort pi_j
        gen long rank2 = _n if !mi(pi_j)
        tw (scatter pi1  rank1, mcolor(ebblue)   msize(vsmall)) ///
           (scatter pi_j rank2, mcolor(dkorange) msize(vsmall) msymbol(T)) ///
           , yline(0, lcolor(red) lpattern(dash)) ///
             xscale(range(1 $XMAX) noextend) xlab($XLAB) ///
             plotregion(margin(l = 1 r = 1)) ///
             xtitle("Institution (ranked within specification)") ///
             ytitle("Post x Institution") ///
             legend(order(1 "Spec 1: Post x Inst" 2 "Spec 2: + Post x Exposure x Inst") ///
                    pos(11) ring(0) size(medsmall))
        graph export ../output/figures/pi_both_specs_sorted.pdf, replace
    restore

    preserve
        * beta_j dropped for collinearity comes back as an exact 0; it would
        * anchor the fit at the origin, so screen it out here too.
        keep if report & se_beta > 0 & !mi(se_beta)
        qui regress beta_j pi_j
        local fsl : di %7.3f _b[pi_j]
        local fse : di %7.3f _se[pi_j]
        local fn  = e(N)
        qui corr beta_j pi_j
        local frho : di %6.3f r(rho)
        di as text "pi_j vs beta_j: slope = `fsl' (se `fse'), corr = `frho', N = `fn'"
        tw (scatter beta_j pi_j, mcolor(ebblue) msize(small)) ///
           (lfit beta_j pi_j, lcolor(gs9)) ///
           , xtitle("Post x Institution") ///
             ytitle("Post x Exposure x Institution") legend(off) ///
             note("Slope = `=trim("`fsl'")' (se `=trim("`fse'")');" ///
                  " correlation = `=trim("`frho'")'; N = `fn'")
        graph export ../output/figures/pi_vs_beta.pdf, replace
    restore
end

program caterpillar
    syntax, y(name) lo(name) hi(name) se(name) ytitle(string) name(string)
    preserve
        keep if report & !mi(`y') & `se' > 0 & !mi(`se')
        qui count
        if r(N) < 2 {
            di as text "caterpillar `name': " r(N) " institutions; skipping."
            exit 0
        }
        sort `y'
        gen long rank = _n
        tw (rcap `lo' `hi' rank, lcolor(gs11) lwidth(vthin)) ///
           (scatter `y' rank, mcolor(ebblue) msize(vsmall)) ///
           , yline(0, lcolor(red) lpattern(dash)) ///
             xscale(range(1 $XMAX) noextend) xlab($XLAB) ///
             plotregion(margin(l = 1 r = 1)) ///
             xtitle("Institution (ranked by coefficient)") ytitle("`ytitle'") ///
             legend(off)
        graph export ../output/figures/`name'.pdf, replace
    restore
end

program output_tables
    foreach s in 1 2 {
        cap confirm matrix pooled`s'
        if !_rc {
            qui matrix_to_txt, saving("../output/tables/pooled_spec`s'.txt") ///
                matrix(pooled`s') title(<tab:pooled_spec`s'>) format(%20.4f) replace
        }
    }
end

main
