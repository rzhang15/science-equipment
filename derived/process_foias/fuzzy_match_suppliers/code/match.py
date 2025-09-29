import pandas as pd
import re
from collections import defaultdict
from rapidfuzz import fuzz
import os
import time

# --- MAPPING DICTIONARY (Values are now all lowercase) ---
CANONICAL_MAPPING = {
    # Thermo Fisher Scientific Family
    'thermo fisher scientific': 'thermo fisher scientific',
    'fisher scientific': 'thermo fisher scientific',
    'thermo fisher': 'thermo fisher scientific',
    'thermofisher': 'thermo fisher scientific',
    'thermo': 'thermo fisher scientific',
    'life technologies': 'life technologies',
    'invitrogen': 'life technologies',
    'applied biosystems': 'life technologies',
    'gibco': 'life technologies',

    # MilliporeSigma / Merck KGaA Family
    'milliporesigma': 'milliporesigma',
    'millipore sigma': 'milliporesigma',
    'merck millipore': 'milliporesigma',
    'sigma aldrich': 'milliporesigma',
    'sigma-aldrich': 'milliporesigma',
    'sigmaaldrich': 'milliporesigma',
    'sigma chemical': 'milliporesigma',
    'millipore': 'milliporesigma',
    'supelco': 'milliporesigma',

    # VWR / Avantor
    'vwr': 'vwr, part of avantor',
    'vwr international': 'vwr, part of avantor',

    # Grainger
    'ww grainger': 'ww grainger',
    'grainger': 'ww grainger',

    # Qiagen
    'qiagen': 'qiagen',

    # Bio-Rad
    'bio rad laboratories': 'bio-rad laboratories',
    'bio rad': 'bio-rad laboratories',
    'biorad': 'bio-rad laboratories',

    # New England Biolabs
    'new england biolabs': 'new england biolabs',
    'neb': 'new england biolabs',

    # Beckman Coulter / Danaher
    'beckman coulter': 'beckman coulter',

    # Becton, Dickinson and Company
    'bd': 'bd (becton, dickinson and company)',
    'becton dickinson': 'bd (becton, dickinson and company)',

    # Corning
    'corning': 'corning',

    # Agilent
    'agilent': 'agilent technologies',
    'agilent technologies': 'agilent technologies',

    # PerkinElmer
    'perkinelmer': 'perkinelmer',
    
    # Promega
    'promega': 'promega corporation',
    'promega corp': 'promega corporation',
    
    # Roche
    'roche': 'roche diagnostics',
    'roche diagnostics': 'roche diagnostics'
}

# --- HELPER FUNCTIONS (Improved with whole-word matching) ---
def normalize_name(name):
    """
    Normalizes a supplier name for better matching.
    """
    if not isinstance(name, str):
        return "", ""
    
    cleaned = name.lower().replace('&', ' and ')
    
    if cleaned in CANONICAL_MAPPING:
        return cleaned, CANONICAL_MAPPING[cleaned]
    
    suffixes = r'\b(inc|llc|ltd|co|corp|corporation|company|international|technologies|laboratories|scientific|gmbh|solutions|diagnostics|chemical|usa)\b'
    cleaned = re.sub(suffixes, '', cleaned)
    cleaned = re.sub(r'[^a-z0-9\s]', '', cleaned).strip()
    cleaned = re.sub(r'\s+', ' ', cleaned)
    
    # --- MODIFIED SECTION: Use whole-word matching ---
    # This is more precise and prevents incorrect substring matches.
    for alias, canonical in CANONICAL_MAPPING.items():
        # The \b characters are "word boundaries". This ensures that we match
        # 'thermo' as a whole word, not as part of 'thermometrics'.
        pattern = r'\b' + re.escape(alias) + r'\b'
        if re.search(pattern, cleaned):
            return cleaned, canonical
            
    return cleaned, cleaned

def group_suppliers(supplier_list, threshold=90):
    """
    Groups similar supplier names using normalization, blocking, and fuzzy matching.
    """
    start_time = time.time()
    print("   -> Step 1/4: Normalizing all supplier names...")
    reps = {name: normalize_name(name)[1] for name in supplier_list}
    unique_canonicals = sorted(list(set(reps.values())))
    print(f"   -> Found {len(unique_canonicals)} unique groups to start.")

    print("   -> Step 2/4: Creating blocks for faster matching...")
    blocks = defaultdict(list)
    for name in unique_canonicals:
        if name and name.split():
            blocks[name.split()[0]].append(name)

    print("   -> Step 3/4: Fuzzy matching suppliers within blocks...")
    final_map = {}
    for block_key, block_items in blocks.items():
        while len(block_items) > 0:
            rep = block_items.pop(0)
            final_map[rep] = rep
            matches = [item for item in block_items if fuzz.token_sort_ratio(rep, item) >= threshold]
            for match in matches:
                final_map[match] = rep
            block_items = [item for item in block_items if item not in matches]

    print("   -> Step 4/4: Assembling the final mapping...")
    final_result = {original: final_map.get(canonical, canonical) for original, canonical in reps.items()}
    print(f"   -> Grouping completed in {time.time() - start_time:.2f} seconds.")
    return final_result

# --- MAIN EXECUTION LOGIC (No changes needed here) ---
def main():
    csv_file_path = '../external/samp/govspend_panel.csv'
    supplier_name_column = 'suppliername'
    output_csv_path = '../output/supplier_mapping_final.csv'

    try:
        print(f"Reading '{csv_file_path}' to find column '{supplier_name_column}'...")
        df = pd.read_csv(csv_file_path, low_memory=False, dtype=str)
        original_columns = df.columns.tolist()
        print(f"   -> Columns found in file: {original_columns}")
        
        df.columns = [col.strip().lower() for col in df.columns]
        normalized_columns = df.columns.tolist()

        if supplier_name_column not in normalized_columns:
            raise KeyError(f"Column '{supplier_name_column}' not found even after cleaning headers.")
        
        print("   -> File read and column confirmed successfully!")
        supplier_names = df[supplier_name_column].dropna().unique().tolist()
        print(f"Found {len(supplier_names)} unique supplier names to process.")
        del df

        print("\nStarting the grouping process...")
        group_map = group_suppliers(supplier_names, threshold=90)

        print("\nCreating the final mapping file...")
        final_df = pd.DataFrame(list(group_map.items()), columns=['original_suppliername', 'canonical_supplier'])
        
        output_dir = os.path.dirname(output_csv_path)
        if output_dir and not os.path.exists(output_dir):
            os.makedirs(output_dir)

        final_df.to_csv(output_csv_path, index=False)
        print(f"   -> Saving complete!")
        print(f"\n✅ All done! The final file is saved at: {output_csv_path}")

    except FileNotFoundError:
        print(f"\n[ERROR] The file was not found at '{csv_file_path}'.")
    except KeyError as e:
        print(f"\n[ERROR] {e}")
        print(f"   -> Please check that a column similar to '{supplier_name_column}' exists in your CSV file.")
        print(f"   -> The script found these columns: {original_columns}")
    except Exception as e:
        print(f"\n[ERROR] An unexpected error occurred: {e}")

if __name__ == "__main__":
    main()