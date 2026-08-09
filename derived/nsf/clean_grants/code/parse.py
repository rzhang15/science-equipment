import csv
import glob
import json
import os
import re
import sys
from collections import Counter

RAW_DIR = '../external/nsf'
TMP_DIR = '../temp'
YEARS = range(2010, 2020)

# NSF grantees have no IPF code, so org ids are minted here. The offset keeps
# them from ever being mistaken for a RePORTER org_ipf_code if the two grant
# panels are pooled.
ORG_ID_BASE = 90_000_000

_RE_WS        = re.compile(r'\s+')
_RE_ORG_PUNCT = re.compile(r'[^a-z0-9 ]')


def clean(s):
    if s is None:
        return ''
    return _RE_WS.sub(' ', str(s)).strip()


def org_key(inst):
    """UEI where NSF records one, else name+state."""
    uei = clean(inst.get('org_uei_num')).upper()
    if uei:
        return 'UEI:' + uei
    name = _RE_ORG_PUNCT.sub(' ', clean(inst.get('inst_name')).lower())
    return 'NAME:' + clean(name) + '|' + clean(inst.get('inst_state_code')).upper()


def pi_name(p):
    """'LAST, FIRST M', the RePORTER convention match.py's norm_pi expects."""
    last  = clean(p.get('pi_last_name')).replace(';', ' ')
    given = clean(clean(p.get('pi_first_name')) + ' ' + clean(p.get('pi_mid_init')))
    given = given.replace(';', ' ')
    if not last or not given:
        return ''
    return f'{last}, {given}'.upper()


AWARD_COLS = ['awd_id','award_year','project_title','project_start','project_end',
              'awd_amount','tot_intn_awd_amt','awd_arra_amount',
              'tran_type','awd_istr_txt','cfda_num','agcy_id',
              'dir_abbr','org_dir_long_name','div_abbr','org_div_long_name',
              'nsf_org_code','po_name','amd_first_date','amd_last_date',
              'org_id','org_uei_num','org_name','org_city','org_state','org_country',
              'perf_inst_name','perf_city','perf_state','perf_country',
              'n_pi','n_pi_lead','pi_names']
FY_COLS   = ['awd_id','fy','total_cost','fy_src']
PI_COLS   = ['awd_id','nsf_id','pi_role','pi_name','pi_first_name','pi_mid_init',
             'pi_last_name','pi_sufx_name','pi_full_name','pi_email_addr',
             'pi_start_date','pi_end_date']
ABS_COLS  = ['awd_id','project_title','abstract']
PGM_COLS  = ['awd_id','pgm_type','pgm_code','pgm_name']

LEAD_ROLES = ('Principal Investigator', 'Former Principal Investigator')


def writer(fh, cols):
    w = csv.DictWriter(fh, fieldnames=cols, extrasaction='ignore',
                       quoting=csv.QUOTE_ALL, lineterminator='\n')
    w.writeheader()
    return w


