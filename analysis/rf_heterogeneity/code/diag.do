set more off
clear all
capture log close
set scheme modern
program drop _all
log using diag.log, replace

* Combined heterogeneity diagnostics. Two parts:
*   Part A: PI-level (LPM, R1/R2 composition, baseline productivity kdensity,
*           age dist by hi/lo institutional characteristic)
*   Part B: panel-level joint 2x2 pooled-DiD PPML (young x hi_char) across
*           the reduced ic-char set, plus figures.
*
* PI-weighted median cutoffs by default. Set DIAG_INSTWTD 1 to also emit the
* inst-weighted variants alongside for comparison.
global DIAG_INSTWTD 0

* Reduced ic set (matches IC_ALIASES in analysis.do; keep in sync).
local ic_aliases tfnd lsf endow

* IC display labels (match `ic_lbl_*' in analysis.do; keep in sync).
local lbl_tfnd  "Total R&D Funding"
local lbl_lsf   "Life-Sci Funding"
local lbl_endow "Endowment"

* Loop over both samples: R1+R2 (public+private) and R1-only (public+private).
* All output PDFs and tempfile paths get the sample suffix appended.
foreach samp_suf in _r1_r2 _r1 {
di as text _n(3) "============================================================" ///
    _n "=== SAMPLE: `samp_suf'"                                                 ///
    _n "============================================================" _n

use ../temp/es_all_jrnls`samp_suf', clear
qui gunique athr_id
di as text "Unique PIs in panel = " r(unique)

* Baseline grants-per-paper: pre-period NIH grants active per year (pre_nihg,
* built in add_het_splits) over pre-period papers per year. Dropped from the
* LPMs when either input is unavailable.
local gppv
cap drop pre_gpp
cap confirm variable pre_nihg
local rc_g = _rc
cap confirm variable pre_ppr_cnt_avg
local rc_p = _rc
if `rc_g' == 0 & `rc_p' == 0 {
    gen double pre_gpp = pre_nihg / pre_ppr_cnt_avg if pre_ppr_cnt_avg > 0 & !mi(pre_ppr_cnt_avg)
    local gppv pre_gpp
}
else di as error "diag `samp_suf': pre_nihg or pre_ppr_cnt_avg missing -- pre_gpp SKIPPED in tabstat/LPMs."

* ============================================================
* Part A: PI-level diagnostics (preserve for the joint 2x2 in Part B)
* ============================================================
preserve
keep if athr_indicator == 1
qui count
di as text _n "Unique PIs after athr_indicator filter = " r(N)

* --- A1: R1 x young cross-tab + bar chart + age histogram by R1 ---
di as text _n(2) "=== R1 x young cross-tab ==="
tabulate r1 young, row col

qui count if r1 == 1
local n_r1 = r(N)
qui count if r1 == 0
local n_r2 = r(N)

graph bar (mean) young, ///
    over(r1, relabel(1 `"R2 (N=`n_r2')"' 2 `"R1 (N=`n_r1')"')) ///
    ytitle("Share Early-Career") bar(1, color(ebblue)) ///
    blabel(bar, format(%4.3f) size(medium)) ///
    plotregion(margin(sides))
graph export ../output/figures/all_jrnls/diag_share_young_by_r1`samp_suf'.pdf, replace

tw histogram age_2014 if r1 == 1, freq lcolor(ebblue) fcolor(ebblue%30) width(2) || ///
   histogram age_2014 if r1 == 0, freq lcolor(dkorange) fcolor(dkorange%30) width(2) ///
   , xtitle("Age in 2014") ytitle("Frequency") ///
     legend(order(1 "R1 (N=`n_r1')" 2 "R2 (N=`n_r2')") pos(2) ring(0) rows(2) size(small)) ///
     plotregion(margin(sides))
graph export ../output/figures/all_jrnls/diag_age_hist_by_r1`samp_suf'.pdf, replace

* --- A2: baseline productivity kdensity (young vs old) ---
* Total pre-period papers and papers per pre-period year.
qui count if young == 1
local n_y = r(N)
qui count if young == 0
local n_o = r(N)
local prod_src    pre_ppr_cnt_sum pre_ppr_cnt_avg
local prod_alias  ppr_tot         ppr_yr
local lbl_ppr_tot "Total Papers"
local lbl_ppr_yr  "Papers per Year"
local fmt_ppr_tot %6.1f
local fmt_ppr_yr  %5.2f
forvalues i = 1/2 {
    local src : word `i' of `prod_src'
    local a   : word `i' of `prod_alias'
    local xlbl "`lbl_`a''"
    local f   "`fmt_`a''"
    cap confirm variable `src'
    if _rc {
        di as error "diag `samp_suf': `src' not found -- `a' kdensity SKIPPED."
        continue
    }
    qui sum `src' if young == 1, d
    local mu_y = strtrim(string(r(mean), "`f'"))
    local md_y = strtrim(string(r(p50),  "`f'"))
    qui sum `src' if young == 0, d
    local mu_o = strtrim(string(r(mean), "`f'"))
    local md_o = strtrim(string(r(p50),  "`f'"))
    di as text "A2 `a': young mean=`mu_y' p50=`md_y' N=`n_y' | old mean=`mu_o' p50=`md_o' N=`n_o'"
    cap drop ln_pre_`a'
    gen double ln_pre_`a' = ln(1 + `src')
    * both densities on one common x grid so rarea can shade the gap
    qui sum ln_pre_`a'
    cap drop _kx _kd_y _kd_o _kd_c
    gen _kx = r(min) + (r(max) - r(min)) * (_n - 1) / 199 if _n <= 200
    kdensity ln_pre_`a' if young == 1, at(_kx) gen(_kd_y) nograph
    kdensity ln_pre_`a' if young == 0, at(_kx) gen(_kd_o) nograph
    gen _kd_c = min(_kd_y, _kd_o)
    tw (rarea _kd_c _kd_y _kx, color(ebblue*0.3) lwidth(none)) ///
       (rarea _kd_c _kd_o _kx, color(dkorange*0.3) lwidth(none)) ///
       (line _kd_y _kx, lcolor(ebblue) lwidth(medthick)) ///
       (line _kd_o _kx, lcolor(dkorange) lwidth(medthick)) ///
       , xtitle("ln(1 + Pre-Period `xlbl')") ///
         ytitle("Density") ///
         legend(order(3 "Early-Career (N=`n_y'): mean=`mu_y'" ///
                      4 "Late-Career (N=`n_o'): mean=`mu_o'") ///
                pos(2) ring(0) rows(2) size(small)) ///
         plotregion(margin(sides))
    graph export ../output/figures/all_jrnls/diag_kd_pre_`a'_ln`samp_suf'.pdf, replace
    cap drop _kx _kd_y _kd_o _kd_c
}

