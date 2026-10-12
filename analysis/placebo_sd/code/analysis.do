set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

global sd_mode  "`1'"
global sd_chunk "`2'"
global sd_lo    "`3'"
global sd_hi    "`4'"

program main
    foreach s in "" "_all3" {
        global suffix `s'
        if inlist("$sd_mode", "", "prep")  prep_data
        if inlist("$sd_mode", "", "chunk") placebo_did
        if "$sd_mode" == "combine" combine_chunks
    }
end

program prep_data
    import delimited ../temp/placebo_sd_pairs$suffix.csv, clear varn(1)
    rename treated_market category
    gegen cid = group(category)
    save ../temp/placebo_sd_pairs$suffix, replace

    gcontract cid category
    drop _freq
    save ../temp/cid_xw$suffix, replace

    use ../external/samp/uni_category_yr_tfidf$suffix, clear
    drop if treated == 1
    gegen uni_mkt = group(uni_id mkt)
    bys uni_mkt : egen min_year = min(year)
    bys uni_mkt : egen max_year = max(year)
    keep if min_year < 2014 & max_year > 2014
    gen post = year >= 2014
    keep category year uni_id mkt spend_2013 post avg_log_price log_raw_spend
    save ../temp/uni_panel$suffix, replace
end

program placebo_did
    use ../temp/placebo_sd_pairs$suffix, clear
    qui sum iter
    local n_iter = r(max)
    local lo = cond("$sd_lo" == "", 1, real("$sd_lo"))
    local hi = cond("$sd_hi" == "", `n_iter', min(`n_iter', real("$sd_hi")))
    local tag = cond("$sd_chunk" == "", "", "_c$sd_chunk")

    cap postclose coefs
    postfile coefs int iter int cid double(b_price se_price b_spend se_spend) ///
        using ../temp/placebo_sd_coefs${suffix}`tag', replace

    forvalues i = `lo'/`hi' {
        di as text "===== iter `i' / `n_iter' ====="
        use ../temp/placebo_sd_pairs$suffix if iter == `i', clear
        save ../temp/pairs_i`tag', replace
        qui glevelsof cid, local(cids)

        keep category
        append using ../temp/pairs_i`tag', keep(control_market)
        replace category = control_market if mi(category)
        keep category
        duplicates drop
        merge 1:m category using ../temp/uni_panel$suffix, keep(3) nogen
        save ../temp/panel_i`tag', replace

        foreach j in `cids' {
            use ../temp/pairs_i`tag' if cid == `j', clear
            keep category control_market
            gen treated = 0
            local N = _N + 1
            set obs `N'
            replace control_market = category[1] in `N'
            replace treated = 1 in `N'
            keep control_market treated
            rename control_market category
            duplicates drop
            merge 1:m category using ../temp/panel_i`tag', keep(3) nogen
            gen posttreat = treated * post

            cap reghdfe avg_log_price posttreat [aw=spend_2013], cluster(mkt) absorb(year uni_id mkt)
            if _rc == 0 {
                local b_p  = _b[posttreat]
                local se_p = _se[posttreat]
            }
            else {
                local b_p  = .
                local se_p = .
            }
            cap reghdfe log_raw_spend posttreat [aw=spend_2013], cluster(mkt) absorb(year uni_id mkt)
            if _rc == 0 {
                local b_s  = _b[posttreat]
                local se_s = _se[posttreat]
            }
            else {
                local b_s  = .
                local se_s = .
            }
            post coefs (`i') (`j') (`b_p') (`se_p') (`b_s') (`se_s')
        }
    }
    postclose coefs

    if "$sd_mode" == "" {
        use ../temp/placebo_sd_coefs$suffix, clear
        merge m:1 cid using ../temp/cid_xw$suffix, assert(2 3) keep(3) nogen
        order iter cid category
        save ../output/placebo_sd_coefs$suffix, replace
    }
end

program combine_chunks
    use ../temp/placebo_sd_pairs$suffix, clear
    qui sum iter
    local n_iter = r(max)

    local files : dir "../temp" files "placebo_sd_coefs${suffix}_c*.dta"
    assert `"`files'"' != ""
    clear
    foreach f of local files {
        append using "../temp/`f'"
    }
    isid iter cid
    qui gegen tagi = tag(iter)
    qui count if tagi
    assert r(N) == `n_iter'
    drop tagi
    merge m:1 cid using ../temp/cid_xw$suffix, assert(2 3) keep(3) nogen
    sort iter cid
    order iter cid category
    save ../output/placebo_sd_coefs$suffix, replace
end

main
