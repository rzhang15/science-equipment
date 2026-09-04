import pandas as pd
import os
import re
import config

TYPO_CORRECTIONS = {
    "anitmony": "antimony",
    "animal - would clip": "animal - wound clip",
    "brushes - benchs": "brushes - bench",
    "cell culture antibiotics - ancomycin": "cell culture antibiotics - vancomycin",
    "cell culture antibiotics - ciprofoxavin": "cell culture antibiotics - ciprofloxacin",
    "cell culture antibiotics - sparfloaxin": "cell culture antibiotics - sparfloxacin",
    "chromatography casettes": "chromatography cassettes",
    "clorimetric dyes": "colorimetric dyes",
    "colorimetriic detection kit": "colorimetric detection kit",
    "deslating columns": "desalting columns",
    "drosophilia": "drosophila",
    "drosphilia vials": "drosophila vials",
    "fees - maintanence/repair": "fees - maintenance/repair",
    "flourescent dyes": "fluorescent dyes",
    "geletin": "gelatin",
    "gl-thread spetum cap": "gl-thread septum cap",
    "hydrophobic-interaction chrmatography": "hydrophobic-interaction chromatography",
    "hyluronic acid": "hyaluronic acid",
    "instrument - refridgerator": "instrument - refrigerator",
    "instrument - refridgerators": "instrument - refrigerators",
    "instrument - sequencerr": "instrument - sequencer",
    "instrument - vauum pump": "instrument - vacuum pump",
    "instrument parrt - sealing gaskets": "instrument part - sealing gaskets",
    "instrument part - air fliters": "instrument part - air filters",
    "instrument part - hplc insertt": "instrument part - hplc insert",
    "instrument part - minearl oil": "instrument part - mineral oil",
    "instrument part - socet": "instrument part - socket",
    "instrument part - vacuum blange": "instrument part - vacuum flange",
    "instrument part - vacuum flushign fluid": "instrument part - vacuum flushing fluid",
    "instrument part - valvce cartridge": "instrument part - valve cartridge",
    "instrumnet part - tlc plate cutter blades": "instrument part - tlc plate cutter blades",
    "instrment - solder": "instrument - solder",
    "intsrument - arc lamp": "instrument - arc lamp",
    "lab furniture - benctop protector": "lab furniture - benchtop protector",
    "ligatioin-based cloning systems": "ligation-based cloning systems",
    "liphophilic tracer": "lipophilic tracer",
    "magnetic-bead based purificaton kit": "magnetic-bead based purification kit",
    "rmpi": "rpmi",
    "rna stabalization reagent": "rna stabilization reagent",
    "tag-binding affiny resins": "tag-binding affinity resins",
    "thermalcouples": "thermocouples",
    "donkey-host anti-goat polyclonal conjugated secondary antiboddy": "donkey-host anti-goat polyclonal conjugated secondary antibody",
    "donkey-host anti-rat polyclonal conjugated secondary antiboddy": "donkey-host anti-rat polyclonal conjugated secondary antibody",
    "horse-host anti-moust polyclonal conjugated secondary antibody": "horse-host anti-mouse polyclonal conjugated secondary antibody",
    "labatory spatulas": "laboratory spatulas",
    "drosophilia vials": "drosophila vials",
    "pastuer pipettes": "pasteur pipettes",
    "reverse transcriptiase": "reverse transcriptase",
    "xray casettes": "xray cassettes",
    "thin layer chromatography alumnium sheets": "thin layer chromatography aluminum sheets",
    "nuclease enyzmes": "nuclease enzymes",
    "microarry chips": "microarray chips",
    "tissue clearning solution": "tissue clearing solution",
    "nonlab - bundle of producs": "nonlab - bundle of products",
}

IRREGULAR_PLURALS = {
    "medium": "media",
    "matrix": "matrices",
    "criterion": "criteria",
    "index": "indices",
    "apparatus": "apparatuses",
    "analysis": "analyses",
}


_UNICODE_NORMALIZE_MAP = {
    '\u2013': '-',
    '\u2014': '-',
    '\u2011': '-',
    '\u2010': '-',
    '\u00ad': '-',
    '\xa0': ' ',
    '\u2018': "'",
    '\u2019': "'",
    '\u201c': '"',
    '\u201d': '"',
    '\u2026': '...',
}


def normalize_unicode(text):
    if not isinstance(text, str):
        return text
    for src, dst in _UNICODE_NORMALIZE_MAP.items():
        if src in text:
            text = text.replace(src, dst)
    return text


