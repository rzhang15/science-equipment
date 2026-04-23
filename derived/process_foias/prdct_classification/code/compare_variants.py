"""
Compare pipeline variants side-by-side.

Usage:
    python compare_variants.py <variant_a> <variant_b>

Example:
    python compare_variants.py baseline umich_supplier

Fixed report wiring:
  - Variant A ({variant_a})   -> utdallas_full_report_... (verified on UT Dallas)
  - Variant B ({variant_b})   -> combined_full_report_... (verified on UT Dallas + UMich)

Comparison is direct:
  variant_a's UT Dallas report   vs.   variant_b's combined report.

Category universe plotted:
  - Filter:  support > MIN_SUPPORT in variant_b's combined report (so every
    point has reliable statistics on the B side).
  - "shared": also appears in variant_a's UT Dallas report (any support).
  - "new-in-Michigan": not present in variant_a's UT Dallas report at all
    (the category was introduced once UMich data was added).  Plotted in
    purple with precision=recall=0 on the baseline axis.

Scatter colors: shared categories in dark blue, new-in-Michigan in purple.
Position relative to the 45-degree line shows better/worse mechanically --
above the line = improved on that metric, below = regressed.
Dot sizes are log-scaled by max(support_a, support_b).

"Good" categories: precision > 0.8, recall > 0.8, support > MIN_SUPPORT.
"""
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.gridspec import GridSpec
import numpy as np
import os
import argparse

import config

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MIN_SUPPORT = 20
GOOD_THRESHOLD = 0.8
F1_DELTA_THRESHOLD = 0.05  # used only for CSV status labeling

