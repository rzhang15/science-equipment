import pandas as pd
import numpy as np
import re
import os
import time
import unicodedata
from collections import defaultdict, Counter
from rapidfuzz import fuzz, process

REPORTER_DTA   = '../external/reporter/reporter_2010_2019.dta'
ATHR_PANEL_DTA = '../external/athr_panel/athr_panel_full_year_all_jrnls.dta'
OUT_DIR        = '../output'
TMP_DIR        = '../temp'

# --- name normalization ------------------------------------------------------

_RE_PUNCT   = re.compile(r'[^a-z\s]')
_RE_MULTISP = re.compile(r'\s+')
_RE_SUFFIX  = re.compile(r'\b(jr|sr|ii|iii|iv|md|phd|mph|do|dds|dvm|rn|esq|facp)\b')
_RE_ROLE    = re.compile(r'\((contact|multi[-\s]?pi|former|previous)\)', re.IGNORECASE)
_RE_APOS    = re.compile(r"['‘’ʼ`]")

# These have no NFKD decomposition, so the ascii encode would delete them:
# Ostbye must come out 'ostbye', not 'stbye'.
_TRANSLIT = str.maketrans({
    'ø':'o','Ø':'O','æ':'ae','Æ':'Ae','œ':'oe','Œ':'Oe','ß':'ss',
    'đ':'d','Đ':'D','ð':'d','Ð':'D','þ':'th','Þ':'Th','ł':'l','Ł':'L',
    'ħ':'h','Ħ':'H','ı':'i','ŋ':'n','Ŋ':'N'})

def _fold(s: str) -> str:
    """Muller/Muller, Garcia/Garcia: RePORTER is ASCII, OpenAlex is not."""
    return unicodedata.normalize('NFKD', s.translate(_TRANSLIT)).encode('ascii', 'ignore').decode('ascii')

def _strip_name(s: str) -> str:
    s = _fold(s).lower()
    s = _RE_ROLE.sub('', s)
    s = _RE_APOS.sub('', s)
    s = _RE_PUNCT.sub(' ', s)
    s = _RE_SUFFIX.sub(' ', s)
    s = _RE_MULTISP.sub(' ', s).strip()
    return s

# Particles are dropped from the blocking keys but kept in `full` for scoring.
_PARTICLES = {'de','del','della','di','da','dos','das','du','la','le','van','von',
              'der','den','ten','ter','bin','ibn','al','st','san','santa'}

_RE_UMLAUT = re.compile(r'(ue|oe|ae)')

def _deumlaut(t: str) -> str:
    """RePORTER holds MULLER where OpenAlex may hold Mueller."""
    return _RE_UMLAUT.sub(lambda m: m.group(0)[0], t).replace('ss', 's')

def _glue_variants(toks):
    out = {''.join(toks)}
    for n in (2, 3):
        if len(toks) > n:
            out.add(''.join(toks[-n:]))
    return out

def _last_keys(toks):
    """Every token that could carry the surname, plus glued trailing runs, so
    'garcia marquez' blocks under garciamarquez and OpenAlex's 'O Brien' meets
    RePORTER's O'BRIEN. Runs are built over the single-letter tokens too --
    those are what an apostrophe or a dropped hyphen leaves behind."""
    core = [t for t in toks if t not in _PARTICLES and len(t) > 1]
    if not core:
        core = [t for t in toks if t]
    keys = set(core)
    run = [t for t in toks if t not in _PARTICLES]
    for n in (2, 3):
        if len(run) >= n:
            keys.add(''.join(run[-n:]))
    keys.update(_deumlaut(k) for k in tuple(keys))
    return frozenset(keys)

def _initials(toks, cap=2):
    return frozenset(t[0] for t in toks[:cap] if t)

_RE_NONALPHA = re.compile(r'[^A-Za-z]')

def _expand_glued_initials(raw: str) -> str:
    """OpenAlex holds 'DK O'Dowd' where RePORTER holds 'O'DOWD, DIANE K';
    DK is two initials, not a given name Diane has to outscore."""
    if raw.isupper():
        return raw
    def ex(seg, guard_last):
        parts = seg.split()
        out = []
        for i, p in enumerate(parts):
            core = _RE_NONALPHA.sub('', p)
            if 2 <= len(core) <= 3 and core.isupper() and not (guard_last and i == len(parts) - 1):
                out.append(' '.join(core))
            else:
                out.append(p)
        return ' '.join(out)
    if ',' in raw:
        head, _, tail = raw.partition(',')
        return head + ', ' + ex(tail, False)
    return ex(raw, True)

