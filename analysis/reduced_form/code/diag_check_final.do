use ../temp/es_all_jrnls_r1_r2_public, clear
gunique athr_id
di as result "Total unique athr_id in es_all_jrnls_r1_r2_public: " r(unique)
gunique athr_id if foia_athr == 1
di as result "  with foia_athr == 1: " r(unique)
gunique athr_id if foia_athr != 1
di as result "  with foia_athr != 1 (non-FOIA): " r(unique)
count if mi(foia_athr)
di as result "  rows with mi(foia_athr): " r(N)
sum foia_athr, d
