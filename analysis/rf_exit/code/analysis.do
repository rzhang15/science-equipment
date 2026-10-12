set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries, loadglob(../external/lib/globals.txt)
adopath ++ "../external/lib/stata"
version 17
global WEIGHT_MSIM 0

program main
    local pubs 0
    if "$RUN_PUBLIC" == "1" local pubs 0 1
    local r1_opts 0
    if "$RUN_R1_ONLY" == "1" local r1_opts 0 1
    cap mkdir "../output/figures/all_jrnls"
    foreach pub of local pubs {
        foreach r1 of local r1_opts {
            foreach wmode in 0 1 {
                global WEIGHT_MSIM `wmode'
                di as text _newline "=========================================="
                di as text "  RUNNING sample=all_jrnls WEIGHT_MSIM=`wmode' PUBLIC=`pub' R1_ONLY=`r1'"
                di as text "=========================================="
                mat drop _all
                exit_analysis, samp(all_jrnls) r1r2(1) public(`pub') r1_only(`r1')
                output_tables, samp(all_jrnls) r1r2(1) public(`pub') r1_only(`r1')
            }
            global WEIGHT_MSIM 0
        }
    }
end

program exit_analysis
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
    local wt ""
    local wsuf ""
    if "$WEIGHT_MSIM" == "1" {
        local wt "[pw=max_sim]"
        local wsuf "_msimwt"
    }
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"
    use ../external/prepped_samples/exit_`samp'`suf', clear

    foreach yvar in exit_gap exit_2022 exit_2024 {
        cap mat drop exit_`yvar'
        mat exit_`yvar' = J(8, 6, .)
        local c = 0
        foreach fe in fld inst {
            local absorb cluster_30
            if "`fe'" == "inst" local absorb cluster_30 inst_pre
            foreach g in all young old {
                local ++c
                cap noi qui reghdfe `yvar' exposure mkt_spend_shr if `g' == 1 `wt', ///
                    absorb(`absorb') vce(cluster inst_pre)
                if _rc {
                    di as error "exit_analysis `samp'`suf' `yvar' `g' `fe' failed (rc=" _rc ")."
                    continue
                }
                mat exit_`yvar'[1,`c'] = _b[exposure]
                mat exit_`yvar'[2,`c'] = _se[exposure]
                mat exit_`yvar'[3,`c'] = _b[mkt_spend_shr]
                mat exit_`yvar'[4,`c'] = _se[mkt_spend_shr]
                qui sum `yvar' if e(sample)
                mat exit_`yvar'[5,`c'] = r(mean)
                mat exit_`yvar'[6,`c'] = e(N)
                di as text "exit_analysis `samp'`suf' `yvar' `g' (`fe' FE): b=" %7.4f _b[exposure] ///
                    " se=" %7.4f _se[exposure] " mean=" %5.3f r(mean) " N=" e(N)
            }
            cap noi qui reghdfe `yvar' c.exposure##i.young c.mkt_spend_shr c.mkt_spend_shr#i.young `wt', ///
                absorb(`absorb') vce(cluster inst_pre)
            if _rc == 0 {
                local cy = cond("`fe'" == "fld", 2, 5)
                mat exit_`yvar'[7,`cy'] = _b[1.young#c.exposure]
                mat exit_`yvar'[8,`cy'] = _se[1.young#c.exposure]
            }
        }
        mat rownames exit_`yvar' = b_exposure se_exposure b_share se_share mean_y N b_early_minus_late se_early_minus_late
        mat colnames exit_`yvar' = all_fld early_fld late_fld all_inst early_inst late_inst
    }

    * Panel analog: any last-author paper in the year, author + field x year FE.
    use ../external/prepped_samples/exit_panel_`samp'`suf', clear
    keep if inrange(year, 2010, 2019)
    merge m:1 athr_id using ../external/prepped_samples/exit_`samp'`suf', ///
        keep(3) keepusing(exposure mkt_spend_shr cluster_30 max_sim young old all) nogen
    gen byte post  = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post
    cap mat drop exit_active
    mat exit_active = J(8, 6, .)
    local c = 0
    foreach fe in clyr yr {
        local absorb athr_id i.cluster_30#i.year
        if "`fe'" == "yr" local absorb athr_id year
        foreach g in all young old {
            local ++c
            cap noi qui reghdfe pub Z_it Z_share_it if `g' == 1 `wt', ///
                absorb(`absorb') vce(cluster athr_id)
            if _rc {
                di as error "exit_analysis `samp'`suf' active `g' `fe' failed (rc=" _rc ")."
                continue
            }
            mat exit_active[1,`c'] = _b[Z_it]
            mat exit_active[2,`c'] = _se[Z_it]
            mat exit_active[3,`c'] = _b[Z_share_it]
            mat exit_active[4,`c'] = _se[Z_share_it]
            qui sum pub if e(sample) & year < 2014
            mat exit_active[5,`c'] = r(mean)
            mat exit_active[6,`c'] = e(N)
            di as text "exit_analysis `samp'`suf' active `g' (`fe' FE): b=" %7.4f _b[Z_it] ///
                " se=" %7.4f _se[Z_it] " pre-mean=" %5.3f r(mean) " N=" e(N)
        }
        cap noi qui reghdfe pub c.Z_it##i.young c.Z_share_it c.Z_share_it#i.young `wt', ///
            absorb(`absorb') vce(cluster athr_id)
        if _rc == 0 {
            local cy = cond("`fe'" == "clyr", 2, 5)
            mat exit_active[7,`cy'] = _b[1.young#c.Z_it]
            mat exit_active[8,`cy'] = _se[1.young#c.Z_it]
        }
    }
    mat rownames exit_active = b_exposure se_exposure b_share se_share pre_mean N b_early_minus_late se_early_minus_late
    mat colnames exit_active = all_clyr early_clyr late_clyr all_yr early_yr late_yr

    cap mkdir "../output/figures/`samp'"
    preserve
        clear
        set obs 9
        gen byte outc = ceil(_n / 3)
        gen byte grp  = mod(_n - 1, 3) + 1
        gen b  = .
        gen se = .
        local o = 0
        foreach yvar in exit_gap exit_2022 exit_2024 {
            local ++o
            forval g = 1/3 {
                replace b  = exit_`yvar'[1,`g'] if outc == `o' & grp == `g'
                replace se = exit_`yvar'[2,`g'] if outc == `o' & grp == `g'
            }
        }
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se
        gen y = (3 - outc)*4 + 1 + (2 - grp)
        local ylabs `"9 "Five-year gap starting 2014-2019" 5 "No last-author paper 2020-2022" 1 "No last-author paper 2020-2024""'
        tw rcap ub lb y if grp == 1, horizontal lcolor(ebblue%70) msize(vsmall) || ///
           scatter y b if grp == 1, mcolor(ebblue) msize(small) || ///
           rcap ub lb y if grp == 2, horizontal lcolor(dkorange%70) msize(vsmall) || ///
           scatter y b if grp == 2, mcolor(dkorange) msymbol(D) msize(small) || ///
           rcap ub lb y if grp == 3, horizontal lcolor(lavender%70) msize(vsmall) || ///
           scatter y b if grp == 3, mcolor(lavender) msymbol(S) msize(small) ///
           , xline(0, lcolor(gs10) lpattern(solid)) ///
             yline(3 7, lcolor(gs12) lpattern(dash)) ///
             ylabel(`ylabs', angle(0) labsize(small) noticks nogrid) ///
             ytitle("") xtitle("Effect of exposure on Pr(Exit)", size(medsmall)) ///
             xlabel(#7, labsize(small)) ///
             legend(order(2 "All PIs" 4 "Early-career PIs" 6 "Late-career PIs") pos(6) ring(1) rows(1) size(small)) ///
             ysize(4) xsize(8) yscale(range(-0.5 10.5)) ///
             plotregion(margin(l=zero r=zero b=zero t=vsmall))
        fig_export, path("../output/figures/`samp'/exit_coefplot`suf'`wsuf'.pdf") xsize(8) ysize(4)
        di as text "wrote ../output/figures/`samp'/exit_coefplot`suf'`wsuf'.pdf"
    restore
end

program output_tables
    syntax, samp(string) [, r1r2(int 0) public(int 0) r1_only(int 0) no_clin(int 0)]
    local wsuf ""
    if "$WEIGHT_MSIM" == "1" local wsuf "_msimwt"
    local suf ""
    if (`r1r2' == 1 & `public' == 0 & `r1_only' == 0) local suf "_r1_r2"
    if (`r1r2' == 1 & `public' == 1 & `r1_only' == 0) local suf "_r1_r2_public"
    if (`r1_only' == 1 & `public' == 0) local suf "_r1"
    if (`r1_only' == 1 & `public' == 1) local suf "_r1_public"
    if (`no_clin' == 1) local suf "_no_clin`suf'"
    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'
    foreach yvar in exit_gap exit_2022 exit_2024 active {
        cap confirm matrix exit_`yvar'
        if !_rc {
            qui matrix_to_txt, saving("../output/tables/`samp'/exit_`yvar'`suf'`wsuf'.txt") ///
                matrix(exit_`yvar') title(<tab:exit_`yvar'`suf'`wsuf'>) format(%20.4f) replace
        }
    }

    write_exit_tex,    samp(`samp') suf(`suf') wsuf(`wsuf')
end

program write_exit_tex
    syntax, samp(string) [suf(string) wsuf(string)]
    cap confirm matrix exit_exit_gap
    if _rc exit 0
    local out ../output/tables/`samp'/exit`suf'`wsuf'.tex
    tempname fh
    file open `fh' using "`out'", write replace
    file write `fh' "\begin{table}[htbp]" _n
    file write `fh' "\centering" _n
    file write `fh' "\caption{Effect of Merger Exposure on Exit}" _n
    file write `fh' "\label{tab:exit`suf'`wsuf'}" _n
    file write `fh' "\begin{tabular}{lccc}" _n
    file write `fh' "\toprule" _n
    file write `fh' " & (1) & (2) & (3) \\" _n
    file write `fh' " & All PIs & Early-Career PIs & Late-Career PIs \\" _n
    file write `fh' "\midrule" _n
    local lbl_exit_2022 "No last-author paper 2020--2022"
    local lbl_exit_2024 "No last-author paper 2020--2024"
    local lbl_exit_gap  "Five-year publishing gap starting 2014--2019"
    local lbl_active    "Any last-author paper in year (panel, author + field x year FE)"
    foreach yvar in exit_gap exit_2022 exit_2024 active {
        cap confirm matrix exit_`yvar'
        if _rc continue
        local line_b  "`lbl_`yvar''"
        local line_se ""
        local line_m  "\quad Mean"
        local line_n  "\quad Observations"
        forval c = 1/3 {
            local b  = exit_`yvar'[1,`c']
            local se = exit_`yvar'[2,`c']
            local m  = exit_`yvar'[5,`c']
            local n  = exit_`yvar'[6,`c']
            local t  = abs(`b' / `se')
            local st = cond(mi(`t'), "", cond(`t' >= 2.576, "^{***}", cond(`t' >= 1.960, "^{**}", cond(`t' >= 1.645, "^{*}", ""))))
            local b_s  : dis %6.3f `b'
            local se_s : dis %6.3f `se'
            local m_s  : dis %5.3f `m'
            local n_s  : dis %9.0fc `n'
            local line_b  "`line_b' & $`b_s'`st'$"
            local line_se "`line_se' & ($`se_s'$)"
            local line_m  "`line_m' & `m_s'"
            local line_n  "`line_n' & `n_s'"
        }
        file write `fh' "`line_b' \\" _n
        file write `fh' "`line_se' \\" _n
        file write `fh' "`line_m' \\" _n
        file write `fh' "`line_n' \\" _n
        file write `fh' "\addlinespace" _n
    }
    file write `fh' "\bottomrule" _n
    file write `fh' "\end{tabular}" _n
    file write `fh' "\end{table}" _n
    file close `fh'
    di as text "wrote `out'"
end

main