def norm_pi(raw: str):
    """RePORTER 'LAST, FIRST M' -> given tokens / surname tokens / block keys."""
    if not isinstance(raw, str):
        return None
    s = raw.strip()
    if not s:
        return None
    if ',' in s:
        last, _, rest = s.partition(',')
        first = rest
    else:
        parts = s.split()
        if len(parts) < 2:
            return None
        last, first = parts[-1], ' '.join(parts[:-1])
    sur   = _strip_name(last).split()
    given = _strip_name(first).split()
    if not sur or not given:
        return None
    return {'given': given, 'sur': sur,
            'lasts': _last_keys(sur), 'fis': _initials(given)}

def norm_athr(raw: str):
    """OpenAlex 'First M Last' / 'F. Last' / 'Last, First' -> same fields.

    Without a comma we cannot tell a middle name from the first half of a
    compound surname, so middle tokens are offered to both sides and the
    scorer settles it."""
    if not isinstance(raw, str):
        return None
    raw = _expand_glued_initials(raw)
    if ',' in raw:
        head, _, tail = raw.partition(',')
        sur   = _strip_name(head).split()
        given = _strip_name(tail).split()
    else:
        parts = _strip_name(raw).split()
        if len(parts) < 2:
            return None
        given, sur = parts[:-1], parts[1:]
    if not sur or not given:
        return None
    return {'given': given, 'sur': sur,
            'lasts': _last_keys(sur), 'fis': _initials(given)}

# --- name comparison ---------------------------------------------------------

def _tok_score(a: str, b: str) -> int:
    """An initial matches the name it abbreviates; a prefix nearly does."""
    if len(a) == 1 or len(b) == 1:
        return 100 if a[0] == b[0] else 0
    if a == b:
        return 100
    if a.startswith(b) or b.startswith(a):
        return 92
    return fuzz.ratio(a, b)

def _sur_score(ps, as_) -> int:
    p, a = set(ps), set(as_)
    if p == a:
        return 100
    if p <= a or a <= p:
        return 95
    if p & a:
        return 88
    # a hyphen or apostrophe dropped on one side leaves the same letters glued
    best = fuzz.token_set_ratio(' '.join(ps), ' '.join(as_))
    for g1 in _glue_variants(ps):
        for g2 in _glue_variants(as_):
            best = max(best, fuzz.ratio(g1, g2), fuzz.ratio(_deumlaut(g1), _deumlaut(g2)))
    return best

def _given_score(gp, ga) -> float:
    best = 0
    for i, tp in enumerate(gp):
        for j, ta in enumerate(ga):
            if (i or j) and (len(tp) == 1 or len(ta) == 1):
                continue    # a middle initial cannot vouch for a first name
            s = _tok_score(tp, ta)
            if i or j:
                s -= 6      # published under a middle name
            if s > best:
                best = s
    if len(gp) > 1 and len(ga) > 1:
        if len({t[0] for t in gp} & {t[0] for t in ga}) < 2:
            best -= 8       # both sides give a middle name and they disagree
    return max(best, 0)

def name_score(p, a) -> float:
    """0-100, over anything exposing .given and .sur. 'John Smith' vs
    'J. Smith' scores 100, not the 86 token_set_ratio gives it: a dropped
    given name is not a mismatch, and it is the most common way OpenAlex
    writes a name we hold in full."""
    return 0.45 * _sur_score(p.sur, a.sur) + 0.55 * _given_score(p.given, a.given)

# --- institution normalization / matching ------------------------------------

_RE_INST_PUNCT = re.compile(r'[^a-z0-9\s]')
_INST_STOP = {
    'the','of','and','at','a','an',
    'university','univ','college','coll','institute','inst','school','sch',
    'center','centre','ctr','cntr',
    'hospital','hosp','medical','med','medicine','health','hlth','healthcare',
    'system','systems','dept','department','div','division',
    'foundation','research','the',
    'inc','llc','corp','ltd','company','co',
}

