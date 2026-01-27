set more off
clear all
capture log close
program drop _all
set scheme modern
pause on
set seed 8975
set maxvar 120000
program main
   * load_files, samp(3)
   * append_files
    clean_panel, time(year)
   * clean_panel, time(qrtr)
   * convert_year_to_qrtr
end

program load_files
    syntax, samp(int)
    di "`samp'"
    // append ls files
   /* forval i = 1/5473 {
        di "`i'"
        qui {
            cap import delimited ../external/ls_pprs/openalex_authors`i', stringcols(_all) clear varn(1) bindquotes(strict) maxquotedrows(unlimited) delimiters(",")
            if _rc == 0 {
                gen date = date(pub_date, "YMD")
                format date %td
                gen qrtr = qofd(date)
                gcontract athr_id  qrtr inst_id, freq(num_times)
                drop if mi(inst_id)
                drop if mi(athr_id) | athr_id == "A9999999999"
                count
                if r(N) > 0 {
                    fmerge m:1 athr_id using ../external/athrs/list_of_athrs, assert(1 2 3) keep(3) nogen
                }
                compress, nocoalesce
                save ../temp/ppr`i', replace

            }
        }
    }*/
    // 20260
    local start = (`samp'-1)*500  + 1
    local end = `samp'*500 
    *forval i = `start'/`end' {
    forval i = 475/500 {
        di "`i'"
        qui {
            cap import delimited ../external/pprs/openalex_authors`i', stringcols(_all) clear varn(1) bindquotes(strict) maxquotedrows(unlimited) delimiters(",")
            if _rc == 0 {
                gen date = date(pub_date, "YMD")
                format date %td
                gen qrtr = qofd(date)
                gcontract athr_id  qrtr inst_id, freq(num_times)
                drop if mi(inst_id)
                drop if mi(athr_id) | athr_id == "A9999999999"
                count
                if r(N) > 0 {
                    fmerge m:1 athr_id using ../external/athrs/list_of_athrs, assert(1 2 3) keep(3) nogen
                }
                compress, nocoalesce
                save ../temp/othr_ppr`i', replace

            }
        }
    }
end

program append_files 
/*    clear
    forval i = 1/5473 {
        di "`i'"
        cap append using ../temp/ppr`i'
    }
    gcollapse (sum) num_times, by(athr_id inst_id qrtr)
    compress, nocoalesce
    save ../temp/appended_pprs_1, replace
    clear*/
    forval i = 1/5000 {
        di "`i'"
        cap append using ../temp/othr_ppr`i'
    }
    gcollapse (sum) num_times, by(athr_id inst_id qrtr)
    compress, nocoalesce
    save ../temp/appended_pprs_2, replace
    /*clear
    forval i = 5001/10000 {
        di "`i'"
        cap append using ../temp/othr_ppr`i'
    }
    gcollapse (sum) num_times, by(athr_id inst_id qrtr)
    compress, nocoalesce
    save ../temp/appended_pprs_3, replace*/
    /*clear
    forval i = 10001/15000 {
        di "`i'"
        cap append using ../temp/othr_ppr`i'
    }
    gcollapse (sum) num_times, by(athr_id inst_id qrtr)
    compress, nocoalesce
    save ../temp/appended_pprs_4, replace*/
/*    clear
    forval i = 15001/20000 {
        di "`i'"
        cap append using ../temp/othr_ppr`i'
    }
    gcollapse (sum) num_times, by(athr_id inst_id qrtr)
    compress, nocoalesce
    save ../temp/appended_pprs_5, replace*/
   /* clear
    forval i = 20001/20260 {
        di "`i'"
        cap append using ../temp/othr_ppr`i'
    }
    gcollapse (sum) num_times, by(athr_id inst_id qrtr)
    compress, nocoalesce
    save ../temp/appended_pprs_6, replace*/
    clear
    forval i = 1/6 {
        append using ../temp/appended_pprs_`i'
    }
    gduplicates drop
    compress, nocoalesce
    save ../temp/appended_pprs, replace
end

