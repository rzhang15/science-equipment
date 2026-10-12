#!/bin/bash
#SBATCH --job-name=fs06c_placebo_sd_chunk
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --array=1-10
#SBATCH --output=logs/%x-%A_%a.out
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/../env.sh"
i=${SLURM_ARRAY_TASK_ID:?}
n=${SLURM_ARRAY_TASK_COUNT:-${N_CHUNKS:-10}}
n_draws=$(grep -oP 'N_DRAWS\s*<-\s*\K[0-9]+' "$REPO/analysis/placebo_sd/code/draw_placebo.R")
size=$(( (n_draws + n - 1) / n ))
lo=$(( (i - 1) * size + 1 ))
hi=$(( i * size ))
run_module $REPO/analysis/placebo_sd --skip-make "analysis.do chunk $i $lo $hi"
