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
    'alfa aesar': 'thermo fisher scientific',
    'alfa aesar thermo fisher': 'thermo fisher scientific',

    # Life Technologies (Thermo Fisher subsidiary, kept separate)
    'life technologies': 'life technologies',
    'life technology': 'life technologies',
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
    'aldrich chemical': 'milliporesigma',
    'millipore': 'milliporesigma',
    'supelco': 'milliporesigma',
    'emd millipore': 'milliporesigma',

    # GE Healthcare / Cytiva
    'ge health': 'ge healthcare',
    'ge healthcare': 'ge healthcare',
    'general electric healthcare': 'ge healthcare',

    # Zimmer Biomet
    'zimmer': 'zimmer biomet',
    'zimmer biomet': 'zimmer biomet',

    # Medtronic
    'medtronic': 'medtronic',
    'medtronic advanced energy': 'medtronic',
    'medtronic cardiac surgery': 'medtronic',
    'medtronic cardio vascular': 'medtronic',
    'medtronic crm': 'medtronic',
    'medtronic cryocath': 'medtronic',
    'medtronic ent': 'medtronic',

    # VWR / Avantor
    'vwr': 'vwr',
    'vwr international': 'vwr',
    'v w r': 'vwr',
    'avantor': 'vwr',

    # Grainger
    'ww grainger': 'ww grainger',
    'w w grainger': 'ww grainger',
    'w.w. grainger': 'ww grainger',
    'grainger': 'ww grainger',
    'grainger industrial supply': 'ww grainger',
    'grainger industrial supplies': 'ww grainger',
    'grainger inc': 'ww grainger',
    'grainger incorporated': 'ww grainger',
    'grainger direct connect': 'ww grainger',
    'lab safety supply': 'ww grainger',

    # Qiagen
    'qiagen': 'qiagen',

    # Jackson ImmunoResearch
    'jacksonimmuno': 'jackson immunoresearch lab',
    'jackson imm': 'jackson immunoresearch lab',
    'jackson immuno': 'jackson immunoresearch lab',
    'jackson immunoresearch': 'jackson immunoresearch lab',

    # Bio-Rad
    'bio rad laboratories': 'bio-rad laboratories',
    'bio rad': 'bio-rad laboratories',
    'biorad': 'bio-rad laboratories',
    'bio rad labs': 'bio-rad laboratories',
    'bio rad lab': 'bio-rad laboratories',
    'bio rad labratories': 'bio-rad laboratories',
    'bio rad abd serotec': 'bio-rad laboratories',
    'bio rad life science': 'bio-rad laboratories',

    # New England Biolabs
    'new england biolabs': 'new england biolabs',
    'neb': 'new england biolabs',

    # Beckman Coulter / Danaher
    'beckman coulter': 'beckman coulter',
    'beckman coulter genomics': 'beckman coulter',
    'beckman coulter bioresearch': 'beckman coulter',

    # Becton, Dickinson and Company
    'bd biosciences': 'bd biosciences',
    'bd biosci': 'bd biosciences',
    'bd biosci clontech': 'bd biosciences',
    'bd biosciences clontech': 'bd biosciences',
    'bd biosciences pharmingen': 'bd biosciences',
    'bd bioscience becton dickinson': 'bd biosciences',
    'becton dickinson': 'bd biosciences',
    'becton': 'bd biosciences',

    # Corning
    'corning': 'corning',

    # Agilent
    'agilent': 'agilent technologies',
    'agilent technologies': 'agilent technologies',

    # Promega
    'promega': 'promega corporation',
    'promega corp': 'promega corporation',

    # Thomas Scientific
    'thomas scientific': 'thomas scientific',
    'thomas sci': 'thomas scientific',

    # Roche
    'roche': 'roche diagnostics',
    'roche diagnostics': 'roche diagnostics',

    # USA Scientific
    'usa scientific': 'usa scientific',
    'usascientific': 'usa scientific',

    # ATCC
    'atcc': 'atcc',
    'amer type culture collec': 'atcc',
    'american type culture collec': 'atcc',
    'amer type culture collection': 'atcc',
    'american type culture collection': 'atcc',

    # PerkinElmer
    'perkinelmer': 'perkinelmer',
    'perkin elmer': 'perkinelmer',
    'perkin-elmer': 'perkinelmer',
    'perkins elmer': 'perkinelmer',
    'perkinelmer las': 'perkinelmer',
    'perkinelmer health sciences': 'perkinelmer',
    'perkinelmer health sci': 'perkinelmer',
    'perkinelmer life and analytical sciences': 'perkinelmer',
    'perkin elmer life and analytical sci': 'perkinelmer',
    'perkin elmer health sciences': 'perkinelmer',
    'perkin elmer life sciences': 'perkinelmer',

    # Carl Zeiss
    'carl zeiss': 'carl zeiss',
    'zeiss': 'carl zeiss',
    'carl zeiss microscopy': 'carl zeiss',
    'carl zeiss microimaging': 'carl zeiss',
    'carl zeiss meditec': 'carl zeiss',

    # Bruker
    'bruker': 'bruker',
    'bruker axs': 'bruker',
    'bruker biospin': 'bruker',
    'bruker bio spin': 'bruker',
    'bruker daltonics': 'bruker',
    'bruker daltronics': 'bruker',
    'bruker optics': 'bruker',
    'bruker nano': 'bruker',
    'bruker scientific': 'bruker',

    # Illumina
    'illumina': 'illumina',

    # Siemens
    'siemens': 'siemens',
    'siemens industry': 'siemens',
    'siemens medical solutions': 'siemens',
    'siemens healthcare': 'siemens',
    'siemens building technologies': 'siemens',
    'siemens building tech': 'siemens',

    # Cardinal Health
    'cardinal health': 'cardinal health',
    'cardinal distribution': 'cardinal health',

    # McKesson
    'mckesson': 'mckesson',

    # Medline Industries
    'medline': 'medline industries',
    'medline industries': 'medline industries',
    'medline ind': 'medline industries',

    # Henry Schein
    'henry schein': 'henry schein',
    'schein': 'henry schein',
    'butler schein': 'henry schein',
    'butler schein animal health': 'henry schein',

    # Boston Scientific
    'boston scientific': 'boston scientific',

    # Baxter
    'baxter': 'baxter healthcare',
    'baxter healthcare': 'baxter healthcare',

    # Eppendorf
    'eppendorf': 'eppendorf',
    'eppendorf north america': 'eppendorf',
    'eppendorf north amer': 'eppendorf',
    'eppendorf scientific': 'eppendorf',

    # CDW
    'cdw': 'cdw government',
    'cdw government': 'cdw government',
    'cdw govt': 'cdw government',
    'cdw direct': 'cdw government',
    'cdw g': 'cdw government',
    'cdw-g': 'cdw government',
    'cdw-g government': 'cdw government',
    'cdw-government': 'cdw government',

    # Hewlett-Packard
    'hewlett packard': 'hewlett packard',
    'hewlett-packard': 'hewlett packard',
    'hewlett packard company': 'hewlett packard',
    'hewlett packard corp': 'hewlett packard',
    'hewlett packard enterprise': 'hewlett packard',

    # McKesson / MCMaster-Carr
    'mcmaster carr': 'mcmaster-carr supply',
    'mcmaster-carr': 'mcmaster-carr supply',
    'mcmaster-carr supply': 'mcmaster-carr supply',
    'mcmaster carr supply': 'mcmaster-carr supply',
    'mc master': 'mcmaster-carr supply',

    # Amazon
    'amazon': 'amazon',
    'amazon business': 'amazon',
    'amazon capital services': 'amazon',
    'amazon com': 'amazon',
    'amazon com llc': 'amazon',
    'amazon dot com': 'amazon',
    'amazon.com': 'amazon',
    'amazon services': 'amazon',
    'amazon web services': 'amazon web services',

    # Carolina Biological
    'carolina biological supply': 'carolina biological supply',
    'carolina biological': 'carolina biological supply',
    'carolina bio supply': 'carolina biological supply',
    'carolina bio': 'carolina biological supply',
    'carolina biologic supply': 'carolina biological supply',

    # Ward's Natural Science
    'wards': 'wards natural science',
    'wards natural science': 'wards natural science',
    'wards natural science est': 'wards natural science',
    'wards natural science establishment': 'wards natural science',

    # Flinn Scientific
    'flinn scientific': 'flinn scientific',

    # Misc
    'zen bio': 'zenbio',
    '3m': '3m',
    'daigger': 'daigger scientific',
    'abnova': 'abnova',
    'abraxis': 'abraxis',
    'abbott': 'abbott lab',
    'abbott laboratories': 'abbott lab',
    'abbott labs': 'abbott lab',
    'abbott lab': 'abbott lab',
    'abbvie': 'abbvie',
    'active motif': 'active motif',
    'wilmad': 'wilmad labglass',
    'walmart': 'walmart',
    'trinity biotech': 'trinity biotech',
    'agrilife': 'texas agrilife research',
}

