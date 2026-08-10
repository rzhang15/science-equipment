#!/bin/bash
#SBATCH --job-name=k5_impute
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=48
#SBATCH --mem=256G
#SBATCH --time=06:00:00
#SBATCH --output=slurm-%j.out

# Main spec: k=5 weights, untagged -> bare filenames that analysis.do reads.
# Produces the filter 2x2: hc / hc_cf / hc_ls / hc_cf_ls (per version).
set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

CL30=../../external/us_appended_text/author_static_clusters_30.csv
CL30_LS=../../external/us_appended_text/author_static_clusters_30_ls.csv

# VECTORIZE=1 reruns 1_vectorize.py first (use when its outputs aren't
# already fresh from the new corpus).
if [ "${VECTORIZE:-0}" = "1" ]; then
    python -u 1_vectorize.py
fi

# REBUILD_W=1 rebuilds the untagged k=5 weight matrix (required after a
# vectorize rerun).
if [ "${REBUILD_W:-0}" = "1" ]; then
    python -u 2_similarity_wts.py --k 5
fi

python -u 4_impute_shift_share.py
python -u 4_impute_shift_share.py --cluster-filter "$CL30"
python -u 4_impute_shift_share.py --ls-filter "$CL30_LS"
python -u 4_impute_shift_share.py --cluster-filter "$CL30" --ls-filter "$CL30_LS"

python -u export_diag_to_dta.py
