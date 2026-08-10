#!/bin/bash
#SBATCH --job-name=k5_impute
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=48
#SBATCH --mem=128G
#SBATCH --time=04:00:00
#SBATCH --output=slurm-%j.out

# k=5 robustness spec. Tagged _k5 so it coexists with the untagged k=3 main
# spec (weight_matrix_k5.npz, final_imputed_*_k5*.csv, ...).
set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

CL30=../../external/us_appended_text/author_static_clusters_30_ls.csv

python -u 2_similarity_wts.py --k 5 --tag k5

# no-cf chain
python -u 4_impute_shift_share.py --tag k5

# _cf chain
for MIN in 1 2 5; do
    python -u 4_impute_shift_share.py --tag k5 --cluster-filter "$CL30" --min-foia-per-cluster $MIN
done

python -u export_diag_to_dta.py --tag k5
