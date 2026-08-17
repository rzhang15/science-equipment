#!/bin/bash
#SBATCH --job-name=k_sweep
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=32
#SBATCH --mem=256G
#SBATCH --time=12:00:00
#SBATCH --output=slurm-%j.out

# Evidence for K=3 in the K-NN imputation. Scores each K on three
# independent targets: held-out FOIA prediction, coauthor validation, and
# cross-cluster agreement.
#
# Step 1 builds the coauthor corpus the validation arm needs (lifetime text
# per coauthor, EXCLUDING papers written with any FOIA PI, so the test is
# not circular). Skipped when the file already exists; force with REBUILD=1.
#
# --tag "" because the current artifacts are untagged (weight_matrix.npz,
# tfidf_foia.npz, ...).
set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

COAUTHOR_TXT=../../output/coauthor_text_stemmed.csv

if [ "${REBUILD:-0}" = "1" ] || [ ! -s "$COAUTHOR_TXT" ]; then
    echo "=== building coauthor corpus ==="
    ( cd .. && python -u 0c_get_coauthor_stemmed.py )
fi

echo "=== K sweep ==="
python -u k_sweep.py --tag "" --version hc --ks 1 2 3 4 5 7 10 20 \
    --k-cluster 30 --copub-thresholds 5 10 20
