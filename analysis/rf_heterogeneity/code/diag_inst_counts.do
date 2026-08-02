set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17
set maxvar 20000
log using diag_inst_counts.log, replace text

* ============================================================================
* Diagnose why cuts on inst chars drop the institution count from ~250 to ~100.
* Hypothesis to test:
*   (a) crosswalk drops (ipeds_openalex): how many inst_chars_pre rows survive
*       the crosswalk merge?
*   (b) analysis-panel <-> inst_chars_pre merge: how many analysis-panel
*       institutions match?
*   (c) hi_/lo_ split behaviour: cutoff is computed on inst_indicator==1
*       across ALL institutions in inst_chars_pre, not just those in the
*       analysis panel. If most panel institutions sit on one side of that
*       cutoff, half the analysis sample sits below.
* ============================================================================

local samp all_jrnls
local suf  _r1

* ---- (1) crosswalk universe ----
import delimited ../external/college/ipeds_openalex.csv, ///
    clear varn(1) stringcols(_all)
keep ipeds_id inst_id
drop if inst_id == "" | ipeds_id == ""
destring ipeds_id, replace
duplicates drop
bys ipeds_id (inst_id): keep if _n == 1
di as text "== xw rows (unique ipeds_id): " _N
save ../temp/xw_diag, replace

* ---- (2) inst_chars_pre pre-merge ----
use ../external/inst_chars/combined_pre, clear
di as text "== combined_pre rows (unique ipeds_id upstream): " _N
count if !mi(tot_fund)
di as text "   with non-missing tot_fund: " r(N)
merge 1:1 ipeds_id using ../temp/xw_diag
di as text "== after ipeds<->inst_id merge:"
tab _merge
keep if _merge == 3
drop _merge
count if !mi(tot_fund)
di as text "   inst_id rows with non-missing tot_fund AFTER xw: " r(N)
drop ipeds_id
bys inst_id: keep if _n == 1
di as text "== unique inst_id after xw (final inst_chars_pre size): " _N
count if !mi(tot_fund)
di as text "   unique inst_id w/ non-missing tot_fund: " r(N)
save ../temp/inst_chars_diag, replace

* ---- (3) analysis panel institution universe ----
use inst_id athr_id year using ../external/prepped_samples/es_`samp'`suf', clear
di as text "== analysis panel rows: " _N
gunique inst_id
di as text "   unique inst_id in analysis panel: " r(unique)
gunique athr_id
di as text "   unique athr_id in analysis panel: " r(unique)
bys inst_id: keep if _n == 1
keep inst_id
save ../temp/panel_insts_diag, replace

* ---- (4) analysis-panel <-> inst_chars_pre merge ----
merge 1:1 inst_id using ../temp/inst_chars_diag
di as text "== inst-panel <-> inst_chars_pre merge:"
tab _merge
count if _merge == 3
di as text "   panel institutions matched to any inst char: " r(N)
count if _merge == 3 & !mi(tot_fund)
di as text "   panel institutions with non-missing tot_fund: " r(N)
count if _merge == 1
di as text "   panel institutions MISSING from inst_chars_pre: " r(N)

* ---- (5) how would cutoff on the full inst_chars_pre split PANEL insts? ----
* Reproduce the pipeline exactly: cutoff computed over ALL inst_chars_pre rows
* (inst_indicator==1), then applied down to panel rows.
use ../temp/inst_chars_diag, clear
sum tot_fund, d
local p50_all = r(p50)
di as text "== tot_fund p50 over ALL inst_chars_pre inst_id rows: " `p50_all'
count if !mi(tot_fund) & tot_fund >= `p50_all'
di as text "   inst_chars_pre insts on HI side: " r(N)
count if !mi(tot_fund) & tot_fund <  `p50_all'
di as text "   inst_chars_pre insts on LO side: " r(N)

* Now restrict to PANEL institutions and see how the SAME cutoff splits them.
merge 1:1 inst_id using ../temp/panel_insts_diag, keep(3) nogen
count if !mi(tot_fund)
di as text "== panel institutions with non-missing tot_fund: " r(N)
count if !mi(tot_fund) & tot_fund >= `p50_all'
di as text "   panel insts on HI side of ALL-inst cutoff: " r(N)
count if !mi(tot_fund) & tot_fund <  `p50_all'
di as text "   panel insts on LO side of ALL-inst cutoff: " r(N)

* ---- (6) what if we computed the cutoff on the PANEL institutions only? ----
sum tot_fund if !mi(tot_fund), d
local p50_panel = r(p50)
di as text "== tot_fund p50 over PANEL institutions only: " `p50_panel'
count if !mi(tot_fund) & tot_fund >= `p50_panel'
di as text "   panel insts on HI side (panel-cutoff): " r(N)
count if !mi(tot_fund) & tot_fund <  `p50_panel'
di as text "   panel insts on LO side (panel-cutoff): " r(N)

log close