def norm_inst(s: str) -> str:
    if not isinstance(s, str):
        return ''
    s = s.lower()
    s = s.replace('&', ' and ')
    s = s.replace('univ/', 'university of ')
    s = _RE_INST_PUNCT.sub(' ', s)
    s = _RE_MULTISP.sub(' ', s).strip()
    return s

def inst_tokens(s: str) -> str:
    toks = [t for t in norm_inst(s).split() if t not in _INST_STOP and len(t) > 2]
    return ' '.join(toks)

MAX_CAND = 20000
MAX_INST_PER_ORG = 40
GEO_RESCUE_CUTOFF = 80

def _ctry(s: str) -> str:
    if not s:
        return ''
    return 'US' if s in ('UNITED STATES', 'USA', 'US') else 'FOREIGN'

def build_inst_crosswalk(org_df: pd.DataFrame, inst_df: pd.DataFrame,
                         threshold: int = 88) -> pd.DataFrame:
    """org_df: org_ipf_code, org_name [+ org_state, org_country]
       inst_df: inst_id, inst [+ state, country]
       Returns: org_ipf_code -> set of candidate inst_id (matched).

       Ties at the token-set score are real and dangerous: 'UNIVERSITY OF
       PENNSYLVANIA' reduces to the token 'pennsylvania', which every
       Pennsylvania inst matches at 100, and an arbitrary cap used to be able
       to drop Penn itself. Exact key equality, then same state, then the full
       string decide who survives the cap; a country conflict kills the edge.
       Orgs the string match strands get one more chance against the insts of
       their own state at a lower bar."""
    org_df  = org_df.copy()
    inst_df = inst_df.copy()
    org_df['org_key']   = org_df['org_name'].map(inst_tokens)
    org_df['org_full']  = org_df['org_name'].map(norm_inst)
    inst_df['inst_key']  = inst_df['inst'].map(inst_tokens)
    inst_df['inst_full'] = inst_df['inst'].map(norm_inst)
    org_df  = org_df[org_df['org_key'].str.len() > 0].drop_duplicates('org_ipf_code')
    inst_df = inst_df[inst_df['inst_key'].str.len() > 0].drop_duplicates('inst_id')

    geo = 'org_state' in org_df.columns and 'state' in inst_df.columns
    inst_ids   = inst_df['inst_id'].tolist()
    inst_keys  = inst_df['inst_key'].tolist()
    inst_fulls = inst_df['inst_full'].tolist()
    inst_state = inst_df['state'].fillna('').tolist() if geo else ['']*len(inst_ids)
    inst_ctry  = [_ctry(c) for c in inst_df['country'].fillna('')] if geo else ['']*len(inst_ids)

    # token -> inst positions, used to block candidates before scoring
    postings, by_state = defaultdict(list), defaultdict(list)
    for j, k in enumerate(inst_keys):
        for t in set(k.split()):
            postings[t].append(j)
        if inst_state[j]:
            by_state[inst_state[j]].append(j)

    key_to_orgs = defaultdict(list)
    for r in org_df.itertuples(index=False):
        st = (getattr(r, 'org_state', '') or '') if geo else ''
        ct = _ctry((getattr(r, 'org_country', '') or '')) if geo else ''
        key_to_orgs[r.org_key].append((r.org_ipf_code, r.org_full, st, ct))

    rows, rescue = [], defaultdict(list)
    for i, (okey, orgs) in enumerate(key_to_orgs.items(), 1):
        if i % 500 == 0:
            print(f'    inst match: {i}/{len(key_to_orgs)} unique org keys')
        toks = sorted(set(okey.split()), key=lambda t: len(postings.get(t, ())))
        cand = set()
        for t in toks:
            p = postings.get(t)
            if not p:
                continue
            if cand and len(cand) + len(p) > MAX_CAND:
                break
            cand.update(p)
        hits = []
        if cand:
            cand = list(cand)
            scores = process.cdist([okey], [inst_keys[j] for j in cand],
                                   scorer=fuzz.token_set_ratio,
                                   score_cutoff=threshold, workers=-1,
                                   dtype=np.uint8)[0]
            hits = [(cand[h], int(scores[h])) for h in np.flatnonzero(scores)]
        for code, ofull, ostate, octry in orgs:
            kept = []
            for j, s in hits:
                if octry and inst_ctry[j] and octry != inst_ctry[j]:
                    continue
                if ostate and inst_state[j] and ostate != inst_state[j] and s < 95:
                    continue
                kept.append((j, s))
            if not kept:
                if ostate:
                    rescue[(okey, ostate)].append((code, ofull))
                continue
            kept.sort(key=lambda js: (inst_keys[js[0]] != okey,
                                      not (ostate and inst_state[js[0]] == ostate),
                                      -js[1],
                                      -fuzz.ratio(ofull, inst_fulls[js[0]])))
            for j, s in kept[:MAX_INST_PER_ORG]:
                rows.append((code, inst_ids[j], s))

    print(f'    rescue pass: {sum(len(v) for v in rescue.values())} stranded orgs with a known state')
    for (okey, ostate), org_list in rescue.items():
        js = by_state.get(ostate)
        if not js:
            continue
        scores = process.cdist([okey], [inst_keys[j] for j in js],
                               scorer=fuzz.token_set_ratio,
                               score_cutoff=GEO_RESCUE_CUTOFF, workers=-1,
                               dtype=np.uint8)[0]
        hits = [(js[h], int(scores[h])) for h in np.flatnonzero(scores)]
        for code, ofull in org_list:
            kept = sorted(hits, key=lambda t: (-t[1], -fuzz.ratio(ofull, inst_fulls[t[0]])))[:10]
            for j, s in kept:
                rows.append((code, inst_ids[j], s))
    return pd.DataFrame(rows, columns=['org_ipf_code','inst_id','inst_score'])

