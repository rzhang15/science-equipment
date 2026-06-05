#!/bin/bash
#SBATCH --job-name=buyer_cluster
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=slurm-%j.out

set -e
# Slurm stages the script into a spool dir, so $0 doesn't point at the real
# code/ directory. Use SLURM_SUBMIT_DIR (where `sbatch` was run from).
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

STAGE="${STAGE:-foia}"          # foia | full   (full = include 5_impute_universe.py)
echo "Stage: $STAGE"

python -u 0_build_purchase_matrix.py
python -u 1_cluster_buyers.py
python -u 2_describe_buyers.py
python -u 3_train_classifier.py
python -u 4_validate.py

if [ "$STAGE" = "full" ]; then
    python -u 5_impute_universe.py
fi
