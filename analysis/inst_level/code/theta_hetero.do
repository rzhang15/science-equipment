set more off
clear all
capture log close
program drop _all
version 16.1
set scheme modern
set linesize 200
set maxvar 20000

* ============================================================================
* What explains institution-specific exposure responses.
*
* Takes the SPEC 2 estimates from analysis.do as given -- no PPML is run here.
* Spec 2 is
*   E[Y_it] = exp(a_i + d_t + b*Z_it + g*Zs_it + pi_j*Post_t + beta_j*Z_it)
* so beta_j is institution j's exposure slope net of its own post-2014 level
* shift pi_j. Carrying pi_j is what makes beta_j interpretable: without it,
* beta_j would also absorb any institution that simply lost output after 2014.
*
* beta_inst = beta_j, se_inst = se_beta, both read from
* ../output/inst_effects.dta. inst_ord 1 is the omitted reference, so
* beta_inst is a deviation from the median-output institution. The level
* slope b + beta_j is also on file; every second-stage delta below is
* identical on either scale (they differ by the constant b) -- only the
* intercept moves -- but the weights are not, and the plan specifies
* 1/se_inst^2 on beta_inst.
*
* STEP 4  beta_inst = Z'delta + e, inverse-variance weighted OLS, Z the 31
*         standardized characteristics. Exhibit: all 31 coefficients.
* STEP 5  Elastic net on the same y and Z, alpha and lambda by CV. Exhibit:
*         selected variables and signs, plus CV curve and coefficient path.
* STEP 6  Random forest on the same y and Z, via rf_theta.py -- tuned by
*         5-fold CV, honest OOS R2/RMSE from an outer fold, SHAP values.
*         Neither rforest nor pystacked is installed and Stata has no forest.
*
* Steps 4-6 share ONE complete-case sample so the three answers compare.
* ============================================================================

global SAMPLE    es_all_jrnls_r1_r2
global MIN_PI    10
global COV_FLOOR 0.75
global RSEED     90210

program main
    cap mkdir ../output
    cap mkdir ../output/tables
    cap mkdir ../output/figures
    cap mkdir ../temp
    log using ../output/theta_hetero.log, replace text

    load_effects
    build_chars
    make_sample
    step4_wls
    step5_enet
    step6_rf
    output_tables

    log close
end

* ====================================================== spec 2 estimates in
program load_effects
    confirm file ../output/inst_effects.dta
    use ../output/inst_effects.dta, clear
    keep inst_ord inst_base name n_pi n_pi_es N_es mean_exp pre_out ///
        pi_j se_pi beta_j se_beta slope se_slope base report
    rename (beta_j se_beta) (beta_inst se_inst)

    * base's 0 is structural and ppmlhdfe returns collinear-dropped terms as an
    * exact 0 with se 0; both are excluded.
    keep if report & !base & !mi(beta_inst) & se_inst > 0 & !mi(se_inst)
    qui count
    global NJ = r(N)
    di as text _n "===== spec 2 beta_j read from analysis.do: $NJ institutions ====="

    gen double w_prec = 1 / se_inst^2
    qui sum beta_inst, d
    di as text "beta_inst: mean " %8.4f r(mean) "  sd " %8.4f r(sd) ///
        "  p10 " %8.4f r(p10) "  p50 " %8.4f r(p50) "  p90 " %8.4f r(p90)
    qui sum beta_inst [aw = w_prec]
    di as text "precision-weighted mean beta_inst = " %9.4f r(mean)
    qui sum se_inst, d
    di as text "se_inst:   p10 " %8.4f r(p10) "  p50 " %8.4f r(p50) ///
        "  p90 " %8.4f r(p90)
    save ../temp/beta_inst.dta, replace
end

