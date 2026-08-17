#!/bin/bash
#SBATCH --job-name=k3_extra
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=16
#SBATCH --mem=96G
#SBATCH --time=03:00:00
#SBATCH --output=slurm-%j.out

# Two additions to run_k3_impute_grid.sbatch:
#   1. peer-K sweep on the non-mask sample (the grid only swept it on _cf_lsa)
#   2. --min-max-sim .164 -> _ms016 (the RF sample's bottom decile), motivated by the k_sweep result that the
#      weakest-max_sim quintile has ~zero predictive correlation at every K.
set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

CL30_LSA=../../external/us_appended_text/author_static_clusters_30_lsa.csv
CL30_FULL=../../external/us_appended_text/author_static_clusters_30.csv
LSA=../../external/us_appended_text/author_ls_authors_indiv.csv

NEW="--cluster-filter $CL30_LSA --ls-filter $LSA --ls-sfx _lsa"

# --- 1. peer-K gap fill on the old-clustering / no-mask sample ---------------
for PK in 3 10; do
    python -u 4_impute_shift_share.py --k 3 --cluster-filter "$CL30_FULL" \
        --eb-own-weight .90 --eb-prior peer --eb-peer-k $PK
done

# --- 2. max_sim floor at .164 ------------------------------------------------
# no EB
python -u 4_impute_shift_share.py --k 3 --eb-own-weight 1 \
    --ls-filter "$LSA" --ls-sfx _lsa --min-max-sim .164
python -u 4_impute_shift_share.py --k 3 --eb-own-weight 1 $NEW --min-max-sim .164
python -u 4_impute_shift_share.py --k 3 --eb-own-weight 1 \
    --cluster-filter "$CL30_FULL" --min-max-sim .164

# main EB spec
python -u 4_impute_shift_share.py --k 3 $NEW --min-max-sim .164 \
    --eb-own-weight .90 --eb-prior peer --eb-peer-k 5
python -u 4_impute_shift_share.py --k 3 --cluster-filter "$CL30_FULL" \
    --min-max-sim .164 --eb-own-weight .90 --eb-prior peer --eb-peer-k 5
