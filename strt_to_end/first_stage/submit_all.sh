#!/bin/bash
# Usage: ./submit_all.sh [FIRST_STAGE]   e.g. ./submit_all.sh 05  (skips stages 01-04)
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

sub 01_merge_price_data
sub 02_fuzzy_match_suppliers   01_merge_price_data
sub 03_select_categories       02_fuzzy_match_suppliers
sub 04_make_mkt_panel          03_select_categories

sub 05a_match_control          04_make_mkt_panel
sub 05b_synthetic_ctrl         04_make_mkt_panel
sub 05c_placebo_dist           04_make_mkt_panel
sub 05d_placebo_sd_prep        04_make_mkt_panel

sub 06a_matched_panel          05a_match_control
sub 06b_placebo_first_stage    05c_placebo_dist
sub 06c_placebo_sd_chunk       05d_placebo_sd_prep

sub 07_first_stage             06a_matched_panel 05b_synthetic_ctrl

sub 08a_placebo_overlay        07_first_stage 06b_placebo_first_stage
sub 08b_placebo_sd_figures     07_first_stage 06c_placebo_sd_chunk

echo
echo "squeue -u \$USER -o '%.10i %.28j %.8T %.10M %R'"
