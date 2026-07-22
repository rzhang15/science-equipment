set more off
clear all
capture log close
program drop _all
set scheme modern
version 17
set maxvar 120000

program main
    build_reporter
end

program build_reporter
    local keepvars pi_names project_start project_end total_cost ///
                   budget_start budget_end full_project_num fy ///
                   org_ipf_code org_name project_terms project_title

    forval y = 2010/2019 {
        import delimited using ../external/nih/RePORTER_PRJ_C_FY`y'.csv, ///
            varnames(1) bindquote(strict) stringcols(_all) encoding(utf8) clear
        keep `keepvars'
        destring total_cost fy org_ipf_code, replace force
        foreach v in project_start project_end budget_start budget_end {
            gen double `v'_d = date(`v', "YMD")
            format %td `v'_d
            drop `v'
            rename `v'_d `v'
        }
        save ../temp/reporter_`y', replace
    }

    clear
    save ../temp/reporter_2010_2019, replace emptyok
    forval y = 2010/2019 {
        append using ../temp/reporter_`y', force
    }
    save ../output/reporter_2010_2019, replace
end

main
