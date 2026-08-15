#!/bin/bash
#SBATCH --job-name=k3_impute_eb_ls
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=16
#SBATCH --mem=96G
#SBATCH --time=06:00:00
#SBATCH --output=slurm-%j.out

# _ls and _cf_ls variants of every EB cell. Imputed values per author are
# identical to the _cf files -- filters are post-imputation row subsets --
# so these only differ in which authors are kept. Reuses weight_matrix_k3.npz.
# --eb-cluster-file is passed explicitly so the cluster prior works in the
# bare-_ls invocations, where no --cluster-filter is set.
set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

CL30=../../external/us_appended_text/author_static_clusters_30.csv
CL30_LS=../../external/us_appended_text/author_static_clusters_30_ls.csv

run_ls () {
    python -u 4_impute_shift_share.py --k 3 --eb-cluster-file "$CL30" --ls-filter "$CL30_LS" "$@"
    python -u 4_impute_shift_share.py --k 3 --eb-cluster-file "$CL30" --cluster-filter "$CL30" --ls-filter "$CL30_LS" "$@"
}

for A in 2500 5000 10000; do
    run_ls --eb-alpha $A
    run_ls --eb-alpha $A --eb-prior peer
    run_ls --eb-alpha $A --eb-prior cluster
done
run_ls --eb-alpha median
