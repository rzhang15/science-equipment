#!/bin/bash
#SBATCH --job-name=us_cluster_sweep
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=48
#SBATCH --mem=256G
#SBATCH --time=12:00:00
#SBATCH --output=slurm-sweep-%j.out

# Re-run 2_cluster.py under the SVD+KMeans pipeline across a K sweep on the
# US-only corpus. Reuses tfidf_matrix.npz, feature_names.pkl, and
# author_ids_aligned.parquet from 1_vectorize.py.
#
# Outputs per K (in ../output/):
#   author_static_clusters_${K}.csv        (OVERWRITES if exists)
#   static_cluster_descriptions_${K}.txt   (OVERWRITES if exists)

set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

# Let BLAS (TruncatedSVD's randomized solver and MiniBatchKMeans' dense
# matmuls) actually use the cores we asked for. Without these, numpy
# defaults to 1 thread and the job runs at ~2% utilization.
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK:-48}
export MKL_NUM_THREADS=${SLURM_CPUS_PER_TASK:-48}
export OPENBLAS_NUM_THREADS=${SLURM_CPUS_PER_TASK:-48}

# source ~/.bashrc
# conda activate sci_eq

# Clean the US corpus first if the v2 parquet is missing (or FORCE_CLEAN=1).
# Drops scraper-boilerplate + short-text authors so the clustering universe
# and the tfidf universe stay identical (both read the v2 file).
if [ ! -f ../output/cleaned_static_author_text_pre_us_v2.parquet ] || [ "$FORCE_CLEAN" = "1" ]; then
    echo "=== 0b_clean_us_corpus.py ==="
    python -u 0b_clean_us_corpus.py
fi

# If tfidf_matrix.npz is stale (or missing), re-run 1_vectorize.py first.
if [ ! -f ../output/tfidf_matrix.npz ] || [ "$FORCE_VECTORIZE" = "1" ]; then
    echo "=== 1_vectorize.py ==="
    python -u 1_vectorize.py
fi

for K in 10 15 20 25 30; do
    echo "=== K=$K ==="
    python -u 2_cluster.py --clusters $K
done

echo "Done."
