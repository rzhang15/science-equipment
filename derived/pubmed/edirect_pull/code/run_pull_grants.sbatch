#!/bin/bash
#SBATCH --job-name=pull_grants
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=12:00:00
#SBATCH --output=slurm-%j.out

set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

# Ensure pmids.txt exists (cheap; ~1 min if it doesn't)
if [ ! -f ../temp/pmids.txt ]; then
    echo "=== Exporting PMIDs from pmids.dta ==="
    python3 export_pmids.py
fi

echo "=== Pulling grants from PubMed ==="
./pull_grants.sh