* =========================================================== characteristics
* 31 characteristics in five concept groups. Levels are logged, composition
* enters as shares so scale is not counted twice. HERD carries no direct
* procurement or overhead measure -- contract / subrecipient funding is the
* closest proxy and is labelled as such. Health-sciences and medical-school
* fields are on file but sit below the coverage floor, so they are excluded
* by construction rather than dropped later.
program char_groups
    global G1 ln_endowment ln_tot_fund shr_fed_fund shr_state_fund ///
              shr_inst_fund shr_bus_fund shr_nonprof_fund
    global G2 ln_ls_fund shr_ls_fund shr_bio_in_ls shr_fed_in_ls shr_hhs_in_bio
    global G3 ln_contracts_fund shr_contracts_fund shr_grants_fund shr_subrec_fund
    global G4 ln_basic_expend shr_basic_expend shr_applied_expend ///
              shr_fed_basic shr_fed_applied ln_dev_expend ln_ls_cap_expend shr_ls_cap
    global G5 ln_n_pi ln_pre_out mean_exp sd_exp public r1 ln_msa_size

    global GLBL1 "Financial resources"
    global GLBL2 "Life-science research intensity"
    global GLBL3 "Procurement and contracting"
    global GLBL4 "Expenditure composition"
    global GLBL5 "Scale, governance, geography"

    global VL_ln_endowment       "Log endowment"
    global VL_ln_tot_fund        "Log total R&D funding"
    global VL_shr_fed_fund       "Federal share of funding"
    global VL_shr_state_fund     "State/local share of funding"
    global VL_shr_inst_fund      "Institutional share of funding"
    global VL_shr_bus_fund       "Business share of funding"
    global VL_shr_nonprof_fund   "Nonprofit share of funding"
    global VL_ln_ls_fund         "Log life-science funding"
    global VL_shr_ls_fund        "Life-science share of funding"
    global VL_shr_bio_in_ls      "Biology share of life science"
    global VL_shr_fed_in_ls      "Federal share of life science"
    global VL_shr_hhs_in_bio     "HHS share of biology"
    global VL_ln_contracts_fund  "Log contract funding"
    global VL_shr_contracts_fund "Contract share of funding"
    global VL_shr_grants_fund    "Grant share of funding"
    global VL_shr_subrec_fund    "Subrecipient share of funding"
    global VL_ln_basic_expend    "Log basic-research expenditure"
    global VL_shr_basic_expend   "Basic share of R&D expenditure"
    global VL_shr_applied_expend "Applied share of R&D expenditure"
    global VL_shr_fed_basic      "Federal share of basic expenditure"
    global VL_shr_fed_applied    "Federal share of applied expenditure"
    global VL_ln_dev_expend      "Log development expenditure"
    global VL_ln_ls_cap_expend   "Log life-science capital expenditure"
    global VL_shr_ls_cap         "Capital intensity of life science"
    global VL_ln_n_pi            "Log number of PIs"
    global VL_ln_pre_out         "Log pre-2014 publication output"
    global VL_mean_exp           "Mean PI exposure"
    global VL_sd_exp             "SD of PI exposure"
    global VL_public             "Public institution"
    global VL_r1                 "R1 Carnegie classification"
    global VL_ln_msa_size        "Log MSA research size"
end