def normalize_unicode_series(s):
    out = s
    for src, dst in _UNICODE_NORMALIZE_MAP.items():
        out = out.str.replace(src, dst, regex=False)
    return out


def clean_category_string(text):
    if not isinstance(text, str):
        return text
    text = normalize_unicode(text)
    text = text.lower().strip()
    text = re.sub(r'^#+\s*', '', text)
    text = re.sub(r'\s{2,}', ' ', text)
    text = text.strip()
    return text


def clean_category_series(s):
    out = normalize_unicode_series(s.astype(str))
    out = out.str.lower().str.strip()
    out = out.str.replace(r'^#+\s*', '', regex=True)
    out = out.str.replace(r'\s{2,}', ' ', regex=True)
    out = out.str.strip()
    return out


def save_nonlab_bucket_assignments(category_counts, output_path):
    df = category_counts.copy()
    df['bucket'] = config.assign_nonlab_bucket_series(df['category'])
    df = df[df['bucket'] != ''][['bucket', 'category', 'count']]
    df = df.sort_values(['bucket', 'count'], ascending=[True, False])
    df.to_csv(output_path, index=False)
    print(f"  Non-lab bucket assignments saved to: {output_path}")
    print(f"  {len(df)} non-lab categories across {df['bucket'].nunique()} buckets")
    n_misc = (df['bucket'] == 'other_misc').sum()
    if n_misc:
        print(f"  ({n_misc} categories fell through to 'other_misc' — "
              f"consider adding explicit bucket rules in config.NONLAB_BUCKET_RULES)")


def apply_sibling_consolidation(df, cat_col):
    cons_map = getattr(config, 'CATEGORY_CONSOLIDATION', None)
    if not cons_map:
        return
    hit_mask = df[cat_col].isin(cons_map.keys())
    n_rows = int(hit_mask.sum())
    if n_rows == 0:
        print("  No sibling-consolidation matches.")
        return
    df.loc[hit_mask, cat_col] = df.loc[hit_mask, cat_col].map(cons_map)
    print(f"  Consolidated {n_rows} rows across {len(cons_map)} sibling renames:")
    for src, dst in cons_map.items():
        print(f"    '{src}' -> '{dst}'")


def build_plural_map(unique_categories):
    cat_set = set(unique_categories)
    plural_map = {}

    for cat in cat_set:
        if cat + 's' in cat_set:
            plural_map[cat] = cat + 's'

    for cat in cat_set:
        if cat + 'es' in cat_set:
            if cat not in plural_map:
                plural_map[cat] = cat + 'es'

    for cat in cat_set:
        if cat.endswith('y') and cat[:-1] + 'ies' in cat_set:
            plural_map[cat] = cat[:-1] + 'ies'

    for singular, plural in IRREGULAR_PLURALS.items():
        for cat in cat_set:
            candidate_plural = cat.replace(singular, plural)
            if candidate_plural != cat and candidate_plural in cat_set:
                plural_map[cat] = candidate_plural

    return plural_map


def report_unmatched_cat_keys(df_raw, df_cat, merge_keys, unmatched_csv=None,
                              max_print=50):
    print("\nChecking that every combined_XXX merge key matches the raw data...")
    missing_cols = [k for k in merge_keys if k not in df_raw.columns or k not in df_cat.columns]
    if missing_cols:
        print(f"  - WARNING: merge key(s) missing from one side: {missing_cols}. Skipping check.")
        return

    raw_keys = df_raw[merge_keys].drop_duplicates()
    raw_keys['_in_raw'] = True
    check = df_cat.merge(raw_keys, on=merge_keys, how='left')
    unmatched = check[check['_in_raw'].isna()].drop(columns=['_in_raw'])

    n_cat = len(df_cat)
    n_unmatched = len(unmatched)
    print(f"  - Category file rows: {n_cat}")
    print(f"  - Unmatched (no raw row found): {n_unmatched}")

    if n_unmatched == 0:
        print("  - All category keys matched the raw data.")
        return

    raw_keys_unique = df_raw[merge_keys].drop_duplicates().copy()
    for k in merge_keys:
        raw_keys_unique[k] = raw_keys_unique[k].astype(str)
    for drop_key in merge_keys:
        other = [k for k in merge_keys if k != drop_key]
        if not other:
            continue
        raw_grouped = (
            raw_keys_unique
            .groupby(other, dropna=False)[drop_key]
            .agg(**{
                f'raw_{drop_key}_n_candidates': 'nunique',
                f'raw_{drop_key}_example': 'min',
            })
            .reset_index()
        )
        unmatched = unmatched.merge(raw_grouped, on=other, how='left')

    near_match_cols = []
    for k in merge_keys:
        near_match_cols += [f'raw_{k}_n_candidates', f'raw_{k}_example']
    preview_cols = list(merge_keys)
    for extra in (config.UT_CAT_COL, 'old_category'):
        if extra in unmatched.columns and extra not in preview_cols:
            preview_cols.append(extra)
    preview_cols += [c for c in near_match_cols if c in unmatched.columns]

    print(f"  - First {min(max_print, n_unmatched)} unmatched rows "
          f"(for each merge key K: n_candidates = # raw rows matching on the "
          f"other keys; example = one raw value of K — if it differs from the "
          f"combined value, K is the mismatched key):")
    with pd.option_context('display.max_rows', max_print,
                           'display.max_colwidth', 80,
                           'display.width', 200):
        print(unmatched[preview_cols].head(max_print).to_string(index=False))

    if unmatched_csv is not None:
        os.makedirs(os.path.dirname(unmatched_csv), exist_ok=True)
        unmatched.to_csv(unmatched_csv, index=False)
        print(f"  - Full unmatched list saved to: {unmatched_csv}")


