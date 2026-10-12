#!/bin/bash
# No-SLURM fallback. Same order as submit_all.sh; the 03 stages run concurrently.
# Usage: ./run_local.sh [FIRST_STAGE]
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
mkdir -p logs
start=${1:-01}
start_num=$(( 10#${start:0:2} ))

run() {
    local name=$1
    local num=$(( 10#${name:0:2} ))
    if (( num < start_num )); then return 0; fi
    echo "[$(date +%T)] start $name"
    bash "stages/${name}.sbatch" > "logs/${name}.local.out" 2>&1
    echo "[$(date +%T)] done  $name"
}

run 01_rf_sample
run 02_rf_groups

run 03a_rf_descriptives &
run 03b_rf_main &
run 03c_rf_robustness &
run 03d_rf_exit &
run 03e_rf_output_loss &
run 03f_rf_het_splits &
run 03g_rf_het_career &
wait
echo "[$(date +%T)] pipeline complete"
