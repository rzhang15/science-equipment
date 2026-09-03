#!/bin/bash
#SBATCH --job-name=athr_age_diag
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=32
#SBATCH --mem=96G
#SBATCH --time=02:00:00
#SBATCH --output=slurm-%j.out

set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

export POLARS_MAX_THREADS=$SLURM_CPUS_PER_TASK
/n/holylabs/LABS/pakes_lab/Lab/env/bin/python -u diag_rf.py > ../temp/diag.log 2>&1
