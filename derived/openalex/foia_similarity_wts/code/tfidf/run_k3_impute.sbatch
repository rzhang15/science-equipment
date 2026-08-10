#!/bin/bash
#SBATCH --job-name=k3_impute
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=48
#SBATCH --mem=256G
#SBATCH --time=06:00:00
#SBATCH --output=slurm-%j.out

set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

# VECTORIZE=1 reruns 1_vectorize.py first (use when its outputs aren't
# already fresh from the new corpus).
if [ "${VECTORIZE:-0}" = "1" ]; then
    python -u 1_vectorize.py
fi

# k=3 weights, untagged -> bare filenames that analysis.do reads
python -u 2_similarity_wts.py --k 3

# no-cf chain
python -u 4_impute_shift_share.py

python -u export_diag_to_dta.py
