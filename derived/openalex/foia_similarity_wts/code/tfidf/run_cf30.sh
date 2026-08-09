#!/bin/bash
# _cf on the K=30 field clustering -- the main spec. Writes the bare _cf names
# analysis.do reads. The K=100 variants live under *_cf*_k100.* as robustness.
set -e
cd "$(dirname "$0")"
CL30=../../external/us_appended_text/author_static_clusters_30_ls.csv
for MIN in 1 2 5; do
    echo "=== K=30 cluster filter: min-foia-per-cluster=$MIN ==="
    python -u 4_impute_shift_share.py --cluster-filter "$CL30" --min-foia-per-cluster $MIN
done
