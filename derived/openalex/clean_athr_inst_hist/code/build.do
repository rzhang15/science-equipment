set more off
clear all
capture log close
program drop _all
set scheme modern
pause on
set seed 8975
set maxvar 120000
global dropbox_dir "~/dropbox (harvard university)/scientific equipment"
global derived_output "${dropbox_dir}/derived_output/"
program main
    append_files
    merge_geo
    clean_panel, time(year)
    *clean_panel, time(qrtr)
    *convert_year_to_qrtr
end

program append_files
    forval i = 1/30 {
        di "`i'"
        qui {
            import delimited ../external/pprs/openalex_authors`i', stringcols(_all) clear varn(1) bindquotes(strict) maxquotedrows(unlimited) delimiters(",")
            gen date = date(pub_date, "YMD")
            format date %td
            gen qrtr = qofd(date)
            gcontract athr_id  qrtr inst_id, freq(num_times)
            drop if mi(inst_id)
            count
            if r(N) > 0 {
                fmerge m:1 athr_id using ../external/athrs/list_of_athrs, assert(1 2 3) keep(3) nogen
            }
            compress, nocoalesce
            save ../temp/ppr`i', replace
        }
    }
    clear
    forval i = 1/30 {
        di "`i'"
        append using ../temp/ppr`i'
    }
    drop if athr_id == "A9999999999"
    gcollapse (sum) num_times, by(athr_id inst_id qrtr)

    compress, nocoalesce
    save ../temp/appended_pprs, replace
end

program merge_geo
    forval i = 1/1 {
        import delimited ../external/pprs/inst_geo_chars`i', stringcols(_all) clear varn(1) bindquotes(strict) maxquotedrows(unlimited)
        compress, nocoalesce
        save ../temp/inst_geo_chars`i', replace
    }
    clear
    count
    forval i = 1/1 {
        di "`i'"
        append using ../temp/inst_geo_chars`i'
        count
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
    // fix
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
    replace new_inst = associated if !mi(associated) & mi(new_inst) & has_parent == 1 & inlist(type,"facility", "other", "nonprofit", "healthcare") & associated_type == "education" & !inlist(associated, "State Univerisity of New York", "City University of New York")
    replace new_inst_id = associated_id if !mi(associated_id) & mi(new_inst_id) & has_parent == 1 &  inlist(type,"facility", "other", "nonprofit", "healthcare") & associated_type == "education" & !inlist(associated, "State Univerisity of New York", "City University of New York")
    replace new_inst = inst if mi(new_inst)
    replace new_inst_id = inst_id if mi(new_inst_id)
    gduplicates tag inst_id, gen(dup)
    gen diff = inst_id != new_inst_id
    bys inst_id : gegen has_new = max(diff)
    drop if dup > 0 & diff == 0 & has_new == 1
    gduplicates drop inst_id, force
    keep inst_id inst new_inst new_inst_id region city country country_code type 
    drop if mi(inst_id) 
    save ../temp/all_inst_chars, replace
end 

program clean_panel
    syntax, time(str)
    use ../temp/appended_pprs, clear
    gen year = yofd(dofq(qrtr))
    drop if mi(`time')
    if "`time'" == "year" {
        gcollapse (sum) num_times, by(athr_id inst_id `time')
    }
    fmerge m:1 inst_id using ../temp/all_inst_chars, assert(1 2 3) keep(3) nogen
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
*    drop if !inrange(year, 1945, 2023) 
    save ../temp/athr_panel, replace

    
    import delimited using ../external/geo/us_cities_states_counties.csv, clear varnames(1)
    glevelsof statefull , local(state_names)
    use ../temp/athr_panel, clear
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
    save ../temp/athr_panel, replace

    import delimited using ../external/geo/us_cities_states_counties.csv, clear varnames(1)
    gcontract stateshort statefull
    drop _freq
    drop if mi(stateshort)
    rename statefull region
    merge 1:m region using ../temp/athr_panel, assert(1 2 3) keep(2 3) nogen
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
    fmerge m:1 inst_id using ../temp/all_inst_chars, assert(1 2 3) keep(3) nogen
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
    save "${derived_output}/clean_athr_inst_hist/filled_in_panel_all_`time'", replace
    keep if inrange(year, 1945, 2023)
    save "${derived_output}/clean_athr_inst_hist/filled_in_panel_`time'", replace
end

program convert_year_to_qrtr
    use ../temp/appended_pprs, clear
    gen year = yofd(dofq(qrtr))
    keep if inrange(year, 1945, 2023)
    drop if mi(qrtr) | mi(year)
    gcontract athr_id qrtr year
    drop _freq
    merge m:1 athr_id year using ../output/filled_in_panel_year, keep(1 3) keepusing(country country_code city inst_id inst msatitle msa_comb msacode) nogen
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
    save "${derived_output}/clean_athr_inst_hist/filled_in_panel_qrtr", replace
end
main
