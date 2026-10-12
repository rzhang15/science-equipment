"""Rerun only equal-share NIH funding and productivity; keep other analyses intact."""
from pathlib import Path
import shutil
import csv
import subprocess
import tempfile

code = Path(__file__).resolve().parent
def rerun():
    source = (code / "analysis.do").read_text()
    programs = source[:source.rfind("\nmain")].replace("capture log close\n", "")
    driver = (code / "rerun_pi_allocation.do").read_text().replace("// INSERT_ANALYSIS_PROGRAMS", programs)
    with tempfile.TemporaryDirectory(prefix="nih_pi_allocation_") as work:
        script = Path(work) / "rerun.do"
        script.write_text(driver)
        subprocess.run([shutil.which("stata-mp") or "stata-mp", "-b", "do", str(script)], cwd=code, check=True)
    log = (code.parent / "output/pi_allocation_rerun.log").read_text(errors="replace")
    if "PI_ALLOCATION_RERUN_PASSED" not in log:
        raise RuntimeError(log[-4000:])
    print("PI allocation and productivity rerun passed")

def export_valuations():
    """Monetary constants 10 and 3.66 are in millions of dollars."""
    out = code.parent / "output/tables"
    rows = []
    for suffix in ("", "_public"):
        with (out / f"section51_all{suffix}.csv").open() as handle:
            stats = {k: float(v) for k, v in next(csv.DictReader(handle)).items()}
        lost = 349 * stats["nih_per_paper"] / 1_000_000
        rows.append(dict(sample="all" + suffix, **stats,
                         value_lost_millions=lost, patents_lost=lost / 10 * 2.3,
                         breakeven_shift_share=1 - 3.66 / lost))
    with (out / "section51_valuation.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    for row in rows:
        print(row)

if __name__ == "__main__":
    rerun()
    export_valuations()
