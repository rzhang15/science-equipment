#!/bin/bash
#SBATCH --job-name=fs05a_match_control
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --output=logs/%x-%j.out
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/../env.sh"
run_module $REPO/derived/first_stage/match_control --setup-only match_trt_ctrl.R
