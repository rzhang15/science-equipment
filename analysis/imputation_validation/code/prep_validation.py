"""Recover the existing K=3 LOO exercise with fixed all3 market price shocks."""
import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd
import scipy.sparse as sp

EXTERNAL = Path('../external')
OUT = Path('../output')
K, SHARPEN, FLOOR = 3, 2.0, 0.05
CATEGORY_RENAMES = {'acrylamide/bis solution': 'acrylamide-bis solution',
                    'dmem/f-12': 'dmem-f-12'}


def export(df, name):
    df.to_csv(OUT / (name + '.csv'), index=False)
    df.to_stata(OUT / (name + '.dta'), write_index=False, version=118)


def source_record(path, digest=True):
    stat = path.stat()
    out = {'path': str(path.resolve()), 'size': stat.st_size,
           'mtime_ns': stat.st_mtime_ns}
    if digest:
        h = hashlib.sha256()
        with path.open('rb') as f:
            for block in iter(lambda: f.read(1024 * 1024), b''):
                h.update(block)
        out['sha256'] = h.hexdigest()
    return out


def load_loo():
    ids = pd.read_csv(EXTERNAL / 'exposure/foia_ids_ordered.csv',
                      dtype={'athr_id': str})['athr_id'].tolist()
    assert len(ids) == len(set(ids)) == 208, 'Expected the existing 208-PI donor bank.'
    shocks = pd.read_stata(EXTERNAL / 'betas/did_coefs_eb_price_all3.dta',
                           convert_categoricals=False)
    shocks['category'] = shocks['category'].replace(CATEGORY_RENAMES)
    shocks = shocks.dropna(subset=['b_eb'])[['category', 'b_eb']].copy()
    assert not shocks['category'].duplicated().any(), 'Duplicate market shocks.'
    export(shocks, 'fixed_market_shocks')
    g = shocks['b_eb'].to_numpy(float)
    shares = pd.read_stata(EXTERNAL / 'real_exposure/athr_exposure_by_category_hc_all3.dta',
                          convert_categoricals=False)
    shares['category'] = shares['category'].replace(CATEGORY_RENAMES)
    shares = shares.dropna(subset=['spend', 'tot_shr_spend'])
    shares = shares[(shares['spend'] > 0) & (shares['tot_shr_spend'] > 0)
                    & shares['athr_id'].isin(ids)
                    & shares['category'].isin(shocks['category'])].copy()
    shares['share'] = shares['spend'].astype(float) / shares['tot_shr_spend'].astype(float)
    ipos = {a: i for i, a in enumerate(ids)}
    mpos = {c: j for j, c in enumerate(shocks['category'])}
    S = sp.csr_matrix((shares['share'], (shares['athr_id'].map(ipos),
                                       shares['category'].map(mpos))),
                      shape=(len(ids), len(g))).toarray()
    assert (S.sum(1) > 0).all(), 'A donor lacks treated-market shares; audit before continuing.'
    X = sp.load_npz(EXTERNAL / 'exposure/tfidf_foia.npz').tocsr()
    assert X.shape[0] == len(ids)
    sim = (X @ X.T).toarray().astype(np.float64)
    np.fill_diagonal(sim, -1.0)
    topk = np.argpartition(-sim, K - 1, axis=1)[:, :K]
    raw = sim[np.arange(len(ids))[:, None], topk]
    weights = np.where(raw >= FLOOR, raw ** SHARPEN, 0.0)
    row_sum = weights.sum(1, keepdims=True)
    weights /= np.where(row_sum > 0, row_sum, 1.0)
    P = np.einsum('ik,ikm->im', weights, S[topk])
    observed = S @ g
    pred = P @ g
    benchmark = (observed.sum() - observed) / (len(ids) - 1)
    loo = pd.DataFrame({'athr_id': ids, 'max_sim': sim.max(1),
                        'exposure': observed, 'exposure_loo': pred,
                        'exposure_null': benchmark, 'mkt_spend_shr': S.sum(1),
                        'mkt_spend_shr_loo': P.sum(1),
                        'n_donors': (weights > 0).sum(1)})
    assert not loo.isna().any().any()
    assert np.all(topk != np.arange(len(ids))[:, None]), 'Self donor in LOO.'
    assert np.allclose(weights.sum(1), 1), 'Unmatched LOO row.'
    old = pd.read_stata(EXTERNAL / 'exposure/loo_shares_pi_hc_all3_k3.dta',
                        convert_categoricals=False).set_index('athr_id')
    new = loo.set_index('athr_id').reindex(old.index)
    differences = {v: float((new[v] - old[v]).abs().max())
                   for v in ['max_sim', 'exposure', 'exposure_loo', 'exposure_null']}
    print('Recovered LOO versus archived file (max absolute difference):', differences)
    # The archived prediction file is a consistency check, not an input to selection.
    return loo, differences