program clean_panel
    syntax, time(str)
    use ../temp/appended_pprs, clear
    gen year = yofd(dofq(qrtr))
    drop if mi(`time')
    if "`time'" == "year" {
        gcollapse (sum) num_times, by(athr_id inst_id `time')
    }
    fmerge m:1 inst_id using ../external/inst/all_inst_geo_chars, assert(1 2 3) keep(3) nogen
    replace inst_id = new_inst_id 
    replace inst = new_inst 
    gen broad_affl = inst == "Broad Institute"
    gen hhmi_affl = inst == "Howard Hughes Medical Institute"
    gen wrong = inst  == "Molecular Oncology (United States)"
    gen funder = (strpos(inst, "Trust")> 0 | strpos(inst, "Foundation")>0 | strpos(inst, "Fund")>0) & !inlist(type, "education", "facility", "healthcare")
    gduplicates tag athr_id inst_id `time', gen(dup_entry)
    bys athr_id inst_id `time': gegen tot_times = sum(num_times) 
    replace num_times = tot_times
    drop if dup_entry > 0 & mi(new_inst)
    bys athr_id `time': gen num_affls = _N 
    drop if (num_affls > 1 & (funder == 1 | broad_affl == 1 | hhmi_affl == 1 ))| wrong == 1 
    drop if inst == "Howard Hughes Medical Institute"
    drop if inst_id == "I1344073410"
    drop new_inst new_inst_id dup_entry tot_times type
    gsort athr_id inst_id `time' country city
    gduplicates drop athr_id inst_id `time', force
    // keep inst with the largest num_times in a  year
    cap drop N
    bys athr_id `time' : gen N = _N 
    bys athr_id `time': gegen max_num_times = max(num_times)
    drop if num_times != max_num_times & N <= 10
    drop max_num_times
    gunique athr_id `time' 
    local N = r(unique)
    // imputation process
    foreach loc in inst_id inst_id inst_id { //inst_id inst_id {
        cap drop has_mult 
        cap drop same_as_after 
        cap drop same_as_before 
        cap drop has_before has_after 
        cap drop N
        bys athr_id `time' : gen N = _N 
        if "`time'" == "year" local range 5 
        if "`time'" == "qrtr" local range 20 
        // if there are mult in a  but sandwiched by the same, then choose that one 
        bys athr_id `time': gen has_mult = _N > 1
        bys athr_id `loc' (`time'): gen same_as_after = `time'[_n+1]-`time' <= `range' & has_mult[_n+1]==0
        by athr_id `loc' (`time'): gen same_as_before = `time' - `time'[_n-1] <= `range'  & has_mult[_n-1]==0
        gen sandwiched = has_mult == 1 & same_as_after == 1 & same_as_before == 1
        bys athr_id `time': gegen has_sandwich = max(sandwiched)
        drop if has_sandwich ==1 & sandwiched == 0 & N<=10 
        drop sandwiched has_sandwich
        bys athr_id `time': replace has_mult = _N > 1
       
        // now we prioritize the  before
        bys athr_id `loc' (`time'): replace same_as_after = `time'[_n+1]-`time' <= `range' & has_mult[_n+1]==0
        by athr_id `loc' (`time'): replace same_as_before = `time' - `time'[_n-1] <= `range'  & has_mult[_n-1]==0
        bys athr_id `time': gegen has_before = max(same_as_before)
        drop if has_mult == 1 & has_before == 1 & same_as_before == 0  & N<=10
        bys athr_id `time': replace has_mult = _N > 1
        // now do same for the `time' after 
        bys athr_id `loc' (`time'): replace same_as_after = `time'[_n+1]-`time' <= `range' & has_mult[_n+1]==0
        by athr_id `loc' (`time'): replace same_as_before = `time' - `time'[_n-1] <= `range'  & has_mult[_n-1]==0
        bys athr_id `time': gegen has_after = max(same_as_after)
        drop if has_mult == 1 & has_after == 1 & same_as_after == 0  & N <= 10
        bys athr_id `time': replace has_mult = _N > 1
    }
    bys athr_id: gegen has_genentech = max(inst_id == "I183934855")
    replace inst_id = "I183934855" if has_genentech == 1 & inst_id == "I4210150208"
    cap drop N
    bys athr_id `time' : gen N = _N 
    // if there are sandwiched insts no mater what the `time' gap is
    hashsort athr_id `time'
    gen prev_inst = inst_id[_n-1]
    gen post_inst = inst_id[_n+1]

    gen sandwich = prev_inst == post_inst & prev_inst != inst_id if athr_id[_n-1] == athr_id[_n+1] & athr[_n-1] == athr_id 
    replace inst_id = prev_inst if sandwich == 1 & sandwich[_n-1] != 1  & N <=10 
    replace inst = inst[_n-1] if sandwich == 1 & sandwich[_n-1] != 1  & N <=10 
    drop sandwich prev_inst post_inst

    hashsort athr_id `time'
    gen prev_inst = inst_id[_n-1]
    gen post_inst = inst_id[_n+1]

    gen sandwich = prev_inst == post_inst & prev_inst != inst_id if athr_id[_n-1] == athr_id[_n+1] & athr[_n-1] == athr_id 
    replace inst_id = prev_inst if sandwich == 1 & sandwich[_n-1] != 1  & N<=10
    replace inst = inst[_n-1] if sandwich == 1 & sandwich[_n-1] != 1 & N<=10
    drop sandwich prev_inst post_inst

    bys athr_id: gegen modal_inst = mode(inst_id)
    by athr_id `time': replace has_mult = _N > 1
    gen mode_match = inst_id == modal_inst
    bys athr_id `time': gegen has_mode_match = max(mode_match)
    gen mode_yr = year if mode_match == 1
    bys athr_id : gegen min_mode_yr = min(mode_yr) 
    by athr_id : gegen max_mode_yr = max(mode_yr) 
    drop if has_mult == 1 & has_mode_match == 1 & mode_match == 0 & inrange(year, min_mode_yr, max_mode_yr) & N <= 10

    gen rand = rnormal(0,1)
    gsort athr_id `time' rand
    gduplicates tag athr_id `time',gen(dup)
    gunique athr_id `time' if  dup > 0
    gduplicates drop athr_id `time', force
    gunique athr_id `time'
    assert r(unique) == `N'
    drop if mi(`time')
    gisid athr_id `time'
    hashsort athr_id `time'
    gen prev_inst = inst_id[_n-1]
    gen post_inst = inst_id[_n+1]

    gen sandwich = prev_inst == post_inst & prev_inst != inst_id if athr_id[_n-1] == athr_id[_n+1] & athr[_n-1] == athr_id 
    replace inst_id = prev_inst if sandwich == 1 & sandwich[_n-1] != 1  
    replace inst = inst[_n-1] if sandwich == 1 & sandwich[_n-1] != 1 
    drop sandwich prev_inst post_inst
    keep athr_id inst_id `time' num_times inst country_code country city region broad_affl hhmi_affl

    // do some final cleaning
    cap gen year  = yofd(dofq(qrtr))
    save ../temp/imputed_athr_panel, replace
    
    import delimited using ../external/geo/us_cities_states_counties.csv, clear varnames(1)
    glevelsof statefull , local(state_names)

    use ../temp/imputed_athr_panel, clear
    foreach s in `state_names' {
        replace region = "`s'" if mi(region) & country_code == "US" & strpos(inst, "`s'")>0
    }
    replace region = "Pennsylvania" if country_code == "US" & inlist(city, "Pittsburgh" , "Philadelphia", "Radnor", "Swarthmore", "Meadville", "Lancaster" , "Wilkes-Barr") 
    replace region = "California" if country_code == "US" & inlist(city, "Stanford", "Los Angeles", "San Diego", "La Jolla", "Berkeley", "San Francisco", "Thousand Oaks", "Mountain View", "Sunnyvale")
    replace region = "California" if country_code == "US" & inlist(city, "Cupertino", "Malibu")
    replace region = "California" if country_code == "US" & inlist(city, "Novato", "Arcata", "Claremont", "Santa Clara", "Castroville", "Pomona", "Emeryville", "Redwood City", "Santa Barbara")
    replace region = "California" if country_code == "US" & inlist(city, "San Jose", "South San Francisco", "Pasadena", "Irving", "La Cañada Flintridge", "Duarte", "Menlo Park", "Livermore")
    replace region = "Massachusetts" if country_code == "US" & inlist(city, "Boston", "Cambridge", "Medford", "Wellesley", "Falmouth", "Woods Hole", "Framingham", "Plymouth", "Worcester")
    replace region = "Massachusetts" if country_code == "US" & inlist(city, "Amherst", "Amherst Center", "Waltham", "Northampton", "South Hadley", "Andover", "Natick", "Newton")
    replace region = "Maryland" if country_code == "US" & inlist(city, "Bethesda", "Baltimore", "Silver Spring", "Greenbelt", "Gaithersburg", "Frederick", "Riverdale Park", "Rockville", "Annapolis")
    replace region = "Maryland" if country_code == "US" & inlist(city, "Towson", "College Park")
    replace region = "Ohio" if country_code == "US" & inlist(city, "Toledo", "Dayton", "Oxford", "Cleveland", "Ardmore", "Oberlin", "Cincinnati")
    replace region = "New Jersey" if country_code == "US" & inlist(city, "New Brunswick", "Bridgewater", "Hoboken", "Raritan", "Glassboro", "Whippany", " Woodcliff Lake", "South Plainfield")
    replace region = "New Jersey" if country_code == "US" & inlist(city, "Montclair", "Princeton")
    replace region = "Iowa" if country_code == "US" & inlist(city, "Ames", "Des Moines")
    replace region = "Nevada" if country_code == "US" & inlist(city, "Reno")
    replace region = "Oklahoma" if country_code == "US" & inlist(city, "Tulsa")
    replace region = "Arizona" if country_code == "US" & inlist(city, "Phoenix", "Tucson")
    replace region = "Illinois" if country_code == "US" & inlist(city, "Chicago", "Evanston", "Downers Grove", "Hines")
    replace region = "New York" if country_code == "US" & inlist(city, "New York", "Ithaca", "Bronx", "Rochester", "Cold Spring Harbor", "Syracuse", "Upton", "Albany", "Manhasset")
    replace region = "New York" if country_code == "US" & inlist(city, "Binghamton", "Brookville", "Hempstead", "Saranac Lake", "New Hyde Park", "Poughkeepsie", "Buffalo", "Niskayuna")
    replace region = "Connecticut" if country_code == "US" & inlist(city, "New Haven", "West Haven", "Fairfield", "Stamford")
    replace region = "Oregon" if country_code == "US" & inlist(city, "Portland")
    replace region = "Alabama" if country_code == "US" & inlist(city, "Tuskegee")
    replace region = "District of Columbia" if country_code == "US" & inlist(city, "Washington")
    replace region = "North Carolina" if country_code == "US" & inlist(city, "Durham", "Asheville", "Chapel Hill")
    replace region = "South Carolina" if country_code == "US" & inlist(city, "Greenville", "Aiken")
    replace region = "Wisconsin" if country_code == "US" & inlist(city, "Madison", "Milwaukee")
    replace region = "Florida" if country_code == "US" & inlist(city, "Coral Gables", "Miami", "Sarasota", "Orlando", "Tampa")
    replace region = "Maine" if country_code == "US" & inlist(city, "Lewiston")
    replace region = "Washington" if country_code == "US" & inlist(city, "Seattle", "Richland", "Bothell")
    replace region = "Colorado" if country_code == "US" & inlist(city, "Denver", "Boulder", "Fort Collins")
    replace region = "Louisiana" if country_code == "US" & inlist(city, "New Orleans")
    replace region = "Delaware" if country_code == "US" & inlist(city, "Wilmington")
    replace region = "Tennessee" if country_code == "US" & inlist(city, "Memphis", "Oak Ridge", "Nashville")
    replace region = "Georgia" if country_code == "US" & inlist(city, "Atlanta", "Augusta", "Macon", "Decatur")
    replace region = "Texas" if country_code == "US" & inlist(city, "Houston", "Dallas", "San Antonio", "The Woodlands", "Austin")
    replace region = "New Mexico" if country_code == "US" & inlist(city, "Los Alamos", "Carlsbad", "Albuquerque", "Santa Fe")
    replace region = "Michigan" if country_code == "US" & inlist(city, "Ann Arbor", "Detroit", "Flint")
    replace region = "Rhode Island" if country_code == "US" & inlist(city, "Providence")
    replace region = "Hawaii" if country_code == "US" & inlist(city, "Honolulu")
    replace region = "Missouri" if country_code == "US" & inlist(city, "St Louis", "Kirksville")
    replace region = "Minnesota" if country_code == "US" & inlist(city, "Minneapolis", "Saint Paul") 
    replace region = "Minnesota" if country_code == "US" & inlist(city, "Rochester") & strpos(inst, "Mayo Clinic")>0 
    replace region = "Virginia" if country_code == "US" & inlist(city, "Reston", "Williamsburg", "North Laurel", "Arlington", "Richmond", "Harrisonburg", "Front Royal", "Falls Church", "Charlottesville")
    replace region = "Virginia" if country_code == "US" & inlist(city, "Tysons Corner", "Fairfax")
    replace region = "New Hampshire" if country_code == "US" & inlist(city, "Hanover")
    replace region = "Illinois" if country_code == "US" & inlist(city, "Lemont", "North Chicago")
    replace region = "Utah" if country_code == "US" & inlist(city, "Provo", "Salt Lake City")
    replace region = "Missouri" if inst_id == "I4210102181"
    replace region = "New Jersey" if inst_id == "I150569930"
    replace region = "Maryland" if inst_id == "I166416128"
    save ../temp/post_state_athr_panel, replace

    import delimited using ../external/geo/us_cities_states_counties.csv, clear varnames(1)
    gcontract stateshort statefull
    drop _freq
    drop if mi(stateshort)
    rename statefull region
    merge 1:m region using ../temp/post_state_athr_panel, assert(1 2 3) keep(2 3) nogen
    replace stateshort =  "DC" if region == "District of Columbia"
    replace stateshort =  "VI" if region == "Virgin Islands, U.S."
    gen us_state = stateshort if country_code == "US"
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
    gen msa_comb = msatitle
    replace  msa_comb = "Research Triangle Park, NC" if msa_comb == "Durham-Chapel Hill, NC" | msa_comb == "Raleigh, NC" | city == "Res Triangle Pk" | city == "Research Triangle Park" | city == "Res Triangle Park"
    replace  msa_comb = "Bay Area, CA" if inlist(msa_comb, "San Francisco-Oakland-Hayward, CA", "San Jose-Sunnyvale-Santa Clara, CA")
    gen msa_c_world = msa_comb
    replace msa_c_world = substr(msa_c_world, 1, strpos(msa_c_world, ", ")-1) + ", US" if country == "United States" & !mi(msa_c_world)
    replace msa_c_world = city + ", " + country_code if country_code != "US" & !mi(city) & !mi(country_code)
    compress, nocoalesce
    // if there are sandwiched msas no mater what the `time' gap is
    hashsort athr_id `time'
    gen prev_msa = msa_comb[_n-1]
    gen post_msa = msa_comb[_n+1]
    gen sandwich = prev_msa == post_msa & prev_msa != msa_comb if athr_id[_n-1] == athr_id[_n+1] & athr[_n-1] == athr_id
    replace msa_comb = prev_msa if sandwich == 1
    drop sandwich prev_msa post_msa
    save ../temp/athr_panel, replace

    replace athr_id = subinstr(athr_id, "A", "", .)
    destring athr_id, replace
    tsset athr_id `time'
    tsfill
    foreach var in inst_id {
        bys athr_id (`time'): replace  `var' = `var'[_n-1] if mi(`var') & !mi(`var'[_n-1])
    }
    tostring athr_id, replace
    replace athr_id = "A" + athr_id
    keep athr_id inst_id year broad_affl hhmi_affl
    fmerge m:1 inst_id using ../external/inst/all_inst_geo_chars, assert(1 2 3) keep(3) nogen
    drop new_inst new_inst_id type 
    foreach s in `state_names' {
        replace region = "`s'" if mi(region) & country_code == "US" & strpos(inst, "`s'")>0
    }
    replace region = "Pennsylvania" if country_code == "US" & inlist(city, "Pittsburgh" , "Philadelphia", "Radnor", "Swarthmore", "Meadville", "Lancaster" , "Wilkes-Barr") 
    replace region = "California" if country_code == "US" & inlist(city, "Stanford", "Los Angeles", "San Diego", "La Jolla", "Berkeley", "San Francisco", "Thousand Oaks", "Mountain View", "Sunnyvale")
    replace region = "California" if country_code == "US" & inlist(city, "Cupertino", "Malibu")
    replace region = "California" if country_code == "US" & inlist(city, "Novato", "Arcata", "Claremont", "Santa Clara", "Castroville", "Pomona", "Emeryville", "Redwood City", "Santa Barbara")
    replace region = "California" if country_code == "US" & inlist(city, "San Jose", "South San Francisco", "Pasadena", "Irving", "La Cañada Flintridge", "Duarte", "Menlo Park", "Livermore")
    replace region = "Massachusetts" if country_code == "US" & inlist(city, "Boston", "Cambridge", "Medford", "Wellesley", "Falmouth", "Woods Hole", "Framingham", "Plymouth", "Worcester")
    replace region = "Massachusetts" if country_code == "US" & inlist(city, "Amherst", "Amherst Center", "Waltham", "Northampton", "South Hadley", "Andover", "Natick", "Newton")
    replace region = "Maryland" if country_code == "US" & inlist(city, "Bethesda", "Baltimore", "Silver Spring", "Greenbelt", "Gaithersburg", "Frederick", "Riverdale Park", "Rockville", "Annapolis")
    replace region = "Maryland" if country_code == "US" & inlist(city, "Towson", "College Park")
    replace region = "Ohio" if country_code == "US" & inlist(city, "Toledo", "Dayton", "Oxford", "Cleveland", "Ardmore", "Oberlin", "Cincinnati")
    replace region = "New Jersey" if country_code == "US" & inlist(city, "New Brunswick", "Bridgewater", "Hoboken", "Raritan", "Glassboro", "Whippany", " Woodcliff Lake", "South Plainfield")
    replace region = "New Jersey" if country_code == "US" & inlist(city, "Montclair", "Princeton")
    replace region = "Iowa" if country_code == "US" & inlist(city, "Ames", "Des Moines")
    replace region = "Nevada" if country_code == "US" & inlist(city, "Reno")
    replace region = "Oklahoma" if country_code == "US" & inlist(city, "Tulsa")
    replace region = "Arizona" if country_code == "US" & inlist(city, "Phoenix", "Tucson")
    replace region = "Illinois" if country_code == "US" & inlist(city, "Chicago", "Evanston", "Downers Grove", "Hines")
    replace region = "New York" if country_code == "US" & inlist(city, "New York", "Ithaca", "Bronx", "Rochester", "Cold Spring Harbor", "Syracuse", "Upton", "Albany", "Manhasset")
    replace region = "New York" if country_code == "US" & inlist(city, "Binghamton", "Brookville", "Hempstead", "Saranac Lake", "New Hyde Park", "Poughkeepsie", "Buffalo", "Niskayuna")
    replace region = "Connecticut" if country_code == "US" & inlist(city, "New Haven", "West Haven", "Fairfield", "Stamford")
    replace region = "Oregon" if country_code == "US" & inlist(city, "Portland")
    replace region = "Alabama" if country_code == "US" & inlist(city, "Tuskegee")
    replace region = "District of Columbia" if country_code == "US" & inlist(city, "Washington")
    replace region = "North Carolina" if country_code == "US" & inlist(city, "Durham", "Asheville", "Chapel Hill")
    replace region = "South Carolina" if country_code == "US" & inlist(city, "Greenville", "Aiken")
    replace region = "Wisconsin" if country_code == "US" & inlist(city, "Madison", "Milwaukee")
    replace region = "Florida" if country_code == "US" & inlist(city, "Coral Gables", "Miami", "Sarasota", "Orlando", "Tampa")
    replace region = "Maine" if country_code == "US" & inlist(city, "Lewiston")
    replace region = "Washington" if country_code == "US" & inlist(city, "Seattle", "Richland", "Bothell")
    replace region = "Colorado" if country_code == "US" & inlist(city, "Denver", "Boulder", "Fort Collins")
    replace region = "Louisiana" if country_code == "US" & inlist(city, "New Orleans")
    replace region = "Delaware" if country_code == "US" & inlist(city, "Wilmington")
    replace region = "Tennessee" if country_code == "US" & inlist(city, "Memphis", "Oak Ridge", "Nashville")
    replace region = "Georgia" if country_code == "US" & inlist(city, "Atlanta", "Augusta", "Macon", "Decatur")
    replace region = "Texas" if country_code == "US" & inlist(city, "Houston", "Dallas", "San Antonio", "The Woodlands", "Austin")
    replace region = "New Mexico" if country_code == "US" & inlist(city, "Los Alamos", "Carlsbad", "Albuquerque", "Santa Fe")
    replace region = "Michigan" if country_code == "US" & inlist(city, "Ann Arbor", "Detroit", "Flint")
    replace region = "Rhode Island" if country_code == "US" & inlist(city, "Providence")
    replace region = "Hawaii" if country_code == "US" & inlist(city, "Honolulu")
    replace region = "Missouri" if country_code == "US" & inlist(city, "St Louis", "Kirksville")
    replace region = "Minnesota" if country_code == "US" & inlist(city, "Minneapolis", "Saint Paul")
    replace region = "Minnesota" if country_code == "US" & inlist(city, "Rochester") & strpos(inst, "Mayo Clinic")>0 
    replace region = "Virginia" if country_code == "US" & inlist(city, "Reston", "Williamsburg", "North Laurel", "Arlington", "Richmond", "Harrisonburg", "Front Royal", "Falls Church", "Charlottesville")
    replace region = "Virginia" if country_code == "US" & inlist(city, "Tysons Corner", "Fiarfax")
    replace region = "New Hampshire" if country_code == "US" & inlist(city, "Hanover")
    replace region = "Illinois" if country_code == "US" & inlist(city, "Lemont", "North Chicago")
    replace region = "Utah" if country_code == "US" & inlist(city, "Provo", "Salt Lake City")
    replace region = "Missouri" if inst_id == "I4210102181"
    replace region = "New Jersey" if inst_id == "I150569930"
    replace region = "Maryland" if inst_id == "I166416128"
    compress, nocoalesce
    save ../temp/pre_fill_msa_`time', replace

    import delimited using ../external/geo/us_cities_states_counties.csv, clear varnames(1)
    gcontract stateshort statefull
    drop _freq
    drop if mi(stateshort)
    rename statefull region
    merge 1:m region using ../temp/pre_fill_msa_`time', assert(1 2 3) keep(2 3) nogen
    replace stateshort =  "DC" if region == "District of Columbia"
    replace stateshort =  "VI" if region == "Virgin Islands, U.S."
    gen us_state = stateshort if country_code == "US"
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
    gen msa_comb = msatitle
    replace  msa_comb = "Research Triangle Park, NC" if msa_comb == "Durham-Chapel Hill, NC" | msa_comb == "Raleigh, NC" | city == "Res Triangle Pk" | city == "Research Triangle Park" | city == "Res Triangle Park"
    replace  msa_comb = "Bay Area, CA" if inlist(msa_comb, "San Francisco-Oakland-Hayward, CA", "San Jose-Sunnyvale-Santa Clara, CA")
    replace msa_comb = "Rochester, MN" if strpos(inst, "Mayo Clinic") > 0 & city == "Rochester" 
    gen msa_c_world = msa_comb
    replace msa_c_world = substr(msa_c_world, 1, strpos(msa_c_world, ", ")-1) + ", US" if country == "United States" & !mi(msa_c_world)
    replace msa_c_world = city + ", " + country_code if country_code != "US" & !mi(city) & !mi(country_code)
    compress, nocoalesce
    save "../output/filled_in_panel_all_`time'", replace
    keep if inrange(year, 1945, 2025)
    save "../output/filled_in_panel_`time'_1945_2025", replace
    keep if country_code == "US"
    contract athr_id
    drop _freq
    save ../output/list_of_us_athrs, replace
end

program convert_year_to_qrtr
    use ../temp/appended_pprs, clear
    gen year = yofd(dofq(qrtr))
    keep if inrange(year, 1945, 2023)
    drop if mi(qrtr) | mi(year)
    gcontract athr_id qrtr year
    drop _freq
    merge m:1 athr_id year using ../output/filled_in_panel_year_1945_2025, keep(1 3) keepusing(country country_code city inst_id inst msatitle msa_comb msacode) nogen
    replace athr_id = subinstr(athr_id, "A", "", .)
    destring athr_id, replace
    tsset athr_id qrtr 
    tsfill
    tostring athr_id, replace
    replace athr_id = "A" + athr_id
    replace year = yofd(dofq(qrtr)) 
    foreach var in inst_id inst country_code country city msatitle msa_comb msatitle msacode {
        bys athr_id (qrtr) : replace  `var' = `var'[_n-1] if mi(`var') & !mi(`var'[_n-1])
    }
    save "../output/filled_in_panel_qrtr_1945_2025", replace
end
main
