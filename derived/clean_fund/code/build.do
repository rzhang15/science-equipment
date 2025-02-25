set more off
clear all
capture log close
program drop _all
set scheme modern
pause on
set seed 8975
here, set
set maxvar 120000
global dropbox_dir "~/dropbox (harvard university)/scientific equipment"
global derived_output "${dropbox_dir}/derived_output"
program main
    *aggregate_insts
    *clean_titles 
    clean_samps
    *clean_mesh
end

program aggregate_insts
    qui {
        forval i = 1/17 {
            cap import delimited using ../external/insts/inst_geo_chars`i', clear varn(1) bindquotes(strict)
            save ../temp/inst_geo_chars`i', replace
        }
        clear 
        forval i = 1/17 {
            cap append using ../temp/inst_geo_chars`i'
        }
    }
	  bys inst_id: gegen has_parent = max(associated_rel == "parent")
    keep if has_parent == 0  | (has_parent == 1 & associated_rel == "parent" ) 
    gen new_inst = ""
    gen new_inst_id = ""
    foreach var in inst inst_id {
        replace new_`var' =  `var' if has_parent == 0
        replace new_`var' = `var' if (((strpos(associated, "Universit")>0|strpos(associated, "College")|strpos(associated, "Higher Education")) & strpos(associated, "System")>0 & associated_type == "education" & (type == "education" | type == "healthcare")) | inlist(associated, "University of London", "Wellcome Trust") | (strpos(associated, "Health")>0 & strpos(associated, "System")>0 & associated_type == "healthcare" & (type == "education" | type == "healthcare")) | strpos(associated, "Ministry of") > 0 | strpos(associated, "Board of")>0 | strpos(associated, "Government of")>0 | (strpos(associated, "Department of")>0 & country != "Russia")) & !inlist(associated, "State Univerisity of New York", "City University of New York")
        replace new_`var' = `var' if country_code != associated_country
    }
    replace associated = "" if !mi(new_inst)
    replace associated_id = "" if !mi(new_inst_id)
    gduplicates drop inst_id new_inst_id, force
    foreach s in "" "_id" {
        replace new_inst`s' = associated`s' if strpos(associated, "University")>0 & strpos(associated, "System")>0 & associated_type == "education" & (type != "education" & type != "healthcare")
        replace new_inst`s' = associated`s' if inlist(associated, "Chinese Academy of Sciences", "Spanish National Research Council", "Max Planck Society", "National Research Council", "National Institutes of Health", "Harvard University")
        replace new_inst`s' = associated`s' if inlist(associated, "Leibniz Association", "Aix-Marseille University", "Indian Council of Agricultural Research", "Inserm", "Polish Academy of Sciences", "National Research Institute for Agriculture, Food and Environment") 
        replace new_inst`s' = associated`s' if inlist(associated, "Institut des Sciences Biologiques", "Institut de Chimie", "Institut des Sciences Humaines et Sociales", "Institut National des Sciences de l'Univers", "Institut des Sciences de l'Ingénierie et des Systèmes", "Institut Écologie et Environnement", "Institut de Physique", "Institut National des Sciences Mathématiques et de leurs Interactions")
        replace new_inst`s' = associated`s' if inlist(associated, "Institut National de Physique Nucléaire et de Physique des Particules", "Institut des Sciences de l'Information et de leurs Interactions")
        replace new_inst`s' = associated`s' if inlist(associated, "French National Centre for Scientific Research")
        replace new_inst`s' = associated`s' if inlist(associated, "Fraunhofer Society", "Istituti di Ricovero e Cura a Carattere Scientifico",  "Claude Bernard University Lyon 1", "Atomic Energy and Alternative Energies Commission", "Japanese Red Cross Society, Japan") 
        replace new_inst`s' = associated`s' if inlist(associated, "Islamic Azad University, Tehran", "National Oceanic and Atmospheric Administratio", "French Institute for Research in Computer Science and Automation", "National Academy of Sciences of Ukraine", "National Institute for Nuclear Physics", "Assistance Publique – Hôpitaux de Paris") 
        replace new_inst`s' = associated`s' if inlist(associated, "Medical Research Council", "National Institute for Health Research", "Academia Sinica", "National Scientific and Technical Research Council","Czech Academy of Sciences", "Commonwealth Scientific and Industrial Research Organisation")
        replace new_inst`s' = associated`s' if inlist(associated, "Slovak Academy of Sciences", "Indian Council of Medical Research", "Council of Scientific and Industrial Research", "National Institute for Astrophysics", "Bulgarian Academy of Sciences", "Centers for Disease Control and Prevention", "National Institute of Technology")
        replace new_inst`s' = associated`s' if inlist(associated, "Helmholtz Association of German Research Centres", "Helios Kliniken", "Shriners Hospitals for Children", "Hungarian Academy of Sciences", "National Agriculture and Food Research Organization", "Australian Research Council")
        replace new_inst`s' = associated`s' if inlist(associated, "Agro ParisTech", "Veterans Health Administration", "Institut de Recherche pour le Développement", "Austrian Academy of Sciences", "Institutos Nacionais de Ciência e Tecnologia", "Chinese Academy of Forestry", "Chinese Academy of Tropical Agricultural Sciences")
        replace new_inst`s' = associated`s' if inlist(associated, "Instituto de Salud Carlos III", "National Aeronautics and Space Administration", "Ludwig Boltzmann Gesellschaft", "United States Air Force", "Centre Nouvelle Aquitaine-Bordeaux", "RIKEN", "Agricultural Research Council")
        replace new_inst`s' = associated`s' if inlist(associated, "Centro Científico Tecnológico - La Plata", "National Research Council Canada", "Royal Netherlands Academy of Arts and Sciences","Defence Research and Development Organisation", "Canadian Institutes of Health Research", "Italian Institute of Technology", "United Nations University")
        replace new_inst`s' = associated`s' if inlist(associated, "IBM Research - Thomas J. Watson Research Center", "Délégation Ile-de-France Sud","Grenoble Institute of Technology", "François Rabelais University", "Chinese Academy of Social Sciences", "National Science Foundation" , "Federal University of Toulouse Midi-Pyearénées")
        replace new_inst`s' = associated`s' if inlist(associated, "Chinese Center For Disease Control and Prevention", "Johns Hopkins Medicine", "Cancer Research UK", "Centre Hospitalier Universitaire de Bordeaux", "Puglia Salute", "Hospices Civils de Lyon", "Ministry of Science and Technology", "Servicio de Salud de Castilla La Mancha")
        replace new_inst`s' = associated`s' if inlist(associated, "Grenoble Alpes University","Arts et Metiers Institute of Technology", "University of Paris-Saclay", "Biomedical Research Council", "Senckenberg Society for Nature Research", "Centre Hospitalier Régional et Universitaire de Lille", "Schön Klinik Roseneck", "ESPCI Paris")
        replace new_inst`s' = associated`s' if inlist(associated, "National Academy of Sciences of Armenia", "University of the Philippines System", "Madrid Institute for Advanced Studies", "CGIAR", "Ministry of Science, Technology and Innovation", "Institut Polytechnique de Bordeaux")

        replace new_inst`s' = associated`s' if inlist(associated, "Department of Biological Sciences", "Department of Chemistry and Material Sciences", "Department of Energy, Engineering, Mechanics and Control Processes","Department of Agricultural Sciences", "Division of Historical and Philological Sciences", "Department of Mathematical Sciences", "Department of Physiological Sciences") & country == "Russia"
        replace new_inst`s' = associated`s' if inlist(associated, "Department of Earth Sciences", "Physical Sciences Division", "Department of Global Issues and International Relations", "Department of Medical Sciences", "Department of Social Sciences") & country == "Russia" 
        replace new_inst`s' = associated`s' if inlist(associated, "Russian Academy")
        replace new_inst`s' = associated`s' if strpos(associated, "Agricultural Research Service -")>0
    }
    // merge national institutions together
    replace new_inst = "French National Centre for Scientific Research" if inlist(inst,"Institut des Sciences Biologiques", "Institut de Chimie", "Institut des Sciences Humaines et Sociales", "Institut National des Sciences de l'Univers", "Institut des Sciences de l'Ingénierie et des Systèmes", "Institut Écologie et Environnement", "Institut de Physique", "Institut National des Sciences Mathématiques et de leurs Interactions") | inlist(inst,"Institut National de Physique Nucléaire et de Physique des Particules", "Institut des Sciences de l'Information et de leurs Interactions")
    replace new_inst = "French National Centre for Scientific Research" if inlist(new_inst,"Institut des Sciences Biologiques", "Institut de Chimie", "Institut des Sciences Humaines et Sociales", "Institut National des Sciences de l'Univers", "Institut des Sciences de l'Ingénierie et des Systèmes", "Institut Écologie et Environnement", "Institut de Physique", "Institut National des Sciences Mathématiques et de leurs Interactions") | inlist(new_inst,"Institut National de Physique Nucléaire et de Physique des Particules", "Institut des Sciences de l'Information et de leurs Interactions")
    replace new_inst_id = "I1294671590" if new_inst =="French National Centre for Scientific Research"
    replace new_inst = "Russian Academy" if inlist(inst, "Department of Biological Sciences", "Department of Chemistry and Material Sciences", "Department of Energy, Engineering, Mechanics and Control Processes","Department of Agricultural Sciences", "Division of Historical and Philological Sciences", "Department of Mathematical Sciences", "Department of Physiological Sciences") | inlist(inst, "Russian Academy of Sciences", "Department of Earth Sciences", "Physical Sciences Division", "Department of Global Issues and International Relations", "Department of Medical Sciences", "Department of Social Sciences") & country == "Russia"
    replace new_inst = "Russian Academy" if inlist(new_inst, "Department of Biological Sciences", "Department of Chemistry and Material Sciences", "Department of Energy, Engineering, Mechanics and Control Processes","Department of Agricultural Sciences", "Division of Historical and Philological Sciences", "Department of Mathematical Sciences", "Department of Physiological Sciences") | inlist(new_inst,"Russian Academy of Sciences", "Department of Earth Sciences", "Physical Sciences Division", "Department of Global Issues and International Relations", "Department of Medical Sciences", "Department of Social Sciences") & country == "Russia"
    replace new_inst_id = "I1313323035" if new_inst  == "Russian Academy"
    replace new_inst  = "Agricultural Research Service" if strpos(inst, "Agricultural Research Service - ")>0
    replace new_inst_id = "I1312222531" if new_inst == "Agricultural Research Service"
    replace new_inst  = "Max Planck Society" if strpos(inst, "Max Planck")>0
    replace new_inst  = "Max Planck Society" if strpos(associated, "Max Planck")>0
    replace new_inst_id = "I149899117" if new_inst == "Max Planck Society"
    replace new_inst = "Mass General Brigham" if inlist(inst, "Massachusetts General Hospital" , "Brigham and Women's Hospital")
    replace new_inst_id = "I48633490" if new_inst == "Mass General Brigham"
    replace new_inst = "Johns Hopkins University" if strpos(inst, "Johns Hopkins")>0
    replace new_inst = "Johns Hopkins University" if strpos(associated, "Johns Hopkins")>0
    replace new_inst_id = "I145311948" if new_inst == "Johns Hopkins University"
    replace new_inst = "Stanford University" if inlist(inst, "Stanford Medicine", "Stanford Health Care", "Stanford Synchrotron Radiation Lightsource", "Stanford Blood Center")
    replace new_inst = "Stanford University" if inlist(associated, "Stanford Medicine", "Stanford Health Care")
    replace new_inst_id = "I97018004" if new_inst == "Stanford University"
    replace new_inst = "Northwestern University" if inlist(inst, "Northwestern Medicine")
    replace new_inst = "Northwestern University" if inlist(associated, "Northwestern Medicine")
    replace new_inst_id = "I111979921" if new_inst == "Northwestern University"
    replace new_inst = "Harvard University" if inlist(inst, "Harvard Global Health Institute", "Harvard Pilgrim Health Care", "Harvard Affiliated Emergency Medicine Residency", "Harvard NeuroDiscovery Center")
    replace new_inst_id = "I136199984" if new_inst == "Harvard University"
    replace new_inst = "University of California, San Francisco" if inlist(inst, "Ernest Gallo Clinic and Research Center")
    replace new_inst_id = "I180670191" if new_inst == "University of California, San Francisco"
    // health systems
    replace new_inst = "University of Virginia" if strpos(inst, "University of Virginia") > 0 & (strpos(inst, "Hospital") >0 | strpos(inst, "Medical")>0 | strpos(inst, "Health")>0)
    replace new_inst_id = "I51556381" if new_inst == "University of Virginia"
    replace new_inst = "University of Missouri" if strpos(inst, "University of Missouri" ) > 0 & (strpos(inst, "Hospital") >0 | strpos(inst, "Medical")>0 | strpos(inst, "Health")>0)
    replace new_inst_id = "I76835614" if new_inst == "University of Missouri"
    replace new_inst = "Baylor University" if strpos(inst, "Baylor University Medical Center")>0
    replace new_inst_id = "I157394403" if new_inst == "Baylor University"
    replace new_inst = "Columbia University" if strpos(inst, "Columbia University Irving")>0
    replace new_inst_id = "I78577930" if new_inst == "Columbia University"
    replace new_inst = "Yale University" if strpos(inst, "Yale New Haven Health System")>0 | strpos(inst, "Yale New Haven Hospital")>0 | strpos(inst, "Yale Cancer Center") >0  
    replace new_inst_id = "I32971472" if new_inst == "Yale University"
    replace new_inst = "University of Florida" if strpos(inst, "UF Health")>0 | strpos(inst, "Florida Medical Entomology Laboratory")>0
    replace new_inst_id = "I33213144" if new_inst == "University of Florida"
    replace new_inst = "University of Wisconsin–Madison" if strpos(inst, "University of Wisconsin Carbone Cancer Center")>0 | strpos(inst, "UW Health")>0
    replace new_inst_id = "I135310074" if new_inst == "University of Wisconsin–Madison"
	replace new_inst = "Scripps Health" if inlist(inst, "Scripps Clinic Medical Group", "Scripps Clinic", "Scripps Laboratories (United States)")
    replace new_inst_id = "I1311914864" if new_inst == "Scripps Health"
	replace new_inst = "Scripps Research Institute" if inlist(inst, "Scripps (United States)")
    replace new_inst_id = "I123431417" if new_inst == "Scripps Research Institute"
	replace new_inst = "Duke University" if inlist(inst, "Duke Medical Center")
	replace new_inst_id = "I170897317" if new_inst == "Duke University"
	replace new_inst = "Washington University in St. Louis" if (inlist(inst, "Washington University") & city == "St Louis") 
	replace new_inst_id = "I204465549" if new_inst == "Washington University in St. Louis" 
	replace new_inst = "University of Michigan–Ann Arbor" if inst == "Michigan Medicine" | inst == "Michigan Center for Translational Pathology"
	replace new_inst_id = "I27837315" if new_inst == "University of Michigan–Ann Arbor"
	replace new_inst = "University of Pittsburgh" if strpos(inst, "UPMC")>0
	replace new_inst_id = "I170201317" if new_inst == "University of Pittsburgh" 
	replace new_inst = "Vanderbilt University" if inst == "Vanderbilt Health"
	replace new_inst_id = "I200719446" if new_inst == "Vanderbilt University"ll
	// fix the UCs
	replace new_inst = "University of California, San Francisco" if strpos(inst, "UCSF")>0 | inst == "University of California San Francisco"
	replace new_inst_id = "I180670191" if new_inst == "University of California, San Francisco"
	replace new_inst = "University of California, San Diego" if inst == "University of California San Diego"
	replace new_inst_id = "I36258959" if inst == "University of California, San Diego" | strpos(inst, "UC San Diego") >0 | strpos(inst, "UCSD")>0
	replace new_inst = "University of California, Davis" if inst == "University of California Davis"
	replace new_inst_id = "I84218800" if inst == "University of California, Davis"
	replace new_inst = "University of California, Los Angeles" if inst == "University of California Los Angeles" | strpos(inst , "UCLA") >0 
	replace new_inst_id = "I161318765" if inst == "University of California, Los Angeles"
	replace new_inst = "University of California, Berkeley" if inst == "University of California Berkeley"
	replace new_inst_id = "I95457486" if inst == "University of California, Berkeley"
	replace new_inst = "University of California, Davis" if strpos(inst, "UC Davis") > 0
	replace new_inst_id = "I84218800" if new_inst ==  "University of California, Davis" 
	replace new_inst = "University of California, Irvine" if strpos(inst, "UC Irvine") > 0
	replace new_inst_id = "I204250578" if new_inst ==  "University of California, Irvine" 
	
    // agencies
    replace new_inst = "National Institute of Standards and Technology" if associated == "National Institute of Standards and Technology" &associated_rel == "parent"
    replace new_inst_id = "I1321296531" if new_inst ==  "National Institute of Standards and Technology"
	replace new_inst = "National Institutes of Health" if inst == "Center for Cancer Research" | inst == "National Center for Biotechnology Information"
	replace new_inst_id = "I1299303238" if new_inst == "National Institutes of Health"
	replace new_inst = "Carnegie Institution for Science" if associated == "Carnegie Institution for Science" & associated_rel == "parent"
	replace new_inst_id = "I196817621" if new_inst == "Carnegie Institution for Science"
    replace new_inst = "Allen Institute" if associated == "Allen Institute" & associated_rel == "parent"
    replace new_inst = "Allen Institute" if inst == "Allen Institute for Artificial Intelligence"
    replace new_inst_id = "I4210140341" if new_inst ==  "Allen Institute"
    replace new_inst = "Abbott (United States)" if inst == "Abbott Fund"
	replace new_inst_id = "I4210088555" if new_inst == "Abbott (United States)"

    replace new_inst = "Synaptic Pharmaceutical Corporation" if inst_id == "I4210132327"
    replace city = "Paramus" if inst_id == "I4210132327"
    replace region = "New Jersey" if inst_id == "I4210132327"
    replace new_inst = "Immunex" if inst_id == "I4210143161"
    replace city = "Seattle" if inst_id == "I4210143161" 
    replace region = "Washington" if inst_id == "I4210143161"
    replace new_inst = "Genetics Institute" if inst_id == "I4210165860"
    replace city = "Cambridge" if inst_id == "I4210165860"
    replace region = "Massachusetts" if inst_id == "I4210165860"
    gen edit = 0
    foreach s in "Health System" "Clinic" "Hospital of the" "Hospital" "Medical Center" {
        replace new_inst = subinstr(inst, "`s'", "", .) if (strpos(inst, "University")>0 | strpos(inst, "UC")>0) & strpos(inst, "`s'") > 0 & edit == 0 & country_code == "US"
        replace edit = 1 if  (strpos(inst, "University")>0 | strpos(inst, "UC")>0) & strpos(inst, "`s'") > 0 &  country_code == "US"
    }
    replace new_inst = strtrim(new_inst)
    bys new_inst (edit) : replace new_inst_id = new_inst_id[_n-1] if edit == 1 & !mi(new_inst_id[_n-1])  & city == city[_n-1]
    replace new_inst = associated if !mi(associated) & mi(new_inst) & has_parent == 1 & inlist(type,"facility", "other", "nonprofit", "healthcare") & associated_type == "education" & !inlist(associated, "State University of New York", "City University of New York")
    replace new_inst_id = associated_id if !mi(associated_id) & mi(new_inst_id) & has_parent == 1 &  inlist(type,"facility", "other", "nonprofit", "healthcare") & associated_type == "education" & !inlist(associated, "State University of New York", "City University of New York")
    replace new_inst = inst if mi(new_inst)
    replace new_inst_id = inst_id if mi(new_inst_id)
    gduplicates tag inst_id, gen(dup)
    gen diff = inst_id != new_inst_id
    bys inst_id : gegen has_new = max(diff)
    drop if dup > 0 & diff == 0 & has_new == 1
    gduplicates drop inst_id, force
    keep inst_id inst new_inst new_inst_id region city country country_code type 
    drop if mi(inst_id) 
    save "${derived_output}/all_inst_geo_chars", replace
end

program clean_titles
    use pmid title id pub_type jrnl using ../external/openalex/openalex_all_jrnls_merged, clear
    keep if pub_type == "article"
    replace title = stritrim(title)
    contract title id jrnl
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
    save ../temp/openalex_clean_titles, replace
end

program clean_samps
    use id title using ../temp/openalex_clean_titles, clear
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
    // add in cite_ct
    replace cite_count = cite_count + 1
    assert cite_count > 0 
    save ../temp/cleaned_all, replace
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
    merge m:1 athr_id year using ../external/year_insts/filled_in_panel_year, assert(1 2 3) keep(3) nogen
    gduplicates drop pmid athr_id inst_id, force
    save ../temp/cleaned_all_prewt, replace

    // wt_adjust articles 
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
    // now give each article a weight based on their ciatation count 
    qui gen years_since_pub = 2025-year+1
    qui gen avg_cite_yr = cite_count/years_since_pub
    qui bys pmid: replace avg_cite_yr = . if _n != 1
    qui sum avg_cite_yr
    gen cite_wt = avg_cite_yr/r(sum) // each article is no longer weighted 1 
    bys jrnl: gegen tot_cite_N = total(cite_wt)
    gsort pmid cite_wt
    qui bys pmid: replace cite_wt = cite_wt[_n-1] if mi(cite_wt)
    qui gunique pmid
    local articles = r(unique)
    qui gen cite_affl_wt = affl_wt * cite_wt * `articles'
   
    foreach wt in affl_wt cite_affl_wt {
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
    save "${derived_output}/cleaned_all", replace
end
main
