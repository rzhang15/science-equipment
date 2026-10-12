program nih_award_period_means
    * Called only for pooled NIH-dollar specifications. Keep the same eligible
    * PIs in both windows; no-award years are already zero in the annual panel.
    * Reject incomplete windows rather than averaging only observed/funded years.
    keep if !mi(nih_total_cost)
    assert inrange(year, 2010, 2019)
    assert nih_total_cost >= 0
    isid athr_id year
    assert post == (year >= 2014)
    quietly ds, has(type numeric)
    local numeric `r(varlist)'
    local exclude athr_id inst_id year post nih_total_cost
    local carry : list numeric - exclude
    collapse (sum) nih_total_cost (count) nih_period_years=year ///
             (firstnm) `carry' inst_id, by(athr_id post)
    assert nih_period_years == cond(post, 6, 4)
    bysort athr_id: assert _N == 2
    replace nih_total_cost = nih_total_cost / cond(post, 6, 4)
    * Existing FE code uses year; here it indexes the two periods.
    gen int year = cond(post, 2014, 2010)
    label var nih_total_cost "Mean annual NIH award dollars: FY2010-2013 / FY2014-2019"
    label var nih_period_years "Calendar years contributing to period mean"
end
