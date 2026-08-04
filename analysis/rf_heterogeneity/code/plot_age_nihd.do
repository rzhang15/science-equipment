* Standard-format PPML coefplots for the age x baseline-NIH-funding 2x2.
* Reads ../temp/age_nihd_results<suf>.dta (written by run_age_nihd.do);
* no regressions rerun.
set more off
clear all
set scheme modern
version 17

local samp  all_jrnls
local sufs  _r1_r2 _r1_r2_public
local yvars ppr_cnt cite_affl_wt

cap mkdir "../output/figures/`samp'"
cap mkdir "../output/figures/`samp'/coefplot_evavg"

foreach suf of local sufs {
    cap confirm file ../temp/age_nihd_results`suf'.dta
    if _rc {
        di as error "plot_age_nihd: ../temp/age_nihd_results`suf'.dta not found -- run run_age_nihd.do first; skipping."
        continue
    }
    foreach yvar of local yvars {
        use ../temp/age_nihd_results`suf', clear
        keep if yvar == "`yvar'" & split_type == "joint_agenih"
        gen double y_pos = .
        replace y_pos = 4.7 if grp == "y_hn"
        replace y_pos = 3.7 if grp == "y_ln"
        replace y_pos = 2   if grp == "o_hn"
        replace y_pos = 1   if grp == "o_ln"
        drop if mi(y_pos) | mi(post_b)
        if _N == 0 continue
        gen ub = post_b + 1.96*post_se
        gen lb = post_b - 1.96*post_se

        qui sum lb
        local xmin = floor(r(min)/0.5)*0.5
        qui sum ub
        local xmax = ceil(r(max)/0.5)*0.5

        tw rcap ub lb y_pos, horizontal lcolor(ebblue%70) msize(vsmall) || ///
           scatter y_pos post_b, mcolor(ebblue) msize(small) ///
           , xline(0, lcolor(gs10) lpattern(solid)) ///
             ylabel(4.7 `""Early-Career Scientists" "More NIH Funding at Baseline""' ///
                    3.7 `""Early-Career Scientists" "Less NIH Funding at Baseline""' ///
                    2   `""Late-Career Scientists" "More NIH Funding at Baseline""' ///
                    1   `""Late-Career Scientists" "Less NIH Funding at Baseline""', ///
                    angle(0) labsize(small) noticks nogrid) ///
             ytitle("") xtitle("Exposure x Post", size(small)) ///
             xlabel(`xmin'(0.5)`xmax', labsize(small)) ///
             legend(off) ///
             ysize(5) xsize(7) ///
             yscale(range(0.9 .)) ///
             plotregion(margin(l=zero r=zero b=zero t=vsmall))
        graph export "../output/figures/`samp'/coefplot_evavg/ppml_het_coefplot_`yvar'_joint_agenih`suf'.pdf", replace
        di as text "wrote ../output/figures/`samp'/coefplot_evavg/ppml_het_coefplot_`yvar'_joint_agenih`suf'.pdf"
    }
}
