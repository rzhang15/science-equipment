#!/bin/bash
#SBATCH --job-name=k3_impute_eb_lsa
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=16
#SBATCH --mem=96G
#SBATCH --time=06:00:00
#SBATCH --output=slurm-%j.out

# _lsa and _cf_lsa variants of every EB cell, using the author-level
# life-science mask (us_cluster_fields/3b_author_ls_score.py) instead of the
# cluster-level _ls mask. Run run_author_ls_score.sbatch first.
set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

CL30=../../external/us_appended_text/author_static_clusters_30.csv
LSA=../../external/us_appended_text/author_ls_authors_indiv.csv

run_lsa () {
    python -u 4_impute_shift_share.py --k 3 --eb-cluster-file "$CL30" --ls-filter "$LSA" --ls-sfx _lsa "$@"
    python -u 4_impute_shift_share.py --k 3 --eb-cluster-file "$CL30" --cluster-filter "$CL30" --ls-filter "$LSA" --ls-sfx _lsa "$@"
}

run_lsa
for A in 2500 5000 10000; do
    run_lsa --eb-alpha $A
    run_lsa --eb-alpha $A --eb-prior peer
    run_lsa --eb-alpha $A --eb-prior cluster
done
run_lsa --eb-alpha median
