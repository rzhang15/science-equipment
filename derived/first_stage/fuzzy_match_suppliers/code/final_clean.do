set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17
program main
    clean_names
end

program clean_names
    import delimited using ../output/supplier_mapping_final, varn(1) clear 
    rename original_suppliername suppliername
    rename canonical_supplier new_suppliername
    qui {
        foreach k in "xpedx" "rent" "event" "travel" "audio" "xerox"  "acct" "cardinal health 411 inc" ///
            "henry ford health system" "illumina" "sports" "sales" "communications" "printing" ///
            "design" "photography" "music" "education" "john" "robert" "graphics" "management" ///
            "community" "publishing" "environmental" "productions" "marketing" "safety" "hour" "hardware" ///
            "investments" "entertainment" "promotional" "maintenance" "american rock salt" "lowes" "equipment" "mailing" ///
            "fire protection" "price waterhouse coopers" "hp" "radio" "cisco systems" "sanitation strategies" "network solutions" ///
            "college board" "proquest" "hill rom" "painting" "warehouse" "assurance" "blind" "davol" "atricure" "media associates" ///
             "cbord group" "united healthcare" "dimension data" "nwn" "farm" "heating" "drainage" "media" ///
             "aviation" "travel" "airline" "defense" "freight" "lumber" "floor" "clean" "construct" "blackboard" ///
             "oil" "commercial products" "kintetsu" "buhler" "nalco" "truck" "milestone" "eckert and ziegler" "newport"  ///
             "engineering" "spectroglyph"  "backup technology" "gerdau" "datadirect" "network" ///
             "plumbing" "hvac" "seating" "sprinkler" "nortrax" "marine"  "insurance" "campus" ///
             "building" "finance" "fitness" "engineering" "airport" "touring" ///
             "meeting" "commercial" "university" "college" "somanetics" "neurotune" "centerplate" "sport" ///
             "cse" "interiors" "sheraton" "film" "pentax" "fire" "machine" "tko" "brow" "lithographing" ///
            "twitchell" "ibm" "athletic" "lenovo" "immigration" "law enforcement" "school" "hotel" ///
             "publication" "advtsng" "backflow" "lymphedema" "gas" "ferguson enterprise"  "valve" "cargo" ///
            "weld" "flagcraft" "henry schein" "dental" "practicon" "alchip" "semiconductor" ///
            "canyon materials" "photo" "display" "broadcasting" "stevesongs" " press" "bioquell" "gle associates" "medrad" ///
            "psychological association" "mechanical" "3m unitek" "roofing" "print" "repair" "trophies" "trophy" "award" ///
            "cater" "repair" "book" "coffee" "auto" "optical" "beauty" "bldg" "mower" "body shop" "eye supply" "golf"  ///
            "fuel" "cdw government" "lma north america" "hamamatsu" "feed" "techniplast" "percival scientific" "zimmer" ///
            "veterinary" "teleflex" "biomet" "waste" "surgical" "surgery" "anesthesia" "salt" "orfit" "endocare" ///
           "medical" "waterpik" "imaging" "optic" "microscopy" "nurse" "urological" "nano"  "shipment" ///
           "animal" "petroleum" "dermatology" "nano" "environment" "manufacturing" "resort" "uniform" "hospital" ///
           "devices" "architectural" "pool" "pools" "use " "packaging" "revenue" "verizon" "art gallery" "team apparel" ///
           "fashion" "gardens" "art suppies" "cellular" "unifirst" "tractor" "toyota" "traffic" "foods"  "deli" "tiger" "thyssenkrupp" "accounting" ///
           "blackboard inc" "apex systems" "simplex grinnell" "mci enterpise" "medline industries" "cardinal health" "air filter" ///
           "med alliance group"  " uni" "university" "uni " "art materials" "gutter" "microscope" "radius systems" "baxter" "w nuhsbaum" "ntmdt" ///
           "xray" "safc carlsbad" "petnet" "infoready" "bmg labtech" "marriot" "structurepoint" "barry forwarding" "data strategy" ///
           "dow agroscieces" "biogen" "charter" "key performance" "professional" "communication" "images" "agency" "demolition" "furniture" ///
           "personnel" "security" "talent" "linkquest" "new york times" "consulting" "sciquest" "fisheries" "telescope" "foundation" "data support" "bowling" "vacuum" "highway" ///
           "engraving" "learning" "data " "cyotometers" "world precision instrumen" "hitachi" "shimadzu" "electronics" "implen" "medtronic" "olympus" "spectrecology" "carl zeiss" "unknown vendor" "moving" "storage" ///
           "instruments" "lighting" "filtration" "underwriters" "journal" "land planning" "water tech" "under armour" "jasco" "reliancecm" ///
           "vascular" {
            drop if strpos(new_suppliername, "`k'") > 0
        }
        * Additional non-life-science keywords found in supplier_mapping_final.csv:
        * news/print media, food/beverage, personal services, trades, real estate,
        * legal/finance, government/civic, religious, fraternal/civic orgs, hospitality.
        * Skipped (false-positive risk): "harbor" (Cold Spring Harbor), "rotary"
        * (rotary evaporator), "isd" (wisdom), "tire" (entire/retire), "title" (titley
        * scientific), "taxi" (taxidermy), "academy" (academy of sciences), "sigma"/
        * "alpha"/"delta"/etc. (would hit milliporesigma and product names).
        foreach k in "advertising" "magazine" "newspaper" "gazette" "tribune" "herald" "chronicle" ///
            "restaurant" "pizza" "cafe" "bakery" "grill" "donuts" "ice cream" ///
            "florist" "barber" "salon" "boutique" "jewelry" "jeweler" "funeral" ///
            "limousine" "shuttle" "van lines" "movers" "marina" "yacht" ///
            "concrete" "asphalt" "mason" "carpet" "drywall" "fence" "fencing" "framing" ///
            "excavat" "septic" "sewer" "rooter" "irrigation" "tree service" "stump" ///
            "refrigeration" "air conditioning" "pest" "extermin" "landscap" "lawn" ///
            "janitorial" "laundry" ///
            "real estate" "realty" "realtor" "mortgage" "title company" "escrow" ///
            "attorney" "lawyer" "law firm" "court reporter" "tax service" "bookkeep" "payroll" ///
            "city of" "county of" "state of" "dept of" "department of" ///
            "police" "sheriff" ///
            " isd" "kindergarten" "daycare" "head start" ///
            " church" "ministry" "synagogue" "mosque" ///
            "baptist" "catholic" "lutheran" "methodist" "presbyterian" "episcopal" ///
            "fraternity" "sorority" "alumni" "ymca" "ywca" "kiwanis" "lions club" "rotary club" ///
            "chamber of commerce" ///
            "casino" "lottery" "vending" "amusement" "lodge" "motel" "country club" ///
            "boy scout" "girl scout" {
            drop if strpos(new_suppliername, "`k'") > 0
        }
        * More non-life-science vendors found in supplier_mapping_final.csv:
        * big-box retail, restaurants/beverages, telecom, IT resellers/printers,
        * MRO/industrial, office furniture, music/theatre/AV, library/publishing,
        * apparel/promo, statistical software, sanitation/janitorial.
        * Skipped (FP risk): "yard"/"tree" (backyard brains, braintree scientific),
        * "dance" (bioimpedance), "monogram" (monogram biosciences), "wireless"
        * (lotek animal tracking), "ortho" (ortholog/orthogonal), "limo" (person
        * names), " seeds" (research seed companies like lehle).
        foreach k in "walmart" "costco" "sams club" "publix" "panera" "chickfila" ///
            "crystal springs" "ds waters" "nuco2" "pepsi" "coca cola" "cocacola" ///
            "oriental trading" "newegg" "barnes and noble" "starbucks" "sodexo" "aramark" ///
            "at&t" "comcast" "time warner" "globalstar" "ricoh" "konica minolta" ///
            "pitney bowes" "monoprice" "motorola" "ellucian" "blackbaud" "moredirect" ///
            "pcmall" "pcmg" "provantage" "govconnection" "mnj tech" "eplus technology" ///
            "insight public sector" "other world computing" "scantron" ///
            "haworth" "gunlocke" "virco" "mayline" "krug furniture" "blockhouse" ///
            "group lacasse" "ofs brands" "kimberly-clark" "shaw industries" "cf stinson" ///
            "herffjones" "ecolab" "amsan" "stericycle" ///
            "grainger" "mcmaster-carr" "hd supply" "fastenal" "anixter" ///
            "motion industries" "msc industrial" "hagemeyer" "applied industrial" ///
            "alro steel" "morrison supply" "coburn supply" "baker distributing" "parts express" ///
            "jw pepper" "woodwind and brasswind" "sweetwater" "full compass" "shar products" ///
            "boosey and hawkes" "samuel french" "dramatists" "markertek" "adorama" ///
            "daktronics" "shutterbooth" "compview" "stevesongs" ///
            "mcgraw-hill" "mcgraw hill" "scholastic" "jostens" "wolters kluwer" ///
            "taylor and francis" "springer nature" "lexisnexis" "oclc" "lyrasis" ///
            "ybp library" "gaylord bros" "gaylord brothers" "brodart" "demco" "highsmith" ///
            "random house" "penguin group" "ww norton" "channing bete" "baker and taylor" ///
            "rr bowker" "rr donnelley" "noellevitz" "ruffalocody" "hobsons" ///
            "nike" "adidas" "eastbay" "baudville" "smilemakers" "paramount ticket" ///
            "wells fargo" "bobcat" "aacsb" "sas institute" "statacorp" {
            drop if strpos(new_suppliername, "`k'") > 0
        }
        * Civic/membership orgs, hotels/hospitality, construction/trades,
        * promo/print/services, transit, retail/hobby, medical-services.
        * These are professional societies/associations (sell journal subs/dues,
        * not lab supplies), hotel chains, construction trades, signage/promo,
        * and other clearly non-LS vendors caught from the long tail.
        foreach k in "society of" " society" "association" " assn" "council" " club" ///
            "ministries" "diocese" "habitat for" "scouting" "youth" ///
            "holiday inn" "hampton inn" "comfort inn" "quality inn" "fairfield inn" ///
            "country inn" "garden inn" "la quinta" "embassy suites" "best western" ///
            "doubletree" "extended stay" "courtyard by" "residence inn" "townplace suites" ///
            "and suites" " tours" "americinn" ///
            "sash and door" "renovation" "appliance" "kitchen" "drapery" "millwork" ///
            "industrial supply" "metal supply" "tool supply" "electric supply" ///
            "metal works" "ironworks" ///
            "signs" "promotions" "studio" "training" "courier" "auction" ///
            "embroidery" "apparel" "wedding" "tuxedo" "stadium" "broadcast" "flowers and" ///
            "hobby" " gifts" " bus " " transit" "hauling" "towing" ///
            "fertilizer" "mulch" "chiropractic" "orthopedic" "orthodontic" {
            drop if strpos(new_suppliername, "`k'") > 0
        }
        foreach k in "cem" "na" "galls" {
            drop if new_suppliername == "`k'"
        }
    }
    drop if mi(suppliername)
    save ../output/lifescience_supplier_map, replace
end
main