# --- THE "BOUNCER" LIST ---
# These are words that are SAFE to drop.
# If a company name differs ONLY by these words, we treat them as the same.
IGNORABLE_TOKENS = {
    # Business Legal Structures
    'inc', 'corp', 'corporation', 'llc', 'ltd', 'company', 'co', 'limited',
    'group', 'holdings', 'partnership', 'associates', 'plc', 'gmbh', 'sa',
    'lp', 'pllc', 'ag',

    # Structural Identifiers
    'division', 'div', 'branch', 'sub', 'subsidiary', 'department', 'dept',
    'global', 'international', 'intl', 'systems', 'solutions',
    'enterprises', 'enterprise',

    # Common connectors
    'dba', 'aka', 'doing', 'business', 'as', 'formerly', 'known',

    # Geographic Regions & Continents
    'north', 'south', 'east', 'west', 'northeast', 'northwest', 'southeast', 'southwest',
    'america', 'americas', 'asia', 'europe', 'africa', 'australia', 'oceania',
    'latin', 'pacific', 'atlantic',

    # Countries
    'usa', 'us', 'united', 'states', 'uk', 'kingdom',
    'canada', 'mexico', 'brazil', 'argentina', 'colombia',
    'china', 'japan', 'korea', 'india', 'singapore', 'taiwan', 'thailand', 'vietnam', 'malaysia',
    'germany', 'france', 'italy', 'spain', 'netherlands', 'switzerland', 'sweden', 'norway', 'denmark', 'finland',
    'ireland', 'belgium', 'austria', 'poland', 'czech', 'hungary', 'greece', 'portugal',
    'russia', 'turkey', 'israel', 'egypt', 'saudi', 'arabia', 'uae',
    'new', 'zealand',

    # Common noise suffixes found in data
    'sales', 'direct',
}

