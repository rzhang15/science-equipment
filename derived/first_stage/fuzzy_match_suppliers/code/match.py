import pandas as pd
import re
from collections import defaultdict
from rapidfuzz import fuzz
import os
import time

CANONICAL_MAPPING = {
    'thermo fisher scientific': 'thermo fisher scientific',
    'fisher scientific': 'thermo fisher scientific',
    'thermo fisher': 'thermo fisher scientific',
    'thermofisher': 'thermo fisher scientific',
    'fisher science': 'thermo fisher scientific',
    'fisher scntfcpossible': 'thermo fisher scientific',
    'fisher scntfcpossible mssnethanol only': 'thermo fisher scientific',
    'fisher sci': 'thermo fisher scientific',
    'fisher healthcare': 'thermo fisher scientific',
    'tfs fishersci': 'thermo fisher scientific',
    'tfs fisher': 'thermo fisher scientific',
    'thermo': 'thermo fisher scientific',
    'alfa aesar': 'thermo fisher scientific',
    'alfa aesar thermo fisher': 'thermo fisher scientific',

    'life technologies': 'life technologies',
    'life technology': 'life technologies',
    'life tech': 'life technologies',
    'lifetech': 'life technologies',
    'invitrogen': 'life technologies',
    'applied biosystems': 'life technologies',
    'gibco': 'life technologies',

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

    'ge health': 'ge healthcare',
    'ge healthcare': 'ge healthcare',
    'general electric healthcare': 'ge healthcare',

    'zimmer': 'zimmer biomet',
    'zimmer biomet': 'zimmer biomet',

    'medtronic': 'medtronic',
    'medtronic advanced energy': 'medtronic',
    'medtronic cardiac surgery': 'medtronic',
    'medtronic cardio vascular': 'medtronic',
    'medtronic crm': 'medtronic',
    'medtronic cryocath': 'medtronic',
    'medtronic ent': 'medtronic',

    'vwr': 'vwr',
    'vwr international': 'vwr',
    'v w r': 'vwr',
    'avantor': 'vwr',

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

    'qiagen': 'qiagen',

    'jacksonimmuno': 'jackson immunoresearch lab',
    'jackson imm': 'jackson immunoresearch lab',
    'jackson immuno': 'jackson immunoresearch lab',
    'jackson immunoresearch': 'jackson immunoresearch lab',

    'bio rad laboratories': 'bio-rad laboratories',
    'bio rad': 'bio-rad laboratories',
    'biorad': 'bio-rad laboratories',
    'bio rad labs': 'bio-rad laboratories',
    'bio rad lab': 'bio-rad laboratories',
    'bio rad labratories': 'bio-rad laboratories',
    'bio rad abd serotec': 'bio-rad laboratories',
    'bio rad life science': 'bio-rad laboratories',
    'biorad lab': 'bio-rad laboratories',
    'biorad lab life science': 'bio-rad laboratories',
    'biorad lab customer service': 'bio-rad laboratories',
    'biorad lab sano': 'bio-rad laboratories',
    'biorad abd serotec': 'bio-rad laboratories',
    'bioraduse biorad lab': 'bio-rad laboratories',
    'biorad laboratories': 'bio-rad laboratories',

    'new england biolabs': 'new england biolabs',
    'neb': 'new england biolabs',

    'beckman coulter': 'beckman coulter',
    'beckman coulter genomics': 'beckman coulter',
    'beckman coulter bioresearch': 'beckman coulter',

    'bd biosciences': 'bd biosciences',
    'bd biosci': 'bd biosciences',
    'bd biosci clontech': 'bd biosciences',
    'bd biosciences clontech': 'bd biosciences',
    'bd biosciences pharmingen': 'bd biosciences',
    'bd bioscience becton dickinson': 'bd biosciences',
    'becton dickinson': 'bd biosciences',
    'becton': 'bd biosciences',

    'corning': 'corning',

    'agilent': 'agilent technologies',
    'agilent technologies': 'agilent technologies',

    'promega': 'promega corporation',
    'promega corp': 'promega corporation',

    'thomas scientific': 'thomas scientific',
    'thomas sci': 'thomas scientific',

    'roche': 'roche diagnostics',
    'roche diagnostics': 'roche diagnostics',

    'usa scientific': 'usa scientific',
    'usascientific': 'usa scientific',

    'atcc': 'atcc',
    'amer type culture collec': 'atcc',
    'american type culture collec': 'atcc',
    'amer type culture collection': 'atcc',
    'american type culture collection': 'atcc',

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

    'carl zeiss': 'carl zeiss',
    'zeiss': 'carl zeiss',
    'carl zeiss microscopy': 'carl zeiss',
    'carl zeiss microimaging': 'carl zeiss',
    'carl zeiss meditec': 'carl zeiss',

    'bruker': 'bruker',
    'bruker axs': 'bruker',
    'bruker biospin': 'bruker',
    'bruker bio spin': 'bruker',
    'bruker daltonics': 'bruker',
    'bruker daltronics': 'bruker',
    'bruker optics': 'bruker',
    'bruker nano': 'bruker',
    'bruker scientific': 'bruker',

    'illumina': 'illumina',

    'siemens': 'siemens',
    'siemens industry': 'siemens',
    'siemens medical solutions': 'siemens',
    'siemens healthcare': 'siemens',
    'siemens building technologies': 'siemens',
    'siemens building tech': 'siemens',

    'cardinal health': 'cardinal health',
    'cardinal distribution': 'cardinal health',

    'mckesson': 'mckesson',

    'medline': 'medline industries',
    'medline industries': 'medline industries',
    'medline ind': 'medline industries',

    'henry schein': 'henry schein',
    'schein': 'henry schein',
    'butler schein': 'henry schein',
    'butler schein animal health': 'henry schein',

    'boston scientific': 'boston scientific',

    'baxter': 'baxter healthcare',
    'baxter healthcare': 'baxter healthcare',

    'eppendorf': 'eppendorf',
    'eppendorf north america': 'eppendorf',
    'eppendorf north amer': 'eppendorf',
    'eppendorf scientific': 'eppendorf',

    'cdw': 'cdw government',
    'cdw government': 'cdw government',
    'cdw govt': 'cdw government',
    'cdw direct': 'cdw government',
    'cdw g': 'cdw government',
    'cdw-g': 'cdw government',
    'cdw-g government': 'cdw government',
    'cdw-government': 'cdw government',

    'hewlett packard': 'hewlett packard',
    'hewlett-packard': 'hewlett packard',
    'hewlett packard company': 'hewlett packard',
    'hewlett packard corp': 'hewlett packard',
    'hewlett packard enterprise': 'hewlett packard',

    'mcmaster carr': 'mcmaster-carr supply',
    'mcmaster-carr': 'mcmaster-carr supply',
    'mcmaster-carr supply': 'mcmaster-carr supply',
    'mcmaster carr supply': 'mcmaster-carr supply',
    'mc master': 'mcmaster-carr supply',

    'amazon': 'amazon',
    'amazon business': 'amazon',
    'amazon capital services': 'amazon',
    'amazon com': 'amazon',
    'amazon com llc': 'amazon',
    'amazon dot com': 'amazon',
    'amazon.com': 'amazon',
    'amazon services': 'amazon',
    'amazon web services': 'amazon web services',

    'carolina biological supply': 'carolina biological supply',
    'carolina biological': 'carolina biological supply',
    'carolina bio supply': 'carolina biological supply',
    'carolina bio': 'carolina biological supply',
    'carolina biologic supply': 'carolina biological supply',

    'wards': 'wards natural science',
    'wards natural science': 'wards natural science',
    'wards natural science est': 'wards natural science',
    'wards natural science establishment': 'wards natural science',

    'flinn scientific': 'flinn scientific',

    'promegacorp': 'promega corporation',

    'mettler toledo': 'mettler-toledo',
    'mettlertoledo': 'mettler-toledo',
    'mettler-toledo': 'mettler-toledo',
    'mettler toledo lab': 'mettler-toledo',
    'mettler toledo intl': 'mettler-toledo',
    'mettler toledo international': 'mettler-toledo',
    'mettler toledo process analytics': 'mettler-toledo',
    'mettler toledo rainin': 'mettler-toledo',
    'mettler toledo raining': 'mettler-toledo',
    'mettler toledo thorton': 'mettler-toledo',
    'mettler toledo thornton': 'mettler-toledo',
    'mettler toledo ingold': 'mettler-toledo',
    'mettler toledo autochem': 'mettler-toledo',
    'mettlertoledo autochem': 'mettler-toledo',
    'mettlertoledo ingold': 'mettler-toledo',
    'mettlertoledo rainin': 'mettler-toledo',

    'cole parmer': 'cole-parmer',
    'coleparmer': 'cole-parmer',
    'cole-parmer': 'cole-parmer',
    'coleparmer instrument': 'cole-parmer',
    'cole parmer instrument': 'cole-parmer',
    'idex health and sciencecole parmer': 'cole-parmer',

    'cell signaling': 'cell signaling technology',
    'cell signaling tech': 'cell signaling technology',
    'cell signaling technology': 'cell signaling technology',

    'santa cruz biotech': 'santa cruz biotechnology',
    'santa cruz biotechnology': 'santa cruz biotechnology',
    'santa cruz bio technology': 'santa cruz biotechnology',

    'novus biological': 'novus biologicals',
    'novus biologicals': 'novus biologicals',

    'sartorius': 'sartorius',
    'sartorius biotech': 'sartorius',
    'sartorius mechatronics': 'sartorius',
    'sartorius stedim': 'sartorius',
    'sartorius stedim north america': 'sartorius',
    'sartorius stedim north amer': 'sartorius',
    'sartorius cellgenix': 'sartorius',

    'lonza': 'lonza',
    'lonza walkersville': 'lonza',
    'lonza rockland': 'lonza',

    'tecan': 'tecan',
    'tecan us': 'tecan',
    'tecan sp': 'tecan',
    'tecan genomics': 'tecan',

    'kimberly clark': 'kimberly-clark',
    'kimberly-clark': 'kimberly-clark',
    'kimberly clark global sales': 'kimberly-clark',
    'kimberly clark healthcare': 'kimberly-clark',

    'sherwin williams': 'sherwin-williams',
    'sherwinwilliams': 'sherwin-williams',
    'sherwin-williams': 'sherwin-williams',
    'sherwinwilliams paint': 'sherwin-williams',
    'sherwinwilliams store': 'sherwin-williams',

    'hach': 'hach',
    'hach company': 'hach',
    'hach co': 'hach',
    'hach chemical': 'hach',
    'hach environmental': 'hach',
    'hach hydromet': 'hach',
    'radiometer analytical hach': 'hach',

    'honeywell': 'honeywell',
    'honeywell intl': 'honeywell',
    'honeywell international': 'honeywell',
    'honeywell analytics': 'honeywell',
    'honeywell analytics distribution': 'honeywell',
    'honeywell sensing and control': 'honeywell',
    'honeywell sensotec': 'honeywell',
    'honeywell sensotechoneywell': 'honeywell',
    'honeywell building solutions': 'honeywell',
    'honeywell process solutions': 'honeywell',
    'honeywell federal manufacturing and tech': 'honeywell',
    'honeywell fm and t': 'honeywell',
    'honeywell hom med': 'honeywell',

    'bayer': 'bayer',
    'bayer healthcare': 'bayer',
    'bayer healthcare pharmaceuticals': 'bayer',
    'bayer materialscience': 'bayer',

    'hitachi': 'hitachi',
    'hitachi america': 'hitachi',
    'hitachi data systems': 'hitachi',
    'hitachi high tech': 'hitachi',
    'hitachi high tech amer': 'hitachi',
    'hitachi high technology': 'hitachi',
    'hitachi high technology america': 'hitachi',
    'hitachi hightech': 'hitachi',
    'hitachi hightech canada': 'hitachi',
    'hitachi medical systems': 'hitachi',
    'hitachi medical systems america': 'hitachi',
    'hitachi aloka medical': 'hitachi',

    'panasonic': 'panasonic',
    'panasonic healthcare': 'panasonic',
    'panasonic healthcare corporati': 'panasonic',
    'panasonic healthcare of na': 'panasonic',
    'panasonic healthcare of north america': 'panasonic',
    'panasonic of na': 'panasonic',
    'panasonic of north america': 'panasonic',

    'leica': 'leica',
    'leica microsystems': 'leica',
    'leica biosystems': 'leica',
    'leica biosystems imaging': 'leica',
    'leica biosystems richmond': 'leica',

    'olympus america': 'olympus',
    'olympus scientific solutions americas': 'olympus',

    'cisco systems': 'cisco systems',
    'cisco webex': 'cisco systems',

    'lenovo': 'lenovo',
    'lenovo us': 'lenovo',
    'lenovo usa': 'lenovo',
    'lenovo united states': 'lenovo',
    'lenovo united state': 'lenovo',
    'direct lenovo': 'lenovo',
    'lenovo global technology us': 'lenovo',

    'ricoh': 'ricoh',
    'xerox': 'xerox',

    'microsoft': 'microsoft',
    'adobe': 'adobe',
    'adobe systems': 'adobe',
    'oracle america': 'oracle',
    'oracle amer': 'oracle',
    'oracle amercia': 'oracle',
    'oracle micros systems': 'oracle',

    'fedex': 'fedex',
    'fed ex': 'fedex',
    'federal express': 'fedex',
    'fedex express': 'fedex',
    'fedex ground': 'fedex',
    'fedex freight': 'fedex',
    'fedex kinkos': 'fedex',
    'fedex custom critical': 'fedex',
    'fedex supply chain': 'fedex',
    'fedex supply chain systems': 'fedex',
    'fedex trade networks': 'fedex',
    'federal express and fedex ground package system': 'fedex',

    'united parcel service': 'united parcel service',
    'ups freight': 'united parcel service',
    'ups store': 'united parcel service',
    'ups supply chain': 'united parcel service',
    'ups supply chain solutions': 'united parcel service',
    'ups expedited mail': 'united parcel service',
    'ups expedited mail service': 'united parcel service',

    'verizon': 'verizon',
    'verizon wireless': 'verizon',
    'verizon online': 'verizon',
    'verizon communications': 'verizon',
    'verizon select services': 'verizon',
    'verizon select service': 'verizon',
    'verizon internet solutions': 'verizon',
    'verizon pennsylvania': 'verizon',
    'verizon network service on behalf': 'verizon',

    'sprint': 'sprint',
    'sprint pcs': 'sprint',
    'sprint nextel': 'sprint',
    'sprint spectrum': 'sprint',

    'comcast': 'comcast',
    'comcast cable': 'comcast',
    'comcast communications': 'comcast',
    'comcast spotlight': 'comcast',
    'comcast cablevision': 'comcast',

    'at and t': 'at&t',
    'atandt': 'at&t',
    'at&t': 'at&t',
    'at and t mobility': 'at&t',
    'atandt mobility': 'at&t',
    'at and t wireless service': 'at&t',
    'at and t business service': 'at&t',
    'at and t global service': 'at&t',

    'pearson education': 'pearson education',
    'pearson clinical': 'pearson education',
    'pearson clinical assessment': 'pearson education',
    'pearson assessment': 'pearson education',
    'pearson evaluation systems': 'pearson education',
    'pearson vue': 'pearson education',
    'pearson ncs': 'pearson education',
    'ncs pearson': 'pearson education',
    'ncs pearson assessments': 'pearson education',
    'awl pearson education': 'pearson education',

    'cengage learning': 'cengage learning',
    'cengage': 'cengage learning',
    'cengage learninggale': 'cengage learning',
    'gale cengage learning': 'cengage learning',
    'galecengage learning': 'cengage learning',
    'ed2go cengage': 'cengage learning',

    'mcgrawhill': 'mcgraw-hill',
    'mcgraw hill': 'mcgraw-hill',
    'mcgraw-hill': 'mcgraw-hill',
    'mcgraw hill publishers': 'mcgraw-hill',
    'mcgraw hill publishing': 'mcgraw-hill',
    'mcgrawhill companies': 'mcgraw-hill',
    'mcgrawhill companies business week': 'mcgraw-hill',
    'mcgrawhill education': 'mcgraw-hill',
    'mcgrawhill higher education': 'mcgraw-hill',
    'mcgrawhill school education': 'mcgraw-hill',
    'glencoe mcgrawhill': 'mcgraw-hill',
    'sramcgrawhill': 'mcgraw-hill',

    'john wiley and sons': 'john wiley and sons',
    'john wiley sons': 'john wiley and sons',
    'john wiley and son': 'john wiley and sons',
    'john wiley': 'john wiley and sons',
    'john wiley and sons bus jrnl': 'john wiley and sons',
    'wiley subscription service': 'john wiley and sons',
    'wiley subscription services': 'john wiley and sons',
    'wiley subscription svc': 'john wiley and sons',
    'wiley vch': 'john wiley and sons',
    'wileyvch': 'john wiley and sons',
    'wiley vch verlag': 'john wiley and sons',
    'wileyvch verlag': 'john wiley and sons',
    'wileyvch verlag and': 'john wiley and sons',
    'wileyvch veriag and kgaa': 'john wiley and sons',
    'wiley vch verlag and kgaa': 'john wiley and sons',
    'wiley blackwell': 'john wiley and sons',
    'wileyblackwell': 'john wiley and sons',
    'wiley jossey bass': 'john wiley and sons',
    'wileyjosseybass': 'john wiley and sons',

    'springer nature': 'springer nature',
    'springer verlag': 'springer nature',
    'springer sci and bus media': 'springer nature',
    'springer science and business media': 'springer nature',
    'springer sciencebusiness media': 'springer nature',
    'springer customer service center': 'springer nature',
    'springer nature amer': 'springer nature',
    'springer nature customer service center': 'springer nature',

    'elsevier': 'elsevier',
    'elsevier bv': 'elsevier',

    'thomson reuters': 'thomson reuters',
    'thomson reuters scientific': 'thomson reuters',
    'thomson reuters markets': 'thomson reuters',
    'thomson reuters tax and accounting': 'thomson reuters',
    'thomson reuters r and g': 'thomson reuters',
    'thomson reuters endnote': 'thomson reuters',
    'thomson reuters grc': 'thomson reuters',

    'lexisnexis': 'lexisnexis',
    'lexis nexis': 'lexisnexis',
    'lexisnexis matthew bender': 'lexisnexis',
    'matthew bender lexisnexis': 'lexisnexis',

    'wolters kluwer': 'wolters kluwer',
    'wolterskluwer': 'wolters kluwer',
    'wolters kluwer health': 'wolters kluwer',

    'home depot': 'home depot',
    'home depot pro': 'home depot',
    'office depot': 'office depot',
    'office max': 'office max',
    'staples': 'staples',
    'staples office superstore': 'staples',
    'best buy': 'best buy',
    'best buy stores': 'best buy',
    'costco': 'costco',
    'costco wholesale': 'costco',
    'lowes home center': 'lowes home improvement',
    'lowes home centers': 'lowes home improvement',
    'lowes home improvement': 'lowes home improvement',
    'lowes home improvement warehouse': 'lowes home improvement',
    'lowes companies': 'lowes home improvement',
    'walmart community': 'walmart',
    'walmart stores': 'walmart',
    'walmart aransas county': 'walmart',

    'b and h photo': 'b and h photo video',
    'b and h photo and video': 'b and h photo video',
    'b and h photo video': 'b and h photo video',
    'b and h photovideo': 'b and h photo video',
    'b and h photovideopro audio': 'b and h photo video',
    'b and h foto and electronics': 'b and h photo video',
    'b&h photo': 'b and h photo video',
    'b&h photo video': 'b and h photo video',

    'wells fargo': 'wells fargo',
    'wells fargo insurance': 'wells fargo',
    'wells fargo insurance service': 'wells fargo',
    'wells fargo trade capital': 'wells fargo',

    'nestle': 'nestle',
    'nestle usa': 'nestle',
    'nestle waters': 'nestle',
    'nestle waters north america': 'nestle',
    'nestle pure life direct': 'nestle',
    'readyrefresh by nestle': 'nestle',

    'barnes and noble': 'barnes and noble',
    'barnes and noble bookseller': 'barnes and noble',
    'barnes and noble booksellers': 'barnes and noble',
    'barnes and noble booksellers usa': 'barnes and noble',
    'barnes and noble bookstores': 'barnes and noble',
    'barnes and noble college bookseller': 'barnes and noble',
    'barnes and noble collegebook': 'barnes and noble',

    'tigerdirect': 'tigerdirect',
    'tiger direct': 'tigerdirect',
    'tiger direct corporate sales': 'tigerdirect',
    'shi internatl': 'shi',
    'shi international': 'shi',
    'shi intl': 'shi',
    'shi international corp': 'shi',
    'govconnection': 'govconnection',
    'gov connection': 'govconnection',
    'pcmg': 'pcmg',
    'pcm g': 'pcmg',

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

IGNORABLE_TOKENS = {
    'inc', 'corp', 'corporation', 'llc', 'ltd', 'company', 'co', 'limited',
    'group', 'holdings', 'partnership', 'associates', 'plc', 'gmbh', 'sa',
    'lp', 'pllc', 'ag',

    'division', 'div', 'branch', 'sub', 'subsidiary', 'department', 'dept',
    'global', 'international', 'intl', 'systems', 'solutions',
    'enterprises', 'enterprise',

    'dba', 'aka', 'doing', 'business', 'as', 'formerly', 'known',

    'north', 'south', 'east', 'west', 'northeast', 'northwest', 'southeast', 'southwest',
    'america', 'americas', 'asia', 'europe', 'africa', 'australia', 'oceania',
    'latin', 'pacific', 'atlantic',

    'usa', 'us', 'united', 'states', 'uk', 'kingdom',
    'canada', 'mexico', 'brazil', 'argentina', 'colombia',
    'china', 'japan', 'korea', 'india', 'singapore', 'taiwan', 'thailand', 'vietnam', 'malaysia',
    'germany', 'france', 'italy', 'spain', 'netherlands', 'switzerland', 'sweden', 'norway', 'denmark', 'finland',
    'ireland', 'belgium', 'austria', 'poland', 'czech', 'hungary', 'greece', 'portugal',
    'russia', 'turkey', 'israel', 'egypt', 'saudi', 'arabia', 'uae',
    'new', 'zealand',

    'sales', 'direct',
}

_SORTED_ALIASES = sorted(CANONICAL_MAPPING.keys(), key=len, reverse=True)
_ALIAS_PATTERNS = [(alias, re.compile(r'\b' + re.escape(alias) + r'\b')) for alias in _SORTED_ALIASES]
_LOCKED_NAMES = frozenset(val.lower() for val in CANONICAL_MAPPING.values())

_RE_UNIVERSITY = re.compile(r'\buni[a-z]*sity\b')
_RE_JUNK_PREFIX = re.compile(r'^((z{2,}|x{2,})[a-z0-9]*(_[a-z0-9]+)*)[\s_]')
_RE_SUFFIXES = re.compile(r'\b(inc|incorporated|llc|ll|ltd|plc|ag|co|corp|corporation|company|international|gmbh|pllc|com|assoc|lp)\b')
_RE_THE = re.compile(r'\bthe\b')
_RE_NONALNUM = re.compile(r'[^a-z0-9\s]')
_RE_MULTISPACE = re.compile(r'\s+')
_RE_PARENS = re.compile(r'\([^)]*\)')
_RE_SEE_USE = re.compile(r'\b(see|use)\s+(vendor\s+)?[#v]?\d+\b')
_RE_LEADING_QUOTE = re.compile(r'^["\']+')
_RE_TRAILING_ACCT = re.compile(r'\s*(acct|account|vendor|vend)?[#]?\s*\d{4,}\s*$')
_RE_FKA = re.compile(r'\b(fka|f/k/a|formerly\s+known\s+as|formerly)\s+.*$')


def normalize_name(name):
    if not isinstance(name, str) or not name.strip():
        return "", ""

    cleaned_for_search = name.lower().strip()

    cleaned_for_search = _RE_LEADING_QUOTE.sub('', cleaned_for_search).strip()

    for alias, pattern in _ALIAS_PATTERNS:
        if pattern.search(cleaned_for_search):
            return cleaned_for_search, CANONICAL_MAPPING[alias]

    cleaned = cleaned_for_search.replace('d.b.a.', 'dba').replace('d/b/a', 'dba')
    if ' dba ' in cleaned:
        parts = cleaned.split(' dba ')
        if len(parts) > 1 and parts[-1].strip():
            cleaned = parts[-1].strip()

    cleaned = _RE_FKA.sub('', cleaned)

    cleaned = cleaned.replace('&', ' and ')

    cleaned = _RE_PARENS.sub('', cleaned)

    cleaned = _RE_SEE_USE.sub('', cleaned)

    cleaned = _RE_TRAILING_ACCT.sub('', cleaned)

    cleaned = cleaned.replace('biotechnologies', 'biotech')
    cleaned = cleaned.replace('biotechnology', 'biotech')

    cleaned = cleaned.replace('university of california', 'uc')
    cleaned = cleaned.replace('uni of california', 'uc')
    cleaned = _RE_UNIVERSITY.sub('uni', cleaned)
    cleaned = cleaned.replace('univ', 'uni')

    cleaned = cleaned.replace('united states', 'us')
    cleaned = cleaned.replace('u s ', 'us')

    cleaned = cleaned.replace('laboratories', 'lab')
    cleaned = cleaned.replace('labortories', 'lab')
    cleaned = cleaned.replace('laboratory', 'lab')
    cleaned = cleaned.replace('labs', 'lab')
    cleaned = cleaned.replace('technologies', 'tech')

    cleaned = cleaned.replace('supplies', 'supply')

    cleaned = cleaned.replace('services', 'service')

    cleaned = _RE_JUNK_PREFIX.sub('', cleaned)

    cleaned = _RE_SUFFIXES.sub('', cleaned)
    cleaned = _RE_THE.sub('', cleaned)

    cleaned = cleaned.replace("zzz", "")
    cleaned = cleaned.replace("xxxx", "")
    cleaned = cleaned.replace("xxx", "")
    cleaned = cleaned.replace("www", "")
    cleaned = cleaned.replace("inactive", "")
    cleaned = cleaned.replace("do not use", "")
    cleaned = cleaned.replace("blocked vendor", "")
    cleaned = cleaned.replace("dnu", "")

    cleaned = _RE_NONALNUM.sub('', cleaned).strip()
    cleaned = _RE_MULTISPACE.sub(' ', cleaned)

    if cleaned in CANONICAL_MAPPING:
        return cleaned, CANONICAL_MAPPING[cleaned]

    return cleaned, cleaned

def is_safe_subset(shorter, longer):
    shorter_tokens = set(shorter.split())
    longer_tokens = set(longer.split())

    extra_in_longer = longer_tokens - shorter_tokens
    extra_in_shorter = shorter_tokens - longer_tokens

    return extra_in_longer.issubset(IGNORABLE_TOKENS) and extra_in_shorter.issubset(IGNORABLE_TOKENS)

def group_suppliers(supplier_list, threshold=92):
    start_time = time.time()
    print("   -> Step 1/4: Normalizing all supplier names...")

    clean_map = {name: normalize_name(name)[1] for name in supplier_list}
    unique_names = list(set(clean_map.values()))

    unique_names.sort(key=len)
    print(f"   -> Found {len(unique_names)} unique cleaned groups to start.")

    print("   -> Step 2/4: Building blocks...")
    blocks = defaultdict(set)
    name_to_keys = defaultdict(set)
    for name in unique_names:
        if not name:
            continue
        stripped = re.sub(r'[^a-z0-9]', '', name)
        key1 = stripped[:3]
        key2 = name[:3]
        keys = {key1, key2}
        if len(stripped) <= 4:
            keys.add(stripped)
        for k in keys:
            blocks[k].add(name)
            name_to_keys[name].add(k)

    print(f"   -> Step 3/4: Matching with Advanced Logic ({len(blocks)} blocks)...")
    parent_map = {}
    total_names = len(unique_names)
    processed = 0
    last_pct = -1

    for name in unique_names:
        if not name or name in parent_map:
            continue

        parent_map[name] = name
        processed += 1

        pct = (processed * 100) // total_names
        if pct >= last_pct + 10:
            last_pct = pct
            print(f"      {pct}% done ({processed}/{total_names} names assigned)...")

        candidates = set()
        for k in name_to_keys[name]:
            candidates.update(blocks[k])
        candidates.discard(name)
        candidates = {c for c in candidates if c not in parent_map}

        for candidate in candidates:
            is_match = False

            if candidate in _LOCKED_NAMES and fuzz.ratio(name, candidate) < 98:
                is_match = False
            else:
                if name.replace(" ", "") == candidate.replace(" ", ""):
                    is_match = True

                elif is_safe_subset(name, candidate) and fuzz.token_set_ratio(name, candidate) == 100:
                    is_match = True

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
    dta_file_path = '../external/samp/first_stage_data_tfidf.dta'
    supplier_name_column = 'suppliername'
    output_csv_path = '../output/supplier_mapping_final.csv'

    try:
        print(f"Reading '{dta_file_path}'...")
        df = pd.read_stata(dta_file_path)

        df.columns = [col.strip().lower() for col in df.columns]

        if supplier_name_column not in df.columns:
            raise KeyError(f"Column '{supplier_name_column}' not found.")

        supplier_names = df[supplier_name_column].dropna().unique().tolist()
        print(f"Found {len(supplier_names)} unique supplier names to process.")
        del df

        print("\nStarting the grouping process...")
        group_map = group_suppliers(supplier_names, threshold=92)

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
