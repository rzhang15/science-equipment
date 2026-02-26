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
           "devices" "architectural" "pools" "use " "packaging" "revenue" "verizon" "art gallery" "team apparel" ///
           "fashion" "gardens" "art suppies" "cellular" "unifirst" "tractor" "toyota" "traffic" "foods"  "deli" "tiger" "thyssenkrupp" "accounting" ///
           "blackboard inc" "apex systems" "simplex grinnell" "mci enterpise" "medline industries" "cardinal health" "air filter" ///
           "med alliance group"  " uni" "university" "uni " "art materials" "gutter" "microscope" "radius systems" "baxter" "w nuhsbaum" "ntmdt" ///
           "xray" "safc carlsbad" "petnet" "infoready" "bmg labtech" "marriot" "structurepoint" "barry forwarding" "data strategy" ///
           "dow agroscieces" "biogen" "charter" "key performance" "professional" "communication" "images" "agency" "demolition" "furniture" ///
           "personnel" "security" "talent" "linkquest" "new york times" "consulting" "sciquest" "fisheries" "telescope" "foundation" "data support" "bowling" "vacuum" "highway" ///
           "engraving" "learning" "data " "cyotometers" "world precision instrumen" "hitachi" "shimadzu" "electronics" "implen" "medtronic" "olympus" "spectrecology" "carl zeiss" "unknown vendor" "moving" "storage" ///
           "instruments" "lighting" "filtration" "underwriters" "journal" "land planning" "water tech" "under armour" "jasco" "reliancecm" {
            drop if strpos(new_suppliername, "`k'") > 0
        }
        foreach k in "cem" "na" {
            drop if new_suppliername == "`k'"
        }
    }
    drop if mi(suppliername)
    save ../output/lifescience_supplier_map, replace
end
main