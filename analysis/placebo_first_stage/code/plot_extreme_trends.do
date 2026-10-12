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

program main
    make_benchmark
    plot_panels
end

program make_benchmark
    use ../../../derived/first_stage/make_mkt_panel/output/category_yr_tfidf.dta, clear
    keep if treated == 0
    gcollapse (mean) bench_log_raw_price = log_raw_price [aw=spend_2013], by(year)
    qui sum bench_log_raw_price if year == 2013
    qui replace bench_log_raw_price = bench_log_raw_price - r(mean)
    tempfile bench
    save `bench'

    use ../../../derived/first_stage/make_mkt_panel/output/category_yr_tfidf.dta, clear
    keep category year log_raw_price
    bys category (year): gen log_2013 = log_raw_price if year == 2013
    bys category (year): egen base = mean(log_2013)
    gen cat_log_raw_price = log_raw_price - base
    drop log_raw_price log_2013 base
    merge m:1 year using `bench', nogen keep(3)

    preserve
    import delimited using ../output/extreme_placebo_diagnostics.csv, clear stringcols(_all) varnames(1)
    keep category mean_b flagged_top flagged_bottom
    destring mean_b flagged_top flagged_bottom, replace
    tempfile flag
    save `flag'
    restore
    merge m:1 category using `flag', keep(3) nogen

    save ../temp/plot_data, replace
end

program plot_panels
    use ../temp/plot_data, clear
    cap mkdir ../temp
    cap mkdir ../output/figures

    gen cat_label = category + " (b=" + string(mean_b, "%5.2f") + ")"
    encode cat_label, gen(cat_id)

    gsort -mean_b
    gen ord_top = .
    qui levelsof cat_label if flagged_top == 1, local(toplbls)
    local i = 1
    foreach l of local toplbls {
        qui replace ord_top = `i' if cat_label == "`l'"
        local ++i
    }
    gsort mean_b
    gen ord_bot = .
    qui levelsof cat_label if flagged_bottom == 1, local(botlbls)
    local i = 1
    foreach l of local botlbls {
        qui replace ord_bot = `i' if cat_label == "`l'"
        local ++i
    }

    preserve
    keep if flagged_top == 1
    drop cat_id
    sort ord_top year
    egen cat_id = group(ord_top)
    labmask cat_id, values(cat_label)
    tw (line cat_log_raw_price year, lcolor(cranberry) lwidth(medthick)) ///
       (line bench_log_raw_price year, lcolor(navy) lwidth(medium) lpattern(dash)), ///
       by(cat_id, cols(5) note("") ///
          title("Placebo extremes: top 10 (positive mean DiD)", size(small)) ///
          subtitle("Category (red) vs. non-treated benchmark (blue dashed) - centered to 0 at 2013") ///
          legend(off)) ///
       subtitle(, size(tiny) bcolor(none)) ///
       xline(2014, lcolor(gs10) lpattern(dot)) ///
       yline(0, lcolor(gs12)) ///
       xtitle("Year", size(medsmall)) ytitle("Log price (centered at 2013)", size(medsmall)) ///
       xlab(2010(2)2019, labsize(small)) ylab(, labsize(small))
    fig_export, path("../output/figures/extreme_trends_top10.pdf")
    restore

    preserve
    keep if flagged_bottom == 1
    drop cat_id
    sort ord_bot year
    egen cat_id = group(ord_bot)
    labmask cat_id, values(cat_label)
    tw (line cat_log_raw_price year, lcolor(cranberry) lwidth(medthick)) ///
       (line bench_log_raw_price year, lcolor(navy) lwidth(medium) lpattern(dash)), ///
       by(cat_id, cols(5) note("") ///
          title("Placebo extremes: bottom 10 (negative mean DiD)", size(small)) ///
          subtitle("Category (red) vs. non-treated benchmark (blue dashed) - centered to 0 at 2013") ///
          legend(off)) ///
       subtitle(, size(tiny) bcolor(none)) ///
       xline(2014, lcolor(gs10) lpattern(dot)) ///
       yline(0, lcolor(gs12)) ///
       xtitle("Year", size(medsmall)) ytitle("Log price (centered at 2013)", size(medsmall)) ///
       xlab(2010(2)2019, labsize(small)) ylab(, labsize(small))
    fig_export, path("../output/figures/extreme_trends_bottom10.pdf")
    restore
end

main