* --- A3: LPM of young on characteristics ---
di as text _n(2) "=== Characteristic means by young / old ==="
tabstat pre_ppr_cnt_sum `gppv' pre_team_avg pre_coauth_avg ///
        age_2014 msa_size_at r1 ic_tfnd ic_fedf ic_endow, ///
        by(young) stats(mean sd n) col(stats)

* Direct test: are young PIs different on baseline productivity / coauthors /
* team size / grants-per-paper? Regress each char on the young dummy. Positive
* young coef = young PIs have MORE of that char; negative = LESS.
di as text _n(2) "=== Char ~ young (per-char reversed regression, cluster inst_id) ==="
foreach c in pre_ppr_cnt_sum pre_coauth_avg pre_team_avg `gppv' msa_size_at {
    di as text _n "--- reg `c' young, vce(cluster inst_id) ---"
    reg `c' young, vce(cluster inst_id)
}
foreach a of local ic_aliases {
    cap confirm variable ic_`a'
    if _rc continue
    di as text _n "--- reg ic_`a' young, vce(cluster inst_id) ---"
    reg ic_`a' young, vce(cluster inst_id)
}

* Standardize PI-level and ic vars so coefficients are directly comparable.
foreach v of varlist pre_ppr_cnt_sum `gppv' pre_team_avg pre_coauth_avg ///
                     msa_size_at {
    qui sum `v'
    gen double z_`v' = (`v' - r(mean)) / r(sd)
}
local z_gppv = cond("`gppv'" == "", "", "z_`gppv'")
foreach a of local ic_aliases {
    cap confirm variable ic_`a'
    if _rc continue
    qui sum ic_`a'
    gen double z_ic_`a' = (ic_`a' - r(mean)) / r(sd)
}

* Per-char LPMs: one regression per ic char so each uses its own max sample
* (PIs missing that specific ic char drop; PIs with other missing chars stay).
di as text _n "--- Per-char LPMs of young on standardized chars ---"
foreach a of local ic_aliases {
    cap confirm variable z_ic_`a'
    if _rc continue
    qui count if !mi(z_ic_`a')
    di as text _n "-- young ~ PI chars + z_ic_`a' (N with z_ic_`a' non-mi = " r(N) ") --"
    reg young z_pre_ppr_cnt_sum `z_gppv' z_pre_team_avg z_pre_coauth_avg ///
              z_msa_size_at r1 z_ic_`a', vce(cluster inst_id)
    di as text _n "-- same, R1 only --"
    reg young z_pre_ppr_cnt_sum `z_gppv' z_pre_team_avg z_pre_coauth_avg ///
              z_msa_size_at z_ic_`a' if r1 == 1, vce(cluster inst_id)
}

* Kitchen-sink LPM using all standardized ic chars (subset with all non-missing).
di as text _n "--- Kitchen-sink LPM: all 8 ic chars simultaneously (common sample) ---"
local all_z
foreach a of local ic_aliases {
    cap confirm variable z_ic_`a'
    if !_rc local all_z `all_z' z_ic_`a'
}
reg young z_pre_ppr_cnt_sum `z_gppv' z_pre_team_avg z_pre_coauth_avg ///
          z_msa_size_at r1 `all_z', vce(cluster inst_id)

* --- A4a: Age distribution by hi/lo baseline productivity ---
* Tests whether "high_pre_ppr" is secretly an age proxy.
local pi_split_specs `" "high_pre_ppr Baseline_Productivity" "'
foreach spec of local pi_split_specs {
    tokenize `"`spec'"'
    local dvar `1'
    local dlbl_raw `2'
    local dlbl : subinstr local dlbl_raw "_" " ", all
    cap confirm variable `dvar'
    if _rc continue
    qui count if `dvar' == 1
    local n_hi = r(N)
    qui count if `dvar' == 0 & !mi(`dvar')
    local n_lo = r(N)
    qui sum age_2014 if `dvar' == 1
    local mu_hi : dis %5.1f r(mean)
    qui sum age_2014 if `dvar' == 0
    local mu_lo : dis %5.1f r(mean)
    qui sum young if `dvar' == 1
    local sh_yh : dis %4.2f r(mean)
    qui sum young if `dvar' == 0
    local sh_yl : dis %4.2f r(mean)
    tw kdensity age_2014 if `dvar' == 1, lcolor(ebblue) lwidth(medthick) || ///
       kdensity age_2014 if `dvar' == 0, lcolor(dkorange) lwidth(medthick) ///
       , xtitle("Age in 2014") ytitle("Density") ///
         subtitle("`dlbl' split (share early-career: Hi=`sh_yh', Lo=`sh_yl')", size(small)) ///
         legend(order(1 "High `dlbl' (N=`n_hi', mean=`mu_hi')" ///
                      2 "Low `dlbl' (N=`n_lo', mean=`mu_lo')") ///
                pos(6) ring(1) rows(1) size(small)) ///
         plotregion(margin(sides))
    graph export ../output/figures/all_jrnls/diag_age_dist_by_`dvar'`samp_suf'.pdf, replace
    di as text _n "-- age composition by `dvar' --" ///
        _n "  High `dlbl': N=`n_hi' mean_age=`mu_hi' share_young=`sh_yh'" ///
        _n "  Low  `dlbl': N=`n_lo' mean_age=`mu_lo' share_young=`sh_yl'"
}

