// 1) verify final FOIA count in the actual analysis dataset
use ../temp/es_all_jrnls_r1_r2_public, clear
gunique athr_id if foia_athr == 1
di as result "FINAL: FOIAs in es_all_jrnls_r1_r2_public = " r(unique)
gunique athr_id
di as result "FINAL: all PIs in es_all_jrnls_r1_r2_public = " r(unique)

// 2) same for top_jrnls
cap noi use ../temp/es_top_jrnls_r1_r2_public, clear
if _rc == 0 {
    gunique athr_id if foia_athr == 1
    di as result "FINAL: FOIAs in es_top_jrnls_r1_r2_public = " r(unique)
    gunique athr_id
    di as result "FINAL: all PIs in es_top_jrnls_r1_r2_public = " r(unique)
}

// 3) search for "204" upstream
foreach f in ../external/exposure/foia_author_text_final ///
             ../external/exposure/foia_author_text_final_dropped {
    cap noi import delimited "`f'.csv", clear varnames(1)
    if _rc == 0 {
        di as result "`f'.csv obs = " _N
        cap confirm var athr_id
        if _rc == 0 {
            gunique athr_id
            di as result "  unique athr_id = " r(unique)
        }
    }
}
