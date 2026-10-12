#!/bin/bash
#SBATCH --job-name=fs05b_synthetic_ctrl
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --output=logs/%x-%j.out
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/../env.sh"
run_module $REPO/derived/first_stage/synthetic_ctrl --setup-only synth_did_estimates.R
