set more off
capture log close
log using diag_check_panel.log, replace text
use ../temp/es_all_jrnls_r1_r2_public.dta, clear
bys athr_id: gen _first = _n == 1
di as text "======= sample & exposure state ======="
count if _first == 1
sum exposure if _first == 1, d
di as text "  pos:"
count if _first == 1 & exposure > 0
di as text "  neg:"
count if _first == 1 & exposure < 0
di as text "  zero:"
count if _first == 1 & exposure == 0
di as text "  mi:"
count if _first == 1 & mi(exposure)

di as text _newline "======= foia vs imputed count ======="
tab foia_athr if _first == 1, missing

di as text _newline "======= mkt_spend_shr on PI ======="
sum mkt_spend_shr if _first == 1, d

log close
