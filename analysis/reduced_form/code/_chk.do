cap log close _all
log using _chk.log, replace text
foreach f in es_all_jrnls_r1_r2 es_all_jrnls_r1_r2_public {
    use ../output/prepped_samples/`f', clear
    qui gunique athr_id
    local na = r(unique)
    qui gunique inst_id
    local ni = r(unique)
    qui sum public
    di as text "`f': obs=" _N "  PIs=`na'  Insts=`ni'  mean(public)=" %5.3f r(mean)
    qui tab type
}
log close