# --- PI <-> athr matching within institution --------------------------------

RARE_THRESHOLD = 94
MIN_EDGE_SUPPORT = 3
COLS = ['pi_name','org_ipf_code','athr_id','athr_name','inst_id',
        'name_score','match_src']

def _index_athr(athr_df):
    by_block, by_name, placed = defaultdict(list), defaultdict(list), set()
    athr_insts = defaultdict(set)
    for r in athr_df.itertuples(index=False):
        athr_insts[r.athr_id].add(r.inst_id)
        for k in r.lasts:
            for gi in r.fis:
                by_block[(r.inst_id, k, gi)].append(r)
        if r.athr_id not in placed:
            placed.add(r.athr_id)
            for k in r.lasts:
                for gi in r.fis:
                    by_name[(k, gi)].append(r)
    return by_block, by_name, athr_insts

def _pass_inst(pi_rows, by_block, inst_lookup, threshold, tag='inst'):
    """Blocked on (institution, surname key, given initial)."""
    hit, miss = [], []
    for i, r in enumerate(pi_rows, 1):
        if i % 20000 == 0:
            print(f'      {i:,}/{len(pi_rows):,}')
        best, seen = None, set()
        for iid in inst_lookup.get(r.org_ipf_code, ()):
            for k in r.lasts:
                for gi in r.fis:
                    for a in by_block.get((iid, k, gi), ()):
                        if a.athr_id in seen:
                            continue
                        seen.add(a.athr_id)
                        s = name_score(r, a)
                        if s >= threshold and (best is None or s > best[3]):
                            best = (a.athr_id, a.athr_name, a.inst_id, s)
        if best is None:
            miss.append(r)
        else:
            hit.append((r.pi_raw, r.org_ipf_code, *best, tag))
    return hit, miss

NAME_DOM_MIN = 96
NAME_DOM_GAP = 6

