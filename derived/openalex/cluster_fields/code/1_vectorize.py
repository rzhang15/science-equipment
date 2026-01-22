import os
import sys
import argparse
import random
import numpy as np
import pandas as pd
import nltk
from nltk.corpus import stopwords
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.cluster import MiniBatchKMeans
import scipy.sparse
import pickle

# --- STOPWORDS SETUP ---
# (Included to ensure TF-IDF behaves exactly as your original script)
nltk.download("stopwords", quiet=True)

# [Your original lists - condensed for brevity, ensure all your lists are here]
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

# --- LOAD PRE-SAVED DATA ---
print("Loading Parquet data...")
# Loading the file you saved in the previous step
pdf = pd.read_parquet("../output/cleaned_static_author_text.parquet")
pdf = pdf.reset_index(drop=True)
# --- CLUSTERING ---
print("Vectorizing...")
tfidf = TfidfVectorizer(
    stop_words=custom_stopwords_list,
    min_df=15,        
    dtype=np.float32
)

matrix = tfidf.fit_transform(pdf['processed_text'])
print(f"Matrix Shape: {matrix.shape}")

scipy.sparse.save_npz("../output/tfidf_matrix.npz", matrix)
with open("../output/feature_names.pkl", "wb") as f:
    pickle.dump(tfidf.get_feature_names_out(), f)

# 3. Save the Author IDs (aligned to the matrix rows)
pdf[['athr_id']].to_parquet("../output/author_ids_aligned.parquet")
