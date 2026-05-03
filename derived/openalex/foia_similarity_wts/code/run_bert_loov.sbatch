#!/bin/bash
#SBATCH --job-name=foia_bert_loov
#SBATCH --partition=gpu
#SBATCH --gres=gpu:nvidia_a100-sxm4-80gb:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --output=slurm-%j.out

set -e
cd "$(dirname "$0")"

# Activate the env that has sentence-transformers + torch.
# source ~/.bashrc
# conda activate sci_eq

MODEL="${MODEL:-allenai-specter}"
echo "Model: $MODEL"

python -u 1_vectorize_bert.py --model "$MODEL"
python -u gen_validation_wts_bert.py --model "$MODEL" --k 50
python -u loov_bert.py --model "$MODEL" --source-k 50
