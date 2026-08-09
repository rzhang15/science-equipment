import re
import nltk
from nltk.corpus import stopwords

# Ensure stopwords are downloaded
nltk.download("stopwords", quiet=True)


academic_stopwords = [
    "study", "studies", "result", "results", "conclusion", "conclusions", 
    "abstract", "introduction", "discussion", "background", "aim", "objective", 
    "hypothesis", "method", "methods", "methodology", "data", "analysis", 
    "analyses", "analyzed", "report", "reported", "review", "case", "series", 
    "figure", "table", "fig", "reference", "appendix", "supplementary", 
    "material", "materials", "experiment", "experimental", "experiments",
    "performed", "conducted", "investigated", "evaluated", "examined", 
    "assessed", "observed", "observation", "findings", "demonstrated", 
    "showed", "shown", "shows", "present", "presented", "presents", 
    "describe", "described", "describes", "suggest", "suggests", "suggesting",
    "propose", "proposed", "identify", "identified", "identification",
    "determine", "determined", "determination", "investigate", "investigation",
    "measure", "measured", "measurement", "calculate", "calculated", 
    "compare", "compared", "comparison", "comparative", "contrast",
    "focus", "focused", "include", "included", "including", "exclude",
    "excluded", "published", "journal", "article", "author", "university",
    "department", "program", "project", "grant", "support", "supported",
    "funding", "received", "copyright", "doi", "vol", "issue", "pp", "research", 
    "among", "relate", "via", "evalu", "compar", "associate", "associated", "association"
]

quantitative_stopwords = [
    "significantly", "significant", "significance", "statistically", "statistics",
    "p-value", "confidence", "interval", "mean", "median", "mode", "average",
    "standard", "deviation", "error", "rate", "ratio", "level", "levels",
    "high", "higher", "highest", "low", "lower", "lowest", "increase", 
    "increased", "increasing", "decrease", "decreased", "decreasing", 
    "reduce", "reduced", "reduction", "elevated", "depleted", "correlated", 
    "correlation", "associate", "associated", "association", "relationship", 
    "effect", "effects", "affect", "affected", "affecting", "impact", 
    "impacted", "influence", "influenced", "change", "changed", "changes",
    "vary", "varied", "variable", "variation", "difference", "different", 
    "differential", "similar", "similarity", "total", "amount", "quantity", 
    "number", "frequency", "percent", "percentage", "range", "ranged", 
    "value", "values", "score", "scores", "sample", "samples", "group", 
    "groups", "cohort", "control", "controls", "n=", "versus", "vs",
    "greater", "less", "approximately", "estimate", "estimated", "estimation",
    "two", "one", "first"
]

clinical_stopwords = [
    "patient", "patients", "subject", "subjects", "participant", "participants",
    "clinical", "preclinical", "trial", "trials", "cohort", "population",
    "treatment", "treated", "therapy", "therapies", "therapeutic", "treat",
    "intervention", "procedure", "management", "care", "outcome", "outcomes",
    "prognosis", "prognostic", "diagnosis", "diagnostic", "diagnose", "diagnosed",
    "disease", "diseases", "disorder", "disorders", "condition", "conditions",
    "symptom", "symptoms", "syndrome", "pathology", "pathological", "lesion",
    "risk", "factor", "factors", "mortality", "morbidity", "survival", 
    "complication", "complications", "adverse", "event", "events", "incidence",
    "prevalence", "epidemiology", "epidemiological", "health", "healthy", 
    "normal", "abnormal", "hospital", "clinic", "center", "centre", "medical",
    "medicine", "physician", "doctor", "nurse", "surgery", "surgical", "surgeon",
    "operation", "operative", "postoperative", "preoperative", "acute", "chronic",
    "severe", "mild", "moderate", "stage", "grade", "response", "responded",
    "remission", "relapse", "recurrence", "follow-up", "baseline", "placebo",
    "randomized", "blinded", "prospective", "retrospective", "exposure", "population",
    "children", "protect", "administer", "administration"
]

