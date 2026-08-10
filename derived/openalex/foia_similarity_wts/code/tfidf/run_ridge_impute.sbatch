#!/bin/bash
#SBATCH --job-name=ridge_impute
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=02:00:00
#SBATCH --output=slurm-%j.out

# Runs Ridge-based imputation as an alternative to K-NN (3_impute_exposure.py).
# Peak memory: X_univ CSR ~4GB (float32) + predictions ~20MB/var. 128G is
# generous; drop to 64G if queue-limited.

set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

# Env: same as run_pipeline.sbatch — expects sklearn/scipy/pandas available.
python -u 3_impute_exposure_ridge.py --tag restricted "$@"
