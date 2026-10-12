#!/bin/bash
#SBATCH --job-name=build_k5
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=48
#SBATCH --mem=256G
#SBATCH --time=04:00:00
#SBATCH --output=slurm-%j.out

set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

CL30_FULL=../../external/us_appended_text/author_static_clusters_30.csv

python -u 4_impute_shift_share.py --k 5 --tag-k --eb-own-weight 1 --cluster-filter "$CL30_FULL" --all3 --versions hc
python -u 8_placebo_shift_share.py --version hc --all3 --k 5 --tag-k --cluster-filter "$CL30_FULL"
python -u 5d_loo_shares.py --version hc --sample all3 --k 5
python -u 9_k_choice_plot.py --k-star 5
