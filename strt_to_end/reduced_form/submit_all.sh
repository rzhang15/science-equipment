#!/bin/bash
# Usage: ./submit_all.sh [FIRST_STAGE]   e.g. ./submit_all.sh 03  (skips 01-02)
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
mkdir -p logs
start=${1:-01}
start_num=$(( 10#${start:0:2} ))

declare -A jid
sub() {
    local name=$1; shift
    local num=$(( 10#${name:0:2} ))
    if (( num < start_num )); then return; fi
    local deps=()
    for d in "$@"; do
        [[ -n "${jid[$d]:-}" ]] && deps+=("${jid[$d]}")
    done
    local depopt=()
    if (( ${#deps[@]} )); then
        depopt=(--dependency=afterok:$(IFS=:; echo "${deps[*]}") --kill-on-invalid-dep=yes)
    fi
    jid[$name]=$(sbatch --parsable "${depopt[@]}" "stages/${name}.sbatch")
    printf '%-26s %-10s deps: %s\n' "$name" "${jid[$name]}" "${deps[*]:-none}"
}

sub 01_rf_sample
sub 02_rf_groups          01_rf_sample

sub 03a_rf_descriptives   02_rf_groups
sub 03b_rf_main           01_rf_sample
sub 03c_rf_robustness     01_rf_sample
sub 03d_rf_exit           01_rf_sample
sub 03e_rf_output_loss    01_rf_sample
sub 03f_rf_het_splits     02_rf_groups
sub 03g_rf_het_career     02_rf_groups

echo
echo "squeue -u \$USER -o '%.10i %.28j %.8T %.10M %R'"
