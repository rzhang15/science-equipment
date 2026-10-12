#!/bin/bash
#SBATCH --job-name=rf03e_rf_output_loss
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --output=logs/%x-%j.out
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/../env.sh"
run_module $REPO/analysis/rf_output_loss
