#!/bin/bash
#SBATCH --job-name=rf03a_rf_descriptives
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --output=logs/%x-%j.out
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/../env.sh"
run_module $REPO/analysis/rf_descriptives