* --- A4: Age distribution by hi/lo institutions (per char) ---
local wt_list piwtd
if "$DIAG_INSTWTD" == "1" local wt_list instwtd piwtd
foreach wt of local wt_list {
    if "`wt'" == "instwtd" {
        local hi hi
        local wt_lbl "inst-wtd median"
    }
    else {
        local hi hiw
        local wt_lbl "PI-wtd median"
    }
    foreach a of local ic_aliases {
        cap confirm variable `hi'_`a'
        if _rc continue
        qui count if `hi'_`a' == 1
        local n_hi = r(N)
        qui count if `hi'_`a' == 0 & !mi(`hi'_`a')
        local n_lo = r(N)
        qui sum age_2014 if `hi'_`a' == 1
        local mu_hi : dis %5.1f r(mean)
        qui sum age_2014 if `hi'_`a' == 0
        local mu_lo : dis %5.1f r(mean)
        tw kdensity age_2014 if `hi'_`a' == 1, lcolor(ebblue) lwidth(medthick) || ///
           kdensity age_2014 if `hi'_`a' == 0, lcolor(dkorange) lwidth(medthick) ///
           , xtitle("Age in 2014") ytitle("Density") ///
             subtitle("Cutoff: `wt_lbl' of ic_`a'", size(small)) ///
             legend(order(1 "Hi `a' (N=`n_hi', mean=`mu_hi')" ///
                          2 "Lo `a' (N=`n_lo', mean=`mu_lo')") ///
                    pos(2) ring(0) rows(2) size(small)) ///
             plotregion(margin(sides))
        graph export ../output/figures/all_jrnls/diag_age_dist_by_`a'_`wt'`samp_suf'.pdf, replace
    }
}

* --- A4b: Baseline-productivity distribution by hi/lo institutions (per char) ---
* Are HP PIs concentrated at hi-resource institutions? If so, "HP x hi" isn't
* a distinct cell -- it's mostly a relabeling of the HP margin.
foreach wt of local wt_list {
    if "`wt'" == "instwtd" {
        local hi hi
        local wt_lbl "inst-wtd median"
    }
    else {
        local hi hiw
        local wt_lbl "PI-wtd median"
    }
    foreach a of local ic_aliases {
        cap confirm variable `hi'_`a'
        if _rc continue
        qui count if `hi'_`a' == 1
        local n_hi = r(N)
        qui count if `hi'_`a' == 0 & !mi(`hi'_`a')
        local n_lo = r(N)
        qui sum pre_ppr_cnt_sum if `hi'_`a' == 1
        local mu_hi : dis %5.1f r(mean)
        qui sum pre_ppr_cnt_sum if `hi'_`a' == 0
        local mu_lo : dis %5.1f r(mean)
        qui sum high_pre_ppr if `hi'_`a' == 1
        local sh_hph : dis %4.2f r(mean)
        qui sum high_pre_ppr if `hi'_`a' == 0
        local sh_hpl : dis %4.2f r(mean)
        tw kdensity ln_pre_ppr_tot if `hi'_`a' == 1, lcolor(ebblue) lwidth(medthick) || ///
           kdensity ln_pre_ppr_tot if `hi'_`a' == 0, lcolor(dkorange) lwidth(medthick) ///
           , xtitle("ln(1 + Pre-Period Paper Count, 2009-2013)") ytitle("Density") ///
             subtitle("Cutoff: `wt_lbl' of ic_`a' (share HP: Hi=`sh_hph', Lo=`sh_hpl')", size(small)) ///
             legend(order(1 "Hi `a' (N=`n_hi', mean=`mu_hi')" ///
                          2 "Lo `a' (N=`n_lo', mean=`mu_lo')") ///
                    pos(2) ring(0) rows(2) size(small)) ///
             plotregion(margin(sides))
        graph export ../output/figures/all_jrnls/diag_pre_ppr_dist_by_`a'_`wt'`samp_suf'.pdf, replace
        di as text _n "-- pre_ppr by `hi'_`a' (`wt') --" ///
            _n "  Hi `a': N=`n_hi' mean_prppr=`mu_hi' share_HP=`sh_hph'" ///
            _n "  Lo `a': N=`n_lo' mean_prppr=`mu_lo' share_HP=`sh_hpl'"
    }
}

* --- A5: Exposure distribution across the 4 productivity × inst-char cells ---
* Tests whether HP × hi_char PIs simply live at higher exposure than the other
* three cells (confound with capacity × input-class story). One kdensity + one
* summary log-block per inst char. PI-wtd hiw_<a> cutoff.
cap confirm variable exposure
if !_rc {
    di as text _n(2) "=== Exposure distribution by high_pre_ppr x hiw_<char> ==="
    foreach a of local ic_aliases {
        cap confirm variable hiw_`a'
        if _rc continue
        cap drop _cell
        gen byte _cell = .
        replace _cell = 1 if high_pre_ppr == 1 & hiw_`a' == 1
        replace _cell = 2 if high_pre_ppr == 1 & hiw_`a' == 0
        replace _cell = 3 if high_pre_ppr == 0 & hiw_`a' == 1
        replace _cell = 4 if high_pre_ppr == 0 & hiw_`a' == 0

        forvalues c = 1/4 {
            qui sum exposure if _cell == `c', d
            local n_`c' = r(N)
            local mu_`c' : dis %5.3f r(mean)
            local p50_`c' : dis %5.3f r(p50)
            local p90_`c' : dis %5.3f r(p90)
        }

        tw kdensity exposure if _cell == 1, lcolor(ebblue) lwidth(medthick) || ///
           kdensity exposure if _cell == 2, lcolor(ebblue%50) lwidth(medthick) lpattern(dash) || ///
           kdensity exposure if _cell == 3, lcolor(dkorange) lwidth(medthick) || ///
           kdensity exposure if _cell == 4, lcolor(dkorange%50) lwidth(medthick) lpattern(dash) ///
           , xtitle("Exposure") ytitle("Density") ///
             subtitle("Cell composition on hiw_`a' x high_pre_ppr", size(small)) ///
             legend(order(1 "HP x Hi `a' (N=`n_1', mean=`mu_1')" ///
                          2 "HP x Lo `a' (N=`n_2', mean=`mu_2')" ///
                          3 "LP x Hi `a' (N=`n_3', mean=`mu_3')" ///
                          4 "LP x Lo `a' (N=`n_4', mean=`mu_4')") ///
                    pos(6) ring(1) rows(2) span size(vsmall)) ///
             plotregion(margin(sides))
        graph export ../output/figures/all_jrnls/diag_exposure_dist_by_`a'`samp_suf'.pdf, replace

        di as text _n "-- exposure by prppr x hiw_`a' --" ///
            _n "  HP x Hi:  N=`n_1' mean=`mu_1' p50=`p50_1' p90=`p90_1'" ///
            _n "  HP x Lo:  N=`n_2' mean=`mu_2' p50=`p50_2' p90=`p90_2'" ///
            _n "  LP x Hi:  N=`n_3' mean=`mu_3' p50=`p50_3' p90=`p90_3'" ///
            _n "  LP x Lo:  N=`n_4' mean=`mu_4' p50=`p50_4' p90=`p90_4'"
        drop _cell
    }
}
else di as error "diag A5: exposure variable not found; skipping."

