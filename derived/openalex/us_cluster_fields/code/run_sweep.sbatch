#!/bin/bash
#SBATCH --job-name=us_cluster_sweep
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=48
#SBATCH --mem=256G
#SBATCH --time=12:00:00
#SBATCH --output=slurm-sweep-%j.out

# Two-stage build on the US-only corpus.
#
#   STAGE 1  cluster all US authors at K=100, then flag the non-life-science
#            clusters. K=100 is a throwaway partition used only to build the
#            author-level keep list; it is never a field variable.
#   STAGE 2  refit TF-IDF on the retained authors only and sweep K. These are
#            the field clusters. Outputs carry the _ls suffix.
#
# Stage 2 refits rather than reusing stage 1's matrix on purpose: dropping the
# materials/ecology/CS authors changes the vocabulary and the IDF weights, so
# a matrix fit on the full pool would still be spending features on terms no
# retained author uses.
#
# Env overrides (all default to "build only if missing"):
#   FORCE_SUBSET=1     re-cut the US subset from the worldwide corpus
#   FORCE_CLEAN=1      re-run the boilerplate/short-text clean
#   FORCE_VECTORIZE=1  re-fit stage 1 TF-IDF
#   STAGE=1|2|all      run only one stage (default all)

set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

# Let BLAS (TruncatedSVD's randomized solver and MiniBatchKMeans' dense
# matmuls) actually use the cores we asked for. Without these, numpy
# defaults to 1 thread and the job runs at ~2% utilization.
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK:-48}
export MKL_NUM_THREADS=${SLURM_CPUS_PER_TASK:-48}
export OPENBLAS_NUM_THREADS=${SLURM_CPUS_PER_TASK:-48}

STAGE=${STAGE:-all}
KEEP=../output/life_science_authors_100.csv

# source ~/.bashrc
# conda activate sci_eq

if [ "$STAGE" = "1" ] || [ "$STAGE" = "all" ]; then
    echo "######## STAGE 1: life-science mask ########"

    # Re-subset from the worldwide corpus if missing (or FORCE_SUBSET=1).
    # Needed whenever cluster_fields rebuilds
    # cleaned_static_author_text_pre.parquet — the stemming there depends on
    # the stopword list in config.py, so a stale subset carries stale text.
    if [ ! -f ../output/cleaned_static_author_text_pre_us.parquet ] || [ "$FORCE_SUBSET" = "1" ]; then
        echo "=== 0_us_subset.py ==="
        python -u 0_us_subset.py
    fi

    if [ ! -f ../output/cleaned_static_author_text_pre_us_v2.parquet ] || [ "$FORCE_CLEAN" = "1" ]; then
        echo "=== 0b_clean_us_corpus.py ==="
        python -u 0b_clean_us_corpus.py
    fi

    if [ ! -f ../output/tfidf_matrix.npz ] || [ "$FORCE_VECTORIZE" = "1" ]; then
        echo "=== 1_vectorize.py (full US pool) ==="
        python -u 1_vectorize.py
    fi

    echo "=== 2_cluster.py --clusters 100 ==="
    python -u 2_cluster.py --clusters 100

    echo "=== 3_filter_life_science.py --k 100 ==="
    python -u 3_filter_life_science.py --k 100

    echo "STAGE 1 done. Review ../output/cluster_filter_audit_100.txt and edit"
    echo "the keep column in ../output/cluster_label_worksheet_100.csv, then"
    echo "re-run 3_filter_life_science.py --k 100 --use-manual before stage 2."
fi

if [ "$STAGE" = "2" ] || [ "$STAGE" = "all" ]; then
    echo "######## STAGE 2: field clusters on life-science authors ########"

    if [ ! -f "$KEEP" ]; then
        echo "missing $KEEP -- run stage 1 first" >&2
        exit 1
    fi

    echo "=== 1_vectorize.py --keep-authors --suffix _ls ==="
    python -u 1_vectorize.py --keep-authors "$KEEP" --suffix _ls

    # Sweep for the K-selection evidence. Every run appends a row to
    # ../output/k_diagnostics_ls.csv (inertia + sampled silhouette).
    #
    # K=100 is not a field-size candidate: it exists so foia_similarity_wts'
    # --cluster-filter (_cf) tests domain validity on a partition fit on the
    # same life-science pool as the K=30 field variable. Using stage 1's
    # K=100 instead leaves the sample restriction and the field FE defined on
    # two different embeddings of two different populations.
    for K in 10 15 20 25 30 35 40 50 100; do
        echo "=== K=$K (life-science pool) ==="
        python -u 2_cluster.py --clusters $K --suffix _ls
    done
fi

echo "Done."