# --- PRE-COMPUTED LOOKUP STRUCTURES (computed once at import time) ---
# Sort aliases longest-first so "thermo fisher scientific" matches before "thermo"
_SORTED_ALIASES = sorted(CANONICAL_MAPPING.keys(), key=len, reverse=True)
# Pre-compile a regex for each alias
_ALIAS_PATTERNS = [(alias, re.compile(r'\b' + re.escape(alias) + r'\b')) for alias in _SORTED_ALIASES]
# Set of locked canonical names for VIP protection
_LOCKED_NAMES = frozenset(val.lower() for val in CANONICAL_MAPPING.values())

# Pre-compile regex patterns used in normalize_name
_RE_UNIVERSITY = re.compile(r'\buni[a-z]*sity\b')
_RE_JUNK_PREFIX = re.compile(r'^((z{2,}|x{2,})[a-z0-9]*(_[a-z0-9]+)*)[\s_]')
_RE_SUFFIXES = re.compile(r'\b(inc|incorporated|llc|ll|ltd|plc|ag|co|corp|corporation|company|international|gmbh|pllc|com|assoc|lp)\b')
_RE_THE = re.compile(r'\bthe\b')
_RE_NONALNUM = re.compile(r'[^a-z0-9\s]')
_RE_MULTISPACE = re.compile(r'\s+')
# Strip parenthetical annotations: (inactive), (see XXXXX), vendor IDs, phone numbers
_RE_PARENS = re.compile(r'\([^)]*\)')
# Strip "see XXXXX" / "use XXXXX" redirect notes
_RE_SEE_USE = re.compile(r'\b(see|use)\s+(vendor\s+)?[#v]?\d+\b')
# Strip leading quotes (CSV artifact)
_RE_LEADING_QUOTE = re.compile(r'^["\']+')
# Strip trailing account/vendor numbers
_RE_TRAILING_ACCT = re.compile(r'\s*(acct|account|vendor|vend)?[#]?\s*\d{4,}\s*$')
# FKA / formerly known as
_RE_FKA = re.compile(r'\b(fka|f/k/a|formerly\s+known\s+as|formerly)\s+.*$')