def add_career_stage(df):
    df['lab_age_2014'] = 2014 - df['min_year']
    age = df['lab_age_2014']
    df['career_stage'] = np.select([age < 10, age.between(10, 20, inclusive='left'),
                                   age >= 20], [1, 2, 3], default=4).astype(np.int8)
    return df


def load_metadata(ids):
    # Use the unrestricted last-author panel, before the RF sample exclusions.
    chunks = []
    source = EXTERNAL / 'samp/athr_panel_full_year_last_all_jrnls.dta'
    for chunk in pd.read_stata(source, columns=['athr_id', 'year'],
                              chunksize=200000, convert_categoricals=False):
        chunk = chunk[chunk['athr_id'].isin(ids)]
        if len(chunk):
            chunks.append(chunk.groupby('athr_id', as_index=False)['year'].min())
    if chunks:
        career = pd.concat(chunks).groupby('athr_id', as_index=False)['year'].min()
        career = career.rename(columns={'year': 'min_year'})
    else:
        career = pd.DataFrame({'athr_id': [], 'min_year': []})
    # Purchasing universities are recovered separately from publication affiliations.
    universities = pd.read_stata('../temp/foia_university.dta', convert_categoricals=False)
    assert not universities['athr_id'].duplicated().any()
    clusters = pd.read_csv(EXTERNAL / 'cluster/author_static_clusters_30.csv',
                           dtype={'athr_id': str})[['athr_id', 'cluster_label']]
    assert not clusters['athr_id'].duplicated().any()
    return career, universities, clusters.rename(columns={'cluster_label': 'cluster_30'})


def load_panel():
    cols = ['athr_id', 'year', 'exposure', 'mkt_spend_shr', 'max_sim', 'foia_athr',
            'min_year', 'min_year_any', 'inst_id', 'inst', 'cluster_30', 'type', 'public']
    panel = pd.read_stata(EXTERNAL / 'rf/prepped_samples/es_all_jrnls_r1_r2.dta',
                          columns=cols, convert_categoricals=False)
    assert not panel[['athr_id', 'year']].duplicated().any()
    assert panel['year'].between(2010, 2019).all()
    for var in [c for c in cols if c not in ['athr_id', 'year']]:
        assert panel.groupby('athr_id')[var].nunique(dropna=False).max() <= 1, var
    panel = panel.drop_duplicates('athr_id').drop(columns='year').copy()
    panel['foia_athr'] = panel['foia_athr'].eq(1).astype(np.int8)
    return add_career_stage(panel)


def main():
    loo, differences = load_loo()
    career, universities, clusters = load_metadata(set(loo['athr_id']))
    for frame in [career, universities, clusters]:
        loo = loo.merge(frame, on='athr_id', how='left', validate='one_to_one')
    loo = add_career_stage(loo)
    panel = load_panel()
    loo['in_estimation_panel'] = loo['athr_id'].isin(panel['athr_id']).astype(np.int8)
    loo['university'] = loo['university'].fillna('Unknown')
    export(loo, 'validation_pi')
    export(panel, 'panel_pi')
    sources = ['exposure/foia_ids_ordered.csv', 'exposure/tfidf_foia.npz',
               'exposure/loo_shares_pi_hc_all3_k3.dta', 'betas/did_coefs_eb_price_all3.dta',
               'real_exposure/athr_exposure_by_category_hc_all3.dta',
               'cluster/author_static_clusters_30.csv',
               'rf/prepped_samples/es_all_jrnls_r1_r2.dta']
    manifest = {'recipe': {'version': 'hc_all3', 'k': K, 'sharpen': SHARPEN,
                            'floor': FLOOR, 'price_shocks': 'fixed b_eb all3'},
                'archived_loo_max_differences': differences,
                'n_validation': len(loo), 'n_panel_pi': len(panel),
                'n_foia_in_panel': int(panel['foia_athr'].eq(1).sum()),
                'missing_metadata': {v: int(loo[v].isna().sum())
                                     for v in ['min_year', 'cluster_30']},
                'sources': [source_record(EXTERNAL / p) for p in sources]}
    manifest['sources'].append(source_record(
        EXTERNAL / 'samp/athr_panel_full_year_last_all_jrnls.dta', digest=False))
    manifest['university_source'] = source_record(Path('../temp/foia_university.dta'))
    manifest['university_inputs'] = json.loads(
        Path('../temp/university_sources.json').read_text())
    (OUT / 'input_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Validation PIs:', len(loo), '; estimation PIs:', len(panel),
          '; observed FOIA PIs in panel:', manifest['n_foia_in_panel'])
    print('Missing metadata:', manifest['missing_metadata'])


if __name__ == '__main__':
    main()
