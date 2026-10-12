#!/bin/bash
# Show pipeline jobs, then the tail of any failed stage log.
cd "$(dirname "$(readlink -f "$0")")"
squeue -u "$USER" -n "$(ls stages | sed 's/^/rf/; s/\.sbatch$//' | paste -sd,)" \
    -o '%.10i %.28j %.8T %.10M %.6D %R' 2>/dev/null
echo
sacct -u "$USER" -S "$(date -d '-3 days' +%F)" -X -n -o JobName%28,State%12,Elapsed,JobID \
    | grep '^ *rf' | sort -k4 -n | tail -20
echo
for f in $(grep -l -E "Stata error|R error|Traceback|ERROR" logs/*.out 2>/dev/null | tail -3); do
    echo "---- $f"; tail -15 "$f"
done
