#!/bin/bash
set -e
cd "$(dirname "$0")"
CL30=../../external/us_appended_text/author_static_clusters_30.csv
CL30_LS=../../external/us_appended_text/author_static_clusters_30_ls.csv

python -u 4_impute_shift_share.py --eb-own-weight 1
python -u 4_impute_shift_share.py --eb-own-weight 1 --cluster-filter "$CL30"
python -u 4_impute_shift_share.py --eb-own-weight 1 --ls-filter "$CL30_LS"
python -u 4_impute_shift_share.py --eb-own-weight 1 --cluster-filter "$CL30" --ls-filter "$CL30_LS"

# for MIN in 2 5; do
#     python -u 4_impute_shift_share.py --eb-own-weight 1 --cluster-filter "$CL30" --min-foia-per-cluster $MIN
#     python -u 4_impute_shift_share.py --eb-own-weight 1 --cluster-filter "$CL30" --min-foia-per-cluster $MIN --ls-filter "$CL30_LS"
# done
