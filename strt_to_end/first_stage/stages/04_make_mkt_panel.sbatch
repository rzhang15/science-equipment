#!/bin/bash
#SBATCH --job-name=fs04_make_mkt_panel
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=4
#SBATCH --mem=128G
#SBATCH --time=03:00:00
#SBATCH --output=logs/%x-%j.out
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/../env.sh"
run_module $REPO/derived/first_stage/make_mkt_panel