def normalize_name(name):
    """
    Standard Cleaning with specific word protections.
    """
    if not isinstance(name, str) or not name.strip():
        return "", ""

    cleaned_for_search = name.lower().strip()

    # --- Step 0: Strip CSV artifacts and obvious junk ---
    cleaned_for_search = _RE_LEADING_QUOTE.sub('', cleaned_for_search).strip()

    # --- Step 1: Check Canonical Mapping (uses pre-sorted, pre-compiled patterns) ---
    for alias, pattern in _ALIAS_PATTERNS:
        if pattern.search(cleaned_for_search):
            return cleaned_for_search, CANONICAL_MAPPING[alias]

    # --- Step 2: DBA Logic ---
    cleaned = cleaned_for_search.replace('d.b.a.', 'dba').replace('d/b/a', 'dba')
    if ' dba ' in cleaned:
        parts = cleaned.split(' dba ')
        if len(parts) > 1 and parts[-1].strip():
            cleaned = parts[-1].strip()

    # --- Step 2b: FKA / formerly logic (keep the current name, drop old) ---
    cleaned = _RE_FKA.sub('', cleaned)

    # --- Step 3: General Cleaning ---
    cleaned = cleaned.replace('&', ' and ')

    # Strip parenthetical annotations: (inactive), (see 49183), etc.
    cleaned = _RE_PARENS.sub('', cleaned)

    # Strip "see #12345" / "use vendor #456" redirects
    cleaned = _RE_SEE_USE.sub('', cleaned)

    # Strip trailing account/vendor numbers
    cleaned = _RE_TRAILING_ACCT.sub('', cleaned)

    # Specific Keyword Protections
    cleaned = cleaned.replace('biotechnologies', 'biotech')
    cleaned = cleaned.replace('biotechnology', 'biotech')

    # University Sledgehammer
    cleaned = cleaned.replace('university of california', 'uc')
    cleaned = cleaned.replace('uni of california', 'uc')
    cleaned = _RE_UNIVERSITY.sub('uni', cleaned)
    cleaned = cleaned.replace('univ', 'uni')

    cleaned = cleaned.replace('united states', 'us')
    cleaned = cleaned.replace('u s ', 'us')

    # Lab variants (order matters: longest first to avoid partial replacements)
    cleaned = cleaned.replace('laboratories', 'lab')
    cleaned = cleaned.replace('labortories', 'lab')
    cleaned = cleaned.replace('laboratory', 'lab')
    cleaned = cleaned.replace('labs', 'lab')
    cleaned = cleaned.replace('technologies', 'tech')

    # Supply variants
    cleaned = cleaned.replace('supplies', 'supply')

    # Services/service normalization
    cleaned = cleaned.replace('services', 'service')

    # Remove junk prefixes (zz_dnu_, zzz_dnu_, xx_)
    cleaned = _RE_JUNK_PREFIX.sub('', cleaned)

    # Remove standard corporate suffixes for matching
    cleaned = _RE_SUFFIXES.sub('', cleaned)
    cleaned = _RE_THE.sub('', cleaned)

    # Remove noise words
    cleaned = cleaned.replace("zzz", "")
    cleaned = cleaned.replace("xxxx", "")
    cleaned = cleaned.replace("xxx", "")
    cleaned = cleaned.replace("www", "")
    cleaned = cleaned.replace("inactive", "")
    cleaned = cleaned.replace("do not use", "")
    cleaned = cleaned.replace("blocked vendor", "")
    cleaned = cleaned.replace("dnu", "")

    # Remove punctuation
    cleaned = _RE_NONALNUM.sub('', cleaned).strip()
    cleaned = _RE_MULTISPACE.sub(' ', cleaned)

    if cleaned in CANONICAL_MAPPING:
        return cleaned, CANONICAL_MAPPING[cleaned]

    return cleaned, cleaned

def is_safe_subset(shorter, longer):
    """
    Checks if two names differ only by ignorable tokens.
    Both directions are checked: extra tokens in either name must all be ignorable.
    """
    shorter_tokens = set(shorter.split())
    longer_tokens = set(longer.split())

    # Tokens in longer but not shorter
    extra_in_longer = longer_tokens - shorter_tokens
    # Tokens in shorter but not longer (handles cases where parent has words child doesn't)
    extra_in_shorter = shorter_tokens - longer_tokens

    # Both sets of extra tokens must be ignorable (or empty)
    return extra_in_longer.issubset(IGNORABLE_TOKENS) and extra_in_shorter.issubset(IGNORABLE_TOKENS)

