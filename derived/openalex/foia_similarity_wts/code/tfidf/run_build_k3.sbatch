#!/bin/bash
#SBATCH --job-name=build_k3
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=48
#SBATCH --mem=256G
#SBATCH --time=06:00:00
#SBATCH --output=slurm-%j.out

# Upstream build for the k=3 spec (k=5 is retired). Produces the TF-IDF
# artifacts, weight_matrix_k3.npz, and the Stata match-diagnostics export.
# The imputation grid itself lives in run_k3_impute_grid.sbatch.
set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

# VECTORIZE=1 reruns 1_vectorize.py first (use when its outputs aren't
# already fresh from the new corpus).
if [ "${VECTORIZE:-0}" = "1" ]; then
    python -u 1_vectorize.py
fi

python -u 2_similarity_wts.py --k 3 --out-tag k3

python -u export_diag_to_dta.py
