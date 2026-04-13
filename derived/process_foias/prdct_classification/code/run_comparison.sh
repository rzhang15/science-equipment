#!/bin/bash
#SBATCH --partition=sapphire
#SBATCH --mem=100G
#SBATCH --time=3-00:00:00
#SBATCH --job-name=model_comparison
#SBATCH -o ../output/comparison_%j.out

set -euo pipefail

CODE="$(cd "$(dirname "$0")" && pwd)"
cd "$CODE"

# ======================================================================
# Usage:
#   PIPELINE_VARIANT=baseline        bash run_comparison.sh   # run one
#   PIPELINE_VARIANT=umich_supplier  bash run_comparison.sh   # run one
#   bash run_comparison.sh                                     # run both
# ======================================================================

run_pipeline() {
    local variant="$1"
    echo ""
    echo "=========================================================="
    echo "  RUNNING PIPELINE: $variant"
    echo "=========================================================="
    export PIPELINE_VARIANT="$variant"

    echo "--- Step 0: Cleaning category files ---"
    python 0_clean_category_file.py

    echo "--- Step 1: Building training dataset ---"
    python 1_build_training_dataset.py

    echo "--- Step 1b: Creating text embeddings ---"
    python 1b_create_text_embeddings.py

    echo "--- Step 1c: Building category vectors ---"
    python 1c_build_category_vectors.py

    echo "--- Step 2: Training binary classifier (tfidf) ---"
    python 2_train_binary_classifier.py tfidf

    echo "--- Step 3: Predicting on UT Dallas ---"
    python 3_predict_product_markets.py utdallas --gatekeeper tfidf --expert non_parametric_tfidf

    echo "--- Step 5: Validating on UT Dallas ---"
    python 5_validate_utdallas.py --gatekeeper tfidf --expert non_parametric_tfidf

    echo ""
    echo "=== $variant pipeline complete ==="
    echo "  Output dir: $(python -c 'import config; print(config.OUTPUT_DIR)')"
    echo ""
}

# If PIPELINE_VARIANT is already set, run just that variant
if [[ -n "${PIPELINE_VARIANT:-}" ]]; then
    run_pipeline "$PIPELINE_VARIANT"
else
    # Run both variants for comparison
    run_pipeline "baseline"
    run_pipeline "umich_supplier"

    # Print side-by-side comparison
    echo ""
    echo "=========================================================="
    echo "  COMPARISON: baseline vs umich_supplier"
    echo "=========================================================="
    python3 -c "
import pandas as pd, os

base = os.path.abspath(os.path.join('$CODE', '..'))
report_name = 'utdallas_full_report_gatekeeper_tfidf_expert_non_parametric_tfidf.csv'

v1_path = os.path.join(base, 'output', 'baseline', report_name)
v2_path = os.path.join(base, 'output', 'umich_supplier', report_name)

try:
    v1 = pd.read_csv(v1_path, index_col=0)
    v2 = pd.read_csv(v2_path, index_col=0)
except FileNotFoundError as e:
    print(f'Could not load reports: {e}')
    exit(0)

# Macro/weighted averages
for label in ['macro avg', 'weighted avg']:
    if label in v1.index and label in v2.index:
        print(f'\n{label.upper()}:')
        for metric in ['precision', 'recall', 'f1-score']:
            val1 = v1.loc[label, metric]
            val2 = v2.loc[label, metric]
            delta = val2 - val1
            arrow = '+' if delta >= 0 else ''
            print(f'  {metric:12s}  baseline={val1:.4f}  umich_supplier={val2:.4f}  ({arrow}{delta:.4f})')

# Per-category changes (top movers by f1 delta)
shared = v1.index.intersection(v2.index)
shared = shared.drop(['accuracy', 'macro avg', 'weighted avg'], errors='ignore')
diff = v2.loc[shared, 'f1-score'] - v1.loc[shared, 'f1-score']
diff = diff.dropna().sort_values()

print('\n--- Biggest F1 DROPS (baseline -> umich_supplier) ---')
print(diff.head(10).to_string())

print('\n--- Biggest F1 GAINS (baseline -> umich_supplier) ---')
print(diff.tail(10).to_string())

# FP/FN counts from step 2 hold-out
for variant in ['baseline', 'umich_supplier']:
    fp_path = os.path.join(base, 'output', variant, 'false_positives.csv')
    fn_path = os.path.join(base, 'output', variant, 'false_negatives.csv')
    try:
        fp = len(pd.read_csv(fp_path))
        fn = len(pd.read_csv(fn_path))
        print(f'\n{variant} hold-out: {fp} false positives, {fn} false negatives')
    except FileNotFoundError:
        pass
"
    echo ""
    echo "=== Comparison complete ==="
    echo "  Baseline output:        $(PIPELINE_VARIANT=baseline python -c 'import config; print(config.OUTPUT_DIR)')"
    echo "  UMich+Supplier output:  $(PIPELINE_VARIANT=umich_supplier python -c 'import config; print(config.OUTPUT_DIR)')"
fi
