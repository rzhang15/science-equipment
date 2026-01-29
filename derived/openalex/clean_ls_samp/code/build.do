set more off
clear all
capture log close
program drop _all
set scheme modern
pause on
set seed 8975
set maxvar 120000

program main
    // samp: all_jrnls_merged, _1...6, top_jrnls
    local samp "top_jrnls"
    clean_titles, samp(`samp')
    clean_samps, samp(`samp')
    clean_mesh, samp(`samp')
end

program clean_titles
    syntax, samp(str) 
    if "`samp'" == "top_jrnls" local fol top
    if strpos("`samp'" , "all_jrnls")  > 0 local fol samp 
    use pmid title id pub_type jrnl using ../external/`fol'/openalex_`samp'_merged, clear
    replace title = stritrim(title)
    contract title id pmid jrnl
    gduplicates drop pmid , force
    gduplicates drop id  , force
    cap drop _freq
    gisid id
    drop if mi(title)
    gen lower_title = stritrim(subinstr(subinstr(subinstr(subinstr(strlower(title), `"""', "", .), ".", "",.)), " :", ":",.), "'", "", .)
    drop if strpos(lower_title, "accountable care")>0 | strpos(title, "ACOs")>0
    drop if lower_title == "response"
    drop if strpos(lower_title , "nuts")>0 & strpos(lower_title, "bolts")>0
    foreach s in "economic" "economy" "public health" "hallmarks" "government" "reform" "equity" "payment" "politics" "policy" "policies" "comment" "guideline" "profession's" "interview" "debate" "professor" "themes:"  "professionals" "physician" "workforce" "medical-education"  "medical education" "funding" "conference" "insurance" "fellowship" "ethics" "legislation" "the editor" "response : " "letters" "this week" "notes" "news " "a note" "obituary"  "review" "perspectives" "scientists" "book" "institution" "meeting" "university" "universities" "journals" "publication" "recent " "costs" "challenges" "researchers" "perspective" "reply" " war" " news" "a correction" "academia" "society" "academy of" "nomenclature" "teaching" "education" "college" "academics"  "political" "association for" "association of" "response by" "societies" "health care" "health-care"  "abstracts" "journal club" "curriculum" "women in science" "report:" "letter:" "editorial:" "lesson" "awards" "doctor" "nurse" "health workers" " story"  "case report" "a brief history" "lecture " "career" "finance" "criticism" "critique" "discussion" "world health" "workload" "compensation" "educators" "war" "announces" "training programmes" "nhs" "nih" "national institutes of health" "address" "public sector" "private sector" "government" "price" "reflections" "health care" "healthcare" "health-care" " law" "report" "note on" "insurer" "health service research" "error" "quality of life" {
        drop if strpos(lower_title, "`s'")>0
    }
    gen strp = substr(lower_title, 1, strpos(lower_title, ": ")) if strpos(lower_title, ": ") > 0
    bys strp jrnl : gen tot_strp = _N
    foreach s in "letter:" "covid-19:" "snapshot:" "editorial:" "david oliver:" "offline:" "helen salisbury:" "margaret mccartney:" "book:" "response:" "letter from chicago:" "a memorable patient:" "<i>response</i> :" "reading for pleasure:" "partha kar" "venus:" "matt morgan:" "bad medicine:" "nota bene:" "cohort profile:" "size matters:" "usa:" "cell of the month:" "living on the edge:" "enhanced snapshot:" "world view:" "science careers:" "clare gerada:" "rammya mathew:" "endpiece:" "role model:" "quick uptakes:" "webiste of the week:" "tv:" "press:" "brief communication:" "essay:" "clinical update:" "assisted dying:" "controversies in management:" "health agencies update:" "the bmj awards 2020:" "lesson of the week:" "ebola:" "media:" "management for doctors:" "monkeypox:" "profile:" "the bmj awards 2017:" "the world in medicine:" "the bmj awards 2021:" "when i use a word . . .:" "personal paper:"  "clinical decision making:" "how to do it:" "10-minute consultation:" "frontline:" "when i use a word:" "medicine as a science:" "personal papers:" "miscellanea:" "the lancet technology:" {
        drop if strpos(lower_title, "`s'") == 1 & tot_strp > 1
    }
    drop if inlist(lower_title, "random samples", "sciencescope", "through the glass lightly", "equipment", "women in science",  "correction", "the metric system")
    drop if inlist(lower_title, "convocation week","the new format", "second-quarter biotech job picture", "gmo roundup")
    drop if strpos(lower_title, "annals ")==1
    drop if strpos(lower_title, "a fatal case of")==1
    drop if strpos(lower_title, "a case of ")==1
    drop if strpos(lower_title, "case ")==1
    drop if strpos(lower_title, "a day ")==1
    drop if strpos(lower_title,"?")>0
    preserve
    contract lower_title jrnl  pmid
    gduplicates tag lower_title jrnl, gen(dup)
    keep if dup> 0 & jrnl != "jbc"
    keep pmid
    gduplicates drop
    save ../temp/possible_non_articles_`samp', replace
    restore
    merge m:1 pmid using ../temp/possible_non_articles_`samp', assert(1 3) keep(1) nogen
    save ../temp/openalex_`samp'_clean_titles, replace
end

program clean_samps
    syntax, samp(str) 
    if "`samp'" == "top_jrnls" local fol top
    if strpos("`samp'" , "all_jrnls")  > 0 local fol samp 
    use id jrnl pmid using ../temp/openalex_`samp'_clean_titles, clear
    merge 1:m id using ../external/`fol'/openalex_`samp'_merged, assert(1 2 3) keep(3) nogen 
    merge m:1 id using ../external/patents/patent_ppr_cnt, assert(1 2 3) keep(1 3) nogen keepusing(patent_count front_only body_only)
    // clean date variables
    gen date = date(pub_date, "YMD")
    format %td date
    drop pub_date
    bys id: gegen min_date = min(date)
    replace date =min_date
    drop min_date
    cap drop author_id
    rename date pub_date
    gen pub_mnth = month(pub_date)
    gen year = year(pub_date)
    gen qrtr = qofd(pub_date)
    drop if year < 1945
    // fix some wrong institutions
    replace inst = "Johns Hopkins University" if strpos(raw_affl , "Bloomberg School of Public Health")>0 & inst == "Bloomberg (United States)"
    merge m:1 inst_id using ../external/inst_xw/all_inst_geo_chars, assert(1 2 3) keep(1 3) nogen 
    replace inst = new_inst if !mi(new_inst)
    replace inst_id = new_inst_id if !mi(new_inst)
    replace inst = "Johns Hopkins University" if  strpos(inst, "Johns Hopkins")>0
    replace inst_id = "I145311948" if inst == "Johns Hopkins University"
    replace inst = "Stanford University" if inlist(inst, "Stanford Medicine", "Stanford Health Care")
    replace inst = "Northwestern University" if inlist(inst, "Northwestern Medicine")
    replace inst = "National Institutes of Health" if  inlist(inst, "National Cancer Institute", "National Eye Institute", "National Heart, Lung, and Blood Institute", "National Human Genome Research Institute") | ///
              inlist(inst, "National Institute on Aging", "National Institute on Alcohol Abuse and Alcoholism", "National Institute of Allergy and Infectious Diseases", "National Institute of Arthritis and Musculoskeletal and Skin Diseases") | ///
                        inlist(inst, "National Institute of Biomedical Imaging and Bioengineering", "National Institute of Child Health and Human Development", "National Institute of Dental and Craniofacial Research") | ///
                                  inlist(inst, "National Institute of Diabetes and Digestive and Kidney Diseases", "National Institute on Drug Abuse", "National Institute of Environmental Health Sciences", "National Institute of General Medical Sciences", "National Institute of Mental Health", "National Institute on Minority Health and Health Disparities") | ///
                                            inlist(inst, "National Institute of Neurological Disorders and Stroke", "National Institute of Nursing Research", "National Library of Medicine", "National Heart Lung and Blood Institute", "National Institutes of Health")
    // drop any authors that are journals - these are probably reviews 
    gen is_lancet = strpos(raw_affl, "The Lancet")>0
    gen is_london = raw_affl == "London, UK." |  raw_affl == "London."
    gen is_bmj = (strpos(raw_affl, "BMJ")>0 | strpos(raw_affl, "British Medical Journal")>0)
    gen is_jama = strpos(raw_affl, " JAMA")>0 & mi(inst)
    gen is_editor = strpos(raw_affl, " Editor")>0 | strpos(raw_affl, "Editor ")>0
    bys pmid: gegen has_lancet = max(is_lancet)
    by pmid: gegen has_london = max(is_london)
    by pmid: gegen has_bmj = max(is_bmj)
    by pmid: gegen has_jama = max(is_jama)
    by pmid: gegen has_editor = max(is_jama)
    drop if has_lancet == 1 | has_london == 1 | has_bmj == 1 | has_jama == 1 | has_editor == 1
    drop is_lancet is_london is_bmj is_jama is_editor has_lancet has_london has_bmj has_jama has_editor
    // add in cite_ct
*    replace cite_count = cite_count + 1
*    assert cite_count > 0 

    save ../temp/cleaned_all_`samp', replace 
    
    cap drop author_id 
    cap drop which_athr_counter num_which_athr min_which_athr which_athr2 
    bys pmid athr_id (which_athr which_affl): gen author_id = _n ==1
    bys pmid (which_athr which_affl): gen which_athr2 = sum(author_id)
    replace which_athr = which_athr2
    drop which_athr2
    bys pmid which_athr: gen num_affls = _N
    cap drop region 
    cap drop inst_id 
    cap drop country
    cap drop country_code
    cap drop city 
    cap drop inst
    cap drop new_inst new_inst_id 
    merge m:1 athr_id year using ../external/year_insts/filled_in_panel_year_1945_2025, assert(1 2 3) keep(3) nogen
    gduplicates drop pmid athr_id inst_id, force
    save ../temp/cleaned_all_`samp'_prewt, replace

    use ../temp/cleaned_all_`samp'_prewt, clear
    // wt_adjust articlesj
    qui hashsort pmid which_athr which_affl
    cap drop author_id
    bys pmid athr_id (which_athr which_affl): gen author_id = _n ==1
    bys pmid (which_athr which_affl): gen which_athr2 = sum(author_id)
    replace which_athr = which_athr2
    drop which_athr2
    bys pmid which_athr: replace num_affls = _N
    assert num_affls == 1
    bys pmid: gegen num_athrs = max(which_athr)
    gen affl_wt = 1/num_affls * 1/num_athrs // this just divides each paper by the # of authors on the paper
    gen pat_affl_wt = patent_count * 1/num_affls * 1/num_athrs
    gen body_affl_wt = body_only * 1/num_affls * 1/num_athrs
    gen front_affl_wt = front_only * 1/num_affls * 1/num_athrs

    // now give each article a weight based on their ciatation count 
    qui gen years_since_pub = 2025-year+1
    qui gen avg_cite_yr = cite_count/years_since_pub
    qui gen avg_pat_yr = patent_count/years_since_pub
    qui gen avg_frnt_yr = front_only/years_since_pub
    qui gen avg_body_yr = body_only/years_since_pub
    qui bys pmid: replace avg_cite_yr = . if _n != 1
    qui bys pmid: replace avg_pat_yr = . if _n != 1
    qui bys pmid: replace avg_frnt_yr = . if _n != 1
    qui bys pmid: replace avg_body_yr = . if _n != 1
    qui sum avg_cite_yr
    gen cite_wt = avg_cite_yr/r(sum) // each article is no longer weighted 1 
    qui sum avg_pat_yr
    gen pat_wt = avg_pat_yr/r(sum) 
    qui sum avg_frnt_yr
    gen frnt_wt = avg_frnt_yr/r(sum) 
    qui sum avg_body_yr
    gen body_wt = avg_body_yr/r(sum) 
    bys jrnl: gegen tot_cite_N = total(cite_wt)
    gsort pmid cite_wt
    qui bys pmid: replace cite_wt = cite_wt[_n-1] if mi(cite_wt)
    gsort pmid pat_wt
    qui bys pmid: replace pat_wt = pat_wt[_n-1] if mi(pat_wt)
    gsort pmid frnt_wt
    qui bys pmid: replace frnt_wt = frnt_wt[_n-1] if mi(frnt_wt)
    gsort pmid body_wt
    qui bys pmid: replace body_wt = body_wt[_n-1] if mi(body_wt)
    qui gunique pmid
    local articles = r(unique)
    qui gen cite_affl_wt = affl_wt * cite_wt * `articles'
    qui gen pat_adj_wt  = affl_wt * pat_wt * `articles'
    qui gen frnt_adj_wt  = affl_wt * frnt_wt * `articles'
    qui gen body_adj_wt  = affl_wt * body_wt * `articles'
   
    qui bys id: gen id_cntr = _n == 1
    qui bys jrnl: gen first_jrnl = _n == 1
    qui by jrnl: gegen jrnl_N = total(id_cntr)
    *qui sum impact_fctr if first_jrnl == 1
    *gen impact_shr = impact_fctr/r(sum) // weight that each journal gets
    *gen reweight_N = impact_shr * `articles' // adjust the N of each journal to reflect impact factor
    *replace  tot_cite_N = tot_cite_N * `articles'
    *gen impact_wt = reweight_N/jrnl_N // after adjusting each journal weight we divide by the number of articles in each journal to assign new weight to each paper
    *gen impact_affl_wt = impact_wt * affl_wt  
    *gen impact_cite_wt = reweight_N * cite_wt / tot_cite_N * `articles' 
    *gen impact_cite_affl_wt = impact_cite_wt * affl_wt 
    foreach wt in affl_wt cite_affl_wt pat_adj_wt { // frnt_adj_wt body_adj_wt { // impact_affl_wt impact_cite_affl_wt 
        sum `wt'
        assert round(r(sum)-`articles') == 0
    }
    compress, nocoalesce
    gen len = length(inst)
    qui sum len
    local n = r(max)
    recast str`n' inst, force
    cap drop n mi_inst has_nonmi_inst population len
    save ../temp/pre_save, replace

    import delimited using ../external/geo/us_cities_states_counties.csv, clear varnames(1)
    glevelsof statefull , local(state_names)

    use ../temp/pre_save, clear
    replace country = "United States" if country_code == "US"
    replace country_code = "US" if country == "United States" 
    foreach s in `state_names' {
        replace region = "`s'" if mi(region) & country_code == "US" & strpos(inst, "`s'")>0
    }
    replace region = "Pennsylvania" if country_code == "US" & inlist(city, "Pittsburgh" , "Philadelphia", "Radnor", "Swarthmore", "Meadville", "Lancaster" , "Wilkes-Barre")  
    replace region = "California" if country_code == "US" & inlist(city, "Stanford", "Los Angeles", "San Diego", "La Jolla", "Berkeley", "San Francisco", "Thousand Oaks", "Mountain View", "Sunnyvale")
    replace region = "California" if country_code == "US" & inlist(city, "Cupertino", "Malibu", "Torrance", "San Carlos", "Escondido")
    replace region = "California" if country_code == "US" & inlist(city, "Novato", "Arcata", "Claremont", "Santa Clara", "Castroville", "Pomona", "Emeryville", "Redwood City", "Santa Barbara")
    replace region = "California" if country_code == "US" & inlist(city, "San Jose", "South San Francisco", "Pasadena", "Irving", "La Cañada Flintridge", "Duarte", "Menlo Park", "Livermore")
    replace region = "Massachusetts" if country_code == "US" & inlist(city, "Boston", "Cambridge", "Medford", "Wellesley", "Falmouth", "Woods Hole", "Framingham", "Plymouth", "Worcester")
    replace region = "Massachusetts" if country_code == "US" & inlist(city, "Amherst", "Amherst Center", "Waltham", "Northampton", "South Hadley", "Andover", "Natick", "Newton")
    replace region = "Maryland" if country_code == "US" & inlist(city, "Bethesda", "Baltimore", "Silver Spring", "Greenbelt", "Gaithersburg", "Frederick", "Riverdale Park", "Rockville", "Annapolis")
    replace region = "Maryland" if country_code == "US" & inlist(city, "Towson", "College Park", "Edgewater")
    replace region = "Ohio" if country_code == "US" & inlist(city, "Toledo", "Dayton", "Oxford", "Cleveland", "Ardmore", "Oberlin", "Cincinnati", "Columbus")
    replace region = "New Jersey" if country_code == "US" & inlist(city, "New Brunswick", "Bridgewater", "Hoboken", "Raritan", "Glassboro", "Whippany", " Woodcliff Lake", "South Plainfield")
    replace region = "New Jersey" if country_code == "US" & inlist(city, "Montclair", "Princeton", "Woodcliff Lake")
    replace region = "Iowa" if country_code == "US" & inlist(city, "Ames", "Des Moines")
    replace region = "Nevada" if country_code == "US" & inlist(city, "Reno")
    replace region = "Nebraska" if country_code == "US" & inlist(city, "Omaha")
    replace region = "Oklahoma" if country_code == "US" & inlist(city, "Tulsa")
    replace region = "Arizona" if country_code == "US" & inlist(city, "Phoenix", "Tucson")
    replace region = "Illinois" if country_code == "US" & inlist(city, "Chicago", "Evanston", "Downers Grove", "Hines")
    replace region = "Indiana" if country_code == "US" & inlist(city, "West Lafayette", "Notre Dame", "Indianapolis", "Fort Wayne")
    replace region = "New York" if country_code == "US" & inlist(city, "New York", "Ithaca", "Bronx", "Rochester", "Cold Spring Harbor", "Syracuse", "Upton", "Albany", "Manhasset")
    replace region = "New York" if country_code == "US" & inlist(city,  "Brooklyn", "Potsdam", "Tarrytown", "Town of Poughkeepsie", "Saratoga Springs", "Millbrook", "Utica")
    replace region = "New York" if country_code == "US" & inlist(city, "Binghamton", "Brookville", "Hempstead", "Saranac Lake", "New Hyde Park", "Poughkeepsie", "Buffalo", "Niskayuna")
    replace region = "Connecticut" if country_code == "US" & inlist(city, "New Haven", "West Haven", "Fairfield", "Stamford", "West Hartford")
    replace region = "Oregon" if country_code == "US" & inlist(city, "Portland")
    replace region = "Alabama" if country_code == "US" & inlist(city, "Tuskegee", "Mobile")
    replace region = "District of Columbia" if country_code == "US" & inlist(city, "Washington")
    replace region = "North Carolina" if country_code == "US" & inlist(city, "Durham", "Asheville", "Chapel Hill", "Winston Salem", "Boone", "Charlotte")
    replace region = "South Carolina" if country_code == "US" & inlist(city, "Greenville", "Aiken", "Charleston")
    replace region = "Wisconsin" if country_code == "US" & inlist(city, "Madison", "Milwaukee")
    replace region = "Florida" if country_code == "US" & inlist(city, "Coral Gables", "Miami", "Sarasota", "Orlando", "Tampa")
    replace region = "Maine" if country_code == "US" & inlist(city, "Lewiston", "Bar Harbor", "Brunswick")
    replace region = "Washington" if country_code == "US" & inlist(city, "Seattle", "Richland", "Bothell", "Redmond")
    replace region = "Colorado" if country_code == "US" & inlist(city, "Denver", "Boulder", "Fort Collins", "Golden")
    replace region = "Louisiana" if country_code == "US" & inlist(city, "New Orleans", "Houma")
    replace region = "Delaware" if country_code == "US" & inlist(city, "Wilmington")
    replace region = "Tennessee" if country_code == "US" & inlist(city, "Memphis", "Oak Ridge", "Nashville")
    replace region = "Georgia" if country_code == "US" & inlist(city, "Atlanta", "Augusta", "Macon", "Decatur", "Kennesaw")
    replace region = "Texas" if country_code == "US" & inlist(city, "Houston", "Dallas", "San Antonio", "The Woodlands", "Austin")
    replace region = "New Mexico" if country_code == "US" & inlist(city, "Los Alamos", "Carlsbad", "Albuquerque", "Santa Fe")
    replace region = "Michigan" if country_code == "US" & inlist(city, "Ann Arbor", "Detroit", "Flint", "Midland", "Royal Oak", "Grand Rapids")
    replace region = "Rhode Island" if country_code == "US" & inlist(city, "Providence")
    replace region = "Hawaii" if country_code == "US" & inlist(city, "Honolulu")
    replace region = "Missouri" if country_code == "US" & inlist(city, "St Louis", "Kirksville")
    replace region = "Mississippi" if country_code == "US" & inlist(city, "Vicksburg")
    replace region = "Minnesota" if country_code == "US" & inlist(city, "Minneapolis", "Saint Paul")
    replace region = "Virginia" if country_code == "US" & inlist(city, "Reston", "Williamsburg", "North Laurel", "Arlington", "Richmond", "Harrisonburg", "Front Royal", "Falls Church", "Charlottesville")
    replace region = "Virginia" if country_code == "US" & inlist(city, "Tysons Corner", "Fairfax", "Ashburn", "Alexandria")
    replace region = "New Hampshire" if country_code == "US" & inlist(city, "Hanover", "Lebanon")
    replace region = "Illinois" if country_code == "US" & inlist(city, "Lemont", "North Chicago")
    replace region = "Utah" if country_code == "US" & inlist(city, "Provo", "Salt Lake City")
    replace region = "Missouri" if inst_id == "I4210102181"
    replace region = "New Jersey" if inst_id == "I150569930"
    replace region = "Maryland" if inst_id == "I166416128"
    replace region = "Iowa" if inst == "Pioneer Hi-Bred"
    replace region = "Iowa" if inst == "WinnMed"
    save ../temp/fill_msa, replace

    import delimited using ../external/geo/us_cities_states_counties.csv, clear varnames(1)
    gcontract stateshort statefull
    cap drop _freq
    drop if mi(stateshort)
    rename statefull region
    merge 1:m region using ../temp/fill_msa, assert(1 2 3) keep(2 3) nogen
    replace stateshort =  "DC" if region == "District of Columbia"
    replace stateshort =  "VI" if region == "Virgin Islands, U.S."
    replace us_state = stateshort if country_code == "US" & mi(us_state)
    replace city = "Saint Louis" if city == "St Louis"
    replace city = "Winston Salem" if city == "Winston-Salem"
    merge m:1 city us_state using ../external/geo/city_msa, assert(1 2 3) keep(1 3) nogen
    replace msatitle = "Washington-Arlington-Alexandria, DC-VA-MD-WV"  if us_state == "DC"
    replace msatitle = "New York-Newark-Jersey City, NY-NJ-PA" if city == "The Bronx" & us_state == "NY"
    replace msatitle = "Miami-Fort Lauderdale-West Palm Beach, FL" if city == "Coral Gables" & us_state == "FL"
    replace msatitle = "Springfield, MA" if city == "Amherst Center"
    replace msatitle = "Hartford-West Hartford-East Hartford, CT" if city == "Storrs" & us_state == "CT"
    replace msatitle = "Tampa-St. Petersburg-Clearwater, FL" if city == "Temple Terrace" & us_state == "FL"
    replace msatitle = "San Francisco-Oakland-Hayward, CA" if city == "Foster City" & us_state == "CA"
    replace msa_comb = msatitle if mi(msa_comb)
    replace  msa_comb = "Research Triangle Park, NC" if msa_comb == "Durham-Chapel Hill, NC" | msa_comb == "Raleigh, NC" | city == "Res Triangle Pk" | city == "Research Triangle Park" | city == "Res Triangle Park"
    replace  msa_comb = "Bay Area, CA" if inlist(msa_comb, "San Francisco-Oakland-Hayward, CA", "San Jose-Sunnyvale-Santa Clara, CA")
    replace msa_c_world = msa_comb if mi(msa_c_world)
    replace msa_c_world = substr(msa_c_world, 1, strpos(msa_c_world, ", ")-1) + ", US" if country == "United States" & !mi(msa_c_world)
    replace msa_c_world = city + ", " + country_code if country_code != "US" & !mi(city) & !mi(country_code)
    save ../output/cleaned_`samp', replace
    preserve
    gcontract id pmid
    cap drop _freq
    save ../temp/pmid_id_xwalk_`samp', replace
    restore

    use ../output/cleaned_`samp', clear
    keep if inrange(pub_date, td(01jan2005), td(31dec2025)) & year >=2005
    drop cite_wt cite_affl_wt tot_cite_N first_jrnl pat_wt pat_adj_wt frnt_wt body_wt frnt_adj_wt body_adj_wt jrnl_N 
    foreach var in impact_wt impact_affl_wt impact_cite_wt impact_cite_affl_wt impact_shr  reweight_N  {
        cap drop `var'
    }
    qui sum avg_cite_yr
    gen cite_wt = avg_cite_yr/r(sum)
    qui sum avg_pat_yr
    gen pat_wt = avg_pat_yr/r(sum)
    qui sum avg_frnt_yr
    gen frnt_wt = avg_frnt_yr/r(sum) 
    qui sum avg_body_yr
    gen body_wt = avg_body_yr/r(sum) 
    bys jrnl: gegen tot_cite_N = total(cite_wt)
    gsort pmid cite_wt
    qui bys pmid: replace cite_wt = cite_wt[_n-1] if mi(cite_wt)
    gsort pmid pat_wt
    qui bys pmid: replace pat_wt = pat_wt[_n-1] if mi(pat_wt)
    gsort pmid frnt_wt
    qui bys pmid: replace frnt_wt = frnt_wt[_n-1] if mi(frnt_wt)
    gsort pmid body_wt
    qui bys pmid: replace body_wt = body_wt[_n-1] if mi(body_wt)
    gunique pmid 
    local articles = r(unique)
    qui gen cite_affl_wt = affl_wt * cite_wt * `articles'
    qui gen pat_adj_wt  = affl_wt * pat_wt * `articles'
    qui gen frnt_adj_wt  = affl_wt * frnt_wt * `articles'
    qui gen body_adj_wt  = affl_wt * body_wt * `articles'
    
    qui bys jrnl: gen first_jrnl = _n == 1
    qui by jrnl: gegen jrnl_N = total(id_cntr)
   /* qui sum impact_fctr if first_jrnl == 1
    gen impact_shr = impact_fctr/r(sum)
    gen reweight_N = impact_shr * `articles'
    replace  tot_cite_N = tot_cite_N * `articles'
    gen impact_wt = reweight_N/jrnl_N
    gen impact_affl_wt = impact_wt * affl_wt
    gen impact_cite_wt = reweight_N * cite_wt / tot_cite_N * `articles'
    gen impact_cite_affl_wt = impact_cite_wt * affl_wt*/

    foreach wt in affl_wt cite_affl_wt pat_adj_wt  { //frnt_adj_wt body_adj_wt { // impact_affl_wt impact_cite_affl_wt 
        qui sum `wt'
        assert round(r(sum)-`articles') == 0
    }
    compress, nocoalesce
    save ../output/cleaned_last20yrs_`samp', replace
end

program clean_mesh  
    syntax, samp(str) 
    if "`samp'" == "top_jrnls" local fol top
    if strpos("`samp'" , "all_jrnls")  > 0 local fol samp 
    use ../external/`fol'/contracted_gen_mesh_`samp', clear
    bys id: gen n = _n
    greshape wide qualifier_name gen_mesh, i(id) j(n)
    gduplicates drop id, force
    save ../output/reshaped_gen_mesh_`samp', replace
end
main