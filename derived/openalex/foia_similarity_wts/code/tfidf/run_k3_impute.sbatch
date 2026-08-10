#!/bin/bash
#SBATCH --job-name=k3_impute
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=48
#SBATCH --mem=256G
#SBATCH --time=06:00:00
#SBATCH --output=slurm-%j.out

# k=3 robustness spec, suffix _k3. Builds weight_matrix_k3.npz from the
# untagged TF-IDF inputs, then the same filter 2x2 as run_k5_impute.sbatch
# (hc_k3 / hc_cf_k3 / hc_ls_k3 / hc_cf_ls_k3, per version).
set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

CL30=../../external/us_appended_text/author_static_clusters_30.csv
CL30_LS=../../external/us_appended_text/author_static_clusters_30_ls.csv

python -u 2_similarity_wts.py --k 3 --out-tag k3

python -u 4_impute_shift_share.py --k 3
python -u 4_impute_shift_share.py --k 3 --cluster-filter "$CL30"
python -u 4_impute_shift_share.py --k 3 --ls-filter "$CL30_LS"
python -u 4_impute_shift_share.py --k 3 --cluster-filter "$CL30" --ls-filter "$CL30_LS"
