#****************************************************
# make.py  --  derived/openalex/predict_impact
#****************************************************
import os
import subprocess
import sys

from gslab_make.move_sources import *
from gslab_make.run_program import *
from gslab_make.modify_dir import *
from gslab_make.write_logs import *

# clear_dir(['../output/', '../temp/'])
remove_dir(['../external/'])
paths = {'makelog': '../output/make.log', 'external_dir': '../external/'}
start_makelog(paths)

# MAKE LINKS
link_externals(paths, ['links.txt'])

# Phase 1: feature build
PYTHON_STEPS = [
    '00_convert_papers_to_parquet.py',
    '01_field_year_normalize.py',
    '02_paper_features.py',
    '02b_pi_features.py',
    '02d_paper_mesh_features.py',
    '02e_pi_svd_features.py',
    '02c_assemble_training_table.py',
    # Phase 2: train, score, collapse
    '03_train_freeze_model.py',
    '04_score_papers.py',
    '05_collapse_to_pi_year.py',
    # Phase 3: self-management variables
    '06_assemble_self_management_panel.py',
]
for step in PYTHON_STEPS:
    print(f"\n>>> python {step}", flush=True)
    rc = subprocess.call([sys.executable, step])
    if rc != 0:
        sys.exit(f"step {step} failed with rc={rc}")

# Final: merge tier counts onto the panel variants
run_stata(paths, program='build.do')

end_makelog(paths)