bio_scaffolding_stopwords = [
    "cell", "cells", "cellular", "tissue", "tissues", "organ", "organs",
    "body", "human", "humans", "mouse", "mice", "murine", "rat", "rats", 
    "animal", "animals", "model", "models", "vivo", "vitro", "ex", "situ",
    "protein", "proteins", "gene", "genes", "genetic", "genomic", "expression",
    "expressed", "activity", "active", "activation", "activated", "function", 
    "functional", "functioning", "role", "roles", "mechanism", "mechanisms",
    "pathway", "pathways", "process", "processes", "system", "systems", 
    "biological", "biology", "physiological", "physiology", "molecular", 
    "biochemical", "chemical", "chemistry", "structure", "structural", 
    "compound", "compounds", "molecule", "molecules", "component", "components",
    "interaction", "interactions", "interact", "interacting", "bind", "binding",
    "bound", "receptor", "receptors", "target", "targets", "targeted", 
    "develop", "development", "developmental", "evolution", "evolutionary",
    "species", "organism", "organisms", "isolate", "isolated", "isolation",
    "detect", "detected", "detection", "assess", "assessment", "monitor", 
    "monitoring", "screen", "screening", "novel", "new", "potential", 
    "promising", "unique", "useful", "efficient", "effective", "efficacy",
    "perform", "performance", "improve", "improved", "improvement", "enhance", 
    "enhanced", "enhancement", "inhibit", "inhibition", "inhibitor", "blocked",
    "regulate", "regulation", "regulator", "mediated", "mediates", "mediation",
    "production", "produce", "produced", "induce", "induced", "induction", 
    "synthesis", "synthesized", "form", "formation", "complex", "characterize", 
    "characterization", "identify", "identification", "analyzed", "analysis",
    "technique", "techniques", "method", "approach", "application", "applications",
    "use", "used", "using", "useful", "utility", "utilize", "utilized", "base",
    "specific", "specifically", "type", "types"
]

unit_stopwords = [
    "mg", "kg", "ml", "l", "dl", "mm", "cm", "m", "nm", "um", "micrometer",
    "min", "hr", "hour", "hours", "day", "days", "week", "weeks", "month",
    "months", "year", "years", "time", "times", "period", "duration", 
    "concentration", "dose", "doses", "dosage", "weight", "volume", 
    "temperature", "degree", "degrees", "celsius", "fahrenheit", "ph", 
    "fig", "table", "eq", "al", "et", "ie", "eg", "etc", "www", "http", 
    "https", "com", "org", "edu", "pdf", "suppl", "doi"
]

# --- NEW ADDITIONS TO CLEAN CLUSTERS ---

# 1. Chemical Artifacts (Removing the "fluorescein" clusters)
chemical_stopwords = [
    "fluorescence", "fluorescent", "fluorescein", "fluorescamine", 
    "fluorenyl", "fluorenylmethyloxycarbonyl", "fmoc", "fluoresc", 
    "fluoresbrit", "fluorenylnitrenium", "fluorenylmethyl", 
    "fluorenylmethylchloroform", "fluorenylmethoxycarbonyl", 
    "fluorenylmethoxi", "fluorenylhydroxam", "fluorenyliden", 
    "sub", "sup" # Common chemical formula subscripts/superscripts
]

# 2. Foreign Language & Nonsense Words (Removing the French/Spanish/German clusters)
foreign_stopwords = [
    "pour", "dans", "avec", "etude", "chez", "une", "nous", "de", "le", "sur", 
    "ca", "tude", "est", "propo", "para", "por", "los", "las", "estudio", 
    "caso", "con", "del", "ncia", "lo", "que", "nica", "la", "entr", "und", 
    "der", "die", "das", "von", "mit", "eine", "einer", "bei", "patienten", 
    "ein", "zur", "ber", "auf", "nach", "den"
]

# 3. XML/Formatting Artifacts (Removing the "Math" cluster)
xml_stopwords = [
    "mml", "math", "mrow", "xmlns", "mathml", "mtext", "msub",
    "mathvariant", "msup", "inline", "fontstyle", "xmln", "mathvari",
    "fontstyl"
]

# 4. Abstract-template / journal-chrome tokens that leak into cluster top-terms
#    (jama, summary, altmetric/altmetrics, scp boilerplate, follow-up).
#    Include both unstemmed and stemmed variants so the upstream
#    `t not in stopwords_set` check in 0_combine_data.py and the
#    TfidfVectorizer stop_words filter both catch them.
template_stopwords = [
    "jama",
    "summary", "summaries", "summari",
    "altmetric", "altmetrics", "altmetr",
    "scp",
    "follow", "follows", "followed", "following",
]

