"""
Compare pipeline variants side-by-side.

Usage:
    python compare_variants.py <variant_a> <variant_b>

Example:
    python compare_variants.py baseline umich_supplier

Fixed report wiring:
  - Variant A ({variant_a})   -> utdallas_full_report_... (verified on UT Dallas)
  - Variant B ({variant_b})   -> combined_full_report_... (verified on UT Dallas + UMich)

Category filter: only categories that appear in BOTH
    output/{variant_a}/utdallas_full_report_...  (cats present in UT Dallas)
AND output/{variant_a}/combined_full_report_...  (cats present once UMich is added)
with support >= MIN_SUPPORT on both sides.  The intersection identifies
categories that exist in both UT Dallas and UMich purchase data.

Produces scatter plots and a summary of "good" categories
(precision > 0.8, recall > 0.8, support >= 25).
"""
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import os
import argparse

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MIN_SUPPORT = 25
GOOD_THRESHOLD = 0.8

UTDALLAS_REPORT = 'utdallas_full_report_gatekeeper_tfidf_expert_tfidf.csv'
COMBINED_REPORT = 'combined_full_report_gatekeeper_tfidf_expert_tfidf.csv'


def load_report(variant, report_file):
    path = os.path.join(BASE_DIR, "output", variant, report_file)
    df = pd.read_csv(path, index_col=0)
    return df


