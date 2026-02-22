# 0_clean_category_file.py (UPDATED with Robust Category Standardization)
"""
Central script for cleaning and merging the UT Dallas data.
This script creates the single source of truth for all downstream processes
and includes logic to:
  1. Normalize unicode characters and strip special characters from categories
  2. Correct known typos/misspellings in category names
  3. Automatically consolidate plural/singular categories (handles -s, -es, -ies, irregulars)
  4. Consolidate sparse antibody categories
"""
import pandas as pd
import os
import re
import config

# ==============================================================================
# Known typo corrections (source category -> corrected category)
# Built from manual audit of combined_nochem.xlsx
# ==============================================================================
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
}

# Known irregular plural mappings (singular -> plural form to keep)
IRREGULAR_PLURALS = {
    "medium": "media",
    "matrix": "matrices",
    "criterion": "criteria",
    "index": "indices",
    "apparatus": "apparatuses",
    "analysis": "analyses",
}


def normalize_unicode(text):
    """Normalize unicode characters in category names to ASCII equivalents."""
    if not isinstance(text, str):
        return text
    # Replace unicode dashes (en-dash, em-dash, non-breaking hyphen, soft hyphen) with regular hyphen
    text = text.replace('\u2013', '-')   # en-dash
    text = text.replace('\u2014', '-')   # em-dash
    text = text.replace('\u2011', '-')   # non-breaking hyphen
    text = text.replace('\u2010', '-')   # hyphen (unicode)
    text = text.replace('\u00ad', '-')   # soft hyphen
    # Replace non-breaking space with regular space
    text = text.replace('\xa0', ' ')
    # Replace smart quotes with regular quotes
    text = text.replace('\u2018', "'").replace('\u2019', "'")
    text = text.replace('\u201c', '"').replace('\u201d', '"')
    return text


def clean_category_string(text):
    """Clean a single category string: normalize, strip, collapse whitespace."""
    if not isinstance(text, str):
        return text
    text = normalize_unicode(text)
    text = text.lower().strip()
    # Remove leading # or ## characters (stray markdown artifacts)
    text = re.sub(r'^#+\s*', '', text)
    # Collapse multiple spaces to single space
    text = re.sub(r'\s{2,}', ' ', text)
    # Strip again after all transformations
    text = text.strip()
    return text


def build_plural_map(unique_categories):
    """
    Build a comprehensive mapping from singular to plural forms.
    Handles: +s, +es, y->ies, and known irregular plurals.
    Strategy: when both forms exist, keep the PLURAL form (more items typically use it).
    """
    cat_set = set(unique_categories)
    plural_map = {}  # maps the form to REMOVE -> form to KEEP

    # 1. Simple +s plurals (e.g., "tube" -> "tubes")
    for cat in cat_set:
        if cat + 's' in cat_set:
            plural_map[cat] = cat + 's'

    # 2. +es plurals (e.g., "dish" -> "dishes", "box" -> "boxes")
    for cat in cat_set:
        if cat + 'es' in cat_set:
            # Avoid double-mapping if already caught by +s rule
            if cat not in plural_map:
                plural_map[cat] = cat + 'es'

    # 3. y -> ies plurals (e.g., "antibody" -> "antibodies", "assay" does NOT become "assaies")
    for cat in cat_set:
        if cat.endswith('y') and cat[:-1] + 'ies' in cat_set:
            plural_map[cat] = cat[:-1] + 'ies'

    # 4. Known irregular plurals
    for singular, plural in IRREGULAR_PLURALS.items():
        # Find categories containing the singular/plural word
        # Match whole words within multi-word category names
        for cat in cat_set:
            # Check if category has the singular form and the corresponding plural exists
            candidate_plural = cat.replace(singular, plural)
            if candidate_plural != cat and candidate_plural in cat_set:
                plural_map[cat] = candidate_plural

    return plural_map


