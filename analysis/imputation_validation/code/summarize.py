"""Write a short, reproducible reading of the completed validation/output check."""
from pathlib import Path
import json

import pandas as pd

OUT = Path('../output')


def main():
    validation = pd.read_stata(OUT / 'tables/validation_by_similarity.dta',
                               convert_categoricals=False)
    candidates = pd.read_stata(OUT / 'tables/validation_candidates.dta',
                               convert_categoricals=False)
    decision = pd.read_stata(OUT / 'validation_selection.dta',
                             convert_categoricals=False).iloc[0]
    regressions = pd.read_stata(OUT / 'output_regressions.dta',
                                convert_categoricals=False).set_index('sample')
    composition = pd.read_stata(OUT / 'output_composition.dta',
                                convert_categoricals=False)
    pooled = validation.loc[validation.sim_group.eq(0)].iloc[0]
    manifest = json.loads((OUT / 'input_manifest.json').read_text())
    lines = ['FOIA imputation validation and one output sensitivity check', '',
             f"All {int(pooled.n)} held-out FOIA PIs: MAE {pooled.mae:.5f} "
             f"versus remaining-FOIA mean {pooled.mae_null:.5f}.",
             ('The method does not improve average absolute error in the pooled validation sample.'
              if pooled.mae >= pooled.mae_null else
              'The method improves average absolute error in the pooled validation sample.'),
             'The market price estimates and donor predictions remain fixed.', '']
    if decision.eligible:
        chosen = candidates.loc[(candidates.cutoff - decision.cutoff).abs().lt(1e-8)].iloc[0]
        lines += [f"Selected absolute similarity >= {decision.cutoff:.2f} before output estimation.",
                  f"Validation upper tail: {int(chosen.n_upper)} PIs; MAE "
                  f"{chosen.mae:.5f} vs {chosen.mae_null:.5f} "
                  f"({100 * chosen.mae_reduction:.1f}% reduction).",
                  f"Conditional paired PI-resampling 95% interval for MAE gain: "
                  f"[{chosen.gain_ci_low:.5f}, {chosen.gain_ci_high:.5f}].",
                  f"This covers {100 * chosen.share_nonfoia:.1f}% of non-FOIA estimation PIs.",
                  ('The error-gain interval includes zero; the restriction is exploratory.'
                   if chosen.gain_ci_includes_zero == 1 else
                   'The restriction remains an exploratory output sensitivity check.'), '']
    else:
        lines += ['No validation candidate was selected; no restricted regression was fit.', '']
    for name, r in regressions.iterrows():
        lines += [f"{name}: {int(r.N_pis):,} PIs / {int(r.N_rows):,} PI-years; "
                  f"exposure coefficient {r.b_exposure:.3f}, "
                  f"95% CI [{r.ci_lo:.3f}, {r.ci_hi:.3f}]; PI exposure SD {r.exposure_sd:.5f}."]
    if 'restricted' in regressions.index:
        full, restricted = regressions.loc['full'], regressions.loc['restricted']
        if full.b_exposure * restricted.b_exposure < 0:
            lines += ['The restricted point estimate changes sign relative to the full estimate.']
        if restricted.ci_lo < 0 < restricted.ci_hi:
            lines += ['The restricted interval spans zero and allows effects in both directions.',
                      'This check does not strengthen the full-sample estimate.']
        lines += ['', 'Composition diagnostic (unique PIs in the actual estimation sample):']
        for category, label in [('Early: <10 lab years', 'Early-career'),
                                ('Late: 20+ lab years', 'Late-career')]:
            shares = composition.loc[composition.characteristic.eq('career_stage')
                                     & composition.category.eq(category)].set_index('sample')['share']
            lines += [f"{label} share: {100 * shares['full_estimated']:.1f}% full "
                      f"versus {100 * shares['restricted_estimated']:.1f}% restricted."]
        lines += [f"Pre-merger annual publication mean: {full.pre_output_mean:.2f} full "
                  f"versus {restricted.pre_output_mean:.2f} restricted.",
                  'Research-cluster composition also changes (see output_composition.csv).',
                  'These descriptive shifts do not establish why the coefficient changes.',
                  'No additional output cutoffs were searched.']
    missing = manifest['missing_metadata']
    lines += ['', f"{missing['min_year']} validation PIs lack the unrestricted publication-based career clock;",
              f"{missing['cluster_30']} lack cluster metadata. All {int(pooled.n)} remain in the validation dataset.",
              'FOIA purchasing records are an imperfect exposure benchmark.',
              'University holdout is deferred; transfer across institutions has not been validated.']
    (OUT / 'results.txt').write_text('\n'.join(lines) + '\n')
    print('Saved ../output/results.txt')


if __name__ == '__main__':
    main()
