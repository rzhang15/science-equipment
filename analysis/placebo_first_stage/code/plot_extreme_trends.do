set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main
    make_benchmark
    plot_panels
end

program make_benchmark
    // Build a "control universe" line: spend-weighted mean log_raw_price by year,
    // pooled across all non-treated categories in the panel.
    // (Panel already filtered to keep==1 in make_mkt_panel build.do.)
    use ../../../derived/first_stage/make_mkt_panel/output/category_yr_tfidf.dta, clear
    keep if treated == 0
    gcollapse (mean) bench_log_raw_price = log_raw_price [aw=spend_2013], by(year)
    // Center benchmark to 0 at 2013
    qui sum bench_log_raw_price if year == 2013
    qui replace bench_log_raw_price = bench_log_raw_price - r(mean)
    tempfile bench
    save `bench'

    // Per-category centered trend
    use ../../../derived/first_stage/make_mkt_panel/output/category_yr_tfidf.dta, clear
    keep category year log_raw_price
    bys category (year): gen log_2013 = log_raw_price if year == 2013
    bys category (year): egen base = mean(log_2013)
    gen cat_log_raw_price = log_raw_price - base
    drop log_raw_price log_2013 base
    merge m:1 year using `bench', nogen keep(3)

    // Filter to our 20 flagged categories using diagnostics CSV
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
    // Two PDFs: top 10 (positive b) and bottom 10 (negative b)
    use ../temp/plot_data, clear
    cap mkdir ../temp
    cap mkdir ../output/figures

    // For a clean panel title, prepend the mean_b to the category name
    gen cat_label = category + " (b=" + string(mean_b, "%5.2f") + ")"
    encode cat_label, gen(cat_id)

    // Order panels by mean_b within each group (biggest extreme first)
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

    // ---- Top 10 (positive b)
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
       xtitle("year", size(small)) ytitle("log price (centered at 2013)", size(small)) ///
       xlab(2010(2)2019, labsize(vsmall)) ylab(, labsize(vsmall))
    graph export ../output/figures/extreme_trends_top10.pdf, replace
    restore

    // ---- Bottom 10 (negative b)
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
       xtitle("year", size(small)) ytitle("log price (centered at 2013)", size(small)) ///
       xlab(2010(2)2019, labsize(vsmall)) ylab(, labsize(vsmall))
    graph export ../output/figures/extreme_trends_bottom10.pdf, replace
    restore
end

main
