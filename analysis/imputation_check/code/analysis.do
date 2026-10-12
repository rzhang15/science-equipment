set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries

global PRES_SCALE 1.2

cap program drop fig_export
program fig_export
    syntax, path(string) [mode(string) xsize(real 6) ysize(real 4)]
    local p : subinstr local path "/paper/" "/", all
    local p : subinstr local p "/pres/" "/", all
    local k = strpos("`p'", "figures/")
    if `k' > 0 {
        local base = substr("`p'", 1, `k' + 7)
        local rest = substr("`p'", `k' + 8, .)
    }
    else {
        local slash = strrpos("`p'", "/")
        local base = substr("`p'", 1, `slash')
        local rest = substr("`p'", `slash' + 1, .)
    }
    local tscale = cond(`xsize' >= `ysize', (2/3) * `xsize' / min(`xsize', `ysize'), 1)
    if "`mode'" == "presentation" local mode pres
    foreach m in paper pres {
        if "`mode'" != "" & "`mode'" != "`m'" continue
        local dir "`base'`m'"
        cap mkdir "`dir'"
        local sub "`rest'"
        while strpos("`sub'", "/") > 0 {
            local seg = substr("`sub'", 1, strpos("`sub'", "/") - 1)
            local dir "`dir'/`seg'"
            cap mkdir "`dir'"
            local sub = substr("`sub'", strpos("`sub'", "/") + 1, .)
        }
        local s = cond("`m'" == "pres", `tscale' * $PRES_SCALE, `tscale')
        graph display, scale(`s')
        graph export "`base'`m'/`rest'", replace
    }
end
version 17

global K        3
global VERSION  hc_all3
global SIM_REF  0.2

program main
    load_loo
    binscatter_pair, y(exposure)      x(exposure_loo)      stem(exposure) null(exposure_null) ///
        xtitle("Imputed exposure (leave-one-out, K=$K)") ytitle("Observed exposure")
    binscatter_pair, y(mkt_spend_shr) x(mkt_spend_shr_loo) stem(mkt_spend_shr) ///
        xtitle("Imputed treated-market spend share (leave-one-out, K=$K)") ytitle("Observed treated-market spend share")
    binscatter_by_sim
    output_tables
end

program load_loo
    use ../external/loo/loo_shares_pi_${VERSION}_k${K}, clear
    gen hi_sim = max_sim >= $SIM_REF
    label define hi_sim 0 "Nearest donor sim < $SIM_REF" 1 "Nearest donor sim >= $SIM_REF"
    label values hi_sim hi_sim
    save ../temp/loo, replace
end

program binscatter_pair
    syntax, y(string) x(string) stem(string) xtitle(string) ytitle(string) [null(string)]
    use ../temp/loo, clear
    qui corr `y' `x'
    local corr : dis %5.3f r(rho)
    qui reg `y' `x'
    local b  : dis %5.3f _b[`x']
    local se : dis %5.3f _se[`x']
    local n = e(N)
    qui gen double _e2 = (`y' - `x')^2
    qui su _e2, meanonly
    local rmse : dis %6.4f sqrt(r(mean))
    qui su `y'
    local sd : dis %6.4f r(sd)
    drop _e2
    local rmse_null = .
    if "`null'" != "" {
        qui gen double _e2 = (`y' - `null')^2
        qui su _e2, meanonly
        local rmse_null : dis %6.4f sqrt(r(mean))
        drop _e2
    }

    cap mat drop stats_`stem'
    mat stats_`stem' = (`n', `corr', `b', `se', `rmse', `rmse_null', `sd')
    mat colnames stats_`stem' = n corr slope_obs_on_imputed se rmse rmse_null sd_observed

    binscatter `y' `x', n(20) msymbol(O) mcolors(gs6) lcolors(ebblue) ///
        xtitle("`xtitle'") ytitle("`ytitle'") ///
        legend(on order(- "N = `n'" - "Corr = `corr'" - "Slope = `b'" - "            (`se')") ring(0) pos(11) cols(1)) ///
        plotregion(margin(sides))
    fig_export, path("../output/figures/binscatter_`stem'_${VERSION}_k${K}.pdf")
end

program binscatter_by_sim
    use ../temp/loo, clear
    foreach g in 0 1 {
        qui corr exposure exposure_loo if hi_sim == `g'
        local corr`g' : dis %5.3f r(rho)
        qui count if hi_sim == `g'
        local n`g' = r(N)
    }
    binscatter exposure exposure_loo, by(hi_sim) n(15) msymbols(O T) mcolors(dkorange ebblue) lcolors(dkorange ebblue) ///
        xtitle("Imputed exposure (leave-one-out, K=$K)") ytitle("Observed exposure") ///
        legend(order(1 "Nearest donor sim < $SIM_REF (N = `n0', corr = `corr0')" ///
                     2 "Nearest donor sim >= $SIM_REF (N = `n1', corr = `corr1')") ///
               ring(0) pos(11) cols(1)) ///
        plotregion(margin(sides))
    fig_export, path("../output/figures/binscatter_exposure_by_sim_${VERSION}_k${K}.pdf")

end

program output_tables
    mat loo_stats = stats_exposure \ stats_mkt_spend_shr
    mat rownames loo_stats = exposure mkt_spend_shr
    qui matrix_to_txt, saving("../output/tables/loo_stats_${VERSION}_k${K}.txt") ///
        matrix(loo_stats) title(<tab:loo_stats_${VERSION}_k${K}>) format(%20.4f) replace
end

main
