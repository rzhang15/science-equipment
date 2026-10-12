program fig_export
    syntax, path(string) [mode(string) xsize(real 6) ysize(real 4)]
    local p : subinstr local path "/paper/" "/", all
    local p : subinstr local p "/pres/" "/", all
    local k = strpos("`p'", "figures/")
    if `k' > 0 {
        local base = substr("`p'", 1, `k' + 7)
        local rest = substr("`p'", `k' + 8, .)
    }
    else {
        local slash = strrpos("`p'", "/")
        local base = substr("`p'", 1, `slash')
        local rest = substr("`p'", `slash' + 1, .)
    }
    local tscale = cond(`xsize' >= `ysize', (2/3) * `xsize' / min(`xsize', `ysize'), 1)
    if "`mode'" == "presentation" local mode pres
    local pres_scale 1.2
    if "$PRES_SCALE" != "" local pres_scale $PRES_SCALE
    foreach m in paper pres {
        if "`mode'" != "" & "`mode'" != "`m'" continue
        local dir "`base'`m'"
        cap mkdir "`dir'"
        local sub "`rest'"
        while strpos("`sub'", "/") > 0 {
            local seg = substr("`sub'", 1, strpos("`sub'", "/") - 1)
            local dir "`dir'/`seg'"
            cap mkdir "`dir'"
            local sub = substr("`sub'", strpos("`sub'", "/") + 1, .)
        }
        local s = cond("`m'" == "pres", `tscale' * `pres_scale', `tscale')
        graph display, scale(`s')
        graph export "`base'`m'/`rest'", replace
    }
end
