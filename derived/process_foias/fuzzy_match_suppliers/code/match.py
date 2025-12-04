import pandas as pd
import re
from collections import defaultdict
from rapidfuzz import fuzz
import os
import time

# --- MAPPING DICTIONARY ---
# This dictionary handles exact overrides. Keys are the variations found in data; 
# Values are the target canonical name.
CANONICAL_MAPPING = {
    # Thermo Fisher Scientific Family
    'thermo fisher scientific': 'thermo fisher scientific',
    'fisher scientific': 'thermo fisher scientific',
    'thermo fisher': 'thermo fisher scientific',
    'thermofisher': 'thermo fisher scientific',
    'fisher science': 'thermo fisher scientific',
    'fisher sci': 'thermo fisher scientific',
    'fisher healthcare': 'thermo fisher scientific',
    'tfs fishersci': 'thermo fisher scientific',
    'tfs fisher': 'thermo fisher scientific',
    'thermo': 'thermo fisher scientific',
    'life technologies': 'life technologies',
    'life tech': 'life technologies',
    'lifetech': 'life technologies',
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

    # Zimmer
    'zimmer': 'zimmer',
    # Medtronic
    'medtronic': 'medtronic',
    # VWR / Avantor
    'vwr': 'vwr, part of avantor',
    'vwr international': 'vwr, part of avantor',
    'v w r': 'vwr, part of avantor',

    # Grainger
    'ww grainger': 'ww grainger',
    'grainger': 'ww grainger',

    # Qiagen
    'qiagen': 'qiagen',

    'jacksonimmuno': 'jackson imunoresearch lab',
    'jackson imm': 'jackson imunoresearch lab',
    'jackson immuno': 'jackson imunoresearch lab',
    'jackson immunoresearch': 'jackson imunoresearch lab',

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
    
    # Promega
    'promega': 'promega corporation',
    'promega corp': 'promega corporation',

    'thomas scientific': 'thomas scientific', 
    'thomas sci': 'thomas scientific', 
     
    # Roche
    'roche': 'roche diagnostics',
    'roche diagnostics': 'roche diagnostics',

    'usa scientific': 'usa scientific',
    'usascientific': 'usa scientific',
    
    'perkinelmer': 'perkinelmer',
    'zen bio': 'zenbio',
    '3m ': '3m',
    'amazon': 'amazon',
    'daigger': 'daigger scientific',
    'abnova': 'abnova',
    'abraxis': 'abraxis',
    'abbott': 'abbott lab',
    'abbvie': 'abbive',
    'active motif': 'active motif',

    'wilmad': 'wilmad labglass',
    'wards' : 'wards natural science', 
    'walmart': 'walmart', 
    'trinity biotech': 'trinity biotech',  
    'agrilife': 'texas agrilife research',
    'carolina biological supply': 'carolina biological supply'
}

# --- THE "BOUNCER" LIST (Updated with Countries) ---
# These are words that are SAFE to drop. 
# If a company name differs ONLY by these words, we treat them as the same.
IGNORABLE_TOKENS = {
    # Business Legal Structures
    'inc', 'corp', 'corporation', 'llc', 'ltd', 'company', 'co', 'limited',
    'group', 'holdings', 'partnership', 'associates', 'plc', 'gmbh', 'sa',
    
    # Structural Identifiers
    'division', 'branch', 'sub', 'subsidiary', 'department',
    'global', 'international', 'intl', 'systems', 'solutions',
    
    # Common connectors
    'dba', 'aka', 'doing', 'business', 'as', 'formerly', 'known',
    
    # Geographic Regions & Continents
    'north', 'south', 'east', 'west', 'northeast', 'northwest', 'southeast', 'southwest',
    'america', 'americas', 'asia', 'europe', 'africa', 'australia', 'oceania',
    'latin', 'pacific', 'atlantic',
    
    # Countries (Comprehensive List)
    'usa', 'us', 'united', 'states', 'uk', 'united', 'kingdom',
    'canada', 'mexico', 'brazil', 'argentina', 'colombia',
    'china', 'japan', 'korea', 'india', 'singapore', 'taiwan', 'thailand', 'vietnam', 'malaysia',
    'germany', 'france', 'italy', 'spain', 'netherlands', 'switzerland', 'sweden', 'norway', 'denmark', 'finland',
    'ireland', 'belgium', 'austria', 'poland', 'czech', 'hungary', 'greece', 'portugal',
    'russia', 'turkey', 'israel', 'egypt', 'saudi', 'arabia', 'uae', 'south', 'africa',
    'new', 'zealand', 'australia'
}

