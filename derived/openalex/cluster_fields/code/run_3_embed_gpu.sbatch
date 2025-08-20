#!/bin/bash
#SBATCH --job-name=embedSpecter
#SBATCH --partition=gpu_test
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --chdir=/n/holylabs/LABS/pakes_lab/Lab/sci_eq/derived/cluster_fields/code

python 3_embed_specter.py            # ← step 3 only