def _pass_name(pi_rows, by_name, threshold,
               org_state=None, inst_state=None, athr_insts=None):
    """No institution required, but the name must pick out one author.
    A rare surname resolves outright; among several candidates, a clear
    scoring winner or a lone candidate in the grantee's state does.
    'SMITH, JOHN' still stays unmatched, as it should."""
    hit, miss = [], []
    geo = org_state is not None and inst_state is not None and athr_insts is not None
    for i, r in enumerate(pi_rows, 1):
        if i % 20000 == 0:
            print(f'      {i:,}/{len(pi_rows):,}')
        hits, seen = {}, set()
        for k in r.lasts:
            for gi in r.fis:
                for a in by_name.get((k, gi), ()):
                    if a.athr_id in seen:
                        continue
                    seen.add(a.athr_id)
                    s = name_score(r, a)
                    if s >= threshold:
                        hits[a.athr_id] = (s, a)
        pick, tag = None, 'name'
        if len(hits) == 1:
            pick = next(iter(hits.values()))
        elif len(hits) > 1:
            ranked = sorted(hits.values(), key=lambda t: -t[0])
            if ranked[0][0] >= NAME_DOM_MIN and ranked[0][0] - ranked[1][0] >= NAME_DOM_GAP:
                pick, tag = ranked[0], 'name_dom'
            elif geo:
                st = org_state.get(r.org_ipf_code, '')
                if st:
                    same = [t for t in hits.values() if st in
                            {inst_state.get(i2, '') for i2 in athr_insts[t[1].athr_id]}]
                    if len(same) == 1:
                        pick, tag = same[0], 'name_geo'
        if pick is None:
            miss.append(r)
            continue
        s, a = pick
        hit.append((r.pi_raw, r.org_ipf_code, a.athr_id, a.athr_name,
                    a.inst_id, s, tag))
    return hit, miss

def _learn_edges(rows, inst_lookup):
    """Where several rare-name PIs at one grantee org all land on the same
    OpenAlex institution, that is a real org-institution relation the string
    matcher missed -- hospital to affiliated school, campus to system."""
    cnt = Counter((row[1], row[4]) for row in rows)
    return [(org, iid) for (org, iid), c in cnt.items()
            if c >= MIN_EDGE_SUPPORT and iid not in inst_lookup.get(org, ())]

def match_pi_to_athr(pi_df: pd.DataFrame, athr_df: pd.DataFrame,
                     inst_xw: pd.DataFrame, threshold: int = 88,
                     org_state=None, inst_state=None) -> pd.DataFrame:
    """pi_df: pi_raw, org_ipf_code, given, sur, lasts, fis
       athr_df: athr_id, athr_name, inst_id, given, sur, lasts, fis
       inst_xw: org_ipf_code -> inst_id (string-matched)
       org_state/inst_state: code -> 2-letter state, for name-pass tiebreaks"""
    by_block, by_name, athr_insts = _index_athr(athr_df)
    inst_lookup = defaultdict(set)
    for r in inst_xw.itertuples(index=False):
        inst_lookup[r.org_ipf_code].add(r.inst_id)

    pi_rows = list(pi_df.itertuples(index=False))
    print(f'    [a] institution-blocked, {len(pi_rows):,} PIs')
    rows, miss = _pass_inst(pi_rows, by_block, inst_lookup, threshold)
    print(f'        placed {len(rows):,}')

    print(f'    [b] name-unique, no institution, {len(miss):,} PIs')
    hit_b, miss = _pass_name(miss, by_name, RARE_THRESHOLD,
                             org_state, inst_state, athr_insts)
    rows += hit_b
    print(f'        placed {len(hit_b):,}')

    new_edges = _learn_edges(hit_b, inst_lookup)
    for org, iid in new_edges:
        inst_lookup[org].add(iid)
    print(f'    [c] learned {len(new_edges):,} org->inst edges; '
          f'rerunning {len(miss):,} PIs')
    hit_c, miss = _pass_inst(miss, by_block, inst_lookup, threshold, tag='inst2')
    rows += hit_c
    print(f'        placed {len(hit_c):,}; {len(miss):,} PIs unmatched')

    pd.DataFrame(new_edges, columns=['org_ipf_code','inst_id']).to_csv(
        f'{OUT_DIR}/inst_crosswalk_learned.csv', index=False)
    return pd.DataFrame(rows, columns=COLS)

# --- io ----------------------------------------------------------------------

def read_dta(path, columns):
    try:
        import pyreadstat
        df, _ = pyreadstat.read_dta(path, usecols=columns)
        return df
    except Exception:
        return pd.read_stata(path, columns=columns)

