set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries

global HT_SAMP "all_jrnls"
global HT_SUF  "_r1_r2"
global HT_YVAR "ppr_cnt"

program main
    local samp $HT_SAMP
    local suf  $HT_SUF
    local yvar $HT_YVAR
    local src ../output/tables/`samp'/phet_results`suf'.txt
    cap confirm file "`src'"
    if _rc {
        di as error "het_table: `src' not found -- run analysis.do first."
        exit 601
    }
    import delimited using "`src'", clear varnames(1) delimiter(tab) case(lower) stringcols(1 2 3 4)
    keep if yvar == "`yvar'" & spec == "mshrctrl" & inlist(split_type, "med_pi", "med_pi_diff")
    save ../temp/het_table_src`suf', replace

    local splits young young_surv y_longtrain young_any high_nihd r1 pub_inst hiw_tfnd hiw_lsf hiw_endow
    local g2_young        old
    local g2_young_surv   old_surv
    local g2_y_longtrain  y_shorttrain
    local g2_young_any    old_any
    local g2_high_nihd    low_nihd
    local g2_r1           r2
    local g2_pub_inst     priv_inst
    local g2_hiw_tfnd     low_tfnd
    local g2_hiw_lsf      low_lsf
    local g2_hiw_endow    low_endow

    local lbl_young        "Lab age"
    local lbl_young_surv   "Lab age, early-career survivors only"
    local lbl_y_longtrain  "Years from first article to first last-authored paper, early-career PIs only"
    local lbl_young_any    "Years since first publication"
    local lbl_high_nihd    "NIH funding at baseline"
    local lbl_r1           "Carnegie classification"
    local lbl_pub_inst     "Institution control"
    local lbl_hiw_tfnd     "Institutional R\&D funding"
    local lbl_hiw_lsf      "Institutional life sciences funding"
    local lbl_hiw_endow    "Institutional endowment"

    local cmp_young        "(early vs. late career)"
    local cmp_young_surv   "(early publishing in 2020--22 vs. late)"
    local cmp_y_longtrain  "(above vs. below median years as trainee)"
    local cmp_young_any    "(early vs. late career)"
    local cmp_high_nihd    "(above vs. below median)"
    local cmp_r1           "(R1 vs. R2)"
    local cmp_pub_inst     "(public vs. private)"
    local cmp_hiw_tfnd     "(above vs. below median)"
    local cmp_hiw_lsf      "(above vs. below median)"
    local cmp_hiw_endow    "(above vs. below median)"

    cap mkdir ../output/tables
    cap mkdir ../output/tables/`samp'
    local out ../output/tables/`samp'/het_splits_`yvar'`suf'.tex
    tempname fh
    file open `fh' using "`out'", write replace
    file write `fh' "\begin{table}[htbp]" _n
    file write `fh' "\centering" _n
    file write `fh' "\caption{Heterogeneity in the Output Effect}" _n
    file write `fh' "\label{tab:het_splits`suf'}" _n
    file write `fh' "\begin{tabular}{lcccc}" _n
    file write `fh' "\toprule" _n
    file write `fh' " & Group 1 & Group 2 & Difference & N \\" _n
    file write `fh' "\midrule" _n

    foreach g1 of local splits {
        local g2 `g2_`g1''
        use ../temp/het_table_src`suf', clear
        local ok 1
        foreach g in `g1' `g2' `g1'_diff {
            qui count if grp == "`g'"
            if r(N) != 1 {
                di as error "het_table: `g' missing from `src' -- row `lbl_`g1'' skipped."
                local ok 0
            }
        }
        if !`ok' continue
        local line_b  "`lbl_`g1''"
        local line_se "\quad \textit{`cmp_`g1''}"
        foreach g in `g1' `g2' `g1'_diff {
            qui sum post_b if grp == "`g'"
            local b = r(mean)
            qui sum post_se if grp == "`g'"
            local se = r(mean)
            local t  = abs(`b' / `se')
            local st = cond(`t' >= 2.576, "^{***}", cond(`t' >= 1.960, "^{**}", cond(`t' >= 1.645, "^{*}", "")))
            local b_s  : dis %6.3f `b'
            local se_s : dis %6.3f `se'
            local line_b  "`line_b' & $`b_s'`st'$"
            local line_se "`line_se' & ($`se_s'$)"
        }
        qui sum n if grp == "`g1'"
        local n_s : dis %9.0fc r(mean)
        file write `fh' "`line_b' & `n_s' \\" _n
        file write `fh' "`line_se' & \\" _n
        file write `fh' "\addlinespace" _n
    }

    file write `fh' "\bottomrule" _n
    file write `fh' "\end{tabular}" _n
    file write `fh' "\end{table}" _n
    file close `fh'
    di as text "wrote `out'"
end

main
