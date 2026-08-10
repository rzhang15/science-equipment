#!/bin/bash
#SBATCH --job-name=k3_impute_cf
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=slurm-%j.out

# _cf chain: reuses the untagged k=3 weight_matrix.npz from run_k3_impute.sbatch
set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

CL30=../../external/us_appended_text/author_static_clusters_30_ls.csv

for MIN in 1 2 5; do
    python -u 4_impute_shift_share.py --cluster-filter "$CL30" --min-foia-per-cluster $MIN
done