# 5. Publisher / scraped-page chrome. These formed whole clusters at K=100:
#    C23 was "commun, urolog, public, onlin, american, date, advertis, inc,
#    s0022, informationhttp, favoritesdownload, toolsadd, citationstrack,
#    intwitteremail" -- 12,197 authors grouped on page furniture, which
#    dropped real life scientists from the life-science filter. C72 mixed
#    real pharmacology with "citat, crossref, text, updat, share, full".
#
#    These also create spurious FOIA similarity: two authors publishing in
#    the same journal share chrome tokens without sharing a topic.
#
#    Deliberately NOT listed, because the Porter stem collides with real
#    science vocabulary:
#      supplement <- "dietary supplementation"    confer <- "confers resistance"
#      reserv     <- "cardiac reserve"            press  <- "blood pressure" adjacent
publisher_stopwords = [
    "onlin", "advertis", "inc", "date", "updat", "citat", "crossref",
    "share", "full", "text", "articl", "journal", "publish", "copyright",
    "pdf", "html", "download", "subscript", "issn", "doi", "volum", "issu",
    "page", "keyword", "correspond", "email", "reprint", "permiss", "licens",
    "elsevier", "springer", "wilei", "cambridg", "oxford", "societi",
    "american", "annual", "meet", "symposium", "editor", "comment",
    "erratum", "retract", "appendix",
    # observed concatenated nav artifacts from page scraping
    "informationhttp", "favoritesdownload", "toolsadd", "citationstrack",
    "intwitteremail", "s0022",
    # short exact-match chrome. NOT eligible for CHROME_FRAGMENTS substring
    # matching: "icon" would swallow "silicon", "cite" would swallow
    # "excite"/"cited-adjacent" stems.
    "icon", "cite", "toview", "inissu", "inadd", "donut", "online1",
    "alert", "compliant", "get", "novemb", "januari", "februari", "april",
    "june", "juli", "august", "septemb", "octob", "decemb",
    # cookie-consent banners and journal-title words. These formed a cluster
    # of 9,568 clinicians grouped on "Archives of Pediatrics / Psychiatry /
    # Neurology / Dermatology / Otolaryngology / Ophthalmology" rather than on
    # what any of them study. The specialty names themselves stay -- they are
    # real vocabulary; it is the title scaffolding that has to go.
    #
    # "sign" deliberately excluded: "signs and symptoms" is clinical content.
    "cooki", "archiv", "forum",
]

# 6. Concatenated navigation strings from page scraping. These cannot be
#    enumerated: the scraper mashes adjacent link text into one token, so the
#    set is open-ended ("sharefacebooklink", "citationspermissionsreprint",
#    "exportriscitationcit", "onfacebooktwitterwechatlink", "downloadload",
#    "figuresreferencesrelateddetailscit", "metricsarticl"). At K=100 they
#    still formed two clusters (C27, C93; 21,964 authors) after the flat
#    publisher_stopwords list was applied.
#
#    Matched as substrings, so they catch novel concatenations. Every fragment
#    here is long enough that no Porter-stemmed biomedical term contains it --
#    checked against the 30k clustering vocabulary.
CHROME_FRAGMENTS = [
    "facebook", "twitter", "wechat", "linkedin", "mendeley",
    "citation", "permission", "metricsarticl", "metricsauthor",
    "downloadload", "figuresrefer", "accessjourn", "exportris",
    "abstractcit", "referencesmor", "referenceadd", "relateddetail",
    "sharefacebook", "toolsadd", "favoritesdownload", "informationhttp",
    "intwitteremail", "citationstrack",
    # "permission" (was "permissionsreprint") also catches permissionsarticl;
    # "onlin" catches online1/onlinefirst without touching real vocabulary.
    "onlin",
]

#    Fragment matching only -- no token-length rule. A length cutoff looks
#    tempting but real biomedical vocabulary runs long: at 24+ characters the
#    30k clustering vocabulary contains glycosylphosphatidylinositol,
#    acetylgalactosaminyltransferas, esophagogastroduodenoscopi,
#    methylenedioxymethamphetamin and uvulopalatopharyngoplasti. Every chrome
#    token observed so far is caught by a fragment anyway.
#
#    Compiled to one alternation rather than looping the list per token: the
#    tokenizer sees ~370M tokens per vectorize pass, so a Python-level loop
#    over 25 fragments costs ~9 billion substring checks and roughly doubled
#    the vectorize step.
_CHROME_RE = re.compile("|".join(re.escape(f) for f in CHROME_FRAGMENTS))


def is_chrome(token: str) -> bool:
    """True if a token is scraped page furniture rather than science."""
    return _CHROME_RE.search(token) is not None


all_custom_stopwords = (
    academic_stopwords +
    quantitative_stopwords +
    clinical_stopwords +
    bio_scaffolding_stopwords +
    unit_stopwords +
    chemical_stopwords +
    foreign_stopwords +
    xml_stopwords +
    template_stopwords +
    publisher_stopwords
)
# Export the final SET (for fast checking) and LIST (for sklearn)
stopwords_set = set(stopwords.words("english")).union(set(all_custom_stopwords))
stopwords_list = list(stopwords_set)
