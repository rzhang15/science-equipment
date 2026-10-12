#!/bin/bash
#SBATCH --job-name=rf03f_rf_het_splits
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --output=logs/%x-%j.out
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/../env.sh"
run_module $REPO/analysis/rf_het_splits