def normalize_name(name):
    """
    Standard Cleaning with specific word protections.
    """
    if not isinstance(name, str) or not name.strip():
        return "", ""
    
    cleaned_for_search = name.lower().strip()

    # --- Step 1: Check Canonical Mapping ---
    sorted_aliases = sorted(CANONICAL_MAPPING.keys(), key=len, reverse=True)
    for alias in sorted_aliases:
        pattern = r'\b' + re.escape(alias) + r'\b'
        if re.search(pattern, cleaned_for_search):
            return cleaned_for_search, CANONICAL_MAPPING[alias]
            
    # --- Step 2: DBA Logic ---
    cleaned = cleaned_for_search.replace('d.b.a.', 'dba').replace('d/b/a', 'dba')
    if ' dba ' in cleaned:
        parts = cleaned.split(' dba ')
        if len(parts) > 1 and parts[-1].strip():
            cleaned = parts[-1].strip()

    # --- Step 3: General Cleaning ---
    cleaned = cleaned.replace('&', ' and ')
    
    # Specific Keyword Protections
    # We standardize 'biotechnologies' -> 'biotech' because they mean the same.
    cleaned = cleaned.replace('biotechnologies', 'biotech')
    cleaned = cleaned.replace('biotechnology', 'biotech')

    # University Sledgehammer
    cleaned = cleaned.replace('university of california', 'uc')
    cleaned = cleaned.replace('uni of california', 'uc')
    cleaned = re.sub(r'\buni[a-z]*sity\b', 'uni', cleaned)
    cleaned = cleaned.replace('univ', 'uni')
    
    cleaned = cleaned.replace('united states', 'us')
    cleaned = cleaned.replace('u s ', 'us')
    
    # Lab variants
    cleaned = cleaned.replace('laboratories', 'lab')
    cleaned = cleaned.replace('labortories', 'lab')
    cleaned = cleaned.replace('labs', 'lab')
    cleaned = cleaned.replace('laboratory', 'lab')
    cleaned = cleaned.replace('technologies', 'tech')

    # Note: We are NOT removing "medical", "scientific", "supply", etc. here.
    # We want those words to survive so the grouping logic sees them.

    # Remove junk prefixes
    cleaned = re.sub(r'^((z{2,}|x{2,})[a-z0-9]*(_[a-z0-9]+)*)_', '', cleaned)
    
    # Remove standard corporate suffixes for matching
    # (We keep IGNORABLE_TOKENS separate for the subset logic check later)
    suffixes = r'\b(inc|incorporated|llc|ll|ltd|plc|ag|co|corp|corporation|company|international|gmbh|pllc|com|assoc|lp)\b'
    cleaned = re.sub(suffixes, '', cleaned)
    cleaned = re.sub(r"\bthe\b", "", cleaned)

    # Remove noise words
    cleaned = cleaned.replace("zzz", "")
    cleaned = cleaned.replace("xxxx", "")
    cleaned = cleaned.replace("xxx", "")
    cleaned = cleaned.replace("www", "")
    cleaned = cleaned.replace("inactive", "")
    cleaned = cleaned.replace("do not use", "")
    cleaned = cleaned.replace("dnu", "")

    # Remove punctuation
    cleaned = re.sub(r'[^a-z0-9\s]', '', cleaned).strip()
    cleaned = re.sub(r'\s+', ' ', cleaned)

    if cleaned in CANONICAL_MAPPING:
        return cleaned, CANONICAL_MAPPING[cleaned]

    return cleaned, cleaned

def is_safe_subset(parent, child):
    """
    Checks if 'child' is just 'parent' + ignorable noise.
    """
    # Split into sets of words
    parent_tokens = set(parent.split())
    child_tokens = set(child.split())
    
    # Find the "Extra" words in the child
    # e.g. Parent={Eppendorf}, Child={Eppendorf, North, America}
    # extra_tokens = {North, America}
    extra_tokens = child_tokens - parent_tokens
    
    # If there are no extra tokens, it's a perfect match (or parent is longer)
    if not extra_tokens:
        return True
        
    # Check if ALL extra tokens are in our IGNORABLE list
    # e.g. "North" and "America" are ignorable -> Returns True
    # e.g. "Medical" is NOT ignorable -> Returns False
    return extra_tokens.issubset(IGNORABLE_TOKENS)

