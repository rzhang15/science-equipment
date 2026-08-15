#!/bin/bash
#SBATCH --job-name=k3_impute_eb
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=16
#SBATCH --mem=96G
#SBATCH --time=03:00:00
#SBATCH --output=slurm-%j.out

# EB-shrunk variants of the production _cf_k3 spec -- reuses
# weight_matrix_k3.npz. Rerun exposure_msr/build.do first so the share
# files reflect the sum-over-pre-period fix. Shrunk S is dense, so the
# imputed share matrices are ~10x larger than the raw-share versions.
set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

CL30=../../external/us_appended_text/author_static_clusters_30.csv

python -u 4_impute_shift_share.py --k 3 --cluster-filter "$CL30" --eb-alpha 5000
python -u 4_impute_shift_share.py --k 3 --cluster-filter "$CL30" --eb-alpha 10000
python -u 4_impute_shift_share.py --k 3 --cluster-filter "$CL30" --eb-alpha median
