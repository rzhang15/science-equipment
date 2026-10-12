import argparse
import os
import shutil
import sys
from pathlib import Path

from gslab_make.move_sources import link_externals
from gslab_make.run_program import run_python, run_stata
from gslab_make.write_logs import start_makelog, end_makelog


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--validation-only', action='store_true')
    args = ap.parse_args()
    os.chdir(Path(__file__).resolve().parent)
    for folder in ['../temp', '../output', '../output/tables',
                   '../output/figures/paper', '../output/figures/pres']:
        os.makedirs(folder, exist_ok=True)
    paths = {'makelog': '../output/make.log', 'external_dir': '../external/',
             'root': str(Path(__file__).resolve().parents[3])}
    external = Path('../external')
    if external.exists():
        entries = list(external.iterdir())
        if any(not p.is_symlink() for p in entries):
            raise RuntimeError('The module external/ contains a non-link; preserving it.')
        for path in entries:
            path.unlink()
        external.rmdir()
    start_makelog(paths)
    link_externals(paths, ['links.txt'])
    run_python(paths, program='prep_university.py', executable=sys.executable,
               log='../output/prep_university.log')
    run_python(paths, program='prep_validation.py', executable=sys.executable,
               log='../output/prep_validation.log')
    stata = os.environ.get('STATA_BIN') or shutil.which('stata-mp') or shutil.which('stata')
    if not stata:
        raise RuntimeError('Stata is required; set STATA_BIN to its executable.')
    run_stata(paths, program='validation.do', executable=stata, option='-b',
              log='../output/validation.log')
    if not args.validation_only:
        run_stata(paths, program='robustness.do', executable=stata, option='-b',
                  log='../output/robustness.log')
        run_python(paths, program='summarize.py', executable=sys.executable,
                   log='../output/summarize.log')
    end_makelog(paths)


if __name__ == '__main__':
    main()