def main():
    print("--- Starting Step 0: Cleaning and Merging UT Dallas Data ---")

    os.makedirs(config.TEMP_DIR, exist_ok=True)

    print("Loading raw data files...")
    try:
        df_ut = pd.read_csv(config.UT_DALLAS_CLEAN_CSV, low_memory=False)
        df_cat = pd.read_excel(config.UT_DALLAS_CATEGORIES_XLSX, keep_default_na=False, na_values=[''])
        print(f"  - Loaded {len(df_ut)} rows from UT Dallas main file.")
        print(f"  - Loaded {len(df_cat)} rows from category mapping file.")
    except FileNotFoundError as e:
        print(f"Error loading data files: {e}. Make sure paths in config.py are correct.")
        return

    print("\n--- Category Standardization Pipeline ---")

    print("  Step 3a: Normalizing unicode, lowercase, stripping whitespace...")
    if config.UT_CAT_COL in df_cat.columns:
        df_cat[config.UT_CAT_COL] = clean_category_series(df_cat[config.UT_CAT_COL])

    if 'old_category' in df_cat.columns:
        df_cat['old_category'] = clean_category_series(df_cat['old_category'])
        df_cat[config.UT_CAT_COL] = df_cat[config.UT_CAT_COL].replace('', pd.NA).fillna(df_cat['old_category'])

    n_categories_before = df_cat[config.UT_CAT_COL].nunique()
    print(f"  Unique categories after normalization: {n_categories_before}")

    print("  Step 3b: Applying known typo corrections...")
    n_typos_fixed = 0
    if config.UT_CAT_COL in df_cat.columns:
        mask = df_cat[config.UT_CAT_COL].isin(TYPO_CORRECTIONS.keys())
        n_typos_fixed = mask.sum()
        df_cat[config.UT_CAT_COL] = df_cat[config.UT_CAT_COL].replace(TYPO_CORRECTIONS)
    print(f"  Fixed {n_typos_fixed} rows with known typos ({len(TYPO_CORRECTIONS)} correction rules)")

    print("  Step 3c: Detecting and merging singular/plural category pairs...")
    if config.UT_CAT_COL in df_cat.columns:
        unique_categories = set(df_cat[config.UT_CAT_COL].dropna().unique())
        plural_map = build_plural_map(unique_categories)

        if plural_map:
            df_cat[config.UT_CAT_COL] = df_cat[config.UT_CAT_COL].replace(plural_map)
            print(f"  Merged {len(plural_map)} singular/plural pairs")
            sample_merges = list(plural_map.items())[:10]
            for singular, plural in sample_merges:
                print(f"    '{singular}' -> '{plural}'")
            if len(plural_map) > 10:
                print(f"    ... and {len(plural_map) - 10} more")
        else:
            print("  No singular/plural pairs detected.")

    n_categories_after = df_cat[config.UT_CAT_COL].nunique()
    print(f"\n  Category count: {n_categories_before} -> {n_categories_after} "
          f"(reduced by {n_categories_before - n_categories_after})")

    for key in config.UT_DALLAS_MERGE_KEYS:
        if key in df_ut.columns and key in df_cat.columns:
            df_ut[key] = df_ut[key].astype(str)
            df_cat[key] = df_cat[key].astype(str)
    print("\nDropping duplicates from category mapping file to ensure unique merge keys...")
    initial_cat_len = len(df_cat)
    df_cat = df_cat.drop_duplicates(subset=config.UT_DALLAS_MERGE_KEYS, keep='first')
    rows_dropped = initial_cat_len - len(df_cat)
    if rows_dropped > 0:
        print(f"  - Dropped {rows_dropped} duplicate rows from the category file.")

    report_unmatched_cat_keys(df_ut, df_cat, config.UT_DALLAS_MERGE_KEYS,
                              unmatched_csv=os.path.join(config.OUTPUT_DIR,
                                                         'utdallas_unmatched_category_keys.csv'))

    print("\nMerging files (inner merge to keep only matched rows)...")
    df_merged = pd.merge(df_ut, df_cat, on=config.UT_DALLAS_MERGE_KEYS, how='inner', validate="many_to_one")
    print(f"  - Merge complete. Resulting dataset has {len(df_merged)} rows.")

    initial_rows = len(df_merged)
    df_merged.dropna(subset=[config.CLEAN_DESC_COL, config.UT_CAT_COL], inplace=True)
    rows_dropped = initial_rows - len(df_merged)
    if rows_dropped > 0:
        print(f"  - Dropped {rows_dropped} rows due to missing descriptions or categories.")

    cat_col_lower = df_merged[config.UT_CAT_COL].astype(str).str.lower()

    print("\nConsolidating antibody categories...")
    is_antibody = cat_col_lower.str.contains("antibod", na=False)
    is_primary = cat_col_lower.str.contains("primary", na=False)
    is_secondary = cat_col_lower.str.contains("secondary", na=False)
    is_poly = cat_col_lower.str.contains("polyclonal", na=False)
    is_mono = cat_col_lower.str.contains("monoclonal", na=False)
    n_ab_before = cat_col_lower[is_antibody].nunique()
    df_merged.loc[is_antibody & is_primary & is_poly, config.UT_CAT_COL] = "polyclonal primary antibodies"
    df_merged.loc[is_antibody & is_primary & is_mono, config.UT_CAT_COL] = "monoclonal primary antibodies"
    df_merged.loc[is_antibody & is_secondary, config.UT_CAT_COL] = "secondary antibodies"
    n_ab_after = df_merged.loc[is_antibody, config.UT_CAT_COL].nunique()
    print(f"  Merged {n_ab_before} antibody subcategories -> {n_ab_after} "
          f"({is_antibody.sum()} rows: polyclonal/monoclonal primary + secondary)")

    print("\nConsolidating pipette tip subcategories...")
    is_pipette_tip = cat_col_lower.str.contains("pipette tip", na=False)
    n_tip_consolidated = is_pipette_tip.sum()
    tip_cats_merged = cat_col_lower[is_pipette_tip].nunique()
    df_merged.loc[is_pipette_tip, config.UT_CAT_COL] = "pipette tips"
    print(f"  Merged {tip_cats_merged} pipette tip subcategories ({n_tip_consolidated} rows) -> 'pipette tips'")

    print("\nConsolidating ELISA kit categories...")
    is_elisa = cat_col_lower.str.contains("elisa", na=False)
    n_elisa_before = cat_col_lower[is_elisa].nunique()
    df_merged.loc[is_elisa, config.UT_CAT_COL] = "elisa kits"
    print(f"  Merged {n_elisa_before} elisa subcategories ({is_elisa.sum()} rows) -> 'elisa kits'")

    print("\nApplying sibling consolidation from config.CATEGORY_CONSOLIDATION...")
    apply_sibling_consolidation(df_merged, config.UT_CAT_COL)

    print("\nGenerating and saving category counts...")
    category_counts = df_merged[config.UT_CAT_COL].value_counts().reset_index()
    category_counts.columns = ['category', 'count']
    counts_output_path = os.path.join(config.OUTPUT_DIR, 'utdallas_category_counts.csv')
    category_counts.to_csv(counts_output_path, index=False)
    print(f"  Category counts saved to: {counts_output_path}")
    print(f"  Final unique categories: {df_merged[config.UT_CAT_COL].nunique()}")

    save_nonlab_bucket_assignments(
        category_counts,
        os.path.join(config.OUTPUT_DIR, 'nonlab_bucket_assignments.csv'),
    )

    df_merged.to_parquet(config.UT_DALLAS_MERGED_CLEAN_PATH, index=False)
    print(f"\nFinal clean and merged data saved to: {config.UT_DALLAS_MERGED_CLEAN_PATH}")
    print("--- Step 0: Complete ---")