def athr_universe():
    cache = f'{TMP_DIR}/athr_universe.parquet'
    cols = ['athr_id','athr_name','inst_id','inst','us_state','country_code']
    if os.path.exists(cache):
        df = pd.read_parquet(cache)
        if set(cols) <= set(df.columns):
            print('    (cached)')
            return df
    athr = read_dta(ATHR_PANEL_DTA, cols)
    athr = athr.dropna(subset=['athr_id','athr_name','inst_id'])
    athr = athr.drop_duplicates(subset=['athr_id','inst_id']).copy()
    athr.to_parquet(cache, index=False)
    return athr

# --- main -------------------------------------------------------------------

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(TMP_DIR, exist_ok=True)

    t0 = time.time()
    print('[1/5] loading RePORTER…')
    geo_cols = ['org_state','org_country']
    try:
        rep = read_dta(REPORTER_DTA, ['pi_names','org_name','org_ipf_code','fy'] + geo_cols)
    except Exception:
        print('    (reporter lacks org_state/org_country -- rebuild clean_reporter '
              'to enable the geographic passes)')
        rep = read_dta(REPORTER_DTA, ['pi_names','org_name','org_ipf_code','fy'])
        for c in geo_cols:
            rep[c] = ''
    rep[geo_cols] = rep[geo_cols].fillna('')
    rep = rep.dropna(subset=['pi_names','org_ipf_code'])
    rep['org_ipf_code'] = rep['org_ipf_code'].astype('int64').astype(str)

    print('[2/5] exploding & normalizing PIs…')
    rep = rep.assign(pi_name=rep['pi_names'].str.split(';')).explode('pi_name')
    rep['pi_name'] = rep['pi_name'].str.strip()
    rep = rep[rep['pi_name'].str.len() > 0]
    pi = rep[['pi_name','org_ipf_code','org_name','org_state','org_country']].drop_duplicates()
    norm = pi['pi_name'].map(norm_pi)
    pi = pi.loc[norm.notna()].copy()
    pi[['given','sur','lasts','fis']] = pd.DataFrame(norm.dropna().tolist(), index=pi.index)
    pi = pi.rename(columns={'pi_name':'pi_raw'})
    pi_uniq = pi.drop_duplicates(subset=['pi_raw','org_ipf_code'])
    print(f'    -> {len(pi_uniq):,} unique (pi_name, org) pairs')

    print('[3/5] loading athr panel…')
    athr_uniq = athr_universe()
    norm_a = athr_uniq['athr_name'].map(norm_athr)
    athr_uniq = athr_uniq.loc[norm_a.notna()].copy()
    athr_uniq[['given','sur','lasts','fis']] = pd.DataFrame(norm_a.dropna().tolist(), index=athr_uniq.index)
    print(f'    -> {len(athr_uniq):,} unique (athr, inst) rows')

    print('[4/5] institution bridge…')
    org_universe  = pi_uniq[['org_ipf_code','org_name','org_state','org_country']] \
                        .drop_duplicates('org_ipf_code')
    inst_universe = athr_uniq[['inst_id','inst','us_state','country_code']] \
                        .drop_duplicates('inst_id') \
                        .rename(columns={'us_state':'state','country_code':'country'})
    inst_xw = build_inst_crosswalk(org_universe, inst_universe)
    inst_xw.to_csv(f'{OUT_DIR}/inst_crosswalk.csv', index=False)
    print(f'    -> {len(inst_xw):,} org->inst edges '
          f'({inst_xw["org_ipf_code"].nunique():,}/{len(org_universe):,} orgs matched)')

    print('[5/5] PI -> athr matching…')
    org_state_map  = {r.org_ipf_code: (r.org_state or '')
                      for r in org_universe.itertuples(index=False)}
    inst_state_map = {r.inst_id: ('' if pd.isna(r.state) else r.state)
                      for r in inst_universe.itertuples(index=False)}
    xw = match_pi_to_athr(pi_uniq, athr_uniq, inst_xw,
                          org_state=org_state_map, inst_state=inst_state_map)
    xw.to_csv(f'{OUT_DIR}/pi_athr_crosswalk.csv', index=False)
    print(f'    -> {len(xw):,} PI matches '
          f'({xw["pi_name"].nunique():,}/{pi_uniq["pi_raw"].nunique():,} PIs matched)')
    print(f'done in {time.time()-t0:.1f}s')

if __name__ == '__main__':
    main()
