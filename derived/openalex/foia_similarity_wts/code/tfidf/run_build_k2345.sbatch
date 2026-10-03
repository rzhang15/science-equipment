#!/bin/bash
#SBATCH --job-name=build_k2345
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=48
#SBATCH --mem=256G
#SBATCH --time=06:00:00
#SBATCH --output=slurm-%j.out

set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

CL30_FULL=../../external/us_appended_text/author_static_clusters_30.csv

for K in 2 3 4 5; do
    python -u 2_similarity_wts.py --k $K --out-tag k$K
    python -u 4_impute_shift_share.py --k $K --tag-k --eb-own-weight 1 --cluster-filter "$CL30_FULL" --all3 --versions hc
    python -u 5d_loo_shares.py --version hc --sample all3 --k $K
done