restore

* --- A6: Institution-level distribution of AVG papers PER YEAR, split by hiw_tfnd ---
* For each institution, sum ppr_cnt across PIs by year, then average across
* years so we get one number per institution (avg annual paper output),
* independent of how many years each inst is observed. Compare log(1+.) across
* hi_tfnd vs lo_tfnd institutions.
preserve
cap confirm variable hiw_tfnd
if !_rc {
    gcollapse (sum) ppr_cnt (mean) hiw_tfnd ic_tfnd, by(inst_id year)
    gcollapse (mean) ppr_cnt (mean) hiw_tfnd ic_tfnd, by(inst_id)
    drop if mi(hiw_tfnd)
    gen double ln_ppr = ln(1 + ppr_cnt)

    qui count if hiw_tfnd == 1
    local n_hi = r(N)
    qui count if hiw_tfnd == 0
    local n_lo = r(N)
    qui sum ppr_cnt if hiw_tfnd == 1
    local mu_hi : dis %8.1fc r(mean)
    qui sum ppr_cnt if hiw_tfnd == 0
    local mu_lo : dis %8.1fc r(mean)

    tw kdensity ln_ppr if hiw_tfnd == 1, lcolor(ebblue) lwidth(medthick) || ///
       kdensity ln_ppr if hiw_tfnd == 0, lcolor(dkorange) lwidth(medthick) ///
       , xtitle("ln(1 + Avg Papers per Year at Institution)") ytitle("Density") ///
         legend(order(1 "Hi Total R&D (N=`n_hi', mean=`mu_hi'/yr)" ///
                      2 "Lo Total R&D (N=`n_lo', mean=`mu_lo'/yr)") ///
                pos(6) ring(1) rows(1) span size(small)) ///
         plotregion(margin(sides))
    graph export ../output/figures/all_jrnls/diag_kd_ln_ppr_per_yr_by_hiw_tfnd`samp_suf'.pdf, replace
    di as text _n "-- inst-level avg papers per year by hiw_tfnd --" ///
        _n "  Hi tfnd: N=`n_hi' mean=`mu_hi'/yr" ///
        _n "  Lo tfnd: N=`n_lo' mean=`mu_lo'/yr"
}
else di as error "diag A6: hiw_tfnd not found; skipping."
restore

* ============================================================
* Part B: Joint 2x2 pooled-DiD PPML across ic chars
* ============================================================
gen post       = year >= 2014
gen Z_it       = exposure      * post
gen Z_share_it = mkt_spend_shr * post

