#!/bin/bash
#SBATCH --job-name=paper_specter
#SBATCH --partition=gpu
#SBATCH --gres=gpu:nvidia_a100-sxm4-80gb:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=96G
#SBATCH --time=24:00:00
#SBATCH --output=slurm-%j.out

set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

# Uses the lab env that already has torch + sentence-transformers (see env check).
PYTHON=/n/holylabs/LABS/pakes_lab/Lab/env/bin/python

# Step 0: build per-paper text (CPU; run on a login or compute node before sbatch).
# $PYTHON 0_build_paper_text.py

# Step 1: embed
$PYTHON -u 1_embed_papers.py

# Step 2/3: run on CPU after embedding finishes
# $PYTHON 2_cluster_papers.py --clusters 50
# $PYTHON 3_aggregate_to_authors.py --clusters 50
