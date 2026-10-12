#!/bin/bash
#SBATCH --job-name=rf01_rf_sample
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=logs/%x-%j.out
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/../env.sh"
run_module $REPO/derived/reduced_form/rf_sample
