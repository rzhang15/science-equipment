#!/bin/bash
#SBATCH --job-name=us_bert_vec
#SBATCH --partition=gpu
#SBATCH --gres=gpu:nvidia_a100-sxm4-80gb:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --output=slurm-%j.out

set -e

cd "$(dirname "$0")"

# Activate your env. Adjust to match your setup (conda or venv).
# Example with conda:
# source ~/.bashrc
# conda activate sci_eq

python -u 1_vectorize_bert.py