def group_suppliers(supplier_list, threshold=92):
    """
    Advanced Grouping with Safe Subset Logic.
    """
    start_time = time.time()
    print("   -> Step 1/4: Normalizing all supplier names...")
    
    clean_map = {name: normalize_name(name)[1] for name in supplier_list}
    unique_names = list(set(clean_map.values()))
    
    LOCKED_NAMES = set(val.lower() for val in CANONICAL_MAPPING.values())

    # Sort by Length (Shortest First)
    unique_names.sort(key=len)
    print(f"   -> Found {len(unique_names)} unique cleaned groups to start.")

    # Blocking
    blocks = defaultdict(list)
    for name in unique_names:
        if not name: continue
        block_key = re.sub(r'[^a-z0-9]', '', name)[:3]
        blocks[block_key].append(name)

    print("   -> Step 3/4: Matching with Advanced Logic...")
    parent_map = {} 

    for block_key, block_items in blocks.items():
        while block_items:
            parent = block_items.pop(0) 
            parent_map[parent] = parent
            
            matches = []
            non_matches = []
            
            for candidate in block_items:
                is_match = False
                
                # VIP Check
                if candidate in LOCKED_NAMES and fuzz.ratio(parent, candidate) < 98:
                     is_match = False
                else:
                    # Check 1: No-Space Match
                    if parent.replace(" ", "") == candidate.replace(" ", ""):
                        is_match = True
                    
                    # Check 2: SAFE Subset Logic (THE FIX)
                    # We only allow the subset match if the extra words are "safe".
                    # e.g. "Eppendorf North America" -> Allowed
                    # e.g. "Cook Medical" -> Blocked (Medical is not in IGNORABLE_TOKENS)
                    elif is_safe_subset(parent, candidate) and fuzz.token_set_ratio(parent, candidate) == 100:
                        is_match = True
                        
                    # Check 3: Standard Fuzzy Match
                    # I bumped threshold to 92 to stop 'Genesee' matching 'Gene'
                    elif fuzz.token_sort_ratio(parent, candidate) >= threshold:
                        is_match = True

                if is_match:
                    matches.append(candidate)
                else:
                    non_matches.append(candidate)
            
            for match in matches:
                parent_map[match] = parent
            
            block_items = non_matches

    print("   -> Step 4/4: Assembling the final mapping...")
    final_result = {original: parent_map.get(cleaned, cleaned) for original, cleaned in clean_map.items()}
    print(f"   -> Grouping completed in {time.time() - start_time:.2f} seconds.")
    return final_result

def main():
    # Define file paths
    csv_file_path = '../external/samp/govspend_panel.csv'
    supplier_name_column = 'suppliername'
    output_csv_path = '../output/supplier_mapping_final.csv'

    try:
        print(f"Reading '{csv_file_path}'...")
        df = pd.read_csv(csv_file_path, low_memory=False, dtype=str)
        
        # Normalize column headers to lower case for consistency
        df.columns = [col.strip().lower() for col in df.columns]

        if supplier_name_column not in df.columns:
            raise KeyError(f"Column '{supplier_name_column}' not found.")
        
        # Extract unique names
        supplier_names = df[supplier_name_column].dropna().unique().tolist()
        print(f"Found {len(supplier_names)} unique supplier names to process.")
        del df # Free up memory

        # Run the grouping process
        print("\nStarting the grouping process...")
        group_map = group_suppliers(supplier_names, threshold=90)

        # Save results
        print("\nCreating the final mapping file...")
        final_df = pd.DataFrame(list(group_map.items()), columns=['original_suppliername', 'canonical_supplier'])
        
        output_dir = os.path.dirname(output_csv_path)
        if output_dir and not os.path.exists(output_dir):
            os.makedirs(output_dir)

        final_df.to_csv(output_csv_path, index=False)
        print(f"\n✅ All done! The final file is saved at: {output_csv_path}")

    except FileNotFoundError:
        print(f"\n[ERROR] The file was not found at '{csv_file_path}'.")
    except KeyError as e:
        print(f"\n[ERROR] {e}")
    except Exception as e:
        print(f"\n[ERROR] An unexpected error occurred: {e}")

if __name__ == "__main__":
    main()