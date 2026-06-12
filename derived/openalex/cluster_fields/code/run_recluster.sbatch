#!/bin/bash
#SBATCH --job-name=recluster_v2
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=48
#SBATCH --mem=512G
#SBATCH --time=12:00:00
#SBATCH --output=slurm-%j.out

# Rebuild the K=100 clustering on the cleaned corpus:
#   00_clean_corpus.py  -> cleaned_static_author_text_pre_v2.parquet
#   1_vectorize.py      -> tfidf_matrix.npz, feature_names.pkl, author_ids_aligned.parquet
#   2_cluster.py        -> author_static_clusters_100.csv, static_cluster_descriptions_100.txt
#
# Note: 1_vectorize.py + 2_cluster.py OVERWRITE the baseline outputs
# (tfidf_matrix.npz, author_static_clusters_100.csv). The K=100 file
# downstream pipelines read (foia_similarity_wts, exposure_msr) gets
# automatically picked up.

set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

# source ~/.bashrc
# conda activate sci_eq

echo "=== Step 0: clean corpus ==="
python -u 00_clean_corpus.py

echo "=== Step 1: vectorize ==="
python -u 1_vectorize.py

echo "=== Step 2: cluster K=100 ==="
python -u 2_cluster.py --clusters 100

echo "Done."
