from pathlib import Path
import pandas as pd
import numpy as np
import argparse
r=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser(description='Prepare a frozen NIH age/funding composition audit')
parser.add_argument('--panel', type=Path, default=r/'analysis/rf_heterogeneity/temp/es_all_jrnls_r1_r2.dta')
parser.add_argument('--work', type=Path, default=Path('/tmp/nih_age_funding_audit'))
parser.add_argument('--out', type=Path, default=r/'analysis/rf_heterogeneity/output/nih_age_funding_audit')
args=parser.parse_args();w=args.work;out=args.out
w.mkdir(parents=True,exist_ok=True);out.mkdir(parents=True,exist_ok=True)
cols=['athr_id','year','ppr_cnt','nih_total_cost','exposure','mkt_spend_shr','young','young_ns','young_any','high_nihd','low_nihd','nih_funding_baseline','pre_ppr_cnt_avg','min_year','min_year_any','inst_id','cluster_30']
d=pd.read_stata(args.panel,columns=cols,convert_categoricals=False)
history=pd.read_csv(out/'historical_labels.csv',dtype={'athr_id':str})
old=history[['athr_id','old_high','old_funding']]
orig=history[['athr_id','orig_high','orig_young','orig_funding']]
d=d.merge(old,on='athr_id',how='left').merge(orig,on='athr_id',how='left')
a=d[(d.year<2014)&d.nih_total_cost.notna()].groupby('athr_id').nih_total_cost.agg(active_years=lambda s:(s>0).sum());d=d.merge(a,on='athr_id',how='left')
d['cell']=np.where(d.high_nihd.notna(),1+2*(1-d.young)+(1-d.high_nihd),np.nan)
d['intermittent']=(d.active_years<4).where(d.active_years.notna()).astype(float)
d['cell8']=2*(d.cell-1)+1+d.intermittent
# Same outcomes/covariates in the fixed-sample label comparisons.
d.to_stata(w/'audit_panel.dta',write_index=False,version=118)
p=d.sort_values('year').drop_duplicates('athr_id').copy()
for period,years in [('pre',range(2010,2014)),('post',range(2014,2020))]:
 z=d[d.year.isin(years)].groupby('athr_id').agg(**{f'pub_{period}':('ppr_cnt','mean'),f'award_{period}':('nih_total_cost','mean')})
 p=p.merge(z,on='athr_id',how='left')
p['funding_loss']=p.old_funding-p.nih_funding_baseline
p['switched']=((p.old_high!=p.high_nihd)&p.old_high.notna()&p.high_nihd.notna())
p['age_switched']=((p.orig_young!=p.young)&p.orig_young.notna())
p['status']=np.select([p.high_nihd.isna() & p.old_high.notna(), p.high_nihd.isna(),p.old_high.isna(),(p.old_high==1)&(p.high_nihd==0),(p.old_high==0)&(p.high_nihd==1)],['now_ineligible','never_eligible','newly_eligible','high_to_low','low_to_high'],default='same')
g=pd.read_stata(r/'derived/nih/match_pi_athr/output/nih_grants_by_athr_id.dta',columns=['athr_id','year','row_key','activity','total_cost','research'],convert_categoricals=False).drop_duplicates(['athr_id','year','row_key'])
g=g[(g.year<2014)&(g.research==1)&g.athr_id.isin(p.athr_id)]
for name,codes in [('r01',['R01']),('r21',['R21']),('dp',['DP1','DP2','DP5']),('coop',['U01','UG1','UG3','UH2','UH3'])]:
 amount=g[g.activity.isin(codes)].groupby('athr_id').total_cost.sum()/4
 p[name+'_funding']=p.athr_id.map(amount).fillna(0)
p['r01_share']=p.r01_funding/p.nih_funding_baseline
p['pub_change']=p.pub_post-p.pub_pre
p['award_change']=p.award_post-p.award_pre
p['pub_ratio']=p.pub_post/p.pub_pre
p['award_ratio']=p.award_post/p.award_pre
p.to_csv(out/'pi_composition.csv',index=False)
summary=p[p.high_nihd.notna()].groupby('cell').agg(pis=('athr_id','size'),exposure_mean=('exposure','mean'),exposure_sd=('exposure','std'),baseline_mean=('nih_funding_baseline','mean'),baseline_median=('nih_funding_baseline','median'),active_years_mean=('active_years','mean'),persistent_fraction=('intermittent',lambda s:1-s.mean()),pre_publications=('pub_pre','mean'),post_publications=('pub_post','mean'),pre_awards=('award_pre','mean'),post_awards=('award_post','mean'),r01_share_mean=('r01_share','mean'),switched=('switched','sum'))
summary.to_csv(out/'four_cell_composition.csv');print(summary.to_string())
print('Funding label moves',p.groupby(['status','young']).size().to_dict());print('Age-label switches relative to earliest snapshot',p.age_switched.sum())
p[p.high_nihd.notna()].groupby(['cell','active_years']).size().rename('pis').to_csv(out/'funding_continuity_counts.csv')
d[d.high_nihd.notna()].groupby(['cell','year']).agg(publications=('ppr_cnt','mean'),awards=('nih_total_cost','mean'),pis=('athr_id','nunique')).to_csv(out/'annual_cell_means.csv')
print('AUDIT_PREPARED')
