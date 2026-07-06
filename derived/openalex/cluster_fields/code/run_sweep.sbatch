#!/bin/bash
#SBATCH --job-name=cluster_sweep
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=48
#SBATCH --mem=512G
#SBATCH --time=24:00:00
#SBATCH --output=slurm-sweep-%j.out

# Re-run 2_cluster.py under the current SVD pipeline across a K sweep.
# TF-IDF cache (tfidf_matrix.npz, feature_names.pkl, author_ids_aligned.parquet)
# from Jun 11 is reused; we do NOT rerun 00_clean_corpus.py or 1_vectorize.py.
#
# Outputs per K:
#   author_static_clusters_${K}.csv        (OVERWRITES existing)
#   static_cluster_descriptions_${K}.txt   (OVERWRITES existing)

set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK:-48}
export MKL_NUM_THREADS=${SLURM_CPUS_PER_TASK:-48}
export OPENBLAS_NUM_THREADS=${SLURM_CPUS_PER_TASK:-48}

for K in 10 15 20 25 30; do
    echo "=== K=$K ==="
    python -u 2_cluster.py --clusters $K
done

echo "Done."
