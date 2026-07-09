#!/bin/bash
#SBATCH --job-name=ridge_vs_knn
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=00:30:00
#SBATCH --output=slurm-%j.out

# Head-to-head Ridge vs top-K K-NN on identical folds.
# Only fits on the 208-row FOIA matrix per fold, so this is cheap.
# 32G / 30 min is generous; the whole loop is well under 5 min.

set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

for V in hc all treated_hc; do
    python -u 6_ridge_vs_knn.py \
        --tag restricted \
        --exposure-dta "../../external/exposure_wts/athr_exposure_${V}.dta" \
        --out-tag "${V}"
done
