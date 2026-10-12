#!/bin/bash
#SBATCH --job-name=fs05d_placebo_sd_prep
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=logs/%x-%j.out
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/../env.sh"
run_module $REPO/analysis/placebo_sd --setup-only draw_placebo.R "analysis.do prep"
