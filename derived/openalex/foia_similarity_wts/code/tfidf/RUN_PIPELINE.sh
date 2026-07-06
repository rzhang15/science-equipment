#!/bin/bash
set -e  # Exit on error

cd "$(dirname "$0")"  # Ensure we're in tfidf/ directory

echo "==============================================="
echo "PHASE 1: VALIDATION & FILTERING (SciBERT-based)"
echo "==============================================="

echo ""
echo "Step 1: Extract FOIA text (250-char minimum)..."
python ../0_get_foia_text.py --cluster-k 0

echo ""
echo "Step 2: Cluster with SciBERT for semantic validation..."
python ../cluster_foias_scibert.py --tag restricted --n-clusters 15 --min-chars 250

echo ""
echo "Step 3: Inspect clusters to identify non-life-science FOIAs..."
echo "  Run: python 0b_validate_foia_clusters.py --tag restricted --scibert --inspect"
echo "  Then manually identify which clusters to drop (e.g., '1,7,9')"
echo ""
read -p "Press Enter after inspection, or Ctrl+C to stop..."

echo ""
echo "Step 4: Drop non-life-science clusters (MANUALLY SPECIFY CLUSTER IDS)..."
read -p "Enter comma-separated cluster IDs to drop (or press Enter to skip): " clusters_to_drop

if [ -n "$clusters_to_drop" ]; then
    python 0b_validate_foia_clusters.py --tag restricted --scibert --drop-clusters "$clusters_to_drop"
    
    echo ""
    echo "Step 5: Copy validated text to make it the authoritative source..."
    cp ../../output/foia_author_text_validated_scibert_restricted.csv ../../output/foia_author_text_final.csv
    echo "Validated FOIA text copied to foia_author_text_final.csv"
else
    echo "Skipping cluster filtering (all FOIAs kept)"
fi

echo ""
echo "==============================================="
echo "PHASE 2: TFIDF-BASED IMPUTATION PIPELINE"
echo "==============================================="

echo ""
echo "Step 6: Vectorize with validated FOIAs..."
python 1_vectorize.py --tag restricted

echo ""
echo "Step 7: Cluster FOIAs with TF-IDF..."
python cluster_foias.py --tag restricted --n-clusters 15

echo ""
echo "Step 8: Filter universe by FOIA distance..."
python 0_filter_universe_by_foia_distance.py --tag restricted --keep-percentile 90

echo ""
echo "Step 9: Assign universe to clusters..."
python assign_universe_to_foia_clusters.py --tag restricted --n-clusters 15

echo ""
echo "Step 10: Compute similarity weights..."
python 2_similarity_wts_within_cluster.py --tag restricted --k 5

echo ""
echo "Step 11: Impute exposure..."
python 3_impute_exposure_within_cluster.py --tag restricted

echo ""
echo "Step 12: Validate with holdout..."
python 5_holdout_stress_within_cluster.py --tag restricted

echo ""
echo "==============================================="
echo "PIPELINE COMPLETE!"
echo "==============================================="
