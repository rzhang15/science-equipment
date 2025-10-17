set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main 
    comp_hhi, embed(tfidf)
end


program comp_hhi 
    syntax, embed(string)
    use ../external/samp/category_hhi_`embed', replace    
    corr simulated_hhi delta_hhi
    local corr: dis %4.3f r(rho)
    tw scatter simulated_hhi delta_hhi, mlabel(category) msize(vsmall) mlabsize(tiny) ///
      ytitle("Simulated HHI = 2 x Thermo x LifeTech",  size(small))  ///
      xlab(, labsize(small)) ylab(, labsize(small)) ///
      xtitle("Delta HHI (Post Period - Pre Period HHI)", size(small)) ///
      legend(on order(- "Correlation : `corr'") ring(0) pos(1) size(vsmall))
    graph export ../output/figures/sim_delta_hhi.pdf, replace
    sum simulated_hhi, d
    local mean : dis %4.3f r(mean)
    local sd  : dis %4.3f r(sd)
    local N : dis %4.3f r(N)
    tw hist simulated_hhi, freq bin(20) color(lavender%80) xtitle("Simulated HHI", size(small)) xlab(, labsize(small)) ylab(, labsize(small)) legend(on order(- "Mean = `mean'" "SD = `sd'" "# of mkts = `N'") ring(0) pos(1) size(small))
    graph export ../output/figures/sim_hhi_dist.pdf, replace
    
    sum delta_hhi, d
    local mean : dis %4.3f r(mean)
    local sd  : dis %4.3f r(sd)
    local N : dis %4.3f r(N)
    
    tw hist delta_hhi, freq bin(20) color(lavender%80) xlabel(-5000(1000)10000, labsize(small)) ylab(, labsize(small)) ytitle(, size(small)) xtitle("Delta HHI", size(small)) legend(on order(- "Mean = `mean'" "SD = `sd'" "# of mkts = `N'") ring(0) pos(1) size(small))
    graph export ../output/figures/delta_hhi_dist.pdf, replace
end

**
main
