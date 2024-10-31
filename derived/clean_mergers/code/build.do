set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 18
set maxvar 120000, perm 
global dropbox_dir "~/dropbox (harvard university)/scientific equipment"
global derived_output "${dropbox_dir}/derived_output"

program main   
end

program clean_mergers 
    syntax, file(str)
    * sigma_aldrich_1965
    * subset_target_sic
    * thermo_fisher_1965
    use ../external/sdc/sdc_mergers_thermo_fisher_1965, clear
    rename *, lower

end

program merger_hist


end

**
main
