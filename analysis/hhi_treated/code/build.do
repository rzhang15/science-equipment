set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries

adopath ++ "../external/lib/stata"
version 17

program main 
    comp_hhi, embed(tfidf)
end

program comp_hhi 
    syntax, embed(string)
    use ../external/samp/category_hhi_`embed', replace    
    drop if strpos(category, "synthetic dna") > 0 | strpos(category, "synthetic rna") > 0
    corr simulated_hhi delta_hhi
    local corr: dis %4.3f r(rho)
    tw scatter simulated_hhi delta_hhi, mlabel(category) msize(vsmall) mlabsize(tiny) ///
      ytitle("Simulated HHI = 2 x Thermo x LifeTech",  size(medsmall))  ///
      xlab(, labsize(small)) ylab(, labsize(small)) ///
      xtitle("Delta HHI (post period - pre period HHI)", size(medsmall)) ///
      legend(on order(- "Correlation : `corr'") ring(0) pos(1) size(small))
    fig_export, path("../output/figures/sim_delta_hhi.pdf")
    sum simulated_hhi, d
    local mean : dis %4.3f r(mean)
    local sd  : dis %4.3f r(sd)
    local N : dis %4.3f r(N)
    tw hist simulated_hhi, freq bin(20) color(lavender%80) xtitle("Simulated HHI", size(medsmall)) xlab(, labsize(small)) ylab(, labsize(small)) legend(on order(- "Mean = `mean'" "SD = `sd'" "# of mkts = `N'") ring(0) pos(1) size(small))
    fig_export, path("../output/figures/sim_hhi_dist.pdf")
    
    sum delta_hhi, d
    local mean : dis %4.3f r(mean)
    local sd  : dis %4.3f r(sd)
    local N : dis %4.3f r(N)
    local p25: dis  %4.3f r(p25)
    local p50: dis  %4.3f r(p50)
    local p75: dis  %4.3f r(p75)
    
    tw hist delta_hhi, freq bin(20) color(lavender%80) xlabel(-7000(1000)3000, labsize(small)) ylab(, labsize(small)) ytitle(, size(small)) xtitle("Delta HHI", size(medsmall)) ///
      legend(on order(- "Mean = `mean'" "SD = `sd'" "# of mkts = `N'" "P25 = `p25'" "P50 = `p50'" "P75 = `p75'") ring(0) pos(11) size(small))
    fig_export, path("../output/figures/delta_hhi_dist.pdf")
end

main
