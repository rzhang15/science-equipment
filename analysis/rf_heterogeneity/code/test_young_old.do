set more off
clear all
capture log close
program drop _all
set scheme modern
version 17
log using test_young_old.log, replace


local fes athr_id year
local vce_cl athr_id

foreach suf in _r1_r2 {
    cap confirm file "../temp/es_all_jrnls`suf'.dta"
    if _rc {
        di as error "../temp/es_all_jrnls`suf'.dta missing -- run analysis.do first."
        continue
    }

    use athr_id year avg_team_size using ///
        ../external/samp/athr_panel_full_year_last_all_jrnls`suf', clear
    gen _nonsolo_yr = year if avg_team_size > 0.001 & !mi(avg_team_size)
    gcollapse (min) min_year_nonsolo = _nonsolo_yr, by(athr_id)
    save ../temp/min_year_nonsolo`suf', replace

    use athr_id year ppr_cnt n_solo_ppr using ///
        ../external/samp/athr_panel_full_year_all_jrnls`suf', clear
    gen _ns_any_yr = year if ppr_cnt - n_solo_ppr > 0.001
    gcollapse (min) min_year_any_ns = _ns_any_yr, by(athr_id)
    save ../temp/min_year_any_ns`suf', replace

    use athr_id year n_last_ppr n_solo_ppr using ///
        ../external/samp/athr_panel_full_year_all_jrnls`suf', clear
    gen ppr_cnt_nonsolo = n_last_ppr - n_solo_ppr
    keep athr_id year n_last_ppr ppr_cnt_nonsolo
    save ../temp/nonsolo_ppr`suf', replace

    use athr_id year ppr_cnt cite_affl_wt exposure mkt_spend_shr ///
        min_year min_year_any young old young_nih old_nih ///
        using ../temp/es_all_jrnls`suf', clear
    merge m:1 athr_id using ../temp/min_year_nonsolo`suf', keep(1 3) nogen
    merge m:1 athr_id using ../temp/min_year_any_ns`suf', keep(1 3) nogen
    merge 1:1 athr_id year using ../temp/nonsolo_ppr`suf', keep(1 3) nogen
    foreach v in n_last_ppr ppr_cnt_nonsolo {
        replace `v' = 0 if mi(`v')
    }
    qui count if ppr_cnt != n_last_ppr
    di as text "  rows where ppr_cnt != n_last_ppr (all-position panel): " r(N)
    qui sum ppr_cnt_nonsolo
    local ns_tot = r(sum)
    qui sum ppr_cnt
    local solo_shr = 100*(1 - `ns_tot'/r(sum))
    di as text "  solo papers are " %5.2f `solo_shr' "% of last-author papers in this sample"

    cap drop athr_indicator
    bys athr_id: gen athr_indicator = _n == 1
    qui sum min_year_nonsolo if athr_indicator == 1, d
    local nsmed = r(p50)
    qui count if athr_indicator == 1 & mi(min_year_nonsolo)
    local n_allsolo = r(N)
    qui count if athr_indicator == 1
    di as result _n "== all_jrnls`suf': min_year_nonsolo median = `nsmed'; `n_allsolo' of " ///
        r(N) " PIs have no non-solo last-author paper =="
    tabstat min_year min_year_nonsolo min_year_any min_year_any_ns if athr_indicator == 1, ///
        stats(n mean p10 p25 p50 p75 p90) col(stat) format(%9.1f)
    gen byte young_ns = min_year_nonsolo >  `nsmed' if !mi(min_year_nonsolo)
    gen byte old_ns   = min_year_nonsolo <= `nsmed' if !mi(min_year_nonsolo)
    qui count if athr_indicator == 1 & young != young_ns & !mi(young) & !mi(young_ns)
    di as text "  PIs that switch side under the non-solo definition: " r(N)

    qui sum min_year_any if athr_indicator == 1, d
    local anymed = r(p50)
    di as text "  min_year_any (first pub ever) median = `anymed'"
    gen byte young_any = min_year_any >  `anymed' if !mi(min_year_any)
    gen byte old_any   = min_year_any <= `anymed' if !mi(min_year_any)
    qui count if athr_indicator == 1 & young != young_any & !mi(young) & !mi(young_any)
    di as text "  PIs that switch side under the first-pub-ever definition: " r(N)

    qui sum min_year_any_ns if athr_indicator == 1, d
    local anynsmed = r(p50)
    di as text "  min_year_any_ns (first non-solo pub, any position) median = `anynsmed'"
    gen byte young_anyns = min_year_any_ns >  `anynsmed' if !mi(min_year_any_ns)
    gen byte old_anyns   = min_year_any_ns <= `anynsmed' if !mi(min_year_any_ns)
    qui count if athr_indicator == 1 & young_any != young_anyns & !mi(young_any) & !mi(young_anyns)
    di as text "  PIs that switch side once solo papers are dropped from the career clock: " r(N)

    gen lab_age     = 2014 - min_year
    gen lab_age_ns  = 2014 - min_year_nonsolo
    gen career_age  = 2014 - min_year_any

    gen gap = min_year - min_year_any
    qui count if athr_indicator == 1 & gap <= 0
    local n_nogap = r(N)
    qui count if athr_indicator == 1
    di as text "  PIs with gap <= 0 (first paper is last-authored): `n_nogap' of " r(N)
    qui sum min_year if athr_indicator == 1 & gap >= 1, d
    local gapmed = r(p50)
    gen byte young_g = min_year >  `gapmed' if !mi(min_year) & gap >= 1 & !mi(gap)
    gen byte old_g   = min_year <= `gapmed' if !mi(min_year) & gap >= 1 & !mi(gap)

    gen byte young_both = young == 1 & young_any == 1 ///
        if young == young_any & !mi(young) & !mi(young_any)
    gen byte old_both   = young == 0 & young_any == 0 ///
        if young == young_any & !mi(young) & !mi(young_any)

    gen post       = year >= 2014
    gen Z_it       = exposure      * post
    gen Z_share_it = mkt_spend_shr * post

    cap matrix drop SPLITS
    local split_rows
    local pairs `" "young old" "young_ns old_ns" "young_g old_g" "young_any old_any" "young_anyns old_anyns" "young_both old_both" "young_nih old_nih" "'
    foreach pair of local pairs {
        local g1 : word 1 of `pair'
        local g2 : word 2 of `pair'
        cap confirm variable `g1'
        local rc1 = _rc
        cap confirm variable `g2'
        if `rc1' | _rc {
            di as text "  `g1'/`g2' not built -- skipping pair."
            continue
        }
        foreach yvar in ppr_cnt {
            cap drop Z_`g1' Z_`g2' S_`g1' S_`g2' PT_`g1'
            gen Z_`g1' = Z_it       * `g1'
            gen Z_`g2' = Z_it       * `g2'
            gen S_`g1' = Z_share_it * `g1'
            gen S_`g2' = Z_share_it * `g2'
            gen PT_`g1' = post * `g1'

            cap noi ppmlhdfe `yvar' Z_`g1' Z_`g2' S_`g1' S_`g2' PT_`g1', ///
                absorb(`fes') vce(cluster `vce_cl')
            local rc = _rc
            if `rc' {
                di as error "test_young_old`suf' `yvar' `g1'/`g2': ppml failed (rc=`rc'); skipping."
                continue
            }
            local b1  = _b[Z_`g1']
            local se1 = _se[Z_`g1']
            local b2  = _b[Z_`g2']
            local se2 = _se[Z_`g2']
            local Nfit = e(N)

            lincom Z_`g1' - Z_`g2'
            local b_diff  = r(estimate)
            local se_diff = r(se)
            local p_diff  = r(p)
            local t_diff = `b_diff'/`se_diff'
            local p_one  = `p_diff'/2
            local se_ind = sqrt(`se1'^2 + `se2'^2)
            local p_ind  = 2*normal(-abs(`b_diff'/`se_ind'))

            di as result _n "== all_jrnls`suf' `yvar' `g1' vs `g2' (N=`Nfit') =="
            di as text "  `g1': b=" %8.4f `b1' " (se=" %7.4f `se1' ")"
            di as text "  `g2': b=" %8.4f `b2' " (se=" %7.4f `se2' ")"
            di as text "  diff, joint VCE:  b=" %8.4f `b_diff' " se=" %7.4f `se_diff' ///
                " t=" %6.3f `t_diff' " p=" %6.4f `p_diff' " (one-sided " %6.4f `p_one' ")"
            di as text "  diff, indep. SEs: se=" %7.4f `se_ind' " p=" %6.4f `p_ind'

            matrix SPLITS = nullmat(SPLITS) \ ///
                (`b1', `se1', `b2', `se2', `b_diff', `se_diff', `p_diff', `p_one', `Nfit')
            local split_rows `split_rows' `g1'
        }
    }

    foreach agevar in lab_age lab_age_ns career_age {
        cap confirm variable `agevar'
        if _rc {
            di as text "  `agevar' not built -- skipping gradient."
            continue
        }
        foreach yvar in ppr_cnt {
            cap drop age_c Z_age S_age PT_age
            qui sum `agevar' if athr_indicator == 1, d
            local age_mean = r(mean)
            gen age_c  = (`agevar' - `age_mean')/10
            gen Z_age  = Z_it       * age_c
            gen S_age  = Z_share_it * age_c
            gen PT_age = post       * age_c

            cap noi ppmlhdfe `yvar' Z_it Z_age Z_share_it S_age PT_age, ///
                absorb(`fes') vce(cluster `vce_cl')
            local rc = _rc
            if `rc' {
                di as error "test_young_old`suf' `yvar' `agevar' gradient: ppml failed (rc=`rc'); skipping."
                continue
            }
            local Nfit = e(N)
            local b_z   = _b[Z_it]
            local se_z  = _se[Z_it]
            local b_ga  = _b[Z_age]
            local se_ga = _se[Z_age]
            local t_ga  = `b_ga'/`se_ga'
            local p_ga  = 2*normal(-abs(`t_ga'))
            local p_ga1 = `p_ga'/2

            di as result _n "== all_jrnls`suf' `yvar' continuous gradient in `agevar' (N=`Nfit') =="
            di as text "  Z at mean lab age (" %4.1f `age_mean' " yrs): b=" %8.4f `b_z' ///
                " (se=" %7.4f `se_z' ")"
            di as text "  Z x lab age (per decade): b=" %8.4f `b_ga' " (se=" %7.4f `se_ga' ///
                ") t=" %6.3f `t_ga' " p=" %6.4f `p_ga' " (one-sided " %6.4f `p_ga1' ")"
        }
    }

    cap drop yc_yl oc_ol oc_yl yc_ol
    gen byte yc_yl = (young_any == 1 & young == 1) if !mi(young_any) & !mi(young)
    gen byte oc_ol = (young_any == 0 & young == 0) if !mi(young_any) & !mi(young)
    gen byte oc_yl = (young_any == 0 & young == 1) if !mi(young_any) & !mi(young)
    gen byte yc_ol = (young_any == 1 & young == 0) if !mi(young_any) & !mi(young)
    foreach c in yc_yl oc_ol oc_yl yc_ol {
        qui count if athr_indicator == 1 & `c' == 1
        di as text "  cell `c': " r(N) " PIs"
    }
    foreach yvar in ppr_cnt {
        foreach c in yc_yl oc_ol oc_yl yc_ol {
            cap drop Z_`c' S_`c' PT_`c'
            gen Z_`c'  = Z_it       * `c'
            gen S_`c'  = Z_share_it * `c'
            gen PT_`c' = post       * `c'
        }
        cap noi ppmlhdfe `yvar' Z_yc_yl Z_oc_ol Z_oc_yl Z_yc_ol ///
                                S_yc_yl S_oc_ol S_oc_yl S_yc_ol ///
                                PT_yc_yl PT_oc_yl PT_yc_ol, ///
            absorb(`fes') vce(cluster `vce_cl')
        local rc = _rc
        if `rc' {
            di as error "test_young_old`suf' `yvar' 2x2: ppml failed (rc=`rc'); skipping."
            continue
        }
        di as result _n "== all_jrnls`suf' `yvar' 2x2 career x lab age (N=" e(N) ") =="
        di as text "  young career, young lab : b=" %8.4f _b[Z_yc_yl] " (se=" %7.4f _se[Z_yc_yl] ")"
        di as text "  young career, OLD lab   : b=" %8.4f _b[Z_yc_ol] " (se=" %7.4f _se[Z_yc_ol] ")   <- gap 0"
        di as text "  OLD career, young lab   : b=" %8.4f _b[Z_oc_yl] " (se=" %7.4f _se[Z_oc_yl] ")   <- long apprenticeship"
        di as text "  OLD career, OLD lab     : b=" %8.4f _b[Z_oc_ol] " (se=" %7.4f _se[Z_oc_ol] ")"
        local clabs `" "career effect within young labs" "career effect within old labs" "lab effect within young careers" "lab effect within old careers" "unambiguous young vs old (switchers dropped)" "'
        local cvars `" "Z_yc_yl Z_oc_yl" "Z_yc_ol Z_oc_ol" "Z_yc_yl Z_yc_ol" "Z_oc_yl Z_oc_ol" "Z_yc_yl Z_oc_ol" "'
        forval k = 1/5 {
            local dtxt  : word `k' of `clabs'
            local dpair : word `k' of `cvars'
            local v1 : word 1 of `dpair'
            local v2 : word 2 of `dpair'
            cap noi lincom `v1' - `v2'
            if _rc continue
            local b_d  = r(estimate)
            local se_d = r(se)
            local p_d  = r(p)
            di as text "  `dtxt': b=" %8.4f `b_d' " (se=" %7.4f `se_d' ") p=" %6.4f `p_d'
        }
    }

    foreach yvar in ppr_cnt {
        cap drop lab_c car_c Z_lab Z_car S_lab S_car PT_lab PT_car
        qui sum lab_age if athr_indicator == 1, d
        local lab_mean = r(mean)
        qui sum career_age if athr_indicator == 1, d
        local car_mean = r(mean)
        gen lab_c  = (lab_age    - `lab_mean')/10
        gen car_c  = (career_age - `car_mean')/10
        gen Z_lab  = Z_it       * lab_c
        gen Z_car  = Z_it       * car_c
        gen S_lab  = Z_share_it * lab_c
        gen S_car  = Z_share_it * car_c
        gen PT_lab = post       * lab_c
        gen PT_car = post       * car_c

        cap noi ppmlhdfe `yvar' Z_it Z_lab Z_car Z_share_it S_lab S_car PT_lab PT_car, ///
            absorb(`fes') vce(cluster `vce_cl')
        local rc = _rc
        if `rc' {
            di as error "test_young_old`suf' `yvar' horse race: ppml failed (rc=`rc'); skipping."
            continue
        }
        local Nfit = e(N)
        local b_lab  = _b[Z_lab]
        local se_lab = _se[Z_lab]
        local b_car  = _b[Z_car]
        local se_car = _se[Z_car]
        local p_lab  = 2*normal(-abs(`b_lab'/`se_lab'))
        local p_car  = 2*normal(-abs(`b_car'/`se_car'))
        lincom Z_car - Z_lab
        local b_hr  = r(estimate)
        local se_hr = r(se)
        local p_hr  = r(p)
        lincom Z_lab + Z_car
        local b_cg  = r(estimate)
        local se_cg = r(se)
        local p_cg  = r(p)

        di as result _n "== all_jrnls`suf' `yvar' horse race: lab age vs career age (N=`Nfit') =="
        di as text "  Z x lab age    (per decade): b=" %8.4f `b_lab' " (se=" %7.4f `se_lab' ") p=" %6.4f `p_lab'
        di as text "  Z x career age (per decade): b=" %8.4f `b_car' " (se=" %7.4f `se_car' ") p=" %6.4f `p_car'
        di as text "  career - lab: b=" %8.4f `b_hr' " (se=" %7.4f `se_hr' ") p=" %6.4f `p_hr'
        di as text "  career age holding gap fixed: b=" %8.4f `b_cg' " (se=" %7.4f `se_cg' ") p=" %6.4f `p_cg'
        local b_gap = -`b_lab'
        di as text "  apprenticeship gap (per decade): b=" %8.4f `b_gap' " (se=" %7.4f `se_lab' ") p=" %6.4f `p_lab'
    }

    if "`split_rows'" != "" {
        matrix colnames SPLITS = b_young se_young b_old se_old b_diff se_diff p_diff p_1sided N
        matrix rownames SPLITS = `split_rows'
        di as result _n "== all_jrnls`suf' ppr_cnt: young - old summary across age splits =="
        matlist SPLITS, format(%9.4f) lines(oneline)
    }
}

log close