def main():
    os.makedirs(TMP_DIR, exist_ok=True)
    awards, org_keys, seen = [], {}, set()
    n_files = n_bad = n_dup = 0
    per_year, fy_dist, role_ct = Counter(), Counter(), Counter()

    f_fy  = open(f'{TMP_DIR}/award_fy.csv',   'w', newline='', encoding='utf-8')
    f_pi  = open(f'{TMP_DIR}/pis.csv',        'w', newline='', encoding='utf-8')
    f_abs = open(f'{TMP_DIR}/abstracts.csv',  'w', newline='', encoding='utf-8')
    f_pgm = open(f'{TMP_DIR}/pgm.csv',        'w', newline='', encoding='utf-8')
    w_fy, w_pi, w_abs, w_pgm = (writer(f_fy, FY_COLS), writer(f_pi, PI_COLS),
                                writer(f_abs, ABS_COLS), writer(f_pgm, PGM_COLS))

    for year in YEARS:
        # '1611112 2.json' is a re-download of '1611112.json'; the canonical
        # name sorts second, so rank it first and let the awd_id guard below
        # drop the copy.
        files = sorted(glob.glob(f'{RAW_DIR}/{year}/*.json'),
                       key=lambda p: (os.path.basename(p).count(' '), p))
        per_year[year] = len(files)
        print(f'[{year}] {len(files):,} json files', flush=True)
        for path in files:
            try:
                with open(path, encoding='utf-8') as fh:
                    d = json.load(fh)
            except Exception as e:
                n_bad += 1
                print(f'    unreadable: {path}: {e}', file=sys.stderr)
                continue

            awd_id = clean(d.get('awd_id')) or os.path.basename(path)[:-5]
            if awd_id in seen:
                n_dup += 1
                continue
            seen.add(awd_id)
            n_files += 1

            inst   = d.get('inst') or {}
            perf   = d.get('perf_inst') or {}

            key = org_key(inst)
            if key not in org_keys:
                org_keys[key] = None

            pis = d.get('pi') or []
            names, lead = [], 0
            for p in pis:
                role_ct[clean(p.get('pi_role'))] += 1
                nm = pi_name(p)
                if nm and nm not in names:
                    names.append(nm)
                if clean(p.get('pi_role')) in LEAD_ROLES:
                    lead += 1
                w_pi.writerow({'awd_id': awd_id, 'pi_name': nm,
                               **{c: clean(p.get(c)) for c in PI_COLS[1:] if c != 'pi_name'}})

            awards.append({
                'awd_id': awd_id, 'award_year': year, 'org_key': key,
                'project_title': clean(d.get('awd_titl_txt')),
                'project_start': clean(d.get('awd_eff_date')),
                'project_end':   clean(d.get('awd_exp_date')),
                'awd_amount':       d.get('awd_amount'),
                'tot_intn_awd_amt': d.get('tot_intn_awd_amt'),
                'awd_arra_amount':  d.get('awd_arra_amount'),
                'tran_type':    clean(d.get('tran_type')),
                'awd_istr_txt': clean(d.get('awd_istr_txt')),
                'cfda_num':     clean(d.get('cfda_num')),
                'agcy_id':      clean(d.get('agcy_id')),
                'dir_abbr':          clean(d.get('dir_abbr')),
                'org_dir_long_name': clean(d.get('org_dir_long_name')),
                'div_abbr':          clean(d.get('div_abbr')),
                'org_div_long_name': clean(d.get('org_div_long_name')),
                'nsf_org_code':   clean(d.get('org_code')),
                'po_name':        clean(d.get('po_sign_block_name')),
                'amd_first_date': clean(d.get('awd_min_amd_letter_date')),
                'amd_last_date':  clean(d.get('awd_max_amd_letter_date')),
                'org_uei_num':  clean(inst.get('org_uei_num')),
                'org_name':     clean(inst.get('inst_name')),
                'org_city':     clean(inst.get('inst_city_name')),
                'org_state':    clean(inst.get('inst_state_code')).upper(),
                'org_country':  clean(inst.get('inst_country_name')).upper(),
                'perf_inst_name': clean(perf.get('perf_inst_name')),
                'perf_city':      clean(perf.get('perf_city_name')),
                'perf_state':     clean(perf.get('perf_st_code')).upper(),
                'perf_country':   clean(perf.get('perf_ctry_name')).upper(),
                'n_pi': len(pis), 'n_pi_lead': lead,
                'pi_names': ';'.join(names),
            })

            oblg = d.get('oblg_fy') or []
            wrote = False
            for o in oblg:
                fy, amt = o.get('fund_oblg_fiscal_yr'), o.get('fund_oblg_amt')
                if fy is None:
                    continue
                w_fy.writerow({'awd_id': awd_id, 'fy': int(fy),
                               'total_cost': amt, 'fy_src': 'oblg'})
                fy_dist[int(fy)] += 1
                wrote = True
            if not wrote:
                # no obligation record: fall back to the award's effective year
                eff = clean(d.get('awd_eff_date'))[:4]
                if eff.isdigit():
                    w_fy.writerow({'awd_id': awd_id, 'fy': int(eff),
                                   'total_cost': d.get('awd_amount'), 'fy_src': 'eff_date'})
                    fy_dist[int(eff)] += 1

            abstract = _RE_WS.sub(' ', clean(d.get('awd_abstract_narration')))
            if abstract:
                w_abs.writerow({'awd_id': awd_id, 'abstract': abstract,
                                'project_title': clean(d.get('awd_titl_txt'))})

            for tag, items, ck, nk in (('ele', d.get('pgm_ele'), 'pgm_ele_code', 'pgm_ele_name'),
                                       ('ref', d.get('pgm_ref'), 'pgm_ref_code', 'pgm_ref_txt')):
                for it in items or []:
                    w_pgm.writerow({'awd_id': awd_id, 'pgm_type': tag,
                                    'pgm_code': clean(it.get(ck)),
                                    'pgm_name': clean(it.get(nk))})

    for f in (f_fy, f_pi, f_abs, f_pgm):
        f.close()

    for i, k in enumerate(sorted(org_keys), 1):
        org_keys[k] = ORG_ID_BASE + i
    with open(f'{TMP_DIR}/awards.csv', 'w', newline='', encoding='utf-8') as fh:
        w = writer(fh, AWARD_COLS)
        for a in awards:
            a['org_id'] = org_keys[a.pop('org_key')]
            w.writerow(a)

    n_uei = sum(1 for k in org_keys if k.startswith('UEI:'))
    print(f'\nawards parsed      : {n_files:,} ({n_bad} unreadable, '
          f'{n_dup} duplicate awd_id skipped)')
    print(f'distinct orgs      : {len(org_keys):,} ({n_uei:,} keyed on UEI, '
          f'{len(org_keys)-n_uei:,} on name+state)')
    print(f'awards with no PI  : {sum(1 for a in awards if not a["pi_names"]):,}')
    print('\nfiles per award-year folder:')
    for y, c in sorted(per_year.items()):
        flag = '   <-- looks incomplete' if c < 0.5 * (sum(per_year.values()) / len(per_year)) else ''
        print(f'  {y}  {c:7,}{flag}')
    print('\nobligation rows per fiscal year:')
    for y, c in sorted(fy_dist.items()):
        print(f'  {y}  {c:7,}')
    print('\npi roles:')
    for r, c in role_ct.most_common():
        print(f'  {r:34s} {c:8,}')


if __name__ == '__main__':
    main()
