# Shared environment for every stage. Sourced by each stages/*.sbatch script.
export REPO=/n/holylabs/LABS/pakes_lab/Lab/sci_eq
export PIPE=$REPO/strt_to_end/reduced_form

if [ -f /etc/profile.d/lmod.sh ]; then
    source /etc/profile.d/lmod.sh
fi
module load python/3.10.13-fasrc01 stata/17.0-fasrc01 2>/dev/null || true

export PATH=/n/holylabs/LABS/pakes_lab/Lab/env/bin:$PATH
export PY=/n/holylabs/LABS/pakes_lab/Lab/env/bin/python
export PYTHONUNBUFFERED=1

run_module() {
    "$PY" -u "$REPO/strt_to_end/run_module.py" "$@"
}