def main():
    parser = argparse.ArgumentParser(description="Compare pipeline variants side-by-side.")
    parser.add_argument("variant_a", type=str, help="First variant name (e.g. baseline)")
    parser.add_argument("variant_b", type=str, help="Second variant name (e.g. umich_supplier)")
    args = parser.parse_args()

    va, vb = args.variant_a, args.variant_b

    # A (baseline) is always verified against UT Dallas;
    # B (umich_supplier) is always verified against combined.
    ra = load_report(va, UTDALLAS_REPORT)
    rb = load_report(vb, COMBINED_REPORT)

    # Category filter: intersection of categories in A's utdallas report and
    # A's combined report (both from variant_a, to identify categories that
    # exist in both UT Dallas and UMich purchase data).
    r_filter = load_report(va, COMBINED_REPORT)

    # Drop summary rows, keep only per-category rows with enough support
    summary_rows = ['accuracy', 'macro avg', 'weighted avg']
    cats_a = ra.drop(summary_rows, errors='ignore')
    cats_b = rb.drop(summary_rows, errors='ignore')
    cats_filter = r_filter.drop(summary_rows, errors='ignore')

    # 1:1 merge (index intersection) to keep only categories present in both
    # UT Dallas and combined reports under variant_a.
    both_datasets = cats_a.index.intersection(cats_filter.index)
    filter_mask = (
        (cats_a.loc[both_datasets, 'support'] >= MIN_SUPPORT)
        & (cats_filter.loc[both_datasets, 'support'] >= MIN_SUPPORT)
    )
    both_datasets = both_datasets[filter_mask]

    # Further restrict to categories that also appear in variant B's report
    shared = both_datasets.intersection(cats_b.index)
    mask = cats_b.loc[shared, 'support'] >= MIN_SUPPORT
    shared = shared[mask]

    prec_a = cats_a.loc[shared, 'precision']
    prec_b = cats_b.loc[shared, 'precision']
    rec_a = cats_a.loc[shared, 'recall']
    rec_b = cats_b.loc[shared, 'recall']
    sup_a = cats_a.loc[shared, 'support']
    sup_b = cats_b.loc[shared, 'support']

    # "Good" categories: precision > 0.8 AND recall > 0.8 AND support >= 25
    good_a = (prec_a > GOOD_THRESHOLD) & (rec_a > GOOD_THRESHOLD)
    good_b = (prec_b > GOOD_THRESHOLD) & (rec_b > GOOD_THRESHOLD)

    # --- Print summary ---
    print("=" * 70)
    print(f"  VARIANT COMPARISON: {va} (utdallas) vs {vb} (combined)")
    print(f"  Categories in both UT Dallas + UMich data (support >= {MIN_SUPPORT}): "
          f"{len(both_datasets)}")
    print(f"  Of those, also present with support >= {MIN_SUPPORT} in {vb}: {len(shared)}")
    print("=" * 70)

    # Macro/weighted averages
    for label in ['macro avg', 'weighted avg']:
        if label in ra.index and label in rb.index:
            print(f"\n  {label.upper()}:")
            for m in ['precision', 'recall', 'f1-score']:
                v1 = ra.loc[label, m]
                v2 = rb.loc[label, m]
                d = v2 - v1
                arrow = '+' if d >= 0 else ''
                print(f"    {m:12s}  {va}={v1:.4f}  {vb}={v2:.4f}  ({arrow}{d:.4f})")

    print(f"\n  GOOD CATEGORIES (precision > {GOOD_THRESHOLD} & recall > {GOOD_THRESHOLD}):")
    print(f"    {va}: {good_a.sum()} / {len(shared)}")
    print(f"    {vb}: {good_b.sum()} / {len(shared)}")

    gained = good_b & ~good_a
    lost = good_a & ~good_b
    if gained.any():
        print(f"\n    Gained ({vb} is now good, {va} was not):")
        for cat in shared[gained]:
            print(f"      + {cat}  (prec {prec_a[cat]:.2f}->{prec_b[cat]:.2f}, rec {rec_a[cat]:.2f}->{rec_b[cat]:.2f})")
    if lost.any():
        print(f"\n    Lost ({va} was good, {vb} is not):")
        for cat in shared[lost]:
            print(f"      - {cat}  (prec {prec_a[cat]:.2f}->{prec_b[cat]:.2f}, rec {rec_a[cat]:.2f}->{rec_b[cat]:.2f})")

    # --- Plots ---
    out_dir = os.path.join(BASE_DIR, "output")
    fig, axes = plt.subplots(1, 3, figsize=(18, 6))

    # Size points by support (log scale for readability)
    sizes = np.clip(np.log1p(sup_a) * 8, 15, 120)

    # 1. Precision scatter
    ax = axes[0]
    ax.scatter(prec_a, prec_b, s=sizes, alpha=0.5, edgecolors='k', linewidths=0.3)
    ax.plot([0, 1], [0, 1], 'k--', alpha=0.3)
    ax.axhline(GOOD_THRESHOLD, color='green', alpha=0.2, linestyle=':')
    ax.axvline(GOOD_THRESHOLD, color='green', alpha=0.2, linestyle=':')
    ax.set_xlabel(f'Precision ({va})')
    ax.set_ylabel(f'Precision ({vb})')
    ax.set_title('Precision by Category')
    ax.set_xlim(-0.05, 1.05)
    ax.set_ylim(-0.05, 1.05)
    ax.set_aspect('equal')

    # 2. Recall scatter
    ax = axes[1]
    ax.scatter(rec_a, rec_b, s=sizes, alpha=0.5, edgecolors='k', linewidths=0.3)
    ax.plot([0, 1], [0, 1], 'k--', alpha=0.3)
    ax.axhline(GOOD_THRESHOLD, color='green', alpha=0.2, linestyle=':')
    ax.axvline(GOOD_THRESHOLD, color='green', alpha=0.2, linestyle=':')
    ax.set_xlabel(f'Recall ({va})')
    ax.set_ylabel(f'Recall ({vb})')
    ax.set_title('Recall by Category')
    ax.set_xlim(-0.05, 1.05)
    ax.set_ylim(-0.05, 1.05)
    ax.set_aspect('equal')

    # 3. "Good category" count comparison (bar chart)
    ax = axes[2]
    counts = [good_a.sum(), good_b.sum()]
    bars = ax.bar([va, vb], counts, color=['#4C72B0', '#DD8452'], edgecolor='k', linewidth=0.5)
    ax.set_ylabel('Number of good categories')
    ax.set_title(f'Good categories\n(prec>{GOOD_THRESHOLD}, rec>{GOOD_THRESHOLD}, support>={MIN_SUPPORT})')
    for bar, c in zip(bars, counts):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.5,
                str(c), ha='center', va='bottom', fontweight='bold')
    ax.set_ylim(0, max(counts) * 1.15)

    plt.tight_layout()
    plot_path = os.path.join(out_dir, f"comparison_{va}_utdallas_vs_{vb}_combined.png")
    fig.savefig(plot_path, dpi=150, bbox_inches='tight')
    print(f"\n  Plot saved to: {plot_path}")
    plt.close()

    # --- Save full category-level comparison CSV ---
    f1_a = cats_a.loc[shared, 'f1-score']
    f1_b = cats_b.loc[shared, 'f1-score']
    f1_delta = f1_b - f1_a

    def status(row):
        if row[f'good_{vb}'] and not row[f'good_{va}']:
            return 'gained_good'
        elif row[f'good_{va}'] and not row[f'good_{vb}']:
            return 'lost_good'
        elif row['f1_delta'] > 0.05:
            return 'better'
        elif row['f1_delta'] < -0.05:
            return 'worse'
        else:
            return 'stable'

    comp = pd.DataFrame({
        f'precision_{va}': prec_a, f'precision_{vb}': prec_b,
        'precision_delta': prec_b - prec_a,
        f'recall_{va}': rec_a, f'recall_{vb}': rec_b,
        'recall_delta': rec_b - rec_a,
        f'f1_{va}': f1_a, f'f1_{vb}': f1_b,
        'f1_delta': f1_delta,
        f'support_{va}': sup_a, f'support_{vb}': sup_b,
        f'good_{va}': good_a, f'good_{vb}': good_b,
    })
    comp['status'] = comp.apply(status, axis=1)
    comp = comp.sort_values('f1_delta', ascending=True)

    csv_path = os.path.join(out_dir, f"comparison_{va}_utdallas_vs_{vb}_combined.csv")
    comp.to_csv(csv_path)
    print(f"  CSV saved to: {csv_path}")

    # Print status summary
    status_counts = comp['status'].value_counts()
    print(f"\n  Category status summary:")
    for s in ['gained_good', 'better', 'stable', 'worse', 'lost_good']:
        print(f"    {s:12s}: {status_counts.get(s, 0)}")


if __name__ == "__main__":
    main()