foreach wt of local wt_list {
    if "`wt'" == "instwtd" local hi hi
    else                    local hi hiw

    tempname res
    postfile `res' str8 alias ///
        double(n_yhi n_ylo n_ohi n_olo ///
               b_yhi se_yhi b_ylo se_ylo b_ohi se_ohi b_olo se_olo ///
               b_diff_hi se_diff_hi b_diff_ylo se_diff_ylo N ///
               b_yhi_ns se_yhi_ns b_ylo_ns se_ylo_ns b_ohi_ns se_ohi_ns b_olo_ns se_olo_ns) ///
        using ../temp/joint_split_`wt'_ppr_cnt`samp_suf'.dta, replace

    foreach a of local ic_aliases {
        cap confirm variable `hi'_`a'
        if _rc {
            di as text "SKIP `a' `wt' -- `hi'_`a' unavailable"
            continue
        }
        cap drop y_hi y_lo o_hi o_lo Z_y_hi Z_y_lo Z_o_hi Z_o_lo S_y_hi S_y_lo S_o_hi S_o_lo
        gen byte y_hi = (young == 1 & `hi'_`a' == 1) if !mi(young) & !mi(`hi'_`a')
        gen byte y_lo = (young == 1 & `hi'_`a' == 0) if !mi(young) & !mi(`hi'_`a')
        gen byte o_hi = (young == 0 & `hi'_`a' == 1) if !mi(young) & !mi(`hi'_`a')
        gen byte o_lo = (young == 0 & `hi'_`a' == 0) if !mi(young) & !mi(`hi'_`a')

        qui gunique athr_id if y_hi == 1
        local nyhi = r(unique)
        qui gunique athr_id if y_lo == 1
        local nylo = r(unique)
        qui gunique athr_id if o_hi == 1
        local nohi = r(unique)
        qui gunique athr_id if o_lo == 1
        local nolo = r(unique)

        if `nyhi' < 100 | `nylo' < 100 | `nohi' < 100 | `nolo' < 100 {
            di as text "SKIP `a' `wt' -- thin cell (`nyhi'/`nylo'/`nohi'/`nolo')"
            continue
        }

        gen Z_y_hi = Z_it       * y_hi
        gen Z_y_lo = Z_it       * y_lo
        gen Z_o_hi = Z_it       * o_hi
        gen Z_o_lo = Z_it       * o_lo
        gen S_y_hi = Z_share_it * y_hi
        gen S_y_lo = Z_share_it * y_lo
        gen S_o_hi = Z_share_it * o_hi
        gen S_o_lo = Z_share_it * o_lo

        cap noi qui ppmlhdfe ppr_cnt Z_y_hi Z_y_lo Z_o_hi Z_o_lo S_y_hi S_y_lo S_o_hi S_o_lo, ///
            absorb(athr_id year) vce(cluster athr_id)
        if _rc {
            di as error "FAIL `a' `wt' main -- rc=`_rc'"
            continue
        }
        local Nppml = e(N)
        local byhi  = _b[Z_y_hi]
        local seyhi = _se[Z_y_hi]
        local bylo  = _b[Z_y_lo]
        local seylo = _se[Z_y_lo]
        local bohi  = _b[Z_o_hi]
        local seohi = _se[Z_o_hi]
        local bolo  = _b[Z_o_lo]
        local seolo = _se[Z_o_lo]
        qui lincom Z_y_hi - Z_o_hi
        local bdh  = r(estimate)
        local sedh = r(se)
        qui lincom Z_y_hi - Z_y_lo
        local bdy  = r(estimate)
        local sedy = r(se)

        cap noi qui ppmlhdfe ppr_cnt Z_y_hi Z_y_lo Z_o_hi Z_o_lo, ///
            absorb(athr_id year) vce(cluster athr_id)
        local byhi_ns  = _b[Z_y_hi]
        local seyhi_ns = _se[Z_y_hi]
        local bylo_ns  = _b[Z_y_lo]
        local seylo_ns = _se[Z_y_lo]
        local bohi_ns  = _b[Z_o_hi]
        local seohi_ns = _se[Z_o_hi]
        local bolo_ns  = _b[Z_o_lo]
        local seolo_ns = _se[Z_o_lo]

        di as text "`a' `wt': y_hi=" %6.3f `byhi' " y_lo=" %6.3f `bylo' ///
                  " o_hi=" %6.3f `bohi' " o_lo=" %6.3f `bolo' ///
                  "  [no-S] o_lo=" %6.3f `bolo_ns' " (se=" %5.3f `seolo_ns' ")"

        post `res' ("`a'") (`nyhi') (`nylo') (`nohi') (`nolo') ///
            (`byhi') (`seyhi') (`bylo') (`seylo') ///
            (`bohi') (`seohi') (`bolo') (`seolo') ///
            (`bdh') (`sedh') (`bdy') (`sedy') (`Nppml') ///
            (`byhi_ns') (`seyhi_ns') (`bylo_ns') (`seylo_ns') ///
            (`bohi_ns') (`seohi_ns') (`bolo_ns') (`seolo_ns')
    }
    postclose `res'

    * ---- Figures for this weighting scheme ----
    preserve
    use ../temp/joint_split_`wt'_ppr_cnt`samp_suf'.dta, clear
    gen ub_yhi = b_yhi + 1.96*se_yhi
    gen lb_yhi = b_yhi - 1.96*se_yhi
    gen ub_ohi = b_ohi + 1.96*se_ohi
    gen lb_ohi = b_ohi - 1.96*se_ohi
    gen ub_ylo = b_ylo + 1.96*se_ylo
    gen lb_ylo = b_ylo - 1.96*se_ylo
    gen ub_olo = b_olo + 1.96*se_olo
    gen lb_olo = b_olo - 1.96*se_olo

    gsort b_diff_hi
    gen y_pos = _N + 1 - _n
    gen y_pos_off = y_pos - 0.2
    local ylabs
    forvalues i = 1/`=_N' {
        local aa = alias[`i']
        local pos = y_pos[`i']
        local ylabs `"`ylabs' `pos' "`aa'""'
    }
    local nrow = _N

    * Cross-char coefplot: Young x Hi vs Old x Hi
    tw rcap ub_yhi lb_yhi y_pos, horizontal lcolor(ebblue%60) msize(vsmall)     || ///
       scatter y_pos b_yhi, mcolor(ebblue) msize(small)                          || ///
       rcap ub_ohi lb_ohi y_pos_off, horizontal lcolor(dkorange%60) msize(vsmall)|| ///
       scatter y_pos_off b_ohi, mcolor(dkorange) msymbol(D) msize(small) ///
       , xline(0, lcolor(gs10) lpattern(solid)) ///
         ylabel(`ylabs', angle(0) labsize(small) noticks nogrid) ///
         ytitle("") xtitle("β on Exposure x Post (ppr_cnt)", size(small)) ///
         legend(order(2 "Early-Career x Hi" 4 "Late-Career x Hi") pos(11) ring(0) rows(2) size(small)) ///
         ysize(`=max(6, `nrow'*0.5)') xsize(7) ///
         plotregion(margin(sides))
    graph export ../output/figures/all_jrnls/diag_joint_`wt'_yhi_vs_ohi`samp_suf'.pdf, replace

    * All 4 cells overlaid, one row per char
    gen y_yhi = y_pos + 0.30
    gen y_ylo = y_pos + 0.10
    gen y_ohi = y_pos - 0.10
    gen y_olo = y_pos - 0.30
    tw rcap ub_yhi lb_yhi y_yhi, horizontal lcolor(ebblue%60) msize(vsmall)      || ///
       scatter y_yhi b_yhi, mcolor(ebblue) msize(small)                           || ///
       rcap ub_ylo lb_ylo y_ylo, horizontal lcolor(navy%60) msize(vsmall)         || ///
       scatter y_ylo b_ylo, mcolor(navy) msymbol(T) msize(small)                  || ///
       rcap ub_ohi lb_ohi y_ohi, horizontal lcolor(dkorange%60) msize(vsmall)     || ///
       scatter y_ohi b_ohi, mcolor(dkorange) msymbol(D) msize(small)              || ///
       rcap ub_olo lb_olo y_olo, horizontal lcolor(cranberry%60) msize(vsmall)    || ///
       scatter y_olo b_olo, mcolor(cranberry) msymbol(S) msize(small)             ///
       , xline(0, lcolor(gs10) lpattern(solid)) ///
         ylabel(`ylabs', angle(0) labsize(small) noticks nogrid) ///
         ytitle("") xtitle("β on Exposure x Post (ppr_cnt)", size(small)) ///
         legend(order(2 "Early-Career x Hi" 4 "Early-Career x Lo" 6 "Late-Career x Hi" 8 "Late-Career x Lo") ///
                pos(11) ring(0) rows(4) size(small)) ///
         ysize(`=max(6, `nrow'*0.7)') xsize(8) ///
         plotregion(margin(sides))
    graph export ../output/figures/all_jrnls/diag_joint_`wt'_4cells`samp_suf'.pdf, replace

    * Per-char 4-cell coefplot (paper-ready, one PDF per char).
    * Reloading results .dta each iteration to avoid nested preserve.
    foreach a of local ic_aliases {
        qui use ../temp/joint_split_`wt'_ppr_cnt`samp_suf'.dta, clear
        qui keep if alias == "`a'"
        if _N == 0 continue
        local byhi  = b_yhi[1]
        local seyhi = se_yhi[1]
        local bylo  = b_ylo[1]
        local seylo = se_ylo[1]
        local bohi  = b_ohi[1]
        local seohi = se_ohi[1]
        local bolo  = b_olo[1]
        local seolo = se_olo[1]
        local nyhi  = n_yhi[1]
        local nylo  = n_ylo[1]
        local nohi  = n_ohi[1]
        local nolo  = n_olo[1]
        clear
        set obs 4
        gen y  = 5 - _n
        gen b  = .
        gen se = .
        replace b  = `byhi'  if y == 4
        replace se = `seyhi' if y == 4
        replace b  = `bylo'  if y == 3
        replace se = `seylo' if y == 3
        replace b  = `bohi'  if y == 2
        replace se = `seohi' if y == 2
        replace b  = `bolo'  if y == 1
        replace se = `seolo' if y == 1
        gen ub = b + 1.96*se
        gen lb = b - 1.96*se

        tw rcap ub lb y if inlist(y, 4, 3), horizontal lcolor(ebblue%70) msize(vsmall)   || ///
           scatter y b if inlist(y, 4, 3), mcolor(ebblue) msize(medium)                   || ///
           rcap ub lb y if inlist(y, 2, 1), horizontal lcolor(dkorange%70) msize(vsmall) || ///
           scatter y b if inlist(y, 2, 1), mcolor(dkorange) msymbol(D) msize(medium)      ///
           , xline(0, lcolor(gs10) lpattern(solid)) ///
             ylabel(4 `"Early-Career × Hi (N=`nyhi')"' ///
                    3 `"Early-Career × Lo (N=`nylo')"' ///
                    2 `"Late-Career × Hi (N=`nohi')"'   ///
                    1 `"Late-Career × Lo (N=`nolo')"',  ///
                    angle(0) labsize(small) noticks nogrid) ///
             ytitle("") xtitle("Exposure x Post", size(small)) ///
             subtitle("Split on `hi'_`a'", size(small)) ///
             legend(order(2 "Early-Career" 4 "Late-Career") pos(11) ring(0) rows(2) size(small)) ///
             xsize(7) ysize(4) ///
             plotregion(margin(sides))
        graph export ../output/figures/all_jrnls/coef_age_x_`a'_`wt'`samp_suf'.pdf, replace
    }
    restore
}

* ============================================================
* Part C: prppr x inst-char joint 2x2 -- hypothesis tests for
* the "crossover" (LP x lo) cell.
*   1. Is LP x lo_char coefficient significantly < 0 alone?
*      If not, the crossover claim is not established.
*   2. Blue-vs-orange at Lo row: HP x Lo - LP x Lo = 0 ?
*      Tests whether HP differs from LP at low-intensity institutions.
*   3. Blue-vs-orange at Hi row: HP x Hi - LP x Hi = 0 ?
*   4. Triple interaction: (HP-LP)_Hi - (HP-LP)_Lo = 0 ?
* Uses analytical cluster-robust SEs on athr_id via lincom. If these p-values
* are non-significant, the wild-cluster bootstrap will not save them.
* ============================================================

di as text _n(2) "=== Part C: crossover-test lincoms per inst char (PI-wtd cutoff) ==="

foreach a of local ic_aliases {
    cap confirm variable hp_hi_`a'
    if _rc {
        di as error "  hp_hi_`a' not found; skipping."
        continue
    }
    foreach grp in hp_hi_`a' hp_lo_`a' lp_hi_`a' lp_lo_`a' {
        cap drop Z_`grp' S_`grp'
        gen Z_`grp' = Z_it       * `grp'
        gen S_`grp' = Z_share_it * `grp'
    }
    cap noi qui ppmlhdfe ppr_cnt Z_hp_hi_`a' Z_hp_lo_`a' Z_lp_hi_`a' Z_lp_lo_`a' ///
                                 S_hp_hi_`a' S_hp_lo_`a' S_lp_hi_`a' S_lp_lo_`a', ///
                                 absorb(athr_id year) vce(cluster athr_id)
    if _rc {
        di as error "  ppmlhdfe failed for `a'; skipping."
        continue
    }

    di as text _n "-- `a' --"
    di as text "  H0: LP x Lo = 0    (is the crossover cell itself significant?)"
    qui lincom Z_lp_lo_`a'
    local b1 = r(estimate)
    local se1 = r(se)
    local t1 = `b1'/`se1'
    local p1 = 2*ttail(1e9, abs(`t1'))
    di as text "    b=" %8.4f `b1' "  se=" %6.4f `se1' "  t=" %6.2f `t1' "  p=" %5.3f `p1'

    di as text "  H0: HP x Lo - LP x Lo = 0    (blue-vs-orange at Lo row)"
    qui lincom Z_hp_lo_`a' - Z_lp_lo_`a'
    local b2 = r(estimate)
    local se2 = r(se)
    local t2 = `b2'/`se2'
    local p2 = 2*ttail(1e9, abs(`t2'))
    di as text "    b=" %8.4f `b2' "  se=" %6.4f `se2' "  t=" %6.2f `t2' "  p=" %5.3f `p2'

    di as text "  H0: HP x Hi - LP x Hi = 0    (blue-vs-orange at Hi row)"
    qui lincom Z_hp_hi_`a' - Z_lp_hi_`a'
    local b3 = r(estimate)
    local se3 = r(se)
    local t3 = `b3'/`se3'
    local p3 = 2*ttail(1e9, abs(`t3'))
    di as text "    b=" %8.4f `b3' "  se=" %6.4f `se3' "  t=" %6.2f `t3' "  p=" %5.3f `p3'

    di as text "  H0: (HP-LP)_Hi - (HP-LP)_Lo = 0    (triple interaction)"
    qui lincom (Z_hp_hi_`a' - Z_lp_hi_`a') - (Z_hp_lo_`a' - Z_lp_lo_`a')
    local b4 = r(estimate)
    local se4 = r(se)
    local t4 = `b4'/`se4'
    local p4 = 2*ttail(1e9, abs(`t4'))
    di as text "    b=" %8.4f `b4' "  se=" %6.4f `se4' "  t=" %6.2f `t4' "  p=" %5.3f `p4'
}

* ============================================================
* Part D: prppr x age x inst-char joint 8-cell pooled-DiD PPML.
* y-axis has Hi/Lo <char> rows (as in the joint_ae_prppr paired
* coefplot); each row carries 4 dots -- LP x young, LP x old,
* HP x young, HP x old -- from a single 8-way interaction fit.
* ============================================================
di as text _n(2) "=== Part D: prppr x age x inst-char 8-cell PPML (PI-wtd cutoff) ==="

tempname resD
postfile `resD' str8 alias ///
    double(n_yhphi n_ylphi n_ohphi n_olphi n_yhplo n_ylplo n_ohplo n_olplo ///
           b_yhphi se_yhphi b_ylphi se_ylphi b_ohphi se_ohphi b_olphi se_olphi ///
           b_yhplo se_yhplo b_ylplo se_ylplo b_ohplo se_ohplo b_olplo se_olplo ///
           N) ///
    using ../temp/joint_split_piwtd_prppr_age_ppr_cnt`samp_suf'.dta, replace

foreach a of local ic_aliases {
    cap confirm variable hiw_`a'
    if _rc {
        di as text "SKIP `a' -- hiw_`a' unavailable"
        continue
    }
    foreach cell in yhphi ylphi ohphi olphi yhplo ylplo ohplo olplo {
        cap drop _`cell' Z_`cell' S_`cell'
    }
    gen byte _yhphi = (young == 1 & high_pre_ppr == 1 & hiw_`a' == 1) if !mi(young) & !mi(high_pre_ppr) & !mi(hiw_`a')
    gen byte _ylphi = (young == 1 & high_pre_ppr == 0 & hiw_`a' == 1) if !mi(young) & !mi(high_pre_ppr) & !mi(hiw_`a')
    gen byte _ohphi = (young == 0 & high_pre_ppr == 1 & hiw_`a' == 1) if !mi(young) & !mi(high_pre_ppr) & !mi(hiw_`a')
    gen byte _olphi = (young == 0 & high_pre_ppr == 0 & hiw_`a' == 1) if !mi(young) & !mi(high_pre_ppr) & !mi(hiw_`a')
    gen byte _yhplo = (young == 1 & high_pre_ppr == 1 & hiw_`a' == 0) if !mi(young) & !mi(high_pre_ppr) & !mi(hiw_`a')
    gen byte _ylplo = (young == 1 & high_pre_ppr == 0 & hiw_`a' == 0) if !mi(young) & !mi(high_pre_ppr) & !mi(hiw_`a')
    gen byte _ohplo = (young == 0 & high_pre_ppr == 1 & hiw_`a' == 0) if !mi(young) & !mi(high_pre_ppr) & !mi(hiw_`a')
    gen byte _olplo = (young == 0 & high_pre_ppr == 0 & hiw_`a' == 0) if !mi(young) & !mi(high_pre_ppr) & !mi(hiw_`a')

    local skip 0
    foreach cell in yhphi ylphi ohphi olphi yhplo ylplo ohplo olplo {
        qui gunique athr_id if _`cell' == 1
        local n_`cell' = r(unique)
        if `n_`cell'' < 30 local skip 1
    }
    if `skip' {
        di as text "SKIP `a' -- thin cell " ///
            "(y_hp_hi=`n_yhphi' y_lp_hi=`n_ylphi' o_hp_hi=`n_ohphi' o_lp_hi=`n_olphi' " ///
            "y_hp_lo=`n_yhplo' y_lp_lo=`n_ylplo' o_hp_lo=`n_ohplo' o_lp_lo=`n_olplo')"
        continue
    }

    foreach cell in yhphi ylphi ohphi olphi yhplo ylplo ohplo olplo {
        gen Z_`cell' = Z_it       * _`cell'
        gen S_`cell' = Z_share_it * _`cell'
    }

    cap noi qui ppmlhdfe ppr_cnt Z_yhphi Z_ylphi Z_ohphi Z_olphi ///
                                  Z_yhplo Z_ylplo Z_ohplo Z_olplo ///
                                  S_yhphi S_ylphi S_ohphi S_olphi ///
                                  S_yhplo S_ylplo S_ohplo S_olplo, ///
                                  absorb(athr_id year) vce(cluster athr_id)
    if _rc {
        di as error "FAIL `a' 8-cell ppml (rc=`_rc'); skipping."
        continue
    }
    local Nppml = e(N)
    foreach cell in yhphi ylphi ohphi olphi yhplo ylplo ohplo olplo {
        local b_`cell'  = _b[Z_`cell']
        local se_`cell' = _se[Z_`cell']
    }

    di as text "`a': [Hi `a'] y_hp=" %6.3f `b_yhphi' " y_lp=" %6.3f `b_ylphi' ///
              " o_hp=" %6.3f `b_ohphi' " o_lp=" %6.3f `b_olphi' _n ///
              _col(11) "[Lo `a'] y_hp=" %6.3f `b_yhplo' " y_lp=" %6.3f `b_ylplo' ///
              " o_hp=" %6.3f `b_ohplo' " o_lp=" %6.3f `b_olplo'

    post `resD' ("`a'") ///
        (`n_yhphi') (`n_ylphi') (`n_ohphi') (`n_olphi') ///
        (`n_yhplo') (`n_ylplo') (`n_ohplo') (`n_olplo') ///
        (`b_yhphi') (`se_yhphi') (`b_ylphi') (`se_ylphi') ///
        (`b_ohphi') (`se_ohphi') (`b_olphi') (`se_olphi') ///
        (`b_yhplo') (`se_yhplo') (`b_ylplo') (`se_ylplo') ///
        (`b_ohplo') (`se_ohplo') (`b_olplo') (`se_olplo') ///
        (`Nppml')
}
postclose `resD'

preserve
use ../temp/joint_split_piwtd_prppr_age_ppr_cnt`samp_suf'.dta, clear
if _N == 0 {
    di as error "Part D: no rows in joint_split_piwtd_prppr_age file; skipping plot."
}
else {
    gen char_idx = _n
    qui sum char_idx
    local nchars = r(max)
    gen double y_group = (`nchars' + 1 - char_idx) * 4.5

    expand 8
    sort char_idx
    by char_idx: gen combo_idx = _n

    gen double b_plot  = .
    gen double se_plot = .
    gen double y_plot  = .
    gen str3   series  = ""

    * Two side-by-side panels split by baseline productivity (HP left, LP right);
    * within each panel Young is blue and Old is orange, offset ±0.25 within
    * each Hi/Lo row (young above, old below).
    replace b_plot = b_yhphi   if combo_idx == 1
    replace se_plot = se_yhphi if combo_idx == 1
    replace y_plot = y_group + 1.2 + 0.25 if combo_idx == 1
    replace series = "yHP"     if combo_idx == 1

    replace b_plot = b_ohphi   if combo_idx == 2
    replace se_plot = se_ohphi if combo_idx == 2
    replace y_plot = y_group + 1.2 - 0.25 if combo_idx == 2
    replace series = "oHP"     if combo_idx == 2

    replace b_plot = b_ylphi   if combo_idx == 3
    replace se_plot = se_ylphi if combo_idx == 3
    replace y_plot = y_group + 1.2 + 0.25 if combo_idx == 3
    replace series = "yLP"     if combo_idx == 3

    replace b_plot = b_olphi   if combo_idx == 4
    replace se_plot = se_olphi if combo_idx == 4
    replace y_plot = y_group + 1.2 - 0.25 if combo_idx == 4
    replace series = "oLP"     if combo_idx == 4

    replace b_plot = b_yhplo   if combo_idx == 5
    replace se_plot = se_yhplo if combo_idx == 5
    replace y_plot = y_group - 1.2 + 0.25 if combo_idx == 5
    replace series = "yHP"     if combo_idx == 5

    replace b_plot = b_ohplo   if combo_idx == 6
    replace se_plot = se_ohplo if combo_idx == 6
    replace y_plot = y_group - 1.2 - 0.25 if combo_idx == 6
    replace series = "oHP"     if combo_idx == 6

    replace b_plot = b_ylplo   if combo_idx == 7
    replace se_plot = se_ylplo if combo_idx == 7
    replace y_plot = y_group - 1.2 + 0.25 if combo_idx == 7
    replace series = "yLP"     if combo_idx == 7

    replace b_plot = b_olplo   if combo_idx == 8
    replace se_plot = se_olplo if combo_idx == 8
    replace y_plot = y_group - 1.2 - 0.25 if combo_idx == 8
    replace series = "oLP"     if combo_idx == 8

    gen double ub = b_plot + 1.96*se_plot
    gen double lb = b_plot - 1.96*se_plot

    local ylabs
    qui levelsof char_idx, local(cids)
    foreach cid of local cids {
        qui levelsof alias if char_idx == `cid' & combo_idx == 1, local(aa) clean
        local clbl = "`lbl_`aa''"
        if "`clbl'" == "" local clbl "`aa'"
        local base = (`nchars' + 1 - `cid') * 4.5
        local pos_hi = `base' + 1.2
        local pos_lo = `base' - 1.2
        local ylabs `"`ylabs' `pos_hi' "High `clbl'""'
        local ylabs `"`ylabs' `pos_lo' "Low `clbl'""'
    }

    qui sum lb
    local xmin = floor(r(min)/0.5)*0.5
    qui sum ub
    local xmax = ceil(r(max)/0.5)*0.5

    * Left panel: High Baseline Productivity PIs (Young blue, Old orange).
    tw rcap ub lb y_plot if series == "yHP", horizontal lcolor(ebblue%50) msize(vsmall)   || ///
       scatter y_plot b_plot if series == "yHP", mcolor(ebblue) msymbol(O) msize(small)   || ///
       rcap ub lb y_plot if series == "oHP", horizontal lcolor(dkorange%50) msize(vsmall) || ///
       scatter y_plot b_plot if series == "oHP", mcolor(dkorange) msymbol(O) msize(small)  ///
       , xline(0, lcolor(gs10) lpattern(solid)) ///
         ylabel(`ylabs', angle(0) labsize(small) noticks nogrid) ///
         ytitle("") xtitle("Exposure x Post", size(small)) ///
         xlabel(`xmin'(0.5)`xmax', labsize(small)) ///
         subtitle("High Baseline Productivity", size(small)) ///
         legend(off) ///
         yscale(range(3.04 .)) ///
         plotregion(margin(l=zero r=zero b=zero t=vsmall)) ///
         graphregion(margin(r=0)) ///
         name(g_hp, replace) nodraw

    * Right panel: Low Baseline Productivity PIs (Young blue, Old orange).
    * Invisible (white) y-labels reserve the same horizontal space as the left
    * panel so plot widths match; graphregion(margin(l=0)) pulls the reserved
    * strip flush to the cell edge to minimise the visible gap between panels.
    tw rcap ub lb y_plot if series == "yLP", horizontal lcolor(ebblue%50) msize(vsmall)   || ///
       scatter y_plot b_plot if series == "yLP", mcolor(ebblue) msymbol(O) msize(small)   || ///
       rcap ub lb y_plot if series == "oLP", horizontal lcolor(dkorange%50) msize(vsmall) || ///
       scatter y_plot b_plot if series == "oLP", mcolor(dkorange) msymbol(O) msize(small)  ///
       , xline(0, lcolor(gs10) lpattern(solid)) ///
         ylabel(`ylabs', angle(0) labsize(small) labcolor(white) noticks nogrid) ///
         ytitle("") xtitle("Exposure x Post", size(small)) ///
         xlabel(`xmin'(0.5)`xmax', labsize(small)) ///
         subtitle("Low Baseline Productivity", size(small)) ///
         legend(order(2 "Early-Career" 4 "Late-Career") ///
                pos(6) ring(1) rows(1) span size(small)) ///
         yscale(noline range(3.04 .)) ///
         plotregion(margin(l=zero r=zero b=zero t=vsmall)) ///
         graphregion(margin(l=0)) ///
         name(g_lp, replace) nodraw

    grc1leg g_hp g_lp, ///
        cols(2) xcommon ycommon imargin(0 0 0 0) ///
        legendfrom(g_lp) position(6) ring(1) ///
        ysize(`=max(10, `nchars'*2.5)') xsize(12)
    graph export ../output/figures/all_jrnls/diag_joint_piwtd_prppr_age_8cells`samp_suf'.pdf, replace
    di as text "wrote diag_joint_piwtd_prppr_age_8cells.pdf"
}
restore

}  // close foreach samp_suf

log close
