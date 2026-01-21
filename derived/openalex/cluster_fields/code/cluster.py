import os
import re
import random
import numpy as np
import pandas as pd
import polars as pl
import nltk
from nltk.corpus import stopwords
from nltk.stem import PorterStemmer
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.cluster import MiniBatchKMeans

# --- SETUP ---
nltk.download("stopwords", quiet=True)
SEED = 42
random.seed(SEED)
np.random.seed(SEED)
stemmer = PorterStemmer()

# --- CONFIGURATION ---
NUM_CLUSTERS = 25       
REGEX_CLEAN = r"[^a-z0-9\s]" 
REGEX_SPACES = r"\s+"

nltk_stopwords = set(stopwords.words("english"))

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
    "funding", "received", "copyright", "doi", "vol", "issue", "pp"
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
    "greater", "less", "approximately", "estimate", "estimated", "estimation"
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
    "randomized", "blinded", "prospective", "retrospective"
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
    "use", "used", "using", "useful", "utility", "utilize", "utilized"
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

all_custom_stopwords = (
    academic_stopwords + 
    quantitative_stopwords + 
    clinical_stopwords + 
    bio_scaffolding_stopwords + 
    unit_stopwords
)

custom_stopwords_set = set(stopwords.words("english")).union(set(all_custom_stopwords))
custom_stopwords_list = list(custom_stopwords_set)

# --- LOAD DATA ---
print("Loading Master ID List...")
pd_samp = pd.read_stata("../external/appended/openalex_all_jrnls_merged.dta")

df_base = pl.from_pandas(pd_samp).lazy()

q_master_list = (
    df_base
    .select(["id", "athr_id"]) 
    .unique() 
)

print("Configuring Abstracts...")
q_abstracts = (
    pl.scan_csv("../output/combined_abstracts.csv")
    .with_columns(
        pl.col("id").str.replace("https://openalex.org/", ""),
        pl.col("abstract").str.to_lowercase()
        .str.replace_all(REGEX_CLEAN, " ")
        .str.replace_all(REGEX_SPACES, " ")
        .str.strip_chars()
        .alias("cleaned_abstract")
    )
    .select(["id", "cleaned_abstract"]) 
)

print("Configuring Titles...")
q_titles = (
    df_base
    .select(["id", "title"])
    .unique()
    .with_columns(
        pl.col("title").str.to_lowercase()
        .str.replace_all(REGEX_CLEAN, " ")
        .str.replace_all(REGEX_SPACES, " ")
        .str.strip_chars()
        .alias("cleaned_title")
    )
    .select(["id", "cleaned_title"])
)

print("Configuring MeSH Sets...")
pd_mesh = pd.read_stata("../external/appended/contracted_gen_mesh_all_jrnls.dta")
q_mesh_raw = pl.from_pandas(pd_mesh).lazy()

q_mesh_agg = (
    q_mesh_raw
    .with_columns([
        pl.col("qualifier_name").str.to_lowercase().str.replace_all(REGEX_CLEAN, "_").fill_null(""),
        pl.col("gen_mesh").str.to_lowercase().str.replace_all(REGEX_CLEAN, "_").fill_null("")
    ])
    .group_by("id")
    .agg([
        pl.col("qualifier_name").str.concat(" ").alias("paper_qualifiers"),
        pl.col("gen_mesh").str.concat(" ").alias("paper_mesh")
    ])
)

print("Merging all text data onto Master List...")

q_full_data = (
    q_master_list
    .join(q_abstracts, on="id", how="left")  
    .join(q_titles, on="id", how="left")     
    .join(q_mesh_agg, on="id", how="left")   
)

print("Aggregating TOTAL career text by Author (Static Measure)...")

q_static_corpus = (
    q_full_data
    .group_by("athr_id")
    .agg([
        (
            pl.col("cleaned_abstract").fill_null("") + " " +
            pl.col("cleaned_title").fill_null("") + " " +
            pl.col("paper_qualifiers").fill_null("") + " " +
            pl.col("paper_mesh").fill_null("")
        ).str.concat(" ").alias("full_text_lifetime")
    ])
)

df_lifetime = q_static_corpus.collect(streaming=True)
print(f"Total Unique Authors to Cluster: {len(df_lifetime)}")

pdf = df_lifetime.to_pandas()

print("Applying Stemming (Single Core)...")
def clean_and_stem(text):
    if not text or len(text) < 5: return ""
    tokens = text.split()
    tokens = [
        stemmer.stem(t) for t in tokens 
        if len(t) > 2 and not t.isdigit() and t not in custom_stopwords_set
    ]
    return " ".join(tokens)

pdf['processed_text'] = pdf['full_text_lifetime'].apply(clean_and_stem)

pdf = pdf[pdf['processed_text'].str.len() > 50] 

print("Saving pre-clustered text data (Parquet)...")
pdf[['athr_id', 'processed_text']].to_parquet("../output/cleaned_static_author_text.parquet", index=False)

print(f"Clustering {len(pdf)} authors into {NUM_CLUSTERS} static subfields...")

tfidf = TfidfVectorizer(
    stop_words=custom_stopwords_list,
    min_df=10,       
    max_df=0.6,      
    dtype=np.float32
)

matrix = tfidf.fit_transform(pdf['processed_text'])

kmeans = MiniBatchKMeans(
    n_clusters=NUM_CLUSTERS,
    random_state=SEED,
    batch_size=8192,
    n_init=3
)
kmeans.fit(matrix)

pdf['cluster_label'] = kmeans.labels_

print("Saving Results...")
pdf[['athr_id', 'cluster_label']].to_csv("../output/author_static_clusters.csv", index=False)

print("Identifying Cluster topics...")
terms = tfidf.get_feature_names_out()
centers = kmeans.cluster_centers_

with open('../output/static_cluster_descriptions.txt', 'w') as f:
    for i, center in enumerate(centers):
        top_idx = center.argsort()[-15:][::-1]
        top_terms = [terms[idx] for idx in top_idx]
        desc = f"Cluster {i}: {', '.join(top_terms)}"
        print(desc)
        f.write(desc + "\n")

print("Done.")