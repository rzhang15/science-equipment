set more off
clear all
capture log close
program drop _all
set scheme modern
version 18
global dropbox_dir "~/dropbox (harvard university)/scientific equipment"

* Ruby's macros 
global dropbox_dir "$sci_equip"
cd "$github/science-equipment/derived/clean_mri/code"

global raw "${dropbox_dir}/raw"
global derived_output "${dropbox_dir}/derived_output"

program main 

	append_nsf_mri_grants
	
end 
