#!/bin/bash
#SBATCH --job-name=foia_build_unstemmed
#SBATCH --partition=shared
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=slurm-%j.out

set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

# Activate the env that has pandas + polars (same as run_pipeline.sbatch).
# source ~/.bashrc
# conda activate sci_eq

python -u 0b_build_foia_unstemmed.py
python -u 0c_build_coauthor_unstemmed.py
