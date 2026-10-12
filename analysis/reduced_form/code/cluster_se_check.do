set more off
clear all
capture log close
version 17

use ../output/prepped_samples/es_all_jrnls_r1_r2, clear
gen post       = year >= 2014
gen Z_it       = exposure      * post
gen Z_share_it = mkt_spend_shr * post

mat cluster_se = J(3,3,.)
local row 0
foreach cl in athr_id cluster_30 inst_id {
    local ++row
    ppmlhdfe ppr_cnt Z_it Z_share_it, absorb(athr_id year) vce(cluster `cl')
    mat cluster_se[`row',1] = _b[Z_it]
    mat cluster_se[`row',2] = _se[Z_it]
    mat cluster_se[`row',3] = e(N_clust)
}
mat rownames cluster_se = athr_id cluster_30 inst_id
mat colnames cluster_se = b se n_clusters
mat list cluster_se, format(%9.4f)
