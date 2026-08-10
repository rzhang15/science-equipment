#!/bin/bash
# Filter variants on the untagged k=5 weight matrix -- writes the bare
# hc / hc_cf / hc_ls / hc_cf_ls names analysis.do reads.
#   (none) : full universe
#   _cf    : clusters with >= min FOIA anchors (full label file)
#   _ls    : life-science authors only
#   _cf_ls : both
# k=3 variants (suffix _k3) come from run_k3_impute.sbatch.
set -e
cd "$(dirname "$0")"
CL30=../../external/us_appended_text/author_static_clusters_30.csv
CL30_LS=../../external/us_appended_text/author_static_clusters_30_ls.csv

python -u 4_impute_shift_share.py
python -u 4_impute_shift_share.py --cluster-filter "$CL30"
python -u 4_impute_shift_share.py --ls-filter "$CL30_LS"
python -u 4_impute_shift_share.py --cluster-filter "$CL30" --ls-filter "$CL30_LS"

# stricter anchor-coverage robustness (_cf2 / _cf5), uncomment to add:
# for MIN in 2 5; do
#     python -u 4_impute_shift_share.py --cluster-filter "$CL30" --min-foia-per-cluster $MIN
#     python -u 4_impute_shift_share.py --cluster-filter "$CL30" --min-foia-per-cluster $MIN --ls-filter "$CL30_LS"
# done
