#!/bin/bash
#SBATCH --job-name=k3_impute_cf
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=slurm-%j.out

# Filtered k=3 variants only -- reuses weight_matrix_k3.npz from
# run_k3_impute.sbatch. Use after refreshing the cluster worksheet / _ls file
# without rebuilding weights.
set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

CL30=../../external/us_appended_text/author_static_clusters_30.csv
CL30_LS=../../external/us_appended_text/author_static_clusters_30_ls.csv

python -u 4_impute_shift_share.py --k 3 --cluster-filter "$CL30"
python -u 4_impute_shift_share.py --k 3 --ls-filter "$CL30_LS"
python -u 4_impute_shift_share.py --k 3 --cluster-filter "$CL30" --ls-filter "$CL30_LS"
