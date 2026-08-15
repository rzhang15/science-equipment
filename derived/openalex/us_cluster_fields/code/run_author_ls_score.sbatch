#!/bin/bash
#SBATCH --job-name=author_ls_score
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=01:00:00
#SBATCH --output=slurm-%j.out

set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

# always-keep = FOIA anchor roster (known lab purchasers); path hard-coded
# because this module has no external alias for foia_similarity_wts
FOIA_IDS=/n/holylabs/LABS/pakes_lab/Lab/sci_eq/derived/openalex/foia_similarity_wts/output/foia_ids_ordered.csv

python -u 3b_author_ls_score.py --always-keep "$FOIA_IDS"