def main():
    print("--- Starting Step 0: Cleaning and Merging UT Dallas Data ---")

    # 1. Create the temporary directory if it doesn't exist
    os.makedirs(config.TEMP_DIR, exist_ok=True)

    # 2. Load the raw UT Dallas data and the category mapping file
    print("Loading raw data files...")
    try:
        df_ut = pd.read_csv(config.UT_DALLAS_CLEAN_CSV, low_memory=False)
        df_cat = pd.read_excel(config.UT_DALLAS_CATEGORIES_XLSX, keep_default_na=False, na_values=[''])
        print(f"  - Loaded {len(df_ut)} rows from UT Dallas main file.")
        print(f"  - Loaded {len(df_cat)} rows from category mapping file.")
    except FileNotFoundError as e:
        print(f"Error loading data files: {e}. Make sure paths in config.py are correct.")
        return

    # =========================================================================
    # 3. CATEGORY STANDARDIZATION PIPELINE
    # =========================================================================
    print("\n--- Category Standardization Pipeline ---")

    # 3a. Basic normalization: unicode, lowercase, strip, collapse whitespace
    print("  Step 3a: Normalizing unicode, lowercase, stripping whitespace...")
    if config.UT_CAT_COL in df_cat.columns:
        df_cat[config.UT_CAT_COL] = df_cat[config.UT_CAT_COL].astype(str).apply(clean_category_string)

    if 'old_category' in df_cat.columns:
        df_cat['old_category'] = df_cat['old_category'].astype(str).apply(clean_category_string)
        df_cat[config.UT_CAT_COL] = df_cat[config.UT_CAT_COL].replace('', pd.NA).fillna(df_cat['old_category'])

    n_categories_before = df_cat[config.UT_CAT_COL].nunique()
    print(f"  Unique categories after normalization: {n_categories_before}")

    # 3b. Apply known typo corrections
    print("  Step 3b: Applying known typo corrections...")
    n_typos_fixed = 0
    if config.UT_CAT_COL in df_cat.columns:
        mask = df_cat[config.UT_CAT_COL].isin(TYPO_CORRECTIONS.keys())
        n_typos_fixed = mask.sum()
        df_cat[config.UT_CAT_COL] = df_cat[config.UT_CAT_COL].replace(TYPO_CORRECTIONS)
    print(f"  Fixed {n_typos_fixed} rows with known typos ({len(TYPO_CORRECTIONS)} correction rules)")

    # 3c. Smart plural/singular merging
    print("  Step 3c: Detecting and merging singular/plural category pairs...")
    if config.UT_CAT_COL in df_cat.columns:
        unique_categories = set(df_cat[config.UT_CAT_COL].dropna().unique())
        plural_map = build_plural_map(unique_categories)

        if plural_map:
            df_cat[config.UT_CAT_COL] = df_cat[config.UT_CAT_COL].replace(plural_map)
            print(f"  Merged {len(plural_map)} singular/plural pairs")
            # Show a sample of merges for transparency
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

    # =========================================================================
    # 4. Prepare keys for merging
    # =========================================================================
    for key in config.UT_DALLAS_MERGE_KEYS:
        if key in df_ut.columns and key in df_cat.columns:
            df_ut[key] = df_ut[key].astype(str)
            df_cat[key] = df_cat[key].astype(str)

    # 5. Perform an inner merge to keep only matched rows
    print("\nMerging files (inner merge to keep only matched rows)...")
    df_merged = pd.merge(df_ut, df_cat, on=config.UT_DALLAS_MERGE_KEYS, how='inner', validate="many_to_one")
    print(f"  - Merge complete. Resulting dataset has {len(df_merged)} rows.")

    # 6. Data Hygiene Step: Drop rows with missing crucial data
    initial_rows = len(df_merged)
    df_merged.dropna(subset=[config.CLEAN_DESC_COL, config.UT_CAT_COL], inplace=True)
    rows_dropped = initial_rows - len(df_merged)
    if rows_dropped > 0:
        print(f"  - Dropped {rows_dropped} rows due to missing descriptions or categories.")

    # --- Consolidate antibody categories ---
    print("\nConsolidating antibody categories...")
    cat_col = df_merged[config.UT_CAT_COL].astype(str).str.lower()
    is_antibody = cat_col.str.contains("antibod", na=False)
    is_primary = cat_col.str.contains("primary", na=False)
    is_secondary = cat_col.str.contains("secondary", na=False)
    n_ab_before = cat_col[is_antibody].nunique()
    df_merged.loc[is_antibody & is_primary, config.UT_CAT_COL] = "primary antibodies"
    df_merged.loc[is_antibody & is_secondary, config.UT_CAT_COL] = "secondary antibodies"
    n_ab_after = df_merged.loc[is_antibody, config.UT_CAT_COL].nunique()
    print(f"  Merged {n_ab_before} antibody subcategories -> {n_ab_after} "
          f"({is_antibody.sum()} rows: primary antibodies + secondary antibodies)")

    # --- Consolidate ELISA kit subcategories ---
    print("\nConsolidating ELISA kit subcategories...")
    cat_col = df_merged[config.UT_CAT_COL].astype(str).str.lower()
    is_elisa = cat_col.str.contains("elisa", na=False)
    n_elisa_before = cat_col[is_elisa].nunique()
    n_elisa_rows = is_elisa.sum()
    df_merged.loc[is_elisa, config.UT_CAT_COL] = "elisa kits"
    print(f"  Merged {n_elisa_before} ELISA subcategories ({n_elisa_rows} rows) -> 'elisa kits'")

    # --- Consolidate pipette tip subcategories ---
    print("\nConsolidating pipette tip subcategories...")
    cat_col = df_merged[config.UT_CAT_COL].astype(str).str.lower()
    is_pipette_tip = cat_col.str.contains("pipette tip", na=False)
    n_tip_consolidated = is_pipette_tip.sum()
    df_merged.loc[is_pipette_tip, config.UT_CAT_COL] = "pipette tips"
    tip_cats_merged = cat_col[is_pipette_tip].nunique()
    print(f"  Merged {tip_cats_merged} pipette tip subcategories ({n_tip_consolidated} rows) -> 'pipette tips'")

    # 7. Generate and save category counts for review
    print("\nGenerating and saving category counts...")
    category_counts = df_merged[config.UT_CAT_COL].value_counts().reset_index()
    category_counts.columns = ['category', 'count']
    counts_output_path = os.path.join(config.OUTPUT_DIR, 'utdallas_category_counts.csv')
    category_counts.to_csv(counts_output_path, index=False)
    print(f"  Category counts saved to: {counts_output_path}")
    print(f"  Final unique categories: {df_merged[config.UT_CAT_COL].nunique()}")

    # 8. Save the final, clean, merged file
    df_merged.to_parquet(config.UT_DALLAS_MERGED_CLEAN_PATH, index=False)
    print(f"\nFinal clean and merged data saved to: {config.UT_DALLAS_MERGED_CLEAN_PATH}")
    print("--- Step 0: Complete ---")

if __name__ == "__main__":
    main()