COLOR_SHARED = '#7fb8e6'   # light blue
COLOR_NEW = '#9467bd'      # purple
COLOR_LOST = '#C44E52'     # crimson ring for categories that were good in
                           # variant_a but dropped below threshold in variant_b

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

    # Drop summary rows, keep only per-category rows.
    summary_rows = ['accuracy', 'macro avg', 'weighted avg']
    cats_a = ra.drop(summary_rows, errors='ignore')
    cats_b = rb.drop(summary_rows, errors='ignore')

    # Universe: every category reported by variant_b with support > MIN_SUPPORT
    # (gives us reliable test-set statistics on the comparison side).
    all_cats = cats_b.index[cats_b['support'] > MIN_SUPPORT]

    # Shared vs. new is decided by *presence* in variant_a's UT Dallas report,
    # not by support there -- a category with sup_a = 5 was still a baseline
    # category, just one with few test instances.
    shared = all_cats.intersection(cats_a.index)
    umich_only = all_cats.difference(cats_a.index)

    # Baseline metrics: real values for shared, zeros for Michigan-only.
    prec_a = pd.Series(0.0, index=all_cats)
    rec_a = pd.Series(0.0, index=all_cats)
    f1_a = pd.Series(0.0, index=all_cats)
    sup_a = pd.Series(0, index=all_cats, dtype='int64')
    prec_a.loc[shared] = cats_a.loc[shared, 'precision']
    rec_a.loc[shared] = cats_a.loc[shared, 'recall']
    f1_a.loc[shared] = cats_a.loc[shared, 'f1-score']
    sup_a.loc[shared] = cats_a.loc[shared, 'support'].astype('int64')

    prec_b = cats_b.loc[all_cats, 'precision']
    rec_b = cats_b.loc[all_cats, 'recall']
    f1_b = cats_b.loc[all_cats, 'f1-score']
    sup_b = cats_b.loc[all_cats, 'support']

    is_new = pd.Series(False, index=all_cats)
    is_new.loc[umich_only] = True

    # Treated vs. control classification (source: first_stage/select_categories
    # /code/build.do).  Any category in tier1 | tier2 | tier3 is treated.
    treated_set = config.TREATED_CATEGORIES
    is_treated = pd.Series(
        [cat in treated_set for cat in all_cats], index=all_cats)

    # "Good" requires support > MIN_SUPPORT on each side; cats_b is already
    # filtered so good_b doesn't need an explicit sup_b check.
    good_a = (sup_a > MIN_SUPPORT) & (prec_a > GOOD_THRESHOLD) & (rec_a > GOOD_THRESHOLD)
    good_b = (prec_b > GOOD_THRESHOLD) & (rec_b > GOOD_THRESHOLD)

    f1_delta = f1_b - f1_a
    # Shared points in dark blue, new-in-Michigan in purple.  Better/worse
    # is read mechanically from the 45-degree line on each scatter.
    point_colors = np.where(is_new.values, COLOR_NEW, COLOR_SHARED)

    # --- Print summary ---
    print("=" * 70)
    print(f"  VARIANT COMPARISON: {va} (utdallas) vs {vb} (combined)")
    print(f"  Shared categories (present in {va} UT Dallas report, any support): "
          f"{len(shared)}")
    print(f"  New-in-Michigan categories (absent from {va} UT Dallas report): "
          f"{len(umich_only)}")
    print(f"  Total categories plotted: {len(all_cats)}  "
          f"(treated={int(is_treated.sum())}, control={int((~is_treated).sum())})")
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

    good_a_count = int(good_a.sum())
    good_b_count = int(good_b.sum())
    good_b_shared = int((good_b & ~is_new).sum())
    good_b_new = int((good_b & is_new).sum())

    print(f"\n  GOOD CATEGORIES (precision > {GOOD_THRESHOLD} & recall > {GOOD_THRESHOLD}):")
    print(f"    {va}: {good_a_count} / {len(shared)}")
    print(f"    {vb}: {good_b_count} / {len(all_cats)}  "
          f"({good_b_shared} shared, {good_b_new} new-in-Michigan)")

    # Gained/lost on shared categories only (umich_only is reported separately).
    gained = good_b & ~good_a & ~is_new
    lost = good_a & ~good_b
    if gained.any():
        print(f"\n    Gained ({vb} is now good, {va} was not):")
        for cat in all_cats[gained.values]:
            print(f"      + {cat}  (prec {prec_a[cat]:.2f}->{prec_b[cat]:.2f}, "
                  f"rec {rec_a[cat]:.2f}->{rec_b[cat]:.2f})")
    if lost.any():
        print(f"\n    Lost ({va} was good, {vb} is not):")
        for cat in all_cats[lost.values]:
            print(f"      - {cat}  (prec {prec_a[cat]:.2f}->{prec_b[cat]:.2f}, "
                  f"rec {rec_a[cat]:.2f}->{rec_b[cat]:.2f})")
    if good_b_new:
        print(f"\n    New-in-Michigan and good in {vb}:")
        new_good = is_new & good_b
        for cat in all_cats[new_good.values]:
            print(f"      * {cat}  (prec {prec_b[cat]:.2f}, rec {rec_b[cat]:.2f}, "
                  f"support {int(sup_b[cat])})")

    # --- Lift attribution: why is each good_b category good? ---
    # Partition the good_b set by which baseline criterion was blocking.
    # Criteria: support > MIN_SUPPORT, precision > GOOD_THRESHOLD,
    # recall > GOOD_THRESHOLD.  is_new categories had no baseline at all.
    a_low_sup = sup_a <= MIN_SUPPORT
    a_low_prec = prec_a <= GOOD_THRESHOLD
    a_low_rec = rec_a <= GOOD_THRESHOLD

    already_good = good_b & good_a
    shared_lifted = good_b & ~good_a & ~is_new
    new_and_good = good_b & is_new

    only_support = shared_lifted & a_low_sup & ~a_low_prec & ~a_low_rec
    only_precision = shared_lifted & ~a_low_sup & a_low_prec & ~a_low_rec
    only_recall = shared_lifted & ~a_low_sup & ~a_low_prec & a_low_rec
    support_and_precision = shared_lifted & a_low_sup & a_low_prec & ~a_low_rec
    support_and_recall = shared_lifted & a_low_sup & ~a_low_prec & a_low_rec
    precision_and_recall = shared_lifted & ~a_low_sup & a_low_prec & a_low_rec
    all_three = shared_lifted & a_low_sup & a_low_prec & a_low_rec

    print(f"\n  LIFT ATTRIBUTION for {vb}'s {good_b_count} good categories:")
    print(f"    already good in {va}:                  {int(already_good.sum())}")
    print(f"    lifted (only support was blocking):    {int(only_support.sum())}")
    print(f"    lifted (only precision was blocking):  {int(only_precision.sum())}")
    print(f"    lifted (only recall was blocking):     {int(only_recall.sum())}")
    print(f"    lifted (support + precision blocking): {int(support_and_precision.sum())}")
    print(f"    lifted (support + recall blocking):    {int(support_and_recall.sum())}")
    print(f"    lifted (precision + recall blocking):  {int(precision_and_recall.sum())}")
    print(f"    lifted (all three blocking):           {int(all_three.sum())}")
    print(f"    new-in-Michigan (no baseline):         {int(new_and_good.sum())}")

    # --- Plots: 2x3 GridSpec.  Left 2x2 block = scatter grid split by
    # treated/control x precision/recall.  Right column spans both rows with
    # the stacked attribution bar chart. ---
    out_dir = os.path.join(BASE_DIR, "output")
    fig = plt.figure(figsize=(20, 11))
    gs = GridSpec(2, 3, figure=fig, width_ratios=[1, 1, 1.1], wspace=0.25,
                  hspace=0.32)
    ax_tp = fig.add_subplot(gs[0, 0])
    ax_tr = fig.add_subplot(gs[0, 1])
    ax_cp = fig.add_subplot(gs[1, 0])
    ax_cr = fig.add_subplot(gs[1, 1])
    ax_bar = fig.add_subplot(gs[:, 2])

    # Size points by max(support_a, support_b) so Michigan-only points (where
    # sup_a = 0) still get sized by their actual support.
    sizes_all = np.clip(np.log1p(np.maximum(sup_a.values, sup_b.values)) * 8,
                        15, 120)

    # Boolean mask of categories that were good in baseline but fell below
    # threshold under variant_b -- overlaid as a red ring on the scatter plots.
    lost_mask = (good_a & ~good_b).values
    treated_mask = is_treated.values
    control_mask = ~treated_mask

    def draw_scatter(ax, x, y, group_mask, xlabel, ylabel, title_metric):
        """Scatter one metric for one group (treated or control)."""
        x_g = x.values[group_mask]
        y_g = y.values[group_mask]
        colors_g = point_colors[group_mask]
        sizes_g = sizes_all[group_mask]
        lost_g = lost_mask[group_mask]

        n_group = int(group_mask.sum())
        n_shared_group = int((~is_new.values & group_mask).sum())
        n_new_group = int((is_new.values & group_mask).sum())
        n_lost_group = int((lost.values & group_mask).sum())
        better = int((y_g > x_g).sum())
        worse = int((y_g < x_g).sum())

        ax.scatter(x_g, y_g, s=sizes_g, c=colors_g, alpha=0.7,
                   edgecolors='k', linewidths=0.3)
        if lost_g.any():
            ax.scatter(x_g[lost_g], y_g[lost_g], s=sizes_g[lost_g] * 1.7,
                       facecolors='none', edgecolors=COLOR_LOST, linewidths=1.8)
        ax.plot([0, 1], [0, 1], 'k--', alpha=0.3)
        ax.axhline(GOOD_THRESHOLD, color='green', alpha=0.2, linestyle=':')
        ax.axvline(GOOD_THRESHOLD, color='green', alpha=0.2, linestyle=':')
        ax.set_xlabel(f'{title_metric} ({xlabel})')
        ax.set_ylabel(f'{title_metric} ({ylabel})')
        ax.set_xlim(-0.05, 1.05)
        ax.set_ylim(-0.05, 1.05)
        ax.set_aspect('equal')

        # Per-panel legend with counts scoped to this group.
        handles = [
            Line2D([0], [0], marker='o', linestyle='', color='w',
                   markerfacecolor=COLOR_SHARED, markeredgecolor='k',
                   markersize=7, label=f'Shared (n={n_shared_group})'),
            Line2D([0], [0], marker='o', linestyle='', color='w',
                   markerfacecolor=COLOR_NEW, markeredgecolor='k',
                   markersize=7, label=f'New in Michigan (n={n_new_group})'),
            Line2D([0], [0], marker='o', linestyle='', color='w',
                   markerfacecolor='none', markeredgecolor=COLOR_LOST,
                   markeredgewidth=1.8, markersize=9,
                   label=f'Lost-good (n={n_lost_group})'),
        ]
        ax.legend(handles=handles, loc='lower right', fontsize=7, framealpha=0.9)
        return n_group, better, worse

    # Row 1: treated
    n_t_prec, t_pb, t_pw = draw_scatter(ax_tp, prec_a, prec_b, treated_mask,
                                         va, vb, 'Precision')
    ax_tp.set_title(f'TREATED  Precision\n'
                    f'N = {n_t_prec}  (above 45° = {t_pb}, below = {t_pw})')
    n_t_rec, t_rb, t_rw = draw_scatter(ax_tr, rec_a, rec_b, treated_mask,
                                        va, vb, 'Recall')
    ax_tr.set_title(f'TREATED  Recall\n'
                    f'N = {n_t_rec}  (above 45° = {t_rb}, below = {t_rw})')

    # Row 2: control
    n_c_prec, c_pb, c_pw = draw_scatter(ax_cp, prec_a, prec_b, control_mask,
                                         va, vb, 'Precision')
    ax_cp.set_title(f'CONTROL  Precision\n'
                    f'N = {n_c_prec}  (above 45° = {c_pb}, below = {c_pw})')
    n_c_rec, c_rb, c_rw = draw_scatter(ax_cr, rec_a, rec_b, control_mask,
                                        va, vb, 'Recall')
    ax_cr.set_title(f'CONTROL  Recall\n'
                    f'N = {n_c_rec}  (above 45° = {c_rb}, below = {c_rw})')

    # --- Stacked attribution bar (right column, spans both rows). ---
    still_good = int(already_good.sum())
    lost_count = int(lost.sum())
    lift_support = int((only_support | support_and_precision
                        | support_and_recall | all_three).sum())
    lift_prec_only = int(only_precision.sum())
    lift_rec_only = int(only_recall.sum())
    lift_prec_rec = int(precision_and_recall.sum())
    new_good_ct = int(new_and_good.sum())

    # Cohesive palette: deep slate-blue anchor (shared in both bars), warmer
    # tones for lifted segments, separate accent hues for "new" and "lost".
    C_STILL = '#3D5A6C'    # deep slate blue (anchor — shared between bars)
    C_SUPP = '#7BA7BC'     # soft sky blue (close to anchor — "same family")
    C_PREC = '#E8B04B'     # warm gold
    C_REC = '#D97757'      # terracotta
    C_PR = '#A56B8B'       # dusty rose

    y_max_bar = max(good_a_count, good_b_count)

    def annotate_segment(x, bottom, count):
        if count >= y_max_bar * 0.03:
            ax_bar.text(x, bottom + count / 2, str(count), ha='center',
                        va='center', fontweight='bold', color='white',
                        fontsize=9)

    # Bar A (baseline)
    ax_bar.bar([va], [still_good], color=C_STILL, edgecolor='k', linewidth=0.5,
               label='still good in both')
    annotate_segment(0, 0, still_good)
    if lost_count:
        ax_bar.bar([va], [lost_count], bottom=[still_good], color=COLOR_LOST,
                   edgecolor='k', linewidth=0.5,
                   label=f'lost (good in {va} only)')
        annotate_segment(0, still_good, lost_count)

    # Bar B
    b_segments = [
        (still_good, C_STILL, None),
        (lift_support, C_SUPP, 'lifted: support was blocking'),
        (lift_prec_only, C_PREC, 'lifted: precision was blocking'),
        (lift_rec_only, C_REC, 'lifted: recall was blocking'),
        (lift_prec_rec, C_PR, 'lifted: prec+rec blocking'),
        (new_good_ct, COLOR_NEW, 'new in Michigan'),
    ]
    cum = 0
    for count, color, label in b_segments:
        if count == 0:
            continue
        ax_bar.bar([vb], [count], bottom=[cum], color=color, edgecolor='k',
                   linewidth=0.5, label=label)
        annotate_segment(1, cum, count)
        cum += count

    good_a_treated = int((good_a & is_treated).sum())
    good_a_control = int((good_a & ~is_treated).sum())
    good_b_treated = int((good_b & is_treated).sum())
    good_b_control = int((good_b & ~is_treated).sum())

    ax_bar.text(0, good_a_count + 0.5,
                f'total {good_a_count}\n'
                f'treated {good_a_treated} / control {good_a_control}',
                ha='center', va='bottom', fontweight='bold', fontsize=9)
    ax_bar.text(1, good_b_count + 0.5,
                f'total {good_b_count}\n'
                f'treated {good_b_treated} / control {good_b_control}',
                ha='center', va='bottom', fontweight='bold', fontsize=9)
    ax_bar.set_ylabel('Number of good categories')
    ax_bar.set_title(f'Good categories by attribution\n'
                     f'(prec>{GOOD_THRESHOLD}, rec>{GOOD_THRESHOLD}, '
                     f'support>{MIN_SUPPORT})')
    ax_bar.set_ylim(0, y_max_bar * 1.28)
    ax_bar.legend(fontsize=7, loc='upper left')

    fig.suptitle(f'{va} (UT Dallas) vs {vb} (combined)  -- '
                 f'treated/control split by {config.__name__}.TREATED_CATEGORIES',
                 fontsize=11, y=0.995)

    plot_path = os.path.join(out_dir, f"comparison_{va}_utdallas_vs_{vb}_combined.png")
    fig.savefig(plot_path, dpi=150, bbox_inches='tight')
    print(f"\n  Plot saved to: {plot_path}")
    plt.close()

    # --- Save full category-level comparison CSV ---
    def status_row(row):
        if row['is_new']:
            return 'new_good' if row[f'good_{vb}'] else 'new_not_good'
        if row[f'good_{vb}'] and not row[f'good_{va}']:
            return 'gained_good'
        if row[f'good_{va}'] and not row[f'good_{vb}']:
            return 'lost_good'
        if row['f1_delta'] > F1_DELTA_THRESHOLD:
            return 'better'
        if row['f1_delta'] < -F1_DELTA_THRESHOLD:
            return 'worse'
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
        'is_new': is_new,
        'is_treated': is_treated,
    })
    comp['status'] = comp.apply(status_row, axis=1)
    comp = comp.sort_values(['is_new', 'f1_delta'], ascending=[True, True])

    csv_path = os.path.join(out_dir, f"comparison_{va}_utdallas_vs_{vb}_combined.csv")
    comp.to_csv(csv_path)
    print(f"  CSV saved to: {csv_path}")

    status_counts = comp['status'].value_counts()
    print(f"\n  Category status summary:")
    for s in ['gained_good', 'better', 'stable', 'worse', 'lost_good',
              'new_good', 'new_not_good']:
        print(f"    {s:14s}: {status_counts.get(s, 0)}")


if __name__ == "__main__":
    main()