def group_suppliers(supplier_list, threshold=92):
    """
    Advanced Grouping with Safe Subset Logic and multi-key blocking.
    """
    start_time = time.time()
    print("   -> Step 1/4: Normalizing all supplier names...")

    clean_map = {name: normalize_name(name)[1] for name in supplier_list}
    unique_names = list(set(clean_map.values()))

    # Sort by Length (Shortest First) — shorter names become parents
    unique_names.sort(key=len)
    print(f"   -> Found {len(unique_names)} unique cleaned groups to start.")

    # --- Blocking: assign each name to multiple block keys ---
    # Use both the first 3 chars WITH spaces and WITHOUT spaces.
    # This catches "bio rad" (key "bio") grouping with "biorad" (key "bio").
    # Also add a no-space full prefix key for very short names (<=4 chars).
    print("   -> Step 2/4: Building blocks...")
    blocks = defaultdict(set)
    name_to_keys = defaultdict(set)
    for name in unique_names:
        if not name:
            continue
        stripped = re.sub(r'[^a-z0-9]', '', name)
        key1 = stripped[:3]  # no-space prefix
        key2 = name[:3]     # with-space prefix (may differ: "bio rad"->"bio", "biorad"->"bio")
        keys = {key1, key2}
        if len(stripped) <= 4:
            keys.add(stripped)  # short names get their own block too
        for k in keys:
            blocks[k].add(name)
            name_to_keys[name].add(k)

    # Deduplicate: each name may appear in multiple blocks,
    # so we track globally which names are already assigned a parent.
    print(f"   -> Step 3/4: Matching with Advanced Logic ({len(blocks)} blocks)...")
    parent_map = {}
    total_names = len(unique_names)
    processed = 0
    last_pct = -1

    # Process names shortest-first globally (not per-block) for deterministic parent assignment
    for name in unique_names:
        if not name or name in parent_map:
            continue

        # This name becomes a parent (it's the shortest unmatched in its group)
        parent_map[name] = name
        processed += 1

        # Progress reporting every 10%
        pct = (processed * 100) // total_names
        if pct >= last_pct + 10:
            last_pct = pct
            print(f"      {pct}% done ({processed}/{total_names} names assigned)...")

        # Gather all candidates from this name's blocks that aren't yet assigned
        candidates = set()
        for k in name_to_keys[name]:
            candidates.update(blocks[k])
        candidates.discard(name)
        # Remove already-assigned names
        candidates = {c for c in candidates if c not in parent_map}

        for candidate in candidates:
            is_match = False

            # VIP Check: don't merge distinct canonical names unless near-exact
            if candidate in _LOCKED_NAMES and fuzz.ratio(name, candidate) < 98:
                is_match = False
            else:
                # Check 1: No-Space Match ("bio rad" == "biorad")
                if name.replace(" ", "") == candidate.replace(" ", ""):
                    is_match = True

                # Check 2: Safe Subset Logic
                # Only merge if extra tokens in EITHER direction are all ignorable
                elif is_safe_subset(name, candidate) and fuzz.token_set_ratio(name, candidate) == 100:
                    is_match = True

                # Check 3: Standard Fuzzy Match
                elif fuzz.token_sort_ratio(name, candidate) >= threshold:
                    is_match = True

            if is_match:
                parent_map[candidate] = name

    print("   -> Step 4/4: Assembling the final mapping...")
    final_result = {original: parent_map.get(cleaned, cleaned) for original, cleaned in clean_map.items()}
    elapsed = time.time() - start_time
    unique_groups = len(set(parent_map.values()))
    print(f"   -> Grouping completed in {elapsed:.2f}s: {total_names} names -> {unique_groups} groups")
    return final_result

def main():
    # Define file paths
    dta_file_path = '../external/samp/first_stage_data_tfidf.dta'
    supplier_name_column = 'suppliername'
    output_csv_path = '../output/supplier_mapping_final.csv'

    try:
        print(f"Reading '{dta_file_path}'...")
        df = pd.read_stata(dta_file_path)

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
        group_map = group_suppliers(supplier_names, threshold=92)

        # Save results
        print("\nCreating the final mapping file...")
        final_df = pd.DataFrame(list(group_map.items()), columns=['original_suppliername', 'canonical_supplier'])

        output_dir = os.path.dirname(output_csv_path)
        if output_dir and not os.path.exists(output_dir):
            os.makedirs(output_dir)

        final_df.to_csv(output_csv_path, index=False)
        print(f"\nAll done! The final file is saved at: {output_csv_path}")

    except FileNotFoundError:
        print(f"\n[ERROR] The file was not found at '{dta_file_path}'.")
    except KeyError as e:
        print(f"\n[ERROR] {e}")
    except Exception as e:
        print(f"\n[ERROR] An unexpected error occurred: {e}")

if __name__ == "__main__":
    main()
