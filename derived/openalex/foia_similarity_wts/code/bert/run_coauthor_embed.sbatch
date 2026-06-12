#!/bin/bash
#SBATCH --job-name=foia_bert_coauthors
#SBATCH --partition=gpu
#SBATCH --gres=gpu:nvidia_a100-sxm4-80gb:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=slurm-%j.out

set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

# source ~/.bashrc
# conda activate sci_eq

MODEL="${MODEL:-pritamdeka/S-PubMedBert-MS-MARCO}"
COAUTHOR_CSV="${COAUTHOR_CSV:-../../output/coauthor_text_unstemmed.csv}"
TAG_SUFFIX="${TAG_SUFFIX:-_coauthors_unstemmed}"
echo "Model: $MODEL   CoauthorCSV: $COAUTHOR_CSV   TagSuffix: '$TAG_SUFFIX'"

python -u 1_vectorize.py \
    --model "$MODEL" \
    --tag-suffix "$TAG_SUFFIX" \
    --foia-csv "$COAUTHOR_CSV"