def main_umich():
    print("--- Starting Step 0: Cleaning and Merging UMich Data (2010-2019) ---")

    os.makedirs(config.TEMP_DIR, exist_ok=True)

    print("Loading raw data files...")
    try:
        df_um = pd.read_csv(config.UMICH_CLEAN_CSV, low_memory=False)
        df_cat = pd.read_excel(config.UMICH_CATEGORIES_XLSX, keep_default_na=False, na_values=[''])
        print(f"  - Loaded {len(df_um)} rows from UMich main file (2010-2019).")
        print(f"  - Loaded {len(df_cat)} rows from category mapping file.")
    except FileNotFoundError as e:
        print(f"Error loading data files: {e}. Make sure paths in config.py are correct.")
        return

    print("\n--- Category Standardization Pipeline ---")

    print("  Step 3a: Normalizing unicode, lowercase, stripping whitespace...")
    if config.UT_CAT_COL in df_cat.columns:
        df_cat[config.UT_CAT_COL] = clean_category_series(df_cat[config.UT_CAT_COL])

    if 'old_category' in df_cat.columns:
        df_cat['old_category'] = clean_category_series(df_cat['old_category'])
        df_cat[config.UT_CAT_COL] = df_cat[config.UT_CAT_COL].replace('', pd.NA).fillna(df_cat['old_category'])

    n_categories_before = df_cat[config.UT_CAT_COL].nunique()
    print(f"  Unique categories after normalization: {n_categories_before}")

    print("  Step 3b: Applying known typo corrections...")
    n_typos_fixed = 0
    if config.UT_CAT_COL in df_cat.columns:
        mask = df_cat[config.UT_CAT_COL].isin(TYPO_CORRECTIONS.keys())
        n_typos_fixed = mask.sum()
        df_cat[config.UT_CAT_COL] = df_cat[config.UT_CAT_COL].replace(TYPO_CORRECTIONS)
    print(f"  Fixed {n_typos_fixed} rows with known typos ({len(TYPO_CORRECTIONS)} correction rules)")

    print("  Step 3c: Detecting and merging singular/plural category pairs...")
    if config.UT_CAT_COL in df_cat.columns:
        unique_categories = set(df_cat[config.UT_CAT_COL].dropna().unique())
        plural_map = build_plural_map(unique_categories)

        if plural_map:
            df_cat[config.UT_CAT_COL] = df_cat[config.UT_CAT_COL].replace(plural_map)
            print(f"  Merged {len(plural_map)} singular/plural pairs")
            sample_merges = list(plural_map.items())[:10]
            for singular, plural in sample_merges:
                print(f"    '{singular}' -> '{plural}'")
            if len(plural_map) > 10:
                print(f"    ... and {len(plural_map) - 10} more")
        else:
            print("  No singular/plural pairs detected.")

    n_categories_after = df_cat[config.UT_CAT_COL].nunique()
    print(f"\n  Category count: {n_categories_before} -> {n_categories_after} "
          f"(reduced by {n_categories_before - n_categories_after})")

    for key in config.UMICH_MERGE_KEYS:
        if key in df_um.columns and key in df_cat.columns:
            df_um[key] = df_um[key].astype(str)
            df_cat[key] = df_cat[key].astype(str)

    for df_ in (df_um, df_cat):
        if 'supplier_id' in df_.columns:
            df_['supplier_id'] = df_['supplier_id'].str.lstrip('0')

    for df_ in (df_um, df_cat):
        if 'product_desc' in df_.columns:
            df_['product_desc'] = normalize_unicode_series(df_['product_desc'])

    print("\nDropping duplicates from category mapping file to ensure unique merge keys...")
    initial_cat_len = len(df_cat)
    df_cat = df_cat.drop_duplicates(subset=config.UMICH_MERGE_KEYS, keep='first')
    rows_dropped = initial_cat_len - len(df_cat)
    if rows_dropped > 0:
        print(f"  - Dropped {rows_dropped} duplicate rows from the category file.")

    report_unmatched_cat_keys(df_um, df_cat, config.UMICH_MERGE_KEYS,
                              unmatched_csv=os.path.join(config.OUTPUT_DIR,
                                                         'umich_unmatched_category_keys.csv'))

    print("\nMerging files (inner merge to keep only matched rows)...")
    df_merged = pd.merge(df_um, df_cat, on=config.UMICH_MERGE_KEYS, how='inner', validate="many_to_one")
    print(f"  - Merge complete. Resulting dataset has {len(df_merged)} rows.")

    initial_rows = len(df_merged)
    df_merged.dropna(subset=[config.CLEAN_DESC_COL, config.UT_CAT_COL], inplace=True)
    rows_dropped = initial_rows - len(df_merged)
    if rows_dropped > 0:
        print(f"  - Dropped {rows_dropped} rows due to missing descriptions or categories.")

    cat_col_lower = df_merged[config.UT_CAT_COL].astype(str).str.lower()

    print("\nConsolidating antibody categories...")
    is_antibody = cat_col_lower.str.contains("antibod", na=False)
    is_primary = cat_col_lower.str.contains("primary", na=False)
    is_secondary = cat_col_lower.str.contains("secondary", na=False)
    is_poly = cat_col_lower.str.contains("polyclonal", na=False)
    is_mono = cat_col_lower.str.contains("monoclonal", na=False)
    n_ab_before = cat_col_lower[is_antibody].nunique()
    df_merged.loc[is_antibody & is_primary & is_poly, config.UT_CAT_COL] = "polyclonal primary antibodies"
    df_merged.loc[is_antibody & is_primary & is_mono, config.UT_CAT_COL] = "monoclonal primary antibodies"
    df_merged.loc[is_antibody & is_secondary, config.UT_CAT_COL] = "secondary antibodies"
    n_ab_after = df_merged.loc[is_antibody, config.UT_CAT_COL].nunique()
    print(f"  Merged {n_ab_before} antibody subcategories -> {n_ab_after} "
          f"({is_antibody.sum()} rows: polyclonal/monoclonal primary + secondary)")

    print("\nConsolidating pipette tip subcategories...")
    is_pipette_tip = cat_col_lower.str.contains("pipette tip", na=False)
    n_tip_consolidated = is_pipette_tip.sum()
    tip_cats_merged = cat_col_lower[is_pipette_tip].nunique()
    df_merged.loc[is_pipette_tip, config.UT_CAT_COL] = "pipette tips"
    print(f"  Merged {tip_cats_merged} pipette tip subcategories ({n_tip_consolidated} rows) -> 'pipette tips'")

    print("\nConsolidating ELISA kit categories...")
    is_elisa = cat_col_lower.str.contains("elisa", na=False)
    n_elisa_before = cat_col_lower[is_elisa].nunique()
    df_merged.loc[is_elisa, config.UT_CAT_COL] = "elisa kits"
    print(f"  Merged {n_elisa_before} elisa subcategories ({is_elisa.sum()} rows) -> 'elisa kits'")

    print("\nApplying sibling consolidation from config.CATEGORY_CONSOLIDATION...")
    apply_sibling_consolidation(df_merged, config.UT_CAT_COL)

    print("\nGenerating and saving category counts...")
    category_counts = df_merged[config.UT_CAT_COL].value_counts().reset_index()
    category_counts.columns = ['category', 'count']
    counts_output_path = os.path.join(config.OUTPUT_DIR, 'umich_category_counts.csv')
    category_counts.to_csv(counts_output_path, index=False)
    print(f"  Category counts saved to: {counts_output_path}")
    print(f"  Final unique categories: {df_merged[config.UT_CAT_COL].nunique()}")

    save_nonlab_bucket_assignments(
        category_counts,
        os.path.join(config.OUTPUT_DIR, 'nonlab_bucket_assignments.csv'),
    )

    df_merged.to_parquet(config.UMICH_MERGED_CLEAN_PATH, index=False)
    print(f"\nFinal clean and merged data saved to: {config.UMICH_MERGED_CLEAN_PATH}")
    print("--- Step 0 (UMich): Complete ---")


