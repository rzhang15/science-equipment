#!/bin/bash
# No-SLURM fallback (e.g. inside a big salloc). Same order as submit_all.sh;
# independent stages run concurrently as background processes.
# Usage: ./run_local.sh [FIRST_STAGE] [N_CHUNKS]
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
mkdir -p logs
start=${1:-01}
start_num=$(( 10#${start:0:2} ))
export N_CHUNKS=${2:-4}

run() {
    local name=$1
    local num=$(( 10#${name:0:2} ))
    if (( num < start_num )); then return 0; fi
    echo "[$(date +%T)] start $name"
    bash "stages/${name}.sbatch" > "logs/${name}.local.out" 2>&1
    echo "[$(date +%T)] done  $name"
}
run_chunks() {
    local name=$1 i
    local num=$(( 10#${name:0:2} ))
    if (( num < start_num )); then return 0; fi
    for i in $(seq 1 "$N_CHUNKS"); do
        echo "[$(date +%T)] start $name task $i"
        SLURM_ARRAY_TASK_ID=$i SLURM_ARRAY_TASK_COUNT=$N_CHUNKS \
            bash "stages/${name}.sbatch" > "logs/${name}_${i}.local.out" 2>&1 &
    done
    wait
    echo "[$(date +%T)] done  $name"
}

run 01_merge_price_data
run 02_fuzzy_match_suppliers
run 03_select_categories
run 04_make_mkt_panel

( run 05a_match_control; run 06a_matched_panel ) &
run 05b_synthetic_ctrl &
( run 05c_placebo_dist; run 06b_placebo_first_stage ) &
( run 05d_placebo_sd_prep; run_chunks 06c_placebo_sd_chunk ) &
wait

run 07_first_stage

run 08a_placebo_overlay &
run 08b_placebo_sd_figures &
wait
echo "[$(date +%T)] pipeline complete"
