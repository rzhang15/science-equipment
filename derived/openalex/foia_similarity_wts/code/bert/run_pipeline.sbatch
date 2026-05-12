#!/bin/bash
#SBATCH --job-name=foia_bert
#SBATCH --partition=gpu
#SBATCH --gres=gpu:nvidia_a100-sxm4-80gb:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=slurm-%j.out

set -e
# Slurm stages the sbatch script into a spool dir, so $0 doesn't point at the
# real bert/ directory. Use SLURM_SUBMIT_DIR (where `sbatch` was run from).
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

# Activate the env that has sentence-transformers + torch.
# source ~/.bashrc
# conda activate sci_eq

MODEL="${MODEL:-allenai-specter}"
STAGE="${STAGE:-validate}"             # validate | full
K="${K:-5}"
TAG_SUFFIX="${TAG_SUFFIX:-}"           # e.g. _unstemmed; keeps variant outputs separate
FOIA_CSV="${FOIA_CSV:-}"               # override default FOIA-text CSV (un-stemmed variant)
echo "Model: $MODEL   Stage: $STAGE   K: $K   TagSuffix: '$TAG_SUFFIX'   FOIA_CSV: '$FOIA_CSV'"

VEC_ARGS=(--model "$MODEL" --tag-suffix "$TAG_SUFFIX")
[ -n "$FOIA_CSV" ] && VEC_ARGS+=(--foia-csv "$FOIA_CSV")
[ "$STAGE" = "full" ] && VEC_ARGS+=(--universe)

python -u 1_vectorize.py "${VEC_ARGS[@]}"

# Validation path: FOIA x FOIA top-K weights + leave-one-out sweep.
python -u gen_validation_wts.py --model "$MODEL" --tag-suffix "$TAG_SUFFIX" --k 50
python -u loov.py --model "$MODEL" --tag-suffix "$TAG_SUFFIX" --source-k 50

# Production path: universe x FOIA weights + impute exposure.
if [ "$STAGE" = "full" ]; then
    python -u 2_similarity_wts.py --model "$MODEL" --k "$K"
    python -u 3_impute_exposure.py --model "$MODEL"
fi
