set more off
clear all
capture log close
program drop _all
set scheme modern
version 17

log using diag_nih_zeros.log, replace text

program main
    zeros_vs_grants
    missing_cost_raw
end

* Separates PI-years that are truly grantless from PI-years that have active
* grants but sum to $0 because total_cost is missing on every record.
program zeros_vs_grants
    foreach s in foia all {
        use ../output/nih_by_age_piyrs_`s', clear
        gen byte zero_amt = nih_amt == 0
        gen byte no_grant = nih_active == 0
        di as text "=== `s': zero amount vs no active grant (PI-years) ==="
        tab no_grant zero_amt, row
        qui count if zero_amt & !no_grant
        di as text "`s': PI-years with grants but \$0 = " r(N)
        if r(N) > 0 sum nih_active if zero_amt & !no_grant, d
    }
end

program missing_cost_raw
    use athr_id grant_id full_project_num fy total_cost ///
        using ../external/nih/nih_grants_by_athr_id, clear
    keep if inrange(fy, 2010, 2013)
    duplicates drop athr_id grant_id, force
    gen byte mi_cost = mi(total_cost)
    gen byte z_cost  = total_cost == 0
    di as text "=== raw project-FY records, FY2010-2013 ==="
    tab mi_cost
    tab z_cost
    gen byte multiproj = strpos(full_project_num, "P01") | ///
                         strpos(full_project_num, "U54") | ///
                         strpos(full_project_num, "P50")
    di as text "=== missing cost by multi-project award ==="
    tab multiproj mi_cost, row
end

main
log close