program build_chars
    preserve
        import delimited ../external/college/ipeds_openalex.csv, clear varn(1) stringcols(_all)
        keep ipeds_id inst_id
        destring ipeds_id, replace force
        drop if mi(ipeds_id) | inst_id == ""
        duplicates drop inst_id, force
        rename inst_id inst_base
        save ../temp/ipeds_xw.dta, replace
    restore

    ensure_panel
    use inst_base athr_id exposure public type msa_size using ../temp/panel.dta, clear
    egen byte _t = tag(inst_base athr_id)
    keep if _t
    gen byte r1 = (type == "r1")
    collapse (mean) public r1 msa_size (sd) sd_exp = exposure, by(inst_base)
    replace public = round(public)
    replace r1     = round(r1)
    gen double ln_msa_size = ln(msa_size) if msa_size > 0 & !mi(msa_size)
    drop msa_size
    save ../temp/chars_panel.dta, replace

    use ../external/inst_chars/combined_pre, clear
    duplicates drop ipeds_id, force
    merge 1:1 ipeds_id using ../temp/ipeds_xw.dta, keep(3) nogen
    merge 1:1 inst_base using ../temp/chars_panel.dta, keep(2 3) nogen

    gen double shr_fed_fund       = tot_fed_fund      / tot_fund
    gen double shr_state_fund     = tot_state_fund    / tot_fund
    gen double shr_inst_fund      = tot_inst_fund     / tot_fund
    gen double shr_bus_fund       = tot_bus_fund      / tot_fund
    gen double shr_nonprof_fund   = tot_nonprof_fund  / tot_fund
    gen double shr_ls_fund        = ls_fund           / tot_fund
    gen double shr_contracts_fund = contracts_fund    / tot_fund
    gen double shr_grants_fund    = grants_fund       / tot_fund
    gen double shr_subrec_fund    = subrecipient_fund / tot_fund
    gen double shr_bio_in_ls      = bio_fund          / ls_fund
    gen double shr_fed_in_ls      = fed_ls_fund       / ls_fund
    gen double shr_hhs_in_bio     = hhs_ls_bio_fund   / bio_fund
    gen double shr_ls_cap         = ls_cap_expend     / ls_fund
    gen double shr_fed_basic      = basic_fed_expend  / basic_expend
    gen double shr_fed_applied    = applied_fed_expend/ applied_expend
    gen double _rd = basic_expend + applied_expend + dev_expend
    gen double shr_basic_expend   = basic_expend   / _rd if _rd > 0
    gen double shr_applied_expend = applied_expend / _rd if _rd > 0
    drop _rd

    foreach v in endowment tot_fund ls_fund contracts_fund basic_expend ///
                 dev_expend ls_cap_expend {
        gen double ln_`v' = ln(`v') if `v' > 0 & !mi(`v')
    }

    keep inst_base ln_* shr_* public r1 sd_exp
    drop if inst_base == ""
    duplicates drop inst_base, force
    save ../temp/chars_wide.dta, replace
end

* panel.dta is analysis.do's; rebuild it only if make.py wiped ../temp and
* analysis.do ran with REUSE_PANEL, in which case inst_base has to be
* reconstructed the same way (modal pre-2014 institution per PI).
program ensure_panel
    cap confirm file ../temp/panel.dta
    if _rc == 0 exit 0
    di as text "../temp/panel.dta absent -- rebuilding from ${SAMPLE}"
    use ../external/prepped_samples/${SAMPLE}.dta, clear
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
    save ../temp/panel.dta, replace
end

* ============================================ common sample + standardization
program make_sample
    char_groups
    use ../temp/beta_inst.dta, clear
    merge 1:1 inst_base using ../temp/chars_wide.dta, keep(1 3) nogen

    gen double ln_n_pi    = ln(n_pi_es)
    gen double ln_pre_out = ln(pre_out) if pre_out > 0

    di as text _n "===== characteristic coverage on $NJ institutions (floor $COV_FLOOR) ====="
    local keepv ""
    local dropv ""
    forval g = 1/5 {
        local gk`g' ""
        foreach v of global G`g' {
            cap confirm variable `v'
            if _rc {
                di as text "  `v': ABSENT"
                local dropv `dropv' `v'
                continue
            }
            qui count if !mi(`v')
            local cov = r(N) / $NJ
            if `cov' >= $COV_FLOOR {
                local keepv `keepv' `v'
                local gk`g' `gk`g'' `v'
                di as text "  `v': " %5.3f `cov'
            }
            else {
                local dropv `dropv' `v'
                di as text "  `v': " %5.3f `cov' "  DROPPED (below floor)"
            }
        }
        global K`g' `gk`g''
    }
    di as text _n "retained (" wordcount("`keepv'") "): `keepv'"
    di as text _n "dropped  (" wordcount("`dropv'") "): `dropv'"

    gen byte csample = 1
    foreach v of local keepv {
        qui replace csample = 0 if mi(`v')
    }
    qui replace csample = 0 if mi(beta_inst) | mi(w_prec)
    qui count if csample
    global NC = r(N)
    di as text _n "===== common sample for steps 4-6: $NC institutions, " ///
        wordcount("`keepv'") " characteristics ====="
    if $NC < 60 di as error "WARNING: thin common sample; read steps 5-6 ordinally."

    local zv ""
    forval g = 1/5 {
        local gz`g' ""
        foreach v of global K`g' {
            qui sum `v' if csample
            if r(sd) == 0 | mi(r(sd)) {
                di as text "  `v': zero variance on the common sample; dropped"
                continue
            }
            qui gen double z_`v' = (`v' - r(mean)) / r(sd) if csample
            local zv `zv' z_`v'
            local gz`g' `gz`g'' z_`v'
        }
        global Z`g' `gz`g''
    }
    global ZALL `zv'
    global NZ = wordcount("$ZALL")
    di as text "standardized characteristics entering steps 4-6: $NZ"

    keep if csample
    save ../temp/step_sample.dta, replace
    export delimited inst_base name beta_inst se_inst w_prec $ZALL ///
        using ../temp/theta_chars.csv, replace
end

* ============================================================ step 4 -- WLS
program step4_wls
    char_groups
    use ../temp/step_sample.dta, clear

    di as text _n "===== STEP 4: inverse-variance weighted OLS, w = 1/se_inst^2 ====="
    regress beta_inst $ZALL [aweight = w_prec], robust
    estimates store wls
    global WLS_R2 = e(r2)
    global WLS_N  = e(N)
    di as text "R2 = " %6.4f e(r2) ", adj R2 = " %6.4f e(r2_a) ", N = " e(N)
    qui testparm $ZALL
    di as text "joint F(" r(df) ", " r(df_r) ") = " %8.3f r(F) "  p = " %6.4f r(p)
    global WLS_F  = r(F)
    global WLS_FP = r(p)

    mat WLS = J($NZ, 4, .)
    mat colnames WLS = coef se t pval
    local rn ""
    tempname pf
    postfile `pf' str32 vname str48 vlbl str40 grp int gnum ///
        double b double se double lo double hi using ../temp/ex4_coefs.dta, replace
    local i = 0
    forval g = 1/5 {
        foreach v of global Z`g' {
            local ++i
            local vn = subinstr("`v'", "z_", "", 1)
            local lb "${VL_`vn'}"
            if "`lb'" == "" local lb "`vn'"
            local bb = _b[`v']
            local ss = _se[`v']
            local tt = `bb' / `ss'
            local pp = 2 * ttail(e(df_r), abs(`tt'))
            mat WLS[`i', 1] = `bb'
            mat WLS[`i', 2] = `ss'
            mat WLS[`i', 3] = `tt'
            mat WLS[`i', 4] = `pp'
            local rn `rn' `vn'
            post `pf' ("`vn'") ("`lb'") ("${GLBL`g'}") (`g') (`bb') (`ss') ///
                (`bb' - 1.96 * `ss') (`bb' + 1.96 * `ss')
        }
    }
    postclose `pf'
    mat rownames WLS = `rn'

    coefplot_grouped, using(../temp/ex4_coefs.dta) name(ex4_wls_coefs) ///
        xtitle("Change in {&beta}{sub:inst} per 1 SD of characteristic")
end

* ==================================================== step 5 -- elastic net
* Elastic net rather than pure LASSO: the characteristics are strongly
* correlated and LASSO keeps one member of a correlated block arbitrarily.
* lasso/elasticnet take iweights, not aweights, so w_prec is rescaled to mean
* 1 -- that leaves the weighted objective unchanged and keeps lambda on a
* comparable scale.
program step5_enet
    char_groups
    use ../temp/step_sample.dta, clear
    qui sum w_prec
    gen double w_i = w_prec / r(mean)

    di as text _n "===== STEP 5: elastic net, alpha and lambda by cross-validation ====="
    * $ZALL is unparenthesized: parentheses would mark the characteristics as
    * always-included and there would be nothing left to select over.
    * alllambdas traces the whole grid instead of stopping at the first CV
    * minimum, so the CV curve and the coefficient path are complete even when
    * the minimum sits at the null model.
    cap noi elasticnet linear beta_inst $ZALL [iweight = w_i], ///
        alpha(0.25 0.5 0.75 1) selection(cv, alllambdas) rseed($RSEED) nolog
    if _rc {
        di as error "weighted elasticnet failed (rc=`=_rc'); refitting unweighted."
        qui replace w_i = 1
        cap noi elasticnet linear beta_inst $ZALL [iweight = w_i], ///
            alpha(0.25 0.5 0.75 1) selection(cv, alllambdas) rseed($RSEED) nolog
        if _rc {
            di as error "elasticnet failed (rc=`=_rc'); skipping step 5."
            exit 0
        }
    }
    estimates store enet
    global ENET_A = .
    global ENET_L = .
    global ENET_K = .
    global ENET_LE = .
    cap global ENET_A = e(alpha_sel)
    cap global ENET_L = e(lambda_sel)
    cap global ENET_K = e(k_nonzero_sel)
    di as text "alpha* = $ENET_A, lambda* = $ENET_L, selected = $ENET_K of $NZ"

    cap noi lassoknots, display(nonzero)
    cap noi cvplot
    if !_rc graph export ../output/figures/ex5_cv_curve.pdf, replace
    cap noi coefpath
    if !_rc graph export ../output/figures/ex5_coef_path.pdf, replace

    qui estimates restore enet
    enet_selected
    if "$ENET_SEL" != "" {
        enet_exhibit, name(ex5_enet_coefs) ///
            xtitle("Penalized elastic-net coefficient per 1 SD")
        enet_post_ols
        exit 0
    }

    di as text _n "CV selects the null model: at lambda* every coefficient is 0,"
    di as text "so no characteristic survives the penalty. That IS the step 5"
    di as text "answer, and it agrees with the forest in step 6. Exhibit 5"
    di as text "instead reports the order of entry as the penalty is relaxed."
    enet_entry
    if "$ENET_SEL" == "" {
        di as error "no knot with nonzero coefficients found; no Exhibit 5."
        exit 0
    }
    enet_exhibit, name(ex5_enet_entry) ///
        xtitle("Elastic-net coefficient at the entry knot, per 1 SD") ///
        note("CV selects zero characteristics; these are the first to enter as lambda falls below lambda*, at lambda = $ENET_LE. Descriptive, not selected.")
    enet_post_ols
end

* Nonzero entries of e(b). Read off the coefficient vector rather than
* e(post_sel_vars), which returns the dependent variable, not the covariates.
program enet_selected
    mat L = e(b)
    global ENET_SEL ""
    foreach v of global ZALL {
        local c = colnumb(L, "`v'")
        if mi(`c') continue
        if L[1, `c'] != 0 global ENET_SEL $ENET_SEL `v'
    }
    di as text "nonzero coefficients (" wordcount("$ENET_SEL") "): $ENET_SEL"
end

* Walk down the path at the CV-selected alpha to the first knot carrying at
* least TARGET nonzero coefficients. Refitting with a single alpha keeps the
* knot table to one block, so the first qualifying row is unambiguous.
program enet_entry
    local a = $ENET_A
    if mi(`a') local a = 1
    local target = min(10, $NZ)
    di as text _n "path at alpha = `a', first knot with >= `target' nonzero:"

    cap noi qui elasticnet linear beta_inst $ZALL [iweight = w_i], ///
        alpha(`a') selection(cv, alllambdas) rseed($RSEED) nolog
    if _rc {
        di as error "single-alpha refit failed (rc=`=_rc')."
        global ENET_SEL ""
        exit 0
    }
    cap qui lassoknots, display(nonzero)
    if _rc {
        di as error "lassoknots failed (rc=`=_rc')."
        global ENET_SEL ""
        exit 0
    }
    mat T = r(table)
    local pick = .
    local pickk = .
    forval r = 1 / `=rowsof(T)' {
        if T[`r', 3] >= `target' & mi(`pick') {
            local pick  = round(T[`r', 1])
            local pickk = T[`r', 3]
        }
    }
    if mi(`pick') {
        local pick  = round(T[`=rowsof(T)', 1])
        local pickk = T[`=rowsof(T)', 3]
        di as text "no knot reaches `target'; using the last knot instead."
    }
    cap noi lassoselect id = `pick'
    if _rc {
        di as error "lassoselect id = `pick' failed (rc=`=_rc')."
        global ENET_SEL ""
        exit 0
    }
    cap global ENET_LE = e(lambda_sel)
    di as text "entry knot id `pick': lambda = $ENET_LE, nonzero = `pickk'"
    enet_selected
end

program enet_exhibit
    syntax, name(string) [xtitle(string) note(string)]
    tempname pf
    postfile `pf' str32 vname str48 vlbl str40 grp int gnum ///
        double b double se double lo double hi using ../temp/ex5_coefs.dta, replace
    mat ENET = J(wordcount("$ENET_SEL"), 2, .)
    mat colnames ENET = penalized_coef sign
    local sl "$ENET_SEL"
    local rn ""
    local i = 0
    forval g = 1/5 {
        foreach v of global Z`g' {
            local inl : list posof "`v'" in sl
            if `inl' == 0 continue
            local ++i
            local vn = subinstr("`v'", "z_", "", 1)
            local lb "${VL_`vn'}"
            if "`lb'" == "" local lb "`vn'"
            local bb = L[1, colnumb(L, "`v'")]
            mat ENET[`i', 1] = `bb'
            mat ENET[`i', 2] = sign(`bb')
            local rn `rn' `vn'
            post `pf' ("`vn'") ("`lb'") ("${GLBL`g'}") (`g') (`bb') (.) (.) (.)
        }
    }
    postclose `pf'
    mat rownames ENET = `rn'
    coefplot_grouped, using(../temp/ex5_coefs.dta) name(`name') points ///
        xtitle("`xtitle'") note("`note'")
end

program enet_post_ols
    di as text _n "===== post-selection OLS on the elastic-net set ====="
    di as text "(inference is not valid post-selection; magnitudes only)"
    regress beta_inst $ENET_SEL [aweight = w_prec], robust
end

* =================================================== step 6 -- random forest
program step6_rf
    char_groups
    di as text _n "===== STEP 6: random forest with SHAP (rf_theta.py) ====="
    cap confirm file ../temp/theta_chars.csv
    if _rc {
        di as error "../temp/theta_chars.csv missing; skipping step 6."
        exit 0
    }
    shell python3 rf_theta.py

    cap confirm file ../temp/rf_metrics.csv
    if _rc == 0 {
        preserve
            import delimited ../temp/rf_metrics.csv, clear varn(1)
            qui count
            mat RF = J(r(N), 1, .)
            mat colnames RF = value
            local rn ""
            forval i = 1/`=_N' {
                mat RF[`i', 1] = value[`i']
                local rn `rn' `=metric[`i']'
            }
            mat rownames RF = `rn'
            list, noobs sep(0)
        restore
    }
    else di as error "rf_theta.py produced no metrics file."

    cap confirm file ../temp/rf_importance.csv
    if _rc {
        di as error "rf_theta.py produced no importance file; skipping Exhibit 6."
        exit 0
    }
    import delimited ../temp/rf_importance.csv, clear varn(1)
    gen str48 vlbl = ""
    gen str40 grp  = ""
    gen int   gnum = .
    forval g = 1/5 {
        foreach v of global Z`g' {
            local vn = subinstr("`v'", "z_", "", 1)
            local lb "${VL_`vn'}"
            if "`lb'" == "" local lb "`vn'"
            qui replace vlbl = "`lb'"       if vname == "`vn'"
            qui replace grp  = "${GLBL`g'}" if vname == "`vn'"
            qui replace gnum = `g'          if vname == "`vn'"
        }
    }
    replace vlbl = vname if vlbl == ""
    replace grp  = "Other" if grp == ""
    replace gnum = 9 if mi(gnum)

    gsort -mean_abs_shap
    keep in 1/`=min(15, _N)'
    rename mean_abs_shap b
    gen double se = .
    gen double lo = .
    gen double hi = .
    save ../temp/ex6_coefs.dta, replace
    coefplot_grouped, using(../temp/ex6_coefs.dta) name(ex6_rf_shap) points ///
        xtitle("Mean |SHAP| (units of {&beta}{sub:inst})")
end

* ============================================================ shared plotter
* One colour throughout; concept groups are distinguished by marker symbol and
* separated by a blank band on the y axis. Legend sits below the plot region
* (ring(1)) so it never covers a coefficient.
program coefplot_grouped
    syntax, using(string) name(string) [xtitle(string) points note(string)]
    preserve
        use `using', clear
        qui count if !mi(b)
        if r(N) < 1 {
            di as text "coefplot_grouped `name': nothing to plot."
            exit 0
        }
        drop if mi(b)

        sort gnum b
        gen long _row = _n
        qui by gnum: gen byte _new = (_n == 1)
        gen long _gi = sum(_new) - 1
        gen double ord = _row + 1.5 * _gi

        local ylabs ""
        forval i = 1 / `=_N' {
            local nm = vlbl[`i']
            local pp = ord[`i']
            local ylabs `ylabs' `pp' "`nm'"
        }

        local pl ""
        if "`points'" == "" local pl (rcap lo hi ord, horizontal lcolor(gs11) lwidth(vthin))
        * symbol is keyed to gnum, not to legend position, so a concept group
        * keeps the same marker across exhibits even when it is absent from one
        local syms O T S D X Oh
        local lgd ""
        local k = 0
        levelsof gnum, local(gs)
        foreach g of local gs {
            local ++k
            local si = cond(`g' > 5, 6, `g')
            local sy : word `si' of `syms'
            local pl `pl' (scatter ord b if gnum == `g', ///
                mcolor(ebblue) msymbol(`sy') msize(small))
            qui levelsof grp if gnum == `g', local(gl) clean
            local pos = `k' + cond("`points'" == "", 1, 0)
            local lgd `lgd' `pos' "`gl'"
        }
        local nt ""
        if "`note'" != "" local nt note("`note'", size(vsmall))
        tw `pl', xline(0, lcolor(gs6) lpattern(dash)) ///
            ylab(`ylabs', angle(0) labsize(vsmall) nogrid) ///
            yscale(range(0 `=ord[_N] + 1')) ///
            ytitle("") xtitle("`xtitle'") ///
            legend(order(`lgd') pos(6) ring(1) rows(3) size(vsmall) ///
                   region(lstyle(none))) ///
            ysize(9) xsize(6.5) `nt'
        graph export ../output/figures/`name'.pdf, replace
        export delimited using ../output/tables/`name'.csv, replace
    restore
end

* =============================================================== text tables
program output_tables
    cap confirm matrix WLS
    if !_rc {
        mat SUMM = J(5, 1, .)
        mat SUMM[1,1] = $NC
        mat SUMM[2,1] = $NZ
        mat SUMM[3,1] = $WLS_R2
        mat SUMM[4,1] = $WLS_F
        mat SUMM[5,1] = $WLS_FP
        mat rownames SUMM = N_inst N_chars r2 joint_F joint_p
        mat colnames SUMM = wls
        qui matrix_to_txt, saving("../output/tables/step4_wls.txt") ///
            matrix(WLS) title(<tab:step4_wls>) format(%20.4f) replace
        qui matrix_to_txt, saving("../output/tables/step4_wls_fit.txt") ///
            matrix(SUMM) title(<tab:step4_wls_fit>) format(%20.4f) replace
    }
    cap confirm matrix ENET
    if !_rc {
        mat ETUNE = J(4, 1, .)
        mat ETUNE[1,1] = $ENET_A
        mat ETUNE[2,1] = $ENET_L
        mat ETUNE[3,1] = $ENET_K
        mat ETUNE[4,1] = $ENET_LE
        mat rownames ETUNE = alpha_sel lambda_sel k_nonzero_cv lambda_entry
        mat colnames ETUNE = enet
        qui matrix_to_txt, saving("../output/tables/step5_enet.txt") ///
            matrix(ENET) title(<tab:step5_enet>) format(%20.4f) replace
        qui matrix_to_txt, saving("../output/tables/step5_enet_tuning.txt") ///
            matrix(ETUNE) title(<tab:step5_enet_tuning>) format(%20.5f) replace
    }
    cap confirm matrix RF
    if !_rc {
        qui matrix_to_txt, saving("../output/tables/step6_rf_fit.txt") ///
            matrix(RF) title(<tab:step6_rf_fit>) format(%20.4f) replace
    }
end

main
