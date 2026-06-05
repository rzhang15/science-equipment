#!/bin/bash
#SBATCH --job-name=foia_tfidf
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=48
#SBATCH --mem=256G
#SBATCH --time=06:00:00
#SBATCH --output=slurm-%j.out

# Why 48 cores: the universe transform is the dominant cost. With
# TRANSFORM_CHUNK_SIZE=20k and ~2.66M universe rows -> ~133 chunks, so
# going above ~64 workers gives diminishing returns. 48 is a good balance
# between parallelism and queue wait time.
#
# Why 256G mem: the loky backend pickles the fitted TfidfVectorizer to
# every worker. With ~60k features in the vocab and 48 workers that's
# tens of GB just in vectorizer copies, plus the universe sparse matrices.
# Bump to 512G if you see OOM in the stack trace.

set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

# source ~/.bashrc
# conda activate sci_eq

STAGE="${STAGE:-full}"     # full = vectorize + sim weights + impute
echo "Stage: $STAGE   CPUs: $SLURM_CPUS_PER_TASK"

python -u 1_vectorize.py

if [ "$STAGE" = "full" ]; then
    python -u 2_similarity_wts.py
    python -u 3_impute_exposure.py
fi
