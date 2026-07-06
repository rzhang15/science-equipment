#!/bin/bash
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=48
#SBATCH --mem=256G
#SBATCH --time=12:00:00
#SBATCH --job-name=predict_impact
#SBATCH --output=slurm-%j.out
#SBATCH --error=slurm-%j.out

# One-time setup, only if missing in the lab env:
#   pip install --user pyreadstat
# lightgbm, pyarrow, polars already in the lab env.

module load python/3.10.13-fasrc01 stata/17.0-fasrc01 2>/dev/null || true

cd /n/holylabs/pakes_lab/Lab/sci_eq/derived/openalex/predict_impact/code
python make.py
