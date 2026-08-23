#!/bin/bash
#SBATCH --job-name=k3_rebuild
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=16
#SBATCH --mem=96G
#SBATCH --time=03:00:00
#SBATCH --output=slurm-%j.out

# _cf_k3, _cf_ms016_k3, _lsa_k3 (all versions, no imputation EB).
set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

CL30_FULL=../../external/us_appended_text/author_static_clusters_30.csv
LSA=../../external/us_appended_text/author_ls_authors_indiv.csv

python -u 4_impute_shift_share.py --k 3 --eb-own-weight 1 --cluster-filter "$CL30_FULL"
python -u 4_impute_shift_share.py --k 3 --eb-own-weight 1 --cluster-filter "$CL30_FULL" --min-max-sim .164
python -u 4_impute_shift_share.py --k 3 --eb-own-weight 1 --ls-filter "$LSA" --ls-sfx _lsa
