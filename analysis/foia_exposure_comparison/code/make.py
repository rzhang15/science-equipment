import os
import shutil
from pathlib import Path

from gslab_make.move_sources import link_externals
from gslab_make.run_program import run_stata
from gslab_make.write_logs import start_makelog, end_makelog


def main():
    os.chdir(Path(__file__).resolve().parent)
    for folder in ['../temp', '../output']:
        os.makedirs(folder, exist_ok=True)
    paths = {'makelog': '../output/make.log', 'external_dir': '../external/',
             'root': str(Path(__file__).resolve().parents[3])}
    external = Path('../external')
    if external.exists():
        entries = list(external.iterdir())
        if any(not p.is_symlink() for p in entries):
            raise RuntimeError('Preserving non-link files in external/.')
        for p in entries:
            p.unlink()
        external.rmdir()
    start_makelog(paths)
    link_externals(paths, ['links.txt'])
    stata = os.environ.get('STATA_BIN') or shutil.which('stata-mp') or shutil.which('stata')
    if not stata:
        raise RuntimeError('Set STATA_BIN to the Stata executable.')
    run_stata(paths, program='analysis.do', executable=stata, option='-b',
              log='../output/analysis.log')
    end_makelog(paths)


if __name__ == '__main__':
    main()
