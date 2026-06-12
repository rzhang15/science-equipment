set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

! cat ../temp/grants_batches/b_*.tsv > ../temp/grants_all.tsv

import delimited using "../temp/grants_all.tsv", ///
    delimiter("\t") varnames(nonames) stringcols(_all) bindquote(nobind) clear

rename v1 pmid
rename v2 grant_id
rename v3 acronym
rename v4 agency
rename v5 country

destring pmid, replace
gduplicates drop pmid grant_id agency, force

save ../output/grants, replace