def main_combined():
    print("--- Starting Step 0: Combined Dallas + UMich cleaning/merging ---")
    os.makedirs(config.TEMP_DIR, exist_ok=True)

    print("Loading raw data files...")
    try:
        df_ut = pd.read_csv(config.UT_DALLAS_CLEAN_CSV, low_memory=False)
        df_um = pd.read_csv(config.UMICH_CLEAN_CSV, low_memory=False)
        df_cat = pd.read_excel(config.COMBINED_CATEGORIES_XLSX,
                               keep_default_na=False, na_values=[''])
        print(f"  - Loaded {len(df_ut)} rows from UT Dallas.")
        print(f"  - Loaded {len(df_um)} rows from UMich (2010-2019).")
        print(f"  - Loaded {len(df_cat)} rows from combined category file.")
    except FileNotFoundError as e:
        print(f"Error loading data files: {e}. Check paths in config.py.")
        return

    for df_ in (df_ut, df_um, df_cat):
        if 'supplier_id' in df_.columns:
            df_['supplier_id'] = df_['supplier_id'].astype(str).str.lstrip('0')

    for df_ in (df_ut, df_um, df_cat):
        if 'product_desc' in df_.columns:
            df_['product_desc'] = normalize_unicode_series(df_['product_desc'])

    df_ut['uni'] = 'utdallas'
    df_um['uni'] = 'umich'
    if 'sku' not in df_um.columns:
        df_um['sku'] = ''

    df_all = pd.concat([df_ut, df_um], ignore_index=True)
    print(f"  - Appended raw rows: {len(df_all)} "
          f"(utdallas={(df_all['uni']=='utdallas').sum()}, "
          f"umich={(df_all['uni']=='umich').sum()})")

    print("\n--- Category Standardization Pipeline ---")

    print("  Step 3a: Normalizing unicode, lowercase, stripping whitespace...")
    if config.UT_CAT_COL in df_cat.columns:
        df_cat[config.UT_CAT_COL] = clean_category_series(df_cat[config.UT_CAT_COL])

    if 'old_category' in df_cat.columns:
        df_cat['old_category'] = clean_category_series(df_cat['old_category'])
        df_cat[config.UT_CAT_COL] = df_cat[config.UT_CAT_COL].replace('', pd.NA).fillna(df_cat['old_category'])

    n_categories_before = df_cat[config.UT_CAT_COL].nunique()
    print(f"  Unique categories after normalization: {n_categories_before}")

    print("  Step 3b: Applying known typo corrections...")
    n_typos_fixed = 0
    if config.UT_CAT_COL in df_cat.columns:
        mask = df_cat[config.UT_CAT_COL].isin(TYPO_CORRECTIONS.keys())
        n_typos_fixed = mask.sum()
        df_cat[config.UT_CAT_COL] = df_cat[config.UT_CAT_COL].replace(TYPO_CORRECTIONS)
    print(f"  Fixed {n_typos_fixed} rows with known typos ({len(TYPO_CORRECTIONS)} correction rules)")

    print("  Step 3c: Detecting and merging singular/plural category pairs...")
    if config.UT_CAT_COL in df_cat.columns:
        unique_categories = set(df_cat[config.UT_CAT_COL].dropna().unique())
        plural_map = build_plural_map(unique_categories)
        if plural_map:
            df_cat[config.UT_CAT_COL] = df_cat[config.UT_CAT_COL].replace(plural_map)
            print(f"  Merged {len(plural_map)} singular/plural pairs")
            sample_merges = list(plural_map.items())[:10]
            for singular, plural in sample_merges:
                print(f"    '{singular}' -> '{plural}'")
            if len(plural_map) > 10:
                print(f"    ... and {len(plural_map) - 10} more")
        else:
            print("  No singular/plural pairs detected.")

    n_categories_after = df_cat[config.UT_CAT_COL].nunique()
    print(f"\n  Category count: {n_categories_before} -> {n_categories_after} "
          f"(reduced by {n_categories_before - n_categories_after})")

    for key in config.COMBINED_MERGE_KEYS:
        if key in df_all.columns and key in df_cat.columns:
            df_all[key] = df_all[key].astype(str)
            df_cat[key] = df_cat[key].astype(str)

    print("\nDropping duplicates from category mapping file...")
    initial_cat_len = len(df_cat)
    df_cat = df_cat.drop_duplicates(subset=config.COMBINED_MERGE_KEYS, keep='first')
    if initial_cat_len - len(df_cat):
        print(f"  - Dropped {initial_cat_len - len(df_cat)} duplicate category rows.")

    report_unmatched_cat_keys(df_all, df_cat, config.COMBINED_MERGE_KEYS,
                              unmatched_csv=os.path.join(config.OUTPUT_DIR,
                                                         'combined_unmatched_category_keys.csv'))

    print("\nMerging files (inner merge on COMBINED_MERGE_KEYS)...")
    df_merged = pd.merge(df_all, df_cat, on=config.COMBINED_MERGE_KEYS,
                         how='inner', validate="many_to_one")
    print(f"  - Combined merged rows: {len(df_merged)} "
          f"(utdallas={(df_merged['uni']=='utdallas').sum()}, "
          f"umich={(df_merged['uni']=='umich').sum()})")

    initial_rows = len(df_merged)
    df_merged.dropna(subset=[config.CLEAN_DESC_COL, config.UT_CAT_COL], inplace=True)
    rows_dropped = initial_rows - len(df_merged)
    if rows_dropped > 0:
        print(f"  - Dropped {rows_dropped} rows due to missing descriptions or categories.")

    cat_col_lower = df_merged[config.UT_CAT_COL].astype(str).str.lower()

    print("\nConsolidating antibody categories...")
    is_antibody = cat_col_lower.str.contains("antibod", na=False)
    is_primary = cat_col_lower.str.contains("primary", na=False)
    is_secondary = cat_col_lower.str.contains("secondary", na=False)
    is_poly = cat_col_lower.str.contains("polyclonal", na=False)
    is_mono = cat_col_lower.str.contains("monoclonal", na=False)
    n_ab_before = cat_col_lower[is_antibody].nunique()
    df_merged.loc[is_antibody & is_primary & is_poly, config.UT_CAT_COL] = "polyclonal primary antibodies"
    df_merged.loc[is_antibody & is_primary & is_mono, config.UT_CAT_COL] = "monoclonal primary antibodies"
    df_merged.loc[is_antibody & is_secondary, config.UT_CAT_COL] = "secondary antibodies"
    n_ab_after = df_merged.loc[is_antibody, config.UT_CAT_COL].nunique()
    print(f"  Merged {n_ab_before} antibody subcategories -> {n_ab_after} "
          f"({is_antibody.sum()} rows: polyclonal/monoclonal primary + secondary)")

    print("\nConsolidating pipette tip subcategories...")
    is_pipette_tip = cat_col_lower.str.contains("pipette tip", na=False)
    n_tip_consolidated = is_pipette_tip.sum()
    tip_cats_merged = cat_col_lower[is_pipette_tip].nunique()
    df_merged.loc[is_pipette_tip, config.UT_CAT_COL] = "pipette tips"
    print(f"  Merged {tip_cats_merged} pipette tip subcategories ({n_tip_consolidated} rows) -> 'pipette tips'")

    print("\nConsolidating ELISA kit categories...")
    is_elisa = cat_col_lower.str.contains("elisa", na=False)
    n_elisa_before = cat_col_lower[is_elisa].nunique()
    df_merged.loc[is_elisa, config.UT_CAT_COL] = "elisa kits"
    print(f"  Merged {n_elisa_before} elisa subcategories ({is_elisa.sum()} rows) -> 'elisa kits'")

    print("\nApplying sibling consolidation from config.CATEGORY_CONSOLIDATION...")
    apply_sibling_consolidation(df_merged, config.UT_CAT_COL)

    print("\nGenerating and saving category counts...")
    category_counts = df_merged[config.UT_CAT_COL].value_counts().reset_index()
    category_counts.columns = ['category', 'count']
    counts_output_path = os.path.join(config.OUTPUT_DIR, 'combined_category_counts.csv')
    category_counts.to_csv(counts_output_path, index=False)
    print(f"  Category counts saved to: {counts_output_path}")
    print(f"  Final unique categories: {df_merged[config.UT_CAT_COL].nunique()}")
    print(f"  Row breakdown: "
          f"utdallas={(df_merged['uni']=='utdallas').sum()}, "
          f"umich={(df_merged['uni']=='umich').sum()}")

    save_nonlab_bucket_assignments(
        category_counts,
        os.path.join(config.OUTPUT_DIR, 'nonlab_bucket_assignments.csv'),
    )

    for col in df_merged.columns:
        if df_merged[col].dtype == object:
            types = df_merged[col].dropna().map(type).unique()
            if len(types) > 1:
                df_merged[col] = df_merged[col].astype(str)

    df_merged.to_parquet(config.COMBINED_MERGED_CLEAN_PATH, index=False)
    print(f"\nFinal clean and merged data saved to: {config.COMBINED_MERGED_CLEAN_PATH}")

    utd_slice = df_merged[df_merged['uni'] == 'utdallas']
    um_slice = df_merged[df_merged['uni'] == 'umich']
    utd_slice.to_parquet(config.UT_DALLAS_MERGED_CLEAN_PATH, index=False)
    um_slice.to_parquet(config.UMICH_MERGED_CLEAN_PATH, index=False)
    print(f"  - Derived utdallas parquet ({len(utd_slice)} rows): {config.UT_DALLAS_MERGED_CLEAN_PATH}")
    print(f"  - Derived umich parquet ({len(um_slice)} rows): {config.UMICH_MERGED_CLEAN_PATH}")
    print("--- Step 0 (Combined): Complete ---")


if __name__ == "__main__":
    print(f"[Variant: {config.VARIANT}]")
    main_combined()
