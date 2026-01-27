set more off
clear all
capture log close
program drop _all
set scheme modern
pause on
set seed 8975
here, set
set maxvar 120000
program main

foreach samp in firstlast last first second {
    create_athr_split, samp(all_jrnls) cut(`samp')
}
end

program create_athr_split
    syntax, samp(str) cut(str)
    cap mkdir "../output/`cut'"
    use id pmid which_athr which_affl pub_date year jrnl cite_count front_only body_only patent_count athr_id athr_name  stateshort region inst_id country_code country city us_state msacode msatitle msa_comb msa_c_world inst using ../external/openalex/cleaned_all_`samp', clear
    bys id: egen first_athr = min(which_athr)
    bys id: egen last_athr = max(which_athr)
    if "`cut'" == "firstlast" {
        keep if which_athr == first_athr | which_athr == last_athr
    }
    if "`cut'" == "second" {
        keep if which_athr == first_athr | which_athr == last_athr | which_athr = first_athr + 1 | which_athr = last_athr - 1
    }
    if "`cut'" == "last" {
        keep if which_athr == last_athr
    }
    if "`cut'" == "first" {
        keep if which_athr == first_athr
    }
    qui hashsort id which_athr which_affl
    cap drop author_id 
    cap drop num_athrs 
    bys id athr_id (which_athr which_affl): gen author_id = _n ==1
    bys id (which_athr which_affl): gen which_athr2 = sum(author_id)
    replace which_athr = which_athr2
    drop which_athr2
    cap drop num_affls
    bys id which_athr: gen num_affls = _N
    bys id: egen num_athrs = max(which_athr)
    if "`cut'" == "firstlast" {
        assert num_affls == 1
        qui sum num_athrs
        assert r(max) == 2
    }
    if "`cut'" == "last" | "`cut'" == "first" {
        assert num_affls == 1
        qui sum num_athrs
        assert r(max) == 1
    }
    gen affl_wt = 1/num_affls * 1/num_athrs
    gen pat_affl_wt = patent_count * 1/num_affls * 1/num_athrs
    gen body_affl_wt = body_only * 1/num_affls * 1/num_athrs
    gen front_affl_wt = front_only * 1/num_affls * 1/num_athrs
    qui gen years_since_pub = 2022-year+1
    qui gen avg_cite_yr = cite_count/years_since_pub
    qui gen avg_pat_yr = patent_count/years_since_pub
    qui gen avg_frnt_yr = front_only/years_since_pub
    qui gen avg_body_yr = body_only/years_since_pub
    qui bys id: replace avg_cite_yr = . if _n != 1
    qui bys id: replace avg_pat_yr = . if _n != 1
    qui bys id: replace avg_frnt_yr = . if _n != 1
    qui bys id: replace avg_body_yr = . if _n != 1
    qui sum avg_cite_yr
    gen cite_wt = avg_cite_yr/r(sum) // each article is no longer weighted 1 
    qui sum avg_pat_yr
    gen pat_wt = avg_pat_yr/r(sum)
    qui sum avg_frnt_yr
    gen frnt_wt = avg_frnt_yr/r(sum)
    qui sum avg_body_yr
    gen body_wt = avg_body_yr/r(sum)
    bys jrnl: egen tot_cite_N = total(cite_wt)
    gsort id cite_wt
    qui bys id: replace cite_wt = cite_wt[_n-1] if mi(cite_wt)
    gsort id pat_wt
    qui bys id: replace pat_wt = pat_wt[_n-1] if mi(pat_wt)
    gsort id frnt_wt
    qui bys id: replace frnt_wt = frnt_wt[_n-1] if mi(frnt_wt)
    gsort id body_wt
    qui bys id: replace body_wt = body_wt[_n-1] if mi(body_wt)

    qui gunique id
    local articles = r(unique)
    qui gen cite_affl_wt = affl_wt * cite_wt * `articles'
    qui gen pat_adj_wt = affl_wt * pat_wt * `articles'
    qui gen frnt_adj_wt  = affl_wt * frnt_wt * `articles'
    qui gen body_adj_wt  = affl_wt * body_wt * `articles'

    qui bys id: gen id_cntr = _n == 1
    qui bys jrnl: gen first_jrnl = _n == 1
    qui bys jrnl: egen jrnl_N = total(id_cntr)
/*    qui sum impact_fctr if first_jrnl == 1
    gen impact_shr = impact_fctr/r(sum) // weight that each journal gets
    gen reweight_N = impact_shr * `articles' // adjust the N of each journal to reflect impact factor
    replace  tot_cite_N = tot_cite_N * `articles'
    gen impact_wt = reweight_N/jrnl_N // after adjusting each journal weight we divide by the number of articles in each journal to assign new weight to each paper
    gen impact_affl_wt = impact_wt * affl_wt  
    gen impact_cite_wt = reweight_N * cite_wt / tot_cite_N * `articles' 
    gen impact_cite_affl_wt = impact_cite_wt * affl_wt */
    foreach wt in affl_wt cite_affl_wt pat_adj_wt { // impact_affl_wt impact_cite_affl_wt pat_adj_wt  frnt_adj_wt body_adj_wt
        sum `wt'
        assert round(r(sum)-`articles') == 0
    }
    compress, nocoalesce
    cap drop len
    gen len = length(inst)
    qui sum len
    local n = r(max)
    recast str`n' inst, force
    save ../output/`cut'/cleaned_all_`samp', replace

    keep if inrange(pub_date, td(01jan2005), td(31dec2025)) & year >=2005
    drop cite_wt cite_affl_wt tot_cite_N jrnl_N first_jrnl  pat_wt pat_adj_wt frnt_wt body_wt frnt_adj_wt body_adj_wt
    cap  drop impact_wt impact_affl_wt impact_cite_wt impact_cite_affl_wt impact_shr  reweight_N
    qui sum avg_cite_yr
    gen cite_wt = avg_cite_yr/r(sum)
    qui sum avg_pat_yr
    gen pat_wt = avg_pat_yr/r(sum)
    qui sum avg_frnt_yr
    gen frnt_wt = avg_frnt_yr/r(sum)
    qui sum avg_body_yr
    gen body_wt = avg_body_yr/r(sum)
    bys jrnl: egen tot_cite_N = total(cite_wt)
    gsort id cite_wt
    qui bys id: replace cite_wt = cite_wt[_n-1] if mi(cite_wt)
    gsort id pat_wt
    qui bys id: replace pat_wt = pat_wt[_n-1] if mi(pat_wt)
    gsort id frnt_wt
    qui bys id: replace frnt_wt = frnt_wt[_n-1] if mi(frnt_wt)
    gsort id body_wt
    qui bys id: replace body_wt = body_wt[_n-1] if mi(body_wt)
    gunique id 
    local articles = r(unique)
    qui gen cite_affl_wt = affl_wt * cite_wt * `articles'
    qui gen pat_adj_wt = affl_wt * pat_wt * `articles'
    qui gen frnt_adj_wt  = affl_wt * frnt_wt * `articles'
    qui gen body_adj_wt  = affl_wt * body_wt * `articles'
    
    qui bys jrnl: gen first_jrnl = _n == 1
    qui bys jrnl: egen jrnl_N = total(id_cntr)
    /*qui sum impact_fctr if first_jrnl == 1
    gen impact_shr = impact_fctr/r(sum)
    gen reweight_N = impact_shr * `articles'
    replace  tot_cite_N = tot_cite_N * `articles'
    gen impact_wt = reweight_N/jrnl_N
    gen impact_affl_wt = impact_wt * affl_wt
    gen impact_cite_wt = reweight_N * cite_wt / tot_cite_N * `articles'
    gen impact_cite_affl_wt = impact_cite_wt * affl_wt*/

    foreach wt in affl_wt cite_affl_wt pat_adj_wt {
        sum `wt'
        assert round(r(sum)-`articles') == 0
    }
    compress, nocoalesce
    save ../output/`cut'/cleaned_last5yrs_`samp', replace
end

main
