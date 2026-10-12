#!/bin/bash
#SBATCH --job-name=fs02_fuzzy_match_suppliers
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=03:00:00
#SBATCH --output=logs/%x-%j.out
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/../env.sh"
run_module $REPO/derived/first_stage/fuzzy_match_suppliers --setup-only match.py final_clean.do
