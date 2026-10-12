"""Run one gslab-style module (derived/* or analysis/*) non-interactively.

    run_module.py MODULE_DIR                       exec the module's make.py as-is
    run_module.py MODULE_DIR --setup-only P ...    make.py with run_* stubbed (clear/mkdir/link only), then run P ...
    run_module.py MODULE_DIR --skip-make  P ...    do not touch make.py, just run P ...

Each P is "script.ext [arg ...]"; .do -> stata-mp, .R -> Rscript, .py -> python.
Stata args are passed through a wrapper do-file so concurrent runs get distinct logs.
"""
import argparse
import builtins
import os
import re
import subprocess
import sys

import gslab_make.private.metadata as md
import gslab_make.run_program as rp
from gslab_make.run_program import run_python, run_r, run_stata

PATHS = {'makelog': '../output/make.log', 'external_dir': '../external/'}


def exec_make(setup_only):
    builtins.input = lambda *a, **k: ''
    if setup_only:
        for name in ('run_stata', 'run_r', 'run_python'):
            setattr(rp, name, lambda *a, **k: None)
    sys.argv = ['make.py']
    with open('make.py') as f:
        src = f.read()
    exec(compile(src, 'make.py', 'exec'), {'__name__': '__main__', '__file__': 'make.py'})


def run_stata_args(program, args):
    stem = os.path.splitext(os.path.basename(program))[0]
    tag = '_'.join(re.sub(r'[^A-Za-z0-9]+', '', a) for a in args)
    os.makedirs('../temp', exist_ok=True)
    wrapper = f'../temp/_run_{stem}_{tag}.do'
    with open(wrapper, 'w') as f:
        f.write(f'do {program} {" ".join(args)}\n')
    log = f'_run_{stem}_{tag}.log'
    rc = subprocess.call(['stata-mp', '-e', 'do', wrapper])
    with open(log) as f:
        out = f.read()
    with open(PATHS['makelog'], 'a') as f:
        f.write(out)
    os.remove(log)
    if rc != 0 or re.search(r'end of do-file[\s]*r\([0-9]*\);', out):
        sys.exit(f'Stata error in {program} {args}; see {PATHS["makelog"]}')


def run_r_args(program, args):
    with open(PATHS['makelog'], 'a') as log:
        rc = subprocess.call(['Rscript', '--no-save', program] + args, stdout=log, stderr=subprocess.STDOUT)
    if rc != 0:
        sys.exit(f'R error in {program} {args}; see {PATHS["makelog"]}')


def run_program(spec):
    parts = spec.split()
    program, args = parts[0], parts[1:]
    ext = os.path.splitext(program)[1].lower()
    print(f'>>> {spec}', flush=True)
    if ext == '.do':
        if args:
            run_stata_args(program, args)
        else:
            run_stata(PATHS, program=program)
    elif ext == '.r':
        if args:
            run_r_args(program, args)
        else:
            run_r(PATHS, program=program)
    elif ext == '.py':
        run_python(PATHS, program=program, args=' '.join(args))
    else:
        sys.exit(f'unknown program type: {spec}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('module_dir')
    ap.add_argument('--setup-only', action='store_true')
    ap.add_argument('--skip-make', action='store_true')
    ap.add_argument('programs', nargs='*')
    a = ap.parse_intermixed_args()

    os.chdir(os.path.join(a.module_dir, 'code'))
    print(f'=== {os.getcwd()}', flush=True)
    if not a.skip_make:
        exec_make(a.setup_only)
    if a.programs:
        os.makedirs('../output', exist_ok=True)
        open(PATHS['makelog'], 'a').close()
        md.makelog_started = True
    for p in a.programs:
        run_program(p)
    print('=== done', flush=True)


if __name__ == '__main__':
    main()
