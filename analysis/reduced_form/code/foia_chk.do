use /n/holylabs/pakes_lab/Lab/sci_eq/analysis/reduced_form/temp/foia_decline_panel, clear
di "=== baseline ==="
ppmlhdfe ppr_cnt Z_it Z_share_it, absorb(athr_id year) vce(cluster athr_id)
di "=== drop min-exposure PI (Zuiderweg, -0.191) ==="
preserve
drop if exposure < -.15
ppmlhdfe ppr_cnt Z_it Z_share_it, absorb(athr_id year) vce(cluster athr_id)
restore
di "=== winsorize exposure at 5/95 ==="
preserve
egen tagw = tag(athr_id)
qui _pctile exposure if tagw==1, p(5 95)
local lo = r(r1)
local hi = r(r2)
gen expw = min(max(exposure,`lo'),`hi')
gen Zw = expw*post
ppmlhdfe ppr_cnt Zw Z_share_it, absorb(athr_id year) vce(cluster athr_id)
restore
di "=== no share control ==="
ppmlhdfe ppr_cnt Z_it, absorb(athr_id year) vce(cluster athr_id)
di "=== institution composition ==="
egen tag = tag(athr_id)
tab inst if tag==1, sort
