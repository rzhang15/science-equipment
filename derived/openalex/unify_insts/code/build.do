set more off
clear all
capture log close
program drop _all
set scheme modern
pause on
set seed 8975
set maxvar 120000

program main
    get_all_insts
    clean_insts
end

program get_all_insts
    clear
    forval i = 1/16 {
        cap append using ../external/ls_samp/inst_geo_chars`i'
    }
    forval i = 1/5 {
        cap append using ../external/samp/inst_geo_chars`i'
    }
    cap drop which_inst
    compress, nocoalesce
    save ../temp/all_insts, replace 
end

program clean_insts
    use ../temp/all_insts, clear
    bys inst_id: gegen has_parent = max(associated_rel == "parent")
    keep if has_parent == 0  | (has_parent == 1 & associated_rel == "parent" ) 
    gen new_inst = ""
    gen new_inst_id = ""
    gen flag =  1 if (strpos(associated, "Universit")>0 | strpos(associated, "College") | strpos(associated, "Higher Education")) & strpos(associated, "System") > 0 & associated_type == "education" & inlist(type, "education", "healthcare")
    replace flag = 1 if inlist(associated, "University of London", "Wellcome Trust") 
    replace flag = 1 if strpos(associated, "Health")>0 & strpos(associated, "System")>0 & associated_type == "healthcare" & inlist(type, "education", "healthcare") 
    replace flag = 1 if strpos(associated, "Ministry of") > 0 | strpos(associated, "Board of")>0
    replace flag = 1 if (strpos(associated, "Government of")>0 | strpos(associated, "Department of")>0) & country != "Russia"
    replace flag = 0 if inlist(associated, "State University of New York", "City University of New York")
    foreach var in inst inst_id {
        replace new_`var' =  `var' if has_parent == 0
        replace new_`var' = `var' if  flag == 1
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
    replace new_inst = "French National Centre for Scientific Research" if inlist(inst,"Institut des Sciences Biologiques", "Institut de Chimie", "Institut des Sciences Humaines et Sociales", "Institut National des Sciences de l'Univers", "Institut des Sciences de l'Ingénierie et des Systèmes", "Institut Écologie et Environnement", "Institut de Physique", "Institut National des Sciences Mathématiques et de leurs Interactions") | inlist(inst,"Institut National de Physique Nucléaire et de Physique des Particules", "Institut des Sciences de l'Information et de leurs Interactions", "Centre National de la Recherche Scientifique")
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

    replace new_inst = "Harvard University" if inlist(inst, "Harvard Global Health Institute", "Harvard Pilgrim Health Care", "Harvard Affiliated Emergency Medicine Residency", "Harvard NeuroDiscovery Center", "Harvard College Observatory")
    replace new_inst_id = "I136199984" if new_inst == "Harvard University"

    replace new_inst = "University of California, San Francisco" if inlist(inst, "Ernest Gallo Clinic and Research Center")
    replace new_inst_id = "I180670191" if new_inst == "University of California, San Francisco"
  
    replace new_inst = "University of Virginia" if strpos(inst, "University of Virginia") > 0 & (strpos(inst, "Hospital") >0 | strpos(inst, "Medical")>0 | strpos(inst, "Health")>0)
    replace new_inst_id = "I51556381" if new_inst == "University of Virginia"

    replace new_inst = "University of Missouri" if strpos(inst, "University of Missouri" ) > 0 & (strpos(inst, "Hospital") >0 | strpos(inst, "Medical")>0 | strpos(inst, "Health")>0)
    replace new_inst_id = "I76835614" if new_inst == "University of Missouri"

    replace new_inst = "Baylor University" if strpos(inst, "Baylor University Medical Center")>0
    replace new_inst_id = "I157394403" if new_inst == "Baylor University"

    replace new_inst = "Columbia University" if strpos(inst, "Columbia University")>0 
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
	
	replace new_inst = "University of California, San Francisco" if strpos(inst, "UCSF")>0 | inst == "University of California San Francisco"
	replace new_inst_id = "I180670191" if new_inst == "University of California, San Francisco"

	replace new_inst = "University of California, San Diego" if strpos(inst , "University of California San Diego") | strpos(inst, "UC San Diego") >0 | strpos(inst, "UCSD")>0
	replace new_inst_id = "I36258959" if new_inst == "University of California, San Diego" 	

    replace new_inst = "University of California, Davis" if inst == "University of California Davis"
	replace new_inst_id = "I84218800" if new_inst == "University of California, Davis"

	replace new_inst = "University of California, Los Angeles" if inst == "University of California Los Angeles" | strpos(inst , "UCLA") >0 
	replace new_inst_id = "I161318765" if new_inst == "University of California, Los Angeles"

	replace new_inst = "University of California, Berkeley" if inst == "University of California Berkeley"
	replace new_inst_id = "I95457486" if new_inst == "University of California, Berkeley"

	replace new_inst = "University of California, Davis" if strpos(inst, "UC Davis") > 0
	replace new_inst_id = "I84218800" if new_inst ==  "University of California, Davis" 

	replace new_inst = "University of California, Irvine" if strpos(inst, "UC Irvine") > 0
	replace new_inst_id = "I204250578" if new_inst ==  "University of California, Irvine" 
    
    replace new_inst = "Dana-Farber Cancer Institute" if strpos(inst, "Dana-Farber") > 0
    replace new_inst_id = "I4210117453" if new_inst == "Dana-Farber Cancer Institute"

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
        replace new_inst = subinstr(inst, "`s'", "", .) if (strpos(inst, "University")>0 | strpos(inst, "UC")>0) & strpos(inst, "`s'") > 0 & edit == 0 & country_code == "US" & strpos(new_inst, "`s'") > 0
        replace edit = 1 if  (strpos(inst, "University")>0 | strpos(inst, "UC")>0) & strpos(inst, "`s'") > 0 &  country_code == "US" & strpos(new_inst, "`s'")
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
    drop dup 
    gduplicates drop inst_id, force
    keep inst_id inst new_inst new_inst_id region city country country_code type 
    drop if mi(inst_id) 
    gegen inst_grp = group(country city new_inst)
    bys inst_grp:  replace new_inst_id = new_inst_id[_n-1] if new_inst_id != new_inst_id[_n-1] & inst_grp == inst_grp[_n-1]
    save ../output/all_inst_geo_chars, replace
end

main
