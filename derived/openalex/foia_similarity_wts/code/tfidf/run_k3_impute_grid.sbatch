#!/bin/bash
#SBATCH --job-name=k3_grid
#SBATCH --partition=sapphire
#SBATCH --cpus-per-task=16
#SBATCH --mem=96G
#SBATCH --time=08:00:00
#SBATCH --output=slurm-%j.out

# Full option grid for the row-sum-preserving EB script, k=3.
# EB off = --eb-own-weight 1 (the script's default is .90).
set -e
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

CL30_LSA=../../external/us_appended_text/author_static_clusters_30_lsa.csv
CL30_FULL=../../external/us_appended_text/author_static_clusters_30.csv
LSA=../../external/us_appended_text/author_ls_authors_indiv.csv
LS=../../external/us_appended_text/author_static_clusters_30_ls.csv

NEW="--cluster-filter $CL30_LSA --ls-filter $LSA --ls-sfx _lsa"

# ---------------------------------------------------------------------------
# 1. No EB
# ---------------------------------------------------------------------------
python -u 4_impute_shift_share.py --k 3 --eb-own-weight 1 \
    --ls-filter "$LSA" --ls-sfx _lsa
python -u 4_impute_shift_share.py --k 3 --eb-own-weight 1 $NEW
for N in 2 5; do
    python -u 4_impute_shift_share.py --k 3 --eb-own-weight 1 $NEW \
        --min-foia-per-cluster $N
done
for N in 1 2 5; do
    python -u 4_impute_shift_share.py --k 3 --eb-own-weight 1 \
        --cluster-filter "$CL30_FULL" --min-foia-per-cluster $N
done
# cluster-level _ls mask, kept for comparison with _lsa
python -u 4_impute_shift_share.py --k 3 --eb-own-weight 1 \
    --cluster-filter "$CL30_FULL" --ls-filter "$LS" --ls-sfx _ls

# ---------------------------------------------------------------------------
# 2. EB, peer prior (main): own-weight and peer-K sweeps
# ---------------------------------------------------------------------------
python -u 4_impute_shift_share.py --k 3 $NEW \
    --eb-own-weight .90 --eb-prior peer --eb-peer-k 5 --loo-influence
for OW in .95 .85; do
    python -u 4_impute_shift_share.py --k 3 $NEW \
        --eb-own-weight $OW --eb-prior peer --eb-peer-k 5
done
for PK in 3 10; do
    python -u 4_impute_shift_share.py --k 3 $NEW \
        --eb-own-weight .90 --eb-prior peer --eb-peer-k $PK
done

# ---------------------------------------------------------------------------
# 3. EB, cluster prior
# ---------------------------------------------------------------------------
for OW in .95 .90 .85; do
    python -u 4_impute_shift_share.py --k 3 $NEW \
        --eb-own-weight $OW --eb-prior cluster --eb-cluster-file "$CL30_LSA"
done

# ---------------------------------------------------------------------------
# 4. EB on the other samples, so mask and EB effects separate
# ---------------------------------------------------------------------------
python -u 4_impute_shift_share.py --k 3 --ls-filter "$LSA" --ls-sfx _lsa \
    --eb-own-weight .90 --eb-prior peer --eb-peer-k 5
python -u 4_impute_shift_share.py --k 3 --cluster-filter "$CL30_FULL" \
    --eb-own-weight .90 --eb-prior peer --eb-peer-k 5
python -u 4_impute_shift_share.py --k 3 --cluster-filter "$CL30_FULL" \
    --eb-own-weight .90 --eb-prior cluster --eb-cluster-file "$CL30_FULL"
