"""Check NIH agency, core, and PI-project selection without rebuilding data."""
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    source = Path(__file__).with_name("build.do").read_text()
    program = source[source.index("program classify_grants\n"):source.index("program collapse_athr_year\n")]
    stata = shutil.which("stata-mp")
    if stata is None:
        raise SystemExit("stata-mp is required for these checks")
    with tempfile.TemporaryDirectory(prefix="nih_filter_test_") as work:
        root = Path(work)
        (root / "test.do").write_text("set more off\nversion 17\n" + program + FIXTURE)
        subprocess.run([stata, "-b", "do", "test.do"], cwd=root, check=True)
        log = (root / "test.log").read_text(errors="replace")
        if "NIH_AGENCY_CORE_TESTS_PASSED\n" not in log:
            raise AssertionError(log[-5000:])
    print("NIH agency/core selection checks passed")


FIXTURE = """
clear
input str3 activity str16 core_project_num str8 subproject_id str40 full_project_num str110 project_title int fy double total_cost double total_cost_sub_project byte want_nih byte want_core
"P01" "P01GM123456" "101" "5P01GM123456-02" "Administrative Core" 2012 . 300 1 1
"P50" "P50CA123456" "102" "5P50CA123456-02" "Biostatistics Shared Resource" 2012 . 200 1 1
"P01" "P01GM123456" "103" "5P01GM123456-02" "Core B: Mouse Models" 2012 . 100 1 1
"P01" "P01GM123456" "104" "5P01GM123456-02" "Research Support Core: Statistics" 2012 . 100 1 1
"P01" "P01GM123456" "105" "5P01GM123456-02" "Crystal structure of the catalytic core of an enzyme" 2012 . 100 1 0
"P01" "P01GM123456" "106" "5P01GM123456-02" "HIV Core Trafficking and Restriction" 2012 . 100 1 0
"P01" "P01GM123456" "107" "5P01GM123456-02" "Core protein assembly in HIV" 2012 . 100 1 0
"R01" "R01GM123457" "" "5R01GM123457-02" "Administration of a drug in mice" 2012 500 . 1 0
"R01" "R01HS123456" "" "5R01HS123456-02" "Health services" 2012 500 . 0 0
"R01" "R01FD123456" "" "5R01FD123456-02" "Drug safety" 2012 500 . 0 0
"U01" "U01OH123456" "" "5U01OH123456-02" "Occupational health" 2012 500 . 0 0
"R01" "R01RR123456" "" "5R01RR123456-02" "Historical NIH" 2012 500 . 1 0
"R01" "R01AT123456" "" "5R01AT123456-02" "Historical NIH" 2012 500 . 1 0
"P01" "P01GM123456" "" "5P01GM123456-02" "Umbrella" 2012 1000 . 1 0
"P01" "P01GM123456" "108" "5P01GM123456-02" "Effects of drug administration on neural signaling" 2012 . 100 1 0
"P01" "P01GM123456" "109" "5P01GM123456-02" "Immunology Core" 2012 . 100 1 1
"P01" "P01GM123456" "110" "5P01GM123456-02" "Core C6" 2012 . 100 1 1
"U01" "U01AI123456" "111" "5U01AI123456-02" "Boston Clinical Core Site" 2012 . 100 1 1
"P01" "P01GM123456" "112" "5P01GM123456-02" "The Core Apoptotic Pathway" 2012 . 100 1 0
"P01" "P01GM123456" "113" "5P01GM123456-02" "Integrative Structure Modeling of the Core SPB" 2012 . 100 1 0
"U01" "U01AI123456" "114" "5U01AI123456-02" "Coordinating Genetics Core & Clinical Trial Site" 2012 . 100 1 1
"P50" "P50CA123456" "115" "5P50CA123456-02" "Satellite Core Expansion" 2012 . 100 1 1
"UM1" "UM1AI123458" "" "5UM1AI123458-02" "Complex research program" 2012 1000 . 1 0
"R21" "R21GM123459" "" "5R21GM123459-02" "Exploratory research project" 2012 200 . 1 0
"U01" "U01AI123460" "" "5U01AI123460-02" "Individual cooperative project" 2012 400 . 1 0
end
classify_grants
assert nih_award == want_nih
assert shared_core == want_core
assert institutional_award == inlist(activity,"P01","P50","UM1")
assert research == 0 if institutional_award
assert multi_project_parent == 1 if core_project_num == "P01GM123456" & mi(subproject_id)
keep if !multi_project_parent & nih_award & !shared_core & !institutional_award & research
assert _N == 5
assert !inlist(nih_ic,"HS","FD","OH")
assert !inlist(activity,"P01","P50","UM1")
assert !shared_core
keep if core_project_num == "R01GM123457"
expand 2
assert total_cost == 500
assert _N == 2
di "NIH_AGENCY_CORE_TESTS_PASSED"
exit, clear
"""

if __name__ == "__main__":
    main()
