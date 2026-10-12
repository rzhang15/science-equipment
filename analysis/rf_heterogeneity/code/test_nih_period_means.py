"""Check fixed-window NIH award means, zero years, and incomplete-window rejection."""
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    source = Path(__file__).with_name("analysis.do").read_text()
    helper = source[source.index("program nih_award_period_means\n"):
                    source.index("program event_study_het\n")]
    stata = shutil.which("stata-mp")
    if stata is None:
        raise SystemExit("stata-mp is required")
    with tempfile.TemporaryDirectory(prefix="nih_period_means_") as work:
        root = Path(work)
        (root / "test.do").write_text("set more off\nversion 17\n" + helper + FIXTURE)
        subprocess.run([stata, "-b", "do", "test.do"], cwd=root, check=True)
        log = (root / "test.log").read_text(errors="replace")
        if "NIH_PERIOD_MEANS_PASSED\n" not in log:
            raise AssertionError(log[-5000:])
    print("NIH period-mean checks passed")


FIXTURE = """
clear
set obs 30
gen str1 athr_id = cond(_n <= 10, "A", cond(_n <= 20, "B", "C"))
bysort athr_id: gen int year = 2009 + _n
gen byte post = year >= 2014
gen str1 inst_id = "X"
gen double exposure = cond(athr_id == "A", .1, .2)
gen double Z_it = exposure * post
gen double nih_total_cost = 0
replace nih_total_cost = 1200 if athr_id == "A" & year == 2010
replace nih_total_cost = 3600 if athr_id == "A" & year == 2015
replace nih_total_cost = 800 if athr_id == "B" & year == 2011
replace nih_total_cost = . if athr_id == "C"
preserve
nih_award_period_means
assert _N == 4
isid athr_id post
assert nih_total_cost == 300 if athr_id == "A" & !post
assert nih_total_cost == 600 if athr_id == "A" & post
assert nih_total_cost == 200 if athr_id == "B" & !post
assert nih_total_cost == 0 if athr_id == "B" & post
assert nih_period_years == cond(post, 6, 4)
assert Z_it == exposure * post
restore
assert _N == 30
drop if athr_id == "A" & year == 2012
preserve
capture nih_award_period_means
assert _rc == 9
restore
di "NIH_PERIOD_MEANS_PASSED"
exit, clear
"""


if __name__ == "__main__":
    main()
