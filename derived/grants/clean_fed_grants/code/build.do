set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17
global temp "/scratch"

program main    
    clean_fund_id 
end

program clean_fund_id 
    use ../external/foias/merged_foias, clear
end


main